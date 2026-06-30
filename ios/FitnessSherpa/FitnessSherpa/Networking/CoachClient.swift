//  CoachClient.swift
//  Ravns
//
//  Streams the AI coach from the deployed Supabase Edge Function (…/functions/v1/coach,
//  --no-verify-jwt). Sends { messages, context }, parses the SSE stream, and yields typed events.
//  Contract (supabase/README.md): events are text / tool / diagnosis / fuel / goals / done.
//  The Anthropic key lives in the function, never in the app.

import Foundation

enum CoachClient {
    static let endpoint = URL(string: "https://rcbjfjgffzadagndxthp.supabase.co/functions/v1/coach")!

    /// One streamed coach reply. `text` deltas append to the answer; `note` surfaces an agent
    /// action (tool call / re-diagnosis / fuel / goals); `done` ends the turn.
    enum Event {
        case text(String)
        case note(String)
        case plan(changes: [[String: Any]], summary: String?)
        case goals(items: [[String: Any]])
        case done
    }

    static func stream(messages: [[String: String]], context: [String: Any]) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = try JSONSerialization.data(
                        withJSONObject: ["messages": messages, "context": context])

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw URLError(.badServerResponse)
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = obj["type"] as? String else { continue }

                        switch type {
                        case "text":
                            if let t = obj["text"] as? String { continuation.yield(.text(t)) }
                        case "tool":
                            if let n = obj["name"] as? String {
                                continuation.yield(.note("↻ \(n.replacingOccurrences(of: "_", with: " "))…"))
                            }
                        case "diagnosis":
                            if let d = obj["data"] as? [String: Any] {
                                let p = d["profile"] as? String ?? "updated"
                                let lim = d["limiter"] as? String
                                continuation.yield(.note("Re-diagnosis: \(p)" + (lim.map { " — limiter: \($0)" } ?? "")))
                            }
                        case "fuel":
                            if let d = obj["data"] as? [String: Any], let kcal = d["calories"] {
                                continuation.yield(.note("Fuel: \(kcal) kcal target"))
                            } else {
                                continuation.yield(.note("Fuel computed"))
                            }
                        case "goals":
                            if let d = obj["data"] as? [String: Any], let items = d["goals"] as? [[String: Any]] {
                                continuation.yield(.goals(items: items))
                            } else {
                                continuation.yield(.note("Suggested goal targets"))
                            }
                        case "plan":
                            if let d = obj["data"] as? [String: Any] {
                                let changes = (d["changes"] as? [[String: Any]]) ?? []
                                continuation.yield(.plan(changes: changes, summary: d["summary"] as? String))
                            }
                        case "done":
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
