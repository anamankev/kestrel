import Foundation
import KestrelCore

/// The in-app guide: answers questions offline from KestrelGuide (every function, step-by-step
/// how-tos and a glossary), remembers what the conversation is about, and offers tap-to-run
/// commands. Nothing leaves the device.
@MainActor @Observable final class GuideService {
    struct Message: Identifiable, Equatable {
        enum Role { case user, guide }
        let id = UUID()
        var role: Role
        var text: String
        var commands: [String] = []
        /// Suggested next questions, shown as tappable chips.
        var followUps: [String] = []
    }

    static let welcome = Message(
        role: .guide,
        text: "Hi, I'm the Kestrel guide. Ask me anything in your own words: how a feature works, how to place a paper trade, or what a term means. I'll explain step by step and give you buttons that open the right screen.",
        commands: ["HELP", "AAPL DES", "W"],
        followUps: ["How do I place a trade?", "What can Kestrel do?", "How do panels work?"])

    private(set) var messages: [Message] = [GuideService.welcome]
    var isOpen = false
    private var context = KestrelGuide.Context()

    /// Runs a command in the focused panel; returns false if it doesn't parse.
    var run: (String) -> Bool = { _ in false }

    func ask(_ raw: String) {
        let question = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !question.isEmpty else { return }
        messages.append(Message(role: .user, text: question))
        let r = KestrelGuide.answer(question, context: &context)
        messages.append(Message(role: .guide, text: r.text, commands: r.commands, followUps: r.followUps))
    }

    func reset() {
        messages = [Self.welcome]
        context = KestrelGuide.Context()
    }
}
