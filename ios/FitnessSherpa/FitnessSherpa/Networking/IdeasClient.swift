//  IdeasClient.swift
//  Ravns
//
//  Reads/writes the product-idea ledger (…/functions/v1/ideas) that Hugin logs to while coaching.
//  Powers the in-app "Hugin's ideas" list; each idea carries a RAVN-<n> ref + a build status.

import Foundation

struct Idea: Identifiable, Decodable, Equatable {
    let ref: String
    let title: String
    let detail: String
    let status: String       // proposed | building | built | dropped
    let source: String
    let created_at: String
    var id: String { ref }

    var created: Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: created_at) ?? ISO8601DateFormatter().date(from: created_at)
    }
}

enum IdeaStatus: String, CaseIterable {
    case proposed, building, built, dropped
    var label: String {
        switch self {
        case .proposed: return "Queued"; case .building: return "Building"
        case .built: return "Built";      case .dropped: return "Dropped"
        }
    }
}

enum IdeasClient {
    static let endpoint = URL(string: "https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/ideas")!

    static func list() async -> [Idea] {
        await post(["action": "list"], as: ListResponse.self)?.ideas ?? []
    }

    @discardableResult
    static func update(ref: String, status: IdeaStatus) async -> Bool {
        await post(["action": "update", "ref": ref, "status": status.rawValue], as: OKResponse.self)?.ok ?? false
    }

    private struct ListResponse: Decodable { let ok: Bool; let ideas: [Idea] }
    private struct OKResponse: Decodable { let ok: Bool }

    private static func post<T: Decodable>(_ body: [String: Any], as: T.Type) async -> T? {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
