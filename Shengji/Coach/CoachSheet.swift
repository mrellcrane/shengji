import SwiftUI
import ShengjiCore

/// The coach chat, shown as a sheet (medium and large) so the table or the page stays in view.
/// Everything can be done by tapping chips; typing is optional.
@MainActor
struct CoachSheet: View {
    let conversation: CoachConversation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CoachScopeNote(scope: conversation.scope)
                CoachMessageList(conversation: conversation)
                CoachInputBar(conversation: conversation)
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("New chat") {
                conversation.newChat()
            }
            .disabled(conversation.messages.isEmpty && conversation.error == nil)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
                dismiss()
            }
        }
    }
}

/// "Sees your hand and the table" under the title.
@MainActor
private struct CoachScopeNote: View {
    let scope: CoachScope

    var body: some View {
        Label(scope.note, systemImage: scope.systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 6)
            .accessibilityLabel("The coach \(scope.note.lowercased())")
    }
}

/// The bubbles, the typing indicator, an error with Retry, and follow-ups under the latest answer.
@MainActor
private struct CoachMessageList: View {
    let conversation: CoachConversation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bottomID = "coach-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showsEmptyState {
                        CoachEmptyState(scope: conversation.scope)
                    }
                    ForEach(conversation.messages) { message in
                        CoachBubble(message: message)
                    }
                    if conversation.isWaitingForFirstToken {
                        CoachTypingIndicator()
                    }
                    if let error = conversation.error {
                        CoachErrorCard(message: error) {
                            conversation.retry()
                        }
                    }
                    if showsFollowUps {
                        CoachChipRow(chips: conversation.followUps, inset: 0) { chip in
                            conversation.ask(chip)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // Opens on the latest message (a reopened chat, the demo scene) and stays pinned to it as
            // a reply streams in; the scrollTo below follows new questions.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.revision, initial: true) { _, _ in
                if reduceMotion || conversation.isStreaming {
                    proxy.scrollTo(Self.bottomID, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var showsEmptyState: Bool {
        conversation.messages.isEmpty && !conversation.isStreaming && conversation.error == nil
    }

    /// Follow-ups sit under the latest answer once it has finished.
    private var showsFollowUps: Bool {
        !conversation.isStreaming && conversation.error == nil && !conversation.followUps.isEmpty
            && conversation.messages.last?.role == .assistant
    }
}

/// Before the first question: what to do and what the coach can see.
@MainActor
private struct CoachEmptyState: View {
    let scope: CoachScope

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ask me anything about the game", systemImage: "graduationcap.fill")
                .font(.headline)
                .foregroundStyle(Theme.usColor)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.usColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detail: String {
        switch scope {
        case .table:
            return "Tap a question below, or type your own. I can see your hand and the table, never anyone else's cards."
        case .lesson:
            return "Tap a question below, or type your own. I know which page of the lesson you're on."
        case .question:
            return "Tap a question below, or type your own. I know the question you just answered."
        }
    }
}

/// One message: yours on the right, the coach's on the left (with **bold** rendered).
@MainActor
private struct CoachBubble: View {
    let message: CoachMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser {
                Spacer(minLength: 48)
            }
            content
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !isUser {
                Spacer(minLength: 28)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.body)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
        case .assistant:
            RichText(message.text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private var fill: Color {
        switch message.role {
        case .user: return Theme.usColor
        case .assistant: return Color.secondary.opacity(0.13)
        }
    }

    private var accessibilityText: String {
        switch message.role {
        case .user: return "You asked: \(message.text)"
        case .assistant: return "Coach: \(message.text.replacingOccurrences(of: "**", with: ""))"
        }
    }
}

/// Shown until the first words of the reply arrive.
@MainActor
private struct CoachTypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.bold))
                .symbolEffect(.pulse, isActive: !reduceMotion)
            Text("Coach is thinking")
                .font(.footnote)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The coach is typing")
    }
}

/// The error, with Retry.
@MainActor
private struct CoachErrorCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.bubble.fill")
                    .foregroundStyle(Theme.wrong)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wrong.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Suggested questions, a text field and Send, pinned to the bottom of the sheet.
@MainActor
private struct CoachInputBar: View {
    let conversation: CoachConversation

    /// A plain get/set binding (like the rest of the app) rather than `$conversation.draft`, which
    /// would form a key path to a main-actor-isolated property.
    private var draft: Binding<String> {
        Binding(get: { conversation.draft }, set: { conversation.draft = $0 })
    }

    var body: some View {
        VStack(spacing: 8) {
            let chips = conversation.visibleSuggestions
            if !chips.isEmpty {
                CoachChipRow(chips: chips, isEnabled: !conversation.isStreaming) { chip in
                    conversation.ask(chip)
                }
            }
            HStack(spacing: 8) {
                TextField("Ask your own question", text: draft)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(canSend ? Theme.usColor : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var canSend: Bool { conversation.canSendDraft && !conversation.isStreaming }

    private func send() {
        guard canSend else { return }
        conversation.sendDraft()
    }
}

/// Tap-to-ask chips in a horizontal row.
@MainActor
struct CoachChipRow: View {
    let chips: [SuggestedQuestion]
    var isEnabled: Bool = true
    /// Space before the first and after the last chip.
    var inset: CGFloat = 16
    let onTap: (SuggestedQuestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    CoachChip(title: chip.label) {
                        onTap(chip)
                    }
                    .disabled(!isEnabled)
                    .opacity(isEnabled ? 1 : 0.5)
                }
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 2)
        }
    }
}

/// One rounded, tinted question chip.
@MainActor
struct CoachChip: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.usColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// "Ask the coach" for lesson pages and question feedback.
@MainActor
struct CoachAskButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "bubble.left.and.text.bubble.right.fill")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(Theme.usColor)
    }
}
