import SwiftUI

/// Inline question card displayed in the chat flow.
/// Keeps the interaction compact and stable so question changes do not feel like modal swaps.
struct InlineQuestionView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(AuthManager.self) private var auth
    @State private var freeformInput = ""
    @State private var selectedOptions: Set<String> = []
    @State private var selectedSingleOption: String?
    @State private var reservedCardHeight: CGFloat = 0
    @FocusState private var isFreeformFocused: Bool

    let question: AskUserQuestion
    let questionIndex: Int
    let totalQuestions: Int
    let currentAnswer: String?
    let canGoBack: Bool

    private enum Layout {
        static let cardPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 10
        static let rowSpacing: CGFloat = 6
        static let rowHorizontalPadding: CGFloat = 10
        static let rowVerticalPadding: CGFloat = 8
        static let footerSpacing: CGFloat = 8
        static let fieldMinHeight: CGFloat = 60
        static let fieldMaxHeight: CGFloat = 88
    }

    private var options: [String] {
        question.options ?? []
    }

    private var hasOptions: Bool {
        !options.isEmpty
    }

    private var trimmedFreeformInput: String {
        freeformInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var progressLabel: String {
        "\(max(questionIndex, 1)) / \(max(totalQuestions, 1))"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
            .fill(Theme.accent.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusMD, style: .continuous)
                    .stroke(Theme.accent.opacity(0.10), lineWidth: 1)
            }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
            .fill(Color.white.opacity(0.03))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
    }

    private var canContinue: Bool {
        if question.multiSelect {
            return !selectedOptions.isEmpty
        }

        if hasOptions {
            return !trimmedFreeformInput.isEmpty || selectedSingleOption != nil
        }

        return !trimmedFreeformInput.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            header

            if hasOptions {
                optionList
            }

            if !hasOptions || !question.multiSelect {
                freeformComposer
            }

            footer
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: reservedCardHeight == 0 ? nil : reservedCardHeight, alignment: .topLeading)
        .background(cardBackground)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        reserveHeight(proxy.size.height)
                    }
                    .onChange(of: proxy.size.height) { _, newValue in
                        reserveHeight(newValue)
                    }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            loadCurrentAnswer()
        }
        .onChange(of: questionIndex) { _, _ in
            loadCurrentAnswer()
        }
        .onChange(of: currentAnswer) { _, _ in
            loadCurrentAnswer()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.spacingXS) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)

                Text("QUESTION")
                    .font(Theme.geistMono(10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)

                Spacer(minLength: 8)

                Text(progressLabel)
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(question.question)
                .font(Theme.geist(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var optionList: some View {
        VStack(alignment: .leading, spacing: Layout.rowSpacing) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                optionRow(
                    title: option,
                    number: index + 1,
                    isSelected: question.multiSelect ? selectedOptions.contains(option) : selectedSingleOption == option
                ) {
                    if question.multiSelect {
                        toggleOption(option)
                    } else {
                        selectSingleOption(option)
                    }
                }
            }
        }
    }

    private func optionRow(
        title: String,
        number: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(number).")
                    .font(Theme.geistMono(10, weight: .medium))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18, alignment: .trailing)

                Text(title)
                    .font(Theme.geist(13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                selectionBadge
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, Layout.rowHorizontalPadding)
            .padding(.vertical, Layout.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                rowBackground
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .fill(Theme.accent.opacity(0.08))
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
                        }
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectionBadge: some View {
        Text("Selected")
            .font(Theme.geist(9.5, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(Theme.accent.opacity(0.10))
            }
    }

    private var freeformComposer: some View {
        Group {
            if hasOptions {
                TextField("Something else…", text: $freeformInput, axis: .vertical)
                    .font(Theme.geist(13))
                    .foregroundStyle(Theme.textPrimary)
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                    .focused($isFreeformFocused)
                    .onChange(of: freeformInput) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            selectedSingleOption = nil
                        }
                    }
                    .onSubmit {
                        submitCurrentSelection()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(fieldBackground)
            } else {
                ZStack(alignment: .topLeading) {
                    if freeformInput.isEmpty {
                        Text("Type your answer…")
                            .font(Theme.geist(13))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $freeformInput)
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: Layout.fieldMinHeight, maxHeight: Layout.fieldMaxHeight)
                        .focused($isFreeformFocused)
                        .onKeyPress(.return, phases: .down) { keyPress in
                            if keyPress.modifiers.contains(.shift) {
                                return .ignored
                            }
                            submitCurrentSelection()
                            return .handled
                        }
                }
                .padding(2)
                .background(fieldBackground)
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
            .fill(Theme.surfaceInset)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            }
    }

    private var footer: some View {
        HStack(spacing: Layout.footerSpacing) {
            if canGoBack {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(Theme.geist(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.04))
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            Button {
                skip()
            } label: {
                HStack(spacing: 8) {
                    Text("Dismiss")
                        .font(Theme.geist(11, weight: .medium))

                    Text("ESC")
                        .font(Theme.geistMono(9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                        }
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                submitCurrentSelection()
            } label: {
                HStack(spacing: 6) {
                    Text("Continue")
                        .font(Theme.geist(11, weight: .semibold))

                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(canContinue ? Theme.accent : Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func selectSingleOption(_ option: String) {
        selectedSingleOption = option
        freeformInput = ""
        isFreeformFocused = false
    }

    private func toggleOption(_ option: String) {
        if selectedOptions.contains(option) {
            selectedOptions.remove(option)
        } else {
            selectedOptions.insert(option)
        }
    }

    private func submitCurrentSelection() {
        guard canContinue else { return }

        if question.multiSelect {
            let orderedSelection = options.filter { selectedOptions.contains($0) }
            respond(orderedSelection.joined(separator: ", "))
            return
        }

        if hasOptions {
            if !trimmedFreeformInput.isEmpty {
                respond(trimmedFreeformInput)
            } else if let selectedSingleOption {
                respond(selectedSingleOption)
            }
            return
        }

        respond(trimmedFreeformInput)
    }

    private func loadCurrentAnswer() {
        let restoredAnswer = currentAnswer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let optionSet = Set(options)

        freeformInput = restoredAnswer
        selectedOptions = []
        selectedSingleOption = nil

        if question.multiSelect {
            let restoredSelections = restoredAnswer
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            selectedOptions = Set(options.filter { restoredSelections.contains($0) })
            return
        }

        if hasOptions {
            if optionSet.contains(restoredAnswer) {
                selectedSingleOption = restoredAnswer
                freeformInput = ""
            } else if !restoredAnswer.isEmpty {
                DispatchQueue.main.async {
                    isFreeformFocused = true
                }
            }
            return
        }

        if restoredAnswer.isEmpty {
            DispatchQueue.main.async {
                isFreeformFocused = true
            }
        }
    }

    private func respond(_ answer: String) {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else { return }

        Task { @MainActor in
            guard let token = await auth.validAccessToken() else { return }
            freeformInput = ""
            selectedOptions = []
            selectedSingleOption = nil
            viewModel.answerCurrentQuestion(trimmedAnswer, accessToken: token)
        }
    }

    private func skip() {
        Task { @MainActor in
            guard let token = await auth.validAccessToken() else { return }
            viewModel.skipCurrentQuestion(accessToken: token)
        }
    }

    private func goBack() {
        viewModel.goToPreviousQuestion()
    }

    private func reserveHeight(_ newValue: CGFloat) {
        let sanitized = ceil(newValue)
        guard sanitized > reservedCardHeight else { return }
        reservedCardHeight = sanitized
    }
}
