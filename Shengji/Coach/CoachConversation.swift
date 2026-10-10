import Foundation
import Observation
import ShengjiCore

/// What the coach can see in a conversation, shown as a one-line note under the sheet's title.
enum CoachScope: Equatable, Sendable {
    /// At the table: your hand, the trick, the score, the hint.
    case table
    /// Inside a lesson: the page on screen.
    case lesson
    /// A practice or review question.
    case question

    var note: String {
        switch self {
        case .table: return "Sees your hand and the table"
        case .lesson: return "Knows this lesson page"
        case .question: return "Knows this question"
        }
    }

    var systemImage: String {
        switch self {
        case .table: return "eye"
        case .lesson: return "book"
        case .question: return "questionmark.circle"
        }
    }
}

/// One chat bubble.
struct CoachMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user, assistant
    }

    let id: UUID
    let role: Role
    /// What the bubble shows: the chip label or the typed text (you), the reply so far (coach).
    var text: String
    /// Your turns: exactly what was sent, and the context it was asked with.
    var sentText: String
    var context: String?
    /// The chip that asked it (nil when typed).
    var question: SuggestedQuestion?
    /// Coach turns: the reply finished. A reply cut short by an error or a new question stays incomplete
    /// and is left out of what is sent next time.
    var isComplete: Bool

    init(id: UUID = UUID(), role: Role, text: String, sentText: String = "", context: String? = nil,
         question: SuggestedQuestion? = nil, isComplete: Bool = true) {
        self.id = id
        self.role = role
        self.text = text
        self.sentText = sentText
        self.context = context
        self.question = question
        self.isComplete = isComplete
    }
}

/// A chat with the coach: the bubbles, the reply streaming in, tap-to-ask chips and follow-ups.
/// Every question carries the context it was asked with (the table, a lesson page or a question),
/// and the history sent to the server always fits its limits. SwiftUI-free.
@MainActor
@Observable
final class CoachConversation {
    private(set) var messages: [CoachMessage] = []
    /// A reply is on its way (or arriving).
    private(set) var isStreaming = false
    /// Learner-facing error for the last question (shown with Retry).
    private(set) var error: String?
    /// Chips for the current moment, set by `prepare`.
    private(set) var suggestions: [SuggestedQuestion] = []
    /// Chips under the latest answer ("Why?", "Show an example", ...).
    private(set) var followUps: [SuggestedQuestion] = []
    private(set) var scope: CoachScope = .table
    /// Bumps whenever something new appears, so the sheet can keep the latest message in view.
    private(set) var revision = 0
    /// The text field's contents.
    var draft = ""

    /// Demo and screenshot conversations never touch the network.
    let isOffline: Bool

    /// The context new questions are asked with (set by `prepare`).
    @ObservationIgnored private(set) var context: String?
    @ObservationIgnored private var client: CoachClient?
    @ObservationIgnored private let makeClient: () -> CoachClient?
    @ObservationIgnored private let makeFollowUps: (SuggestedQuestion?) -> [SuggestedQuestion]
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Increases with every reply started or cancelled; stale stream events are ignored.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var replyID: UUID?
    @ObservationIgnored private var askedSuggestionIDs: Set<String> = []

    /// - Parameters:
    ///   - offline: answer with a canned line instead of calling the server (demo scenes).
    ///   - makeClient: the coach server client, created on the first question.
    ///   - followUps: the chips offered under an answer to a question (nil when it was typed).
    init(offline: Bool,
         makeClient: @escaping () -> CoachClient? = { CoachClient.standard() },
         followUps: @escaping (SuggestedQuestion?) -> [SuggestedQuestion] = { SuggestedQuestions.followUps(after: $0) }) {
        self.isOffline = offline
        self.makeClient = makeClient
        self.makeFollowUps = followUps
    }

    /// The live coach, or an offline one in demo / screenshot scenes.
    static func live() -> CoachConversation {
        CoachConversation(offline: DemoScene.current != nil)
    }

    // MARK: Reading

    /// Waiting for the first words of the reply (shows the typing indicator).
    var isWaitingForFirstToken: Bool {
        guard isStreaming, let last = messages.last else { return false }
        return last.role == .user || last.text.isEmpty
    }

    /// Suggested chips not asked yet since the last `prepare`.
    var visibleSuggestions: [SuggestedQuestion] {
        suggestions.filter { !askedSuggestionIDs.contains($0.id) }
    }

    /// The draft can be sent.
    var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Asking

    /// Sets what the coach sees for the next questions and which chips to offer. Call each time the
    /// sheet opens (the table, the page or the question may have changed). History is kept.
    func prepare(scope: CoachScope, context: String?, suggestions: [SuggestedQuestion]) {
        self.scope = scope
        self.context = context.map { CoachText.clamp($0, to: CoachLimits.maxContextChars) }
        self.suggestions = CoachConversation.uniqueChips(suggestions)
        askedSuggestionIDs = []
    }

