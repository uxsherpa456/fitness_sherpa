//  StateSync.swift
//  Fitness Sherpa
//
//  Cloud persistence client — mirrors the same `public.app_state` row the prototype writes, via the
//  deployed `state` Edge Function. Pull on launch (cloud wins when it has data), push after
//  onboarding and after any goals/settings edit. Same posture as the coach: DB credentials live in
//  the function; the app only speaks this small JSON contract.
//
//  Contract (POST https://<ref>.supabase.co/functions/v1/state):
//      { "action":"load", "user_key":"ryan" }                               -> AppState
//      { "action":"save", "user_key":"ryan", onboarded, profile, goals, settings } -> { ok:true }
//
//  These DTOs intentionally mirror the cloud row, NOT the SwiftData models (Goal/Baseline/…).
//  Map between them at the edges: load → seed the store; store/edits → save().

import Foundation

// MARK: - DTOs (shape matches public.app_state)

struct AppState: Codable {
    var onboarded: Bool = false
    var profile: ProfileData = .init()
    var goals: [GoalArc] = []
    var settings: AppSettings = .init()
    var sessions: [SessionDTO] = []        // workout history (only manual / edited — the rest re-imports)
    var readiness: [ReadinessDTO] = []     // readiness-over-time log (can't be reconstructed)
    var updated_at: String? = nil          // nil ⇒ the cloud has nothing for this user yet
}

/// Workout history mirror — the user-authored fields + provenance, so edits survive a restore.
struct SessionDTO: Codable {
    var healthkitUUID: String?
    var date: Date
    var category: String
    var title: String
    var durationMin: Int
    var distanceKm: Double?
    var caloriesKcal: Double?
    var avgHR: Int?
    var maxHR: Int?
    var rpe: Int?
    var notes: String?
    var provenance: Provenance

    init(_ s: TrainingSession) {
        healthkitUUID = s.healthkitUUID?.uuidString
        date = s.date; category = s.category; title = s.title
        durationMin = s.durationMin; distanceKm = s.distanceKm; caloriesKcal = s.caloriesKcal
        avgHR = s.avgHR; maxHR = s.maxHR; rpe = s.rpe; notes = s.notes
        provenance = s.provenance
    }
    func makeModel() -> TrainingSession {
        let m = TrainingSession(healthkitUUID: healthkitUUID.flatMap { UUID(uuidString: $0) },
                                date: date, category: category, title: title, durationMin: durationMin,
                                distanceKm: distanceKm, caloriesKcal: caloriesKcal, avgHR: avgHR,
                                maxHR: maxHR, rpe: rpe, notes: notes, source: .user)
        m.provenance = provenance
        return m
    }
}

/// One readiness-log day.
struct ReadinessDTO: Codable {
    var day: Date, score: Int, hrv: Double, ctl: Double, atl: Double, form: Double, acr: Double
    init(_ r: DailyReadiness) { day = r.day; score = r.score; hrv = r.hrv; ctl = r.ctl; atl = r.atl; form = r.form; acr = r.acr }
    func makeModel() -> DailyReadiness {
        DailyReadiness(day: day, score: score, hrv: hrv, ctl: ctl, atl: atl, form: form, acr: acr)
    }
}

struct ProfileData: Codable {
    var format: String? = nil     // "singles" | "doubles" | "relay" | "elite15"
    var gender: String? = nil     // "mens" | "womens" | "mixed" (mixed only for doubles/relay)
    var tier: String? = nil       // "open" | "pro"  (singles only; Pro = heavier stations)
    var age: Int? = nil
}

/// A focus-metric arc — mirrors the prototype's goal objects
/// (key/label/unit/kind/better + start/current/goal). Values are time- or number-valued.
struct GoalArc: Codable {
    var key: String
    var label: String? = nil
    var unit: String? = nil
    var kind: String? = nil        // "num" | "time"
    var better: String? = nil      // "up" | "down"
    var start: GoalValue? = nil
    var current: GoalValue? = nil
    var goal: GoalValue? = nil
}

/// A goal value that arrives as either a number (214) or a string ("22:00") — decode/encode either.
enum GoalValue: Codable, Equatable {
    case number(Double)
    case text(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .text(s) }
        else { self = .text("") }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .text(let s):   try c.encode(s)
        }
    }
    /// "214", "22:00" — for display.
    var display: String {
        switch self {
        case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .text(let s):   return s
        }
    }
}

struct AppSettings: Codable {
    var name: String? = nil
    var location: String? = nil
    var goalTime: String? = nil
    var raceDate: String? = nil
    var raceLoc: String? = nil
    var weightUnit: String? = nil   // "lb" | "kg"
    var distUnit: String? = nil     // "mi" | "km"
    var format: String? = nil       // "singles" | "doubles" | "relay" | "elite15"
    var gender: String? = nil       // "mens" | "womens" | "mixed"
    var tier: String? = nil         // "open" | "pro"
    var age: Int? = nil
    var weightLb: Double? = nil     // manual / confirmed bodyweight fallback (Apple Health wins when present)
    var bodyFatPct: Double? = nil
}

// MARK: - Client

enum StateClient {
    /// Same endpoint the prototype uses; deployed --no-verify-jwt, so no key is required yet.
    static let endpoint = URL(string: "https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/state")!

    /// The real, durable cloud row + an isolated sandbox row used by "experience as a new user".
    static let liveKey = "ryan"
    static let sandboxKey = "ryan-sandbox"

    /// Single-user for now — persisted so a sandbox switch survives relaunch. Swap for the
    /// authenticated user id once sign-in lands.
    static var userKey: String {
        get { UserDefaults.standard.string(forKey: "dev.userKey") ?? liveKey }
        set { UserDefaults.standard.set(newValue, forKey: "dev.userKey") }
    }
    static var isSandbox: Bool { userKey == sandboxKey }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// Pull the durable copy on launch. `updated_at == nil` ⇒ nothing in the cloud yet → run onboarding.
    static func load() async throws -> AppState {
        var req = request()
        req.httpBody = try JSONSerialization.data(withJSONObject: ["action": "load", "user_key": userKey])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp)
        return try decoder.decode(AppState.self, from: data)
    }

    /// Mirror state up. The backend merges per field, so a settings/goals push leaves history alone;
    /// `includeHistory` adds the workout + readiness history (omitted otherwise → preserved).
    static func save(_ state: AppState, includeHistory: Bool = false) async throws {
        struct SavePayload: Encodable {
            let action = "save"
            let user_key: String
            let onboarded: Bool
            let profile: ProfileData
            let goals: [GoalArc]
            let settings: AppSettings
            let sessions: [SessionDTO]?
            let readiness: [ReadinessDTO]?
        }
        var req = request()
        req.httpBody = try encoder.encode(
            SavePayload(user_key: userKey, onboarded: state.onboarded,
                        profile: state.profile, goals: state.goals, settings: state.settings,
                        sessions: includeHistory ? state.sessions : nil,
                        readiness: includeHistory ? state.readiness : nil))
        let (_, resp) = try await URLSession.shared.data(for: req)
        try check(resp)
    }

    // MARK: helpers
    private static func request() -> URLRequest {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // If `state` is ever redeployed WITHOUT --no-verify-jwt, send the Supabase anon key:
        //   req.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        return req
    }
    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
