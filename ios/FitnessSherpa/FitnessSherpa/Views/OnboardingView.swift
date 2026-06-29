//  OnboardingView.swift
//  Fitness Sherpa
//
//  First-run baseline assessment, ported from the prototype's onboarding flow and adapted to what
//  we actually have built: real Settings, a live HealthKit read, and the real DiagnosisEngine.
//  Flow: Welcome → Your race → Connect Apple Health → Your run → Your strength → Quadrant reveal.
//  On finish it writes the full baseline into AppModel (settings + onboarded flag), seeds the
//  profile goals, syncs to the cloud, and triggers the first real refresh.

import SwiftUI
import SwiftData

struct OnboardingView: View {
    let model: AppModel
    @Environment(\.modelContext) private var context

    // Working copy of settings — committed to the model only on finish.
    @State private var s: UserSettings
    @State private var goalH: Int
    @State private var goalM: Int
    @State private var raceDate: Date

    @State private var step = 0
    @State private var connecting = false
    @State private var connected = false
    @State private var bodyweightText = ""
    @State private var bodyFatText = ""
    @State private var reading: HealthData.Reading?
    @State private var diagnosis: Diagnosis?
    @State private var finishing = false

    // Strength assessment (branched questionnaire → continuous strength axis).
    @State private var experienced: Bool?          // nil until the gate is answered
    @State private var strAnswers: [String: Double] = [:]   // qid → value (omitted when "not sure")
    @State private var strNotSure: Set<String> = []         // qids explicitly marked "not sure"

    // Mobility assessment (advisory flag — never touches the quadrant/score).
    @State private var mobilityAnswers: [String: Double] = [:]
    @State private var mobilityNotSure: Set<String> = []

    private static let lastStep = 6

    init(model: AppModel) {
        self.model = model
        var settings = model.settings
        // A genuinely new athlete (never onboarded) starts with nothing pre-filled or pre-selected;
        // a re-run keeps the existing values so you can tweak them.
        let fresh = !UserDefaults.standard.bool(forKey: OnboardingView.everKey)
        if fresh {
            settings.location = ""; settings.raceLocation = ""; settings.recent5k = ""
            settings.format = ""; settings.gender = ""; settings.tier = ""
            settings.raceDate = DateFormatters.ymd.string(
                from: Calendar.current.date(byAdding: .day, value: 56, to: Date()) ?? Date())
        }
        _s = State(initialValue: settings)
        let parts = settings.goalTime.split(separator: ":").map { Int($0) ?? 0 }
        _goalH = State(initialValue: parts.count > 0 ? parts[0] : 1)
        _goalM = State(initialValue: parts.count > 1 ? parts[1] : 10)
        _raceDate = State(initialValue: DateFormatters.ymd.date(from: settings.raceDate) ?? Date())
        // Re-runs pre-fill the entered weight; a fresh user starts blank (Health fills it on connect).
        if !fresh, settings.bodyweightLb > 0 {
            let v = settings.weightUnit == "kg" ? settings.bodyweightLb * 0.453592 : settings.bodyweightLb
            _bodyweightText = State(initialValue: String(format: "%.0f", v))
        }
        if !fresh, settings.bodyFatPct > 0 {
            _bodyFatText = State(initialValue: String(format: "%.0f", settings.bodyFatPct))
        }
    }

