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
    @State private var goalS: Int
    @State private var raceDate: Date

    @State private var step = 0
    @State private var connecting = false
    @State private var connected = false
    @State private var reading: HealthData.Reading?
    @State private var diagnosis: Diagnosis?
    @State private var finishing = false

    private static let lastStep = 5

    init(model: AppModel) {
        self.model = model
        let settings = model.settings
        _s = State(initialValue: settings)
        let parts = settings.goalTime.split(separator: ":").map { Int($0) ?? 0 }
        _goalH = State(initialValue: parts.count > 0 ? parts[0] : 1)
        _goalM = State(initialValue: parts.count > 1 ? parts[1] : 10)
        _goalS = State(initialValue: parts.count > 2 ? parts[2] : 0)
        _raceDate = State(initialValue: DateFormatters.ymd.date(from: settings.raceDate) ?? Date())
    }

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
                obField("e.g. Washington, DC", text: $s.location)
            }
            field("RACE LOCATION") {
                obField("City", text: $s.raceLocation)
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
                    pulledRow("Bodyweight", reading?.bodyMass.map { "\(Int($0.value.rounded())) lb" })
                    pulledRow("Resting HR", reading?.restingHR.map { "\(Int($0.value.rounded())) bpm" })
                    pulledRow("HRV", reading?.hrv.map { "\(Int($0.value.rounded())) ms" })
                    pulledRow("Last run", reading?.lastRunDate.map { $0.formatted(.relative(presentation: .named)) })
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
            } else {
                Text("Optional — you can connect later in Settings. We'll fall back to sensible defaults for the map.")
                    .font(.footnote).foregroundStyle(Palette.textFaint)
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

    private var strengthStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepTitle("Your strength", "The thing Apple Health can't see. Be honest — it sets your strength axis.")
            field("AGE") {
                Stepper("\(s.age) years", value: $s.age, in: 14...90)
                    .tint(Palette.mint).foregroundStyle(Palette.text)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("STATIONS AFTER A HARD RUN")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(Palette.textMuted)
                choice("Barely change", "I hold output under fatigue", holds: true,  selected: s.stationsHold)
                choice("Dip a little",  "Mostly hold, minor drop",     holds: true,  selected: s.stationsHold)
                choice("Drop a lot",    "Stations fall off when tired", holds: false, selected: !s.stationsHold)
                choice("Fall apart",    "I grind to a stop",            holds: false, selected: !s.stationsHold)
            }
        }
    }

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
            Picker("S", selection: $goalS) { ForEach(0...59, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                .labelsHidden().frame(width: 60).clipped()
            Text("s").foregroundStyle(Palette.textMuted)
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

    private func choice(_ title: String, _ detail: String, holds: Bool, selected: Bool) -> some View {
        Button { s.stationsHold = holds } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Palette.mint : Palette.textFaint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Palette.text)
                    Text(detail).font(.caption).foregroundStyle(Palette.textMuted)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Palette.surface2 : Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Palette.mint.opacity(0.5) : Palette.surfaceLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
        }
    }

    private func computeDiagnosis() {
        let bw = reading?.bodyMass?.value ?? 200
        let input = DiagnosisInput(bodyweightLb: bw,
                                   recent5k: DiagnosisEngine.parse5k(s.recent5k),
                                   stationsHold: s.stationsHold)
        diagnosis = DiagnosisEngine.diagnose(input)
    }

    private func finish() {
        finishing = true
        // Commit the goal time + race date the pickers built.
        s.goalTime = "\(goalH):\(String(format: "%02d", goalM)):\(String(format: "%02d", goalS))"
        s.raceDate = DateFormatters.ymd.string(from: raceDate)
        if !genderOptions.contains(where: { $0.0 == s.gender }) { s.gender = "mens" }
        s.onboarded = true

        model.settings = s
        model.saveSettings()
        model.diagnosis = diagnosis           // so goals seed from the right profile
        model.refreshGoals()                  // seeds GoalLibrary.seed(for: profile) + live currents
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
