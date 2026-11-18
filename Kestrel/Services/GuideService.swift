import Foundation
import KestrelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The in-app guide. With Apple Intelligence on the device it answers through Apple's on-device
/// model (free, private: nothing leaves the device) and can open functions itself; otherwise the
/// offline KestrelGuide answers from the function directory. Either way every answer comes with
/// tap-to-run commands.
@MainActor @Observable final class GuideService {
    struct Message: Identifiable, Equatable {
        enum Role { case user, guide }
        let id = UUID()
        var role: Role
        var text: String
        var commands: [String] = []
    }

    private(set) var messages: [Message] = [
        Message(role: .guide, text: "Hi, I'm the Kestrel guide. Tell me what you want to do in your own words, like \"show Apple's dividends\" or \"what is beta?\", and I'll take you there.",
                commands: ["HELP", "AAPL DES", "W"])
    ]
    private(set) var busy = false
    /// Why the on-device model last failed (the answer then came from the offline guide).
    private(set) var lastModelError: String?
    var isOpen = false

    /// Runs a command in the focused panel; returns false if it doesn't parse.
    var run: (String) -> Bool = { _ in false }

    /// Set when the model reports itself available but can't generate (e.g. its assets aren't
    /// installed); the guide then answers offline for the rest of the session.
    private(set) var modelFailed = false

    var usesOnDeviceModel: Bool {
        #if canImport(FoundationModels)
        if !modelFailed, case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    func ask(_ raw: String) async {
        let question = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !question.isEmpty, !busy else { return }
        messages.append(Message(role: .user, text: question))
        busy = true
        defer { busy = false }
        let offline = KestrelGuide.answer(question)
        #if canImport(FoundationModels)
        if usesOnDeviceModel, let text = await modelReply(question) {
            messages.append(Message(role: .guide, text: text, commands: offline.commands))
            return
        }
        #endif
        messages.append(Message(role: .guide, text: offline.text, commands: offline.commands))
    }

    func reset() {
        messages = Array(messages.prefix(1))
        #if canImport(FoundationModels)
        session = nil
        #endif
    }

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?

    private static let instructions = """
    You are the guide inside Kestrel, a command-line market terminal for iPad and Mac. Help people find and use its functions.
    Answer in two to four short, plain sentences. A command is a security then a function, for example AAPL DVD or NVDA GP; functions that don't need a security work alone, like WEI or TOP.
    When the person wants to see something, call openFunction with the exact command, then say what you opened.
    You may explain financial concepts, but never give personalized investment advice or tell someone what to buy or sell. Trading in Kestrel is paper trading with play money.
    Only describe functions from this list:
    """

    private func makeSession() -> LanguageModelSession {
        let tool = OpenFunctionTool { [weak self] command in await MainActor.run { self?.run(command) ?? false } }
        return LanguageModelSession(tools: [tool], instructions: Self.instructions + "\n" + KestrelGuide.directory)
    }

    /// The on-device model's answer, or nil to fall back offline (guardrails, context limit, errors).
    private func modelReply(_ question: String) async -> String? {
        for attempt in 0..<2 {
            if session == nil || attempt == 1 { session = makeSession() }
            do {
                let r = try await session!.respond(to: question)
                let text = r.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch let e as LanguageModelSession.GenerationError {
                lastModelError = String(describing: e)
                switch e {
                case .exceededContextWindowSize: continue          // start a fresh conversation once
                case .guardrailViolation, .refusal: return nil      // this question only
                default: modelFailed = true; return nil
                }
            } catch {
                lastModelError = String(describing: error)
                modelFailed = true
                return nil
            }
        }
        return nil
    }
    #endif
}

#if canImport(FoundationModels)
/// Lets the on-device model open a function in the terminal. Commands are validated by the
/// same parser the command line uses; trading functions only open the ticket, never place orders.
struct OpenFunctionTool: Tool {
    let name = "openFunction"
    let description = "Opens a Kestrel function in the terminal, e.g. 'AAPL DVD', 'NVDA GP', 'WEI', 'SECF TOYOTA'."

    @Generable
    struct Arguments {
        @Guide(description: "The exact Kestrel command: optional security, then the function code")
        var command: String
    }

    let open: @Sendable (String) async -> Bool

    func call(arguments: Arguments) async throws -> String {
        let cmd = String(arguments.command.uppercased().prefix(64))
        guard (try? CommandParser.parse(cmd, current: nil)) != nil else {
            return "'\(cmd)' isn't a valid command. Use a function code from the list, with a ticker first if it needs one."
        }
        return await open(cmd) ? "Opened \(cmd)." : "Couldn't open \(cmd)."
    }
}
#endif
