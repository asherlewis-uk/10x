import SwiftUI

/// Live assistant bubble that keeps a tokenized reveal effect while staying
/// close to the real streamed chunk timing.
struct StreamingAssistantBubble: View {
    let text: String
    var onRenderedTextChange: (String) -> Void = { _ in }

    @State private var receivedText: String = ""
    @State private var renderedText: String = ""
    @State private var pendingTokens: [String] = []
    @State private var streamingTask: Task<Void, Never>?

    var body: some View {
        MarkdownTextView(text: renderedText, animateTransitions: false)
            .equatable()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                applyTextUpdate(text)
                onRenderedTextChange(renderedText)
            }
            .onChange(of: text) { _, newValue in
                applyTextUpdate(newValue)
            }
            .onChange(of: renderedText) { _, newValue in
                onRenderedTextChange(newValue)
            }
            .onDisappear {
                streamingTask?.cancel()
                streamingTask = nil
            }
    }

    private func applyTextUpdate(_ newValue: String) {
        if newValue.isEmpty {
            resetState()
            return
        }

        guard newValue != receivedText else { return }

        if newValue.hasPrefix(receivedText) {
            let delta = String(newValue.dropFirst(receivedText.count))
            receivedText = newValue
            enqueue(delta)
            return
        }

        // If the server restarts the segment or the view is recreated with a
        // different base string, snap to the latest text instead of replaying.
        receivedText = newValue
        renderedText = newValue
        pendingTokens.removeAll()
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func enqueue(_ delta: String) {
        let tokens = tokenize(delta)
        guard !tokens.isEmpty else {
            renderedText = receivedText
            return
        }

        pendingTokens.append(contentsOf: tokens)
        trimAnimatedBacklogIfNeeded()
        startStreamingIfNeeded()
    }

    private func trimAnimatedBacklogIfNeeded() {
        let maxAnimatedBacklog = 120
        let overflow = pendingTokens.count - maxAnimatedBacklog
        guard overflow > 0 else { return }

        renderedText += pendingTokens.prefix(overflow).joined()
        pendingTokens.removeFirst(overflow)
    }

    private func startStreamingIfNeeded() {
        guard streamingTask == nil, !pendingTokens.isEmpty else { return }

        streamingTask = Task { @MainActor in
            while !Task.isCancelled {
                guard !pendingTokens.isEmpty else { break }

                let batchSize = nextBatchSize(for: pendingTokens.count)
                let emitCount = min(batchSize, pendingTokens.count)
                renderedText += pendingTokens.prefix(emitCount).joined()
                pendingTokens.removeFirst(emitCount)

                if pendingTokens.isEmpty {
                    break
                }

                try? await Task.sleep(nanoseconds: nextDelay(for: pendingTokens.count))
            }

            if !Task.isCancelled {
                renderedText = receivedText
            }
            streamingTask = nil
        }
    }

    private func nextBatchSize(for pendingCount: Int) -> Int {
        switch pendingCount {
        case 0...6:
            return 1
        case 7...20:
            return 2
        case 21...48:
            return 3
        case 49...90:
            return 5
        default:
            return 8
        }
    }

    private func nextDelay(for pendingCount: Int) -> UInt64 {
        switch pendingCount {
        case 0...6:
            return 26_000_000
        case 7...20:
            return 18_000_000
        case 21...48:
            return 12_000_000
        case 49...90:
            return 8_000_000
        default:
            return 5_000_000
        }
    }

    private func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        var tokens: [String] = []
        var buffer = ""

        for character in text {
            if character.isWhitespace || character.isNewline || punctuationSet.contains(character) {
                if !buffer.isEmpty {
                    tokens.append(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                tokens.append(String(character))
            } else {
                buffer.append(character)
            }
        }

        if !buffer.isEmpty {
            tokens.append(buffer)
        }

        return tokens
    }

    private var punctuationSet: Set<Character> {
        [".", ",", "!", "?", ";", ":", "\"", "'", "(", ")", "[", "]", "{", "}", "`", "*", "_", "-", "+", "=", "/", "\\", "<", ">"]
    }

    private func resetState() {
        receivedText = ""
        renderedText = ""
        pendingTokens.removeAll()
        streamingTask?.cancel()
        streamingTask = nil
    }
}
