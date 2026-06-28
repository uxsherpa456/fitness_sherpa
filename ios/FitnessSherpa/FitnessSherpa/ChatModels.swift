//  ChatModels.swift
//  Fitness Sherpa
//
//  Persistent AI-coach conversations: a Conversation owns an ordered list of messages, saved to
//  SwiftData so chat history survives launches and is browsable (like Claude's conversation list).

import Foundation
import SwiftData

enum ChatRole: String, Codable { case user, assistant, note }

@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = "New chat"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageRecord.conversation)
    var messages: [ChatMessageRecord] = []

    init() {
        let now = Date()
        id = UUID(); createdAt = now; updatedAt = now
    }

    var sortedMessages: [ChatMessageRecord] { messages.sorted { $0.order < $1.order } }
    var nextOrder: Int { (messages.map(\.order).max() ?? -1) + 1 }
    var isEmpty: Bool { messages.isEmpty }
    var preview: String {
        sortedMessages.first(where: { $0.role == .user })?.text ?? "New chat"
    }
}

@Model
final class ChatMessageRecord {
    var id: UUID = UUID()
    var roleRaw: String = ChatRole.user.rawValue
    var text: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    var conversation: Conversation?

    init(role: ChatRole, text: String, order: Int) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.text = text
        self.order = order
        self.createdAt = Date()
    }

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
}