    static let everKey = "onboardedBefore"

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch step {
                    case 0: welcomeStep
                    case 1: raceStep
                    case 2: healthStep
                    case 3: runStep
                    case 4: strengthStep
                    case 5: mobilityStep
                    default: revealStep
                    }
                }
                .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .background(Palette.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BASELINE ASSESSMENT")
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2)
                .foregroundStyle(Palette.textMuted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceLine)
                    Capsule().fill(Palette.mint)
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)
            .animation(.easeInOut(duration: 0.25), value: step)
            Text(stepLabel).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.text)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 6)
    }

    private var progress: Double { Double(step + 1) / Double(Self.lastStep + 1) }
    private var stepLabel: String {
        switch step {
        case 0: return "Welcome"
        case Self.lastStep: return "Your result"
        default: return "Step \(step) of \(Self.lastStep - 1)"
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { withAnimation { step -= 1 } }
                    .font(.body.weight(.medium)).foregroundStyle(Palette.textMuted)
            }
            Spacer()
            Button(action: advance) {
                Text(nextTitle)
                    .font(.body.weight(.semibold)).foregroundStyle(Palette.ink)
                    .padding(.vertical, 13).padding(.horizontal, 28)
                    .background(Capsule().fill(nextEnabled ? Palette.mint : Palette.surfaceLine))
            }
            .disabled(!nextEnabled)
        }
        .padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 14)
        .background(Palette.bg)
    }

    private var nextTitle: String {
        switch step {
        case 0: return "Start"
        case Self.lastStep: return finishing ? "Setting up…" : "Enter the app"
        default: return "Continue"
        }
    }

    private var nextEnabled: Bool {
        switch step {
        case 3: return DiagnosisEngine.parse5k(s.recent5k) > 0
        case 4: return experienced != nil && !strAnswers.isEmpty   // gate + at least one real answer
        case Self.lastStep: return !finishing
        default: return true
        }
    }

    private func advance() {
        if step < Self.lastStep {
            if step + 1 == Self.lastStep { computeDiagnosis() }   // entering the reveal
            withAnimation { step += 1 }
        } else {
            finish()
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let's find your ").font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.text)
            + Text("limiter.").font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.mint)
            Text("A quick baseline assessment — your real numbers, not a guess. We'll place you on the HYROX map and track only what moves your goal time. About a minute.")
                .font(.body).foregroundStyle(Palette.textMuted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var raceStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Your race", "The fixed point everything reasons against. Your format sets your division, standards, and station weights.")

            field("FORMAT") {
                pills([("singles", "Singles"), ("doubles", "Doubles"), ("relay", "Relay"), ("elite15", "Elite 15")],
                      selection: s.format) { setFormat($0) }
            }
            field("DIVISION") {
                pills(genderOptions, selection: s.gender) { s.gender = $0 }
            }
            if s.format == "singles" {
                field("WEIGHTS") {
                    pills([("open", "Open"), ("pro", "Pro")], selection: s.tier) { s.tier = $0 }
                }
            }
            field("HOME LOCATION") {
                LocationField(placeholder: "Start typing a city…", text: $s.location)
            }
            field("RACE LOCATION") {
                LocationField(placeholder: "Start typing a city…", text: $s.raceLocation)
            }
            field("RACE DATE") {
                DatePicker("", selection: $raceDate, displayedComponents: [.date])
                    .labelsHidden().datePickerStyle(.compact).tint(Palette.mint)
            }
            field("TARGET FINISH TIME") { goalTimePicker }
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Connect Apple Health", "We read bodyweight, resting HR and your recent runs — and always show how fresh it is. Stations & strength you'll enter by hand.")
            Button(action: connectHealth) {
                HStack(spacing: 8) {
                    Image(systemName: connected ? "checkmark.circle.fill" : "heart.fill")
                    Text(connecting ? "Syncing Apple Health…" : connected ? "Apple Health connected" : "Connect Apple Health")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(connected ? Palette.green : Palette.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Capsule().fill(connected ? Palette.surface : Palette.mint))
            }
            .disabled(connecting || connected)

            if connected {
                VStack(alignment: .leading, spacing: 8) {
                    pulledRow("Resting HR", reading?.restingHR.map { "\(Int($0.value.rounded())) bpm" })
                    pulledRow("HRV", reading?.hrv.map { "\(Int($0.value.rounded())) ms" })
                    pulledRow("Last run", reading?.lastRunDate.map { $0.formatted(.relative(presentation: .named)) })
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
            } else {
                Text("Optional — or enter your numbers below. We'll fall back to sensible defaults for anything blank.")
                    .font(.footnote).foregroundStyle(Palette.textFaint)
            }

            // Bodyweight drives power-to-weight (half your run axis) + your weight goal. Pre-filled
            // from Health when it has it; editable, and enterable when it doesn't.
            field("BODYWEIGHT (\(Units.weightUnit(s).uppercased()))") {
                obField("e.g. 200", text: $bodyweightText).keyboardType(.decimalPad)
            }
            field("BODY FAT % · OPTIONAL") {
                obField("e.g. 18", text: $bodyFatText).keyboardType(.decimalPad)
            }
        }
    }

    private var runStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Your run", "Roughly half of a HYROX is running. Your recent 5k sets your run axis.")
            field("RECENT 5K TIME (MM:SS)") {
                obField("e.g. 24:31", text: $s.recent5k).keyboardType(.numbersAndPunctuation)
            }
            Text("Use a chip-timed result if you have one — it's more honest than a watch lap.")
                .font(.footnote).foregroundStyle(Palette.textFaint)
        }
    }

    // The strength axis is the one thing Apple Health can't see, so the athlete answers for it.
    // Barbell max-strength is asked on BOTH paths — it's the most reliable strength signal, so a strong
    // lifter (e.g. a CrossFitter) always registers regardless of HYROX experience. The experience gate
    // then adds either station capacity (experienced) or bodyweight movements (new). Answers average to 0…1.
    // Barbell option values are BODYWEIGHT MULTIPLES (not axis values) — StrengthStandards scores them
    // against the athlete's division to decide "strong enough." Station/bodyweight questions below
    // still carry direct 0…1 axis values.
    private static let barbellQuestions: [(id: String, label: String, options: [(String, Double?)])] = [
        ("squat", "BACK SQUAT vs BODYWEIGHT",
         [("under bodyweight", 0.8), ("~bodyweight", 1.0), ("1.25× BW", 1.25), ("1.5×+ BW", 1.6), ("not sure", nil)]),
        ("bench", "BENCH PRESS vs BODYWEIGHT",
         [("under 0.75× BW", 0.6), ("~bodyweight", 1.0), ("1.25× BW", 1.25), ("1.5×+ BW", 1.6), ("not sure", nil)]),
        ("deadlift", "DEADLIFT vs BODYWEIGHT",
         [("under bodyweight", 0.8), ("1.5× BW", 1.5), ("2× BW", 2.0), ("2.5×+ BW", 2.6), ("not sure", nil)]),
    ]
    private static let hyroxQuestions: [(id: String, label: String, options: [(String, Double?)])] = [
        ("wallballs", "WALL BALLS — UNBROKEN, FRESH",
         [("<20", 0.20), ("20–40", 0.50), ("40–70", 0.75), ("70+", 0.95), ("not sure", nil)]),
        ("sled", "RACE-WEIGHT SLED PUSH · 50 M",
         [("can't / long breaks", 0.15), ("unbroken, grindy", 0.50), ("unbroken, steady", 0.80), ("unbroken, fast", 0.95), ("not sure", nil)]),
        ("fatigue", "STATIONS AFTER A HARD RUN",
         [("fall apart", 0.20), ("drop a lot", 0.45), ("dip a little", 0.75), ("barely change", 0.95), ("not sure", nil)]),
    ]
    private static let generalQuestions: [(id: String, label: String, options: [(String, Double?)])] = [
        ("pushups", "MAX PUSH-UPS · UNBROKEN",
         [("<10", 0.20), ("10–25", 0.50), ("25–40", 0.75), ("40+", 0.95), ("not sure", nil)]),
        ("pullups", "STRICT PULL-UPS · UNBROKEN",
         [("0–2", 0.20), ("3–8", 0.50), ("9–15", 0.80), ("15+", 0.95), ("not sure", nil)]),
    ]

    private var strengthStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Your strength", "The one axis Apple Health can't see. A couple of honest answers place you left-to-right on the map.")
            field("AGE") {
                Stepper("\(s.age) years", value: $s.age, in: 14...90)
                    .tint(Palette.mint).foregroundStyle(Palette.text)
            }

            field("HOW MUCH HYROX HAVE YOU DONE?") {
                VStack(spacing: 8) {
                    expChoice("Experienced", "I've raced HYROX or train the stations", value: true)
                    expChoice("New to it", "Haven't really trained the stations yet", value: false)
                }
            }

            if let exp = experienced {
                Text("Lifts are scored against your division — \(StrengthStandards.divisionLabel(s)). Hit your division's numbers and you're \u{201C}strong enough.\u{201D}")
                    .font(.footnote).foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Self.barbellQuestions + (exp ? Self.hyroxQuestions : Self.generalQuestions), id: \.id) { q in
                    questionRow(q.id, q.label, q.options, answers: $strAnswers, notSure: $strNotSure)
                }
            }
        }
    }

    // Mobility — an advisory flag, not a quadrant axis. Range gates how you express fitness in the
    // stations (wall-ball depth, lunges, burpees), so it's surfaced as a flag + coach signal only.
    private static let mobilityQuestions: [(id: String, label: String, options: [(String, Double?)])] = [
        ("squatdepth", "BODYWEIGHT SQUAT DEPTH",
         [("below parallel", 1.0), ("to parallel", 0.7), ("above parallel", 0.4), ("can't get low", 0.1), ("not sure", nil)]),
        ("ankle", "HEELS STAY DOWN AT THE BOTTOM",
         [("grounded deep", 1.0), ("partway", 0.6), ("heels lift early", 0.3), ("not sure", nil)]),
        ("toetouch", "TOE TOUCH · LEGS STRAIGHT",
         [("palms to floor", 1.0), ("fingers to toes", 0.75), ("mid-shin", 0.45), ("above knee", 0.2), ("not sure", nil)]),
    ]

    private var mobilityStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Your mobility", "Range gates how you express it — wall-ball depth, lunges, burpees. This won't move your quadrant; it flags where stations might no-rep or strain.")
            ForEach(Self.mobilityQuestions, id: \.id) { q in
                questionRow(q.id, q.label, q.options, answers: $mobilityAnswers, notSure: $mobilityNotSure)
            }
            if let flag = liveMobilityFlag {
                Text("Reads as: \(flag.label) — \(flag.read)")
                    .font(.footnote).foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            }
        }
    }

    private func expChoice(_ title: String, _ detail: String, value: Bool) -> some View {
        Button {
            if experienced != value { strAnswers.removeAll(); strNotSure.removeAll() }   // switching branch clears answers
            experienced = value
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: experienced == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(experienced == value ? Palette.mint : Palette.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                    Text(detail).font(.caption).foregroundStyle(Palette.textMuted)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(experienced == value ? Palette.surface2 : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(experienced == value ? Palette.mint.opacity(0.5) : Palette.surfaceLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// One pill-group question, writing into the given answers/not-sure state (strength or mobility).
    private func questionRow(_ qid: String, _ label: String, _ options: [(String, Double?)],
                             answers: Binding<[String: Double]>, notSure: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Palette.textMuted)
            FlowLayout(spacing: 8) {
                ForEach(options.indices, id: \.self) { i in
                    let (txt, val) = options[i]
                    let isSel = val == nil ? notSure.wrappedValue.contains(qid) : (answers.wrappedValue[qid] == val)
                    Button {
                        if let val { answers.wrappedValue[qid] = val; notSure.wrappedValue.remove(qid) }
                        else { answers.wrappedValue.removeValue(forKey: qid); notSure.wrappedValue.insert(qid) }
                    } label: {
                        Text(txt)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isSel ? Palette.ink : (val == nil ? Palette.textFaint : Palette.text))
                            .padding(.vertical, 9).padding(.horizontal, 14)
                            .background(Capsule().fill(isSel ? Palette.mint : Palette.surface))
                            .overlay(Capsule().stroke(isSel ? Color.clear : Palette.surfaceLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let liftIds: Set<String> = ["squat", "bench", "deadlift"]

    /// Strength axis: the barbell lifts vs your division standards drive it (StrengthStandards). The
    /// station/bodyweight answers are a fallback when the lifts are skipped, and otherwise can only
    /// nudge a strong-enough lifter higher — never drag you below the line if your lifts clear it.
    private var computedStrengthAxis: Double {
        let liftPairs = strAnswers.compactMap { k, v -> (StrengthLift, Double)? in
            Self.liftIds.contains(k) ? StrengthLift(rawValue: k).map { ($0, v) } : nil
        }
        let capacity = strAnswers.filter { !Self.liftIds.contains($0.key) }.map(\.value)
        let capAxis = capacity.isEmpty ? nil : capacity.reduce(0, +) / Double(capacity.count)

        guard let liftAxis = StrengthStandards.liftAxis(Dictionary(uniqueKeysWithValues: liftPairs), s) else {
            return capAxis ?? 0.5   // no lifts answered → fall back to station/bodyweight capacity
        }
        guard let cap = capAxis else { return liftAxis }
        let blended = liftAxis * 0.75 + cap * 0.25
        return liftAxis >= 0.5 ? max(blended, 0.5) : blended   // clearing your lifts keeps you "strong enough"
    }

    // MARK: - Plan messaging (reveal)

    /// Days to race from the picker's date (s.raceDate isn't committed until finish()).
    private var daysToRace: Int? {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: raceDate)).day
    }

    private var planIntro: String {
        let base = "From your answers we'll build a phased training plan — base → build → peak → taper — that ramps to race day"
        if let n = daysToRace, n > 0 { return base + ", across the \(n) days you've got." }
        return base + "."
    }

    /// Every athlete's different — the plan's emphasis follows the diagnosed limiter.
    private func planMessage(_ p: AthleteProfile) -> String {
        switch p {
        case .heavySlowStrong:
            return "You've got the strength — your lever is strength-to-weight and pace. We'll periodize toward dropping weight and sharpening your run, with lifting held at maintenance."
        case .lightFastWeak:
            return "Your engine's there — what you need is strength and station capacity. We'll build those without costing you your run."
        case .goodAtEverything:
            return "You're already prime HYROX material — so the plan optimizes: race simulation, pacing, and compromised running to find the last minutes."
        case .weakAtEverything:
            return "You need both — engine and strength. We'll build a base on each, biggest deficit first, then re-check as you progress."
        }
    }

    /// Average of the answered mobility questions (nil if none answered → not assessed).
    private var mobilityScore: Double? {
        let vals = Array(mobilityAnswers.values)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
    private var liveMobilityFlag: MobilityFlag? { mobilityScore.map { Mobility.flag(score: $0) } }

    @ViewBuilder private var revealStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR LIMITER")
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2)
                .foregroundStyle(Palette.mint)
            if let d = diagnosis {
                Text(d.profile.title).font(.system(size: 24, weight: .heavy)).foregroundStyle(Palette.text)
                Text("Limiter: \(d.limiter)").font(.subheadline).foregroundStyle(Palette.textMuted)
                QuadrantChart(markerX: d.markerX, markerY: d.markerY, active: d.profile)
                    .frame(height: 260)
                Card(style: .dark) {
                    VStack(alignment: .leading, spacing: 6) {
                        ModuleLabel("Your focus")
                        Text(d.focus).font(.subheadline).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card(style: .ai) {
                    VStack(alignment: .leading, spacing: 8) {
                        ModuleLabel("Your plan")
                        Text(planIntro).font(.subheadline).foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(planMessage(d.profile)).font(.subheadline).foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let m = liveMobilityFlag {
                    Card(style: .dark) {
                        VStack(alignment: .leading, spacing: 6) {
                            ModuleLabel("Mobility · \(m.label)")
                            Text(m.read).font(.subheadline).foregroundStyle(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("We'll seed your focus metrics from this and keep them on the Athlete tab. The AI Coach can refine them anytime.")
                    .font(.footnote).foregroundStyle(Palette.textFaint).fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView().tint(Palette.mint).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Building blocks

    private func stepTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Palette.text)
            Text(sub).font(.subheadline).foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(Palette.textMuted)
            content()
        }
    }

    private func pills(_ options: [(String, String)], selection: String, action: @escaping (String) -> Void) -> some View {
        FlowPills(options: options, selection: selection, action: action)
    }

    private func obField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .foregroundStyle(Palette.text)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.surfaceLine, lineWidth: 1))
    }

    private var goalTimePicker: some View {
        HStack(spacing: 6) {
            Picker("H", selection: $goalH) { ForEach(0...3, id: \.self) { Text("\($0)").tag($0) } }
                .labelsHidden().frame(width: 54).clipped()
            Text("h").foregroundStyle(Palette.textMuted)
            Picker("M", selection: $goalM) { ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                .labelsHidden().frame(width: 60).clipped()
            Text("m").foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .pickerStyle(.wheel).frame(height: 96)
        .tint(Palette.text)
    }

    private func pulledRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Image(systemName: value == nil ? "exclamationmark.triangle.fill" : "checkmark")
                .font(.caption).foregroundStyle(value == nil ? Palette.yellow : Palette.green)
            Text(label).font(.subheadline).foregroundStyle(Palette.textMuted)
            Spacer()
            Text(value ?? "not found").font(.subheadline.weight(.semibold))
                .foregroundStyle(value == nil ? Palette.textFaint : Palette.text)
        }
    }

    // MARK: - Logic

    private var genderOptions: [(String, String)] {
        switch s.format {
        case "doubles", "relay": return [("mens", "Men's"), ("womens", "Women's"), ("mixed", "Mixed")]
        default: return [("mens", "Men's"), ("womens", "Women's")]
        }
    }

    private func setFormat(_ f: String) {
        s.format = f
        if !genderOptions.contains(where: { $0.0 == s.gender }) { s.gender = "mens" }
    }

    private func connectHealth() {
        connecting = true
        Task {
            try? await HealthData.requestAuthorization()
            reading = try? await HealthData.readSnapshot()
            connecting = false
            connected = true
            // Pre-fill the editable fields from Health (only if the athlete hasn't typed their own).
            if bodyweightText.isEmpty, let bw = reading?.bodyMass?.value { bodyweightText = weightToInput(bw) }
            if bodyFatText.isEmpty, let bf = reading?.bodyFat?.value { bodyFatText = String(format: "%.0f", bf * 100) }
        }
    }

    private func weightToInput(_ lb: Double) -> String {
        String(format: "%.0f", s.weightUnit == "kg" ? lb * 0.453592 : lb)
    }
    private func inputToLb(_ text: String) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return s.weightUnit == "kg" ? v / 0.453592 : v
    }

    private func computeDiagnosis() {
        // Fold the questionnaire into the continuous strength axis (and keep the legacy boolean in sync).
        let axis = computedStrengthAxis
        s.strengthAxis = axis
        s.stationsHold = axis >= 0.5
        s.mobilityScore = mobilityScore ?? -1   // advisory flag; <0 = not assessed
        // Persist the entered bodyweight / body fat (manual fallback when Health has none).
        s.bodyweightLb = inputToLb(bodyweightText) ?? 0
        s.bodyFatPct = Double(bodyFatText.trimmingCharacters(in: .whitespaces)) ?? 0
        let bw = inputToLb(bodyweightText) ?? reading?.bodyMass?.value ?? 214
        let input = DiagnosisInput(bodyweightLb: bw,
                                   recent5k: DiagnosisEngine.parse5k(s.recent5k),
                                   strengthAxis: axis)
        diagnosis = DiagnosisEngine.diagnose(input)
    }

    private func finish() {
        finishing = true
        // Commit the goal time + race date the pickers built.
        s.goalTime = "\(goalH):\(String(format: "%02d", goalM))"
        s.raceDate = DateFormatters.ymd.string(from: raceDate)
        // Fall back to sensible defaults for anything left unselected.
        if s.format.isEmpty { s.format = "singles" }
        if !genderOptions.contains(where: { $0.0 == s.gender }) { s.gender = "mens" }
        if s.tier.isEmpty { s.tier = "open" }
        s.onboarded = true
        UserDefaults.standard.set(true, forKey: Self.everKey)   // re-runs will pre-fill from here on

        model.settings = s
        model.saveSettings()
        model.diagnosis = diagnosis                       // so goals seed from the right profile
        model.reseedGoals(for: diagnosis?.profile)        // re-seed the goal set (profile may have changed) + live currents
        // Rebuild the full periodized plan for the (possibly new) profile + race date.
        PlannedWorkout.regeneratePlan(profile: diagnosis?.profile, settings: s, context: context)
        model.pushToCloud()

        Task { await model.refresh(context: context) }   // first real read now that we're in
    }
}

/// A wrapping row of selectable pills, laid out with a simple greedy flow layout.
private struct FlowPills: View {
    let options: [(String, String)]
    let selection: String
    let action: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                let isSel = opt.0 == selection
                Button { action(opt.0) } label: {
                    Text(opt.1)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isSel ? Palette.ink : Palette.text)
                        .padding(.vertical, 9).padding(.horizontal, 16)
                        .background(Capsule().fill(isSel ? Palette.mint : Palette.surface))
                        .overlay(Capsule().stroke(isSel ? Color.clear : Palette.surfaceLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Minimal greedy flow layout for a handful of pills.
private struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > maxWidth, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