    /// Chips with distinct ids, first one kept (the chip rows are `ForEach`es keyed by id).
    static func uniqueChips(_ chips: [SuggestedQuestion]) -> [SuggestedQuestion] {
        var seen = Set<String>()
        return chips.filter { seen.insert($0.id).inserted }
    }

    /// Asks a chip's question with the prepared context.
    func ask(_ question: SuggestedQuestion) {
        ask(question, context: context)
    }

    /// Asks a chip's question: the bubble shows its label, the coach gets its full prompt.
    func ask(_ question: SuggestedQuestion, context: String?) {
        askedSuggestionIDs.insert(question.id)
        send(shown: question.label, sent: question.prompt, context: context, question: question)
    }

    /// Asks a typed question.
    func ask(text: String, context: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        send(shown: trimmed, sent: trimmed, context: context, question: nil)
    }

    /// Sends the text field's contents with the prepared context.
    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        ask(text: text, context: context)
    }

    /// Asks the last question again after an error.
    func retry() {
        guard !isStreaming, error != nil, let index = messages.lastIndex(where: { $0.role == .user }) else { return }
        // Drop a reply that was cut short; the question gets a fresh one.
        messages.removeSubrange((index + 1)...)
        error = nil
        followUps = []
        revision += 1
        startReply(to: messages[index], history: Array(messages[..<index]))
    }

    /// Stops the reply in progress (what arrived so far stays on screen).
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        if let id = replyID, let index = messages.firstIndex(where: { $0.id == id }), messages[index].text.isEmpty {
            messages.remove(at: index)
        }
        replyID = nil
        isStreaming = false
    }

    /// Clears the conversation (the chips stay).
    func newChat() {
        cancel()
        messages = []
        error = nil
        followUps = []
        draft = ""
        askedSuggestionIDs = []
        revision += 1
    }

    private func send(shown: String, sent: String, context: String?, question: SuggestedQuestion?) {
        let text = CoachText.clamp(sent.trimmingCharacters(in: .whitespacesAndNewlines), to: CoachLimits.maxUserChars)
        guard !text.isEmpty else { return }
        if isStreaming { cancel() }
        error = nil
        followUps = []
        let shownText = shown.isEmpty ? text : shown
        let message = CoachMessage(role: .user, text: shownText, sentText: text,
                                   context: context.map { CoachText.clamp($0, to: CoachLimits.maxContextChars) },
                                   question: question)
        let history = messages
        messages.append(message)
        revision += 1
        startReply(to: message, history: history)
    }

    // MARK: Streaming

    private func startReply(to question: CoachMessage, history: [CoachMessage]) {
        generation += 1
        let current = generation
        isStreaming = true
        replyID = nil
        if isOffline {
            appendReply(CoachConversation.offlineReply, generation: current)
            finishReply(generation: current, followUps: CoachConversation.demoFollowUps)
            return
        }
        if client == nil { client = makeClient() }
        guard let client else {
            failReply(CoachClientError.unavailableMessage, generation: current)
            return
        }
        let turns = CoachConversation.requestTurns(history: history, question: question)
        let asked = question.question
        task = Task { [weak self] in
            do {
                for try await event in client.stream(turns: turns) {
                    guard let self, self.generation == current else { return }
                    switch event {
                    case let .text(text):
                        self.appendReply(text, generation: current)
                    case .done:
                        self.finishReply(generation: current, followUps: self.makeFollowUps(asked))
                    case let .error(_, message):
                        self.failReply(message, generation: current)
                    }
                }
                // The stream closed without saying it was done: keep what arrived, or report the drop.
                guard let self, self.generation == current, self.isStreaming else { return }
                if self.replyText.isEmpty {
                    self.failReply(CoachClientError.offlineMessage, generation: current)
                } else {
                    self.finishReply(generation: current, followUps: self.makeFollowUps(asked))
                }
            } catch is CancellationError {
                return
            } catch let error as CoachClientError {
                self?.failReply(error.message, generation: current)
            } catch {
                self?.failReply(CoachClientError.offlineMessage, generation: current)
            }
        }
    }

    private var replyText: String {
        guard let id = replyID, let message = messages.first(where: { $0.id == id }) else { return "" }
        return message.text
    }

    private func appendReply(_ text: String, generation current: Int) {
        guard current == generation, !text.isEmpty else { return }
        if let id = replyID, let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text += text
        } else {
            let reply = CoachMessage(role: .assistant, text: text, isComplete: false)
            replyID = reply.id
            messages.append(reply)
        }
        revision += 1
    }

    private func finishReply(generation current: Int, followUps next: [SuggestedQuestion]) {
        guard current == generation else { return }
        guard let id = replyID, let index = messages.firstIndex(where: { $0.id == id }),
              !messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            failReply("The coach didn't have an answer that time. Try asking another way.", generation: current)
            return
        }
        messages[index].isComplete = true
        replyID = nil
        task = nil
        isStreaming = false
        followUps = CoachConversation.uniqueChips(next)
        revision += 1
    }

    private func failReply(_ message: String, generation current: Int) {
        guard current == generation else { return }
        if let id = replyID, let index = messages.firstIndex(where: { $0.id == id }), messages[index].text.isEmpty {
            messages.remove(at: index)
        }
        replyID = nil
        task = nil
        isStreaming = false
        error = message
        revision += 1
    }

    // MARK: Building requests

    /// The turns to send: past questions that got a complete reply (oldest dropped first while the
    /// request is over the server's limits), then the new question. Alternates user/assistant, starts
    /// and ends with a user turn. A context is only sent when it differs from the previous one sent
    /// in the request (the coach reads them in order).
    static func requestTurns(history: [CoachMessage], question: CoachMessage) -> [CoachTurn] {
        var exchanges: [(question: CoachMessage, reply: CoachMessage)] = []
        var pending: CoachMessage?
        for message in history {
            switch message.role {
            case .user:
                pending = message
            case .assistant:
                if let asked = pending, message.isComplete,
                   !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !asked.sentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    exchanges.append((asked, message))
                }
                pending = nil
            }
        }
        var start = max(0, exchanges.count - (CoachLimits.maxTurns - 1) / 2)
        while true {
            let turns = buildTurns(Array(exchanges[start...]), question: question)
            if start >= exchanges.count || fits(turns) { return turns }
            start += 1
        }
    }

    private static func buildTurns(_ exchanges: [(question: CoachMessage, reply: CoachMessage)],
                                   question: CoachMessage) -> [CoachTurn] {
        var turns: [CoachTurn] = []
        var lastContext: String?
        func userTurn(_ message: CoachMessage) -> CoachTurn {
            let text = CoachText.clamp(message.sentText, to: CoachLimits.maxUserChars)
            var context = message.context.map { CoachText.clamp($0, to: CoachLimits.maxContextChars) }
            if context?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { context = nil }
            if let current = context {
                if current == lastContext {
                    context = nil
                } else {
                    lastContext = current
                }
            }
            return CoachTurn(role: .user, text: text, context: context)
        }
        for exchange in exchanges {
            turns.append(userTurn(exchange.question))
            turns.append(CoachTurn(role: .assistant, text: CoachText.clamp(exchange.reply.text, to: CoachLimits.maxAssistantChars)))
        }
        turns.append(userTurn(question))
        return turns
    }

    /// Within the turn count, the total characters and the body size (measured on the real JSON).
    static func fits(_ turns: [CoachTurn]) -> Bool {
        guard turns.count <= CoachLimits.maxTurns else { return false }
        let total = turns.reduce(0) { $0 + $1.countedChars }
        guard total <= CoachLimits.targetTotalChars else { return false }
        let body = CoachRequestBody(deviceId: String(repeating: "0", count: 64), turns: turns)
        guard let data = try? JSONEncoder().encode(body) else { return false }
        return data.count <= CoachLimits.targetBodyBytes
    }

    // MARK: Demo

    static let offlineReply = "This is a demo, so the coach is offline here. In a real game I'd answer using your hand and the table."

    static let demoFollowUps: [SuggestedQuestion] = [
        SuggestedQuestion(id: "followUp.why", label: "Why?", prompt: "Why? Explain the reason behind that."),
        SuggestedQuestion(id: "followUp.example", label: "Show an example",
                          prompt: "Show me a short example with real cards."),
    ]

    /// A canned exchange at the table for screenshots. Never touches the network.
    static func demo() -> CoachConversation {
        let conversation = CoachConversation(offline: true)
        conversation.prepare(scope: .table, context: nil, suggestions: [
            SuggestedQuestion(id: "table.whatToPlay", label: "What should I play?",
                              prompt: "It's my turn. What should I play here, and why?"),
            SuggestedQuestion(id: "table.whoIsWinning", label: "Who's winning this trick?",
                              prompt: "Who is winning this trick right now, and why?"),
            SuggestedQuestion(id: "table.whatIsTrump", label: "What's trump right now?",
                              prompt: "What is trump in this round? List the trump order."),
        ])
        let asked = SuggestedQuestion(id: "demo.ruff", label: "When can I ruff?",
                                      prompt: "When am I allowed to ruff, and when is it a good idea?")
        conversation.askedSuggestionIDs = []
        conversation.messages = [
            CoachMessage(role: .user, text: asked.label, sentText: asked.prompt, question: asked),
            CoachMessage(role: .assistant, text: """
                You can **ruff** (毙 bì) when you have no cards left in the suit that was led. \
                Then any trump beats that suit, even a small one: if East leads K♠ and you're out of spades, \
                your 3♥ takes it when hearts are trump.

                It's best when the trick holds points, like that K♠ worth 10. \
                Which suit are you shortest in right now?
                """),
        ]
        conversation.followUps = demoFollowUps
        conversation.revision = 1
        return conversation
    }
}

/// Text helpers for the coach protocol.
enum CoachText {
    /// `text` cut to at most `limit` UTF-16 code units (the server counts like JavaScript),
    /// never splitting a character.
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.utf16.count > limit else { return text }
        var result = ""
        var count = 0
        for character in text {
            let size = String(character).utf16.count
            if count + size > limit { break }
            result.append(character)
            count += size
        }
        return result
    }
}
