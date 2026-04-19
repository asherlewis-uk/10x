import SwiftUI

struct ProjectChatSidebarView: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""
    private let rowHeight: CGFloat = 46
    private let timestampWidth: CGFloat = 36

    private var filteredChats: [BuilderChat] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.chats }

        return viewModel.chats.filter { chat in
            let preview = chat.lastMessagePreview ?? ""
            return chat.name.localizedCaseInsensitiveContains(query)
                || preview.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    if filteredChats.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredChats) { chat in
                            chatRow(chat)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        .frame(width: 304, height: 336)
        .onAppear {
            searchText = ""
            Task { @MainActor in
                isSearchFocused = true
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

            TextField("Search chats", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color.primary.opacity(0.045))
        )
        .padding(8)
    }

    private func chatRow(_ chat: BuilderChat) -> some View {
        let isActive = viewModel.activeChat?.id == chat.id
        let subtitle = chat.lastMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSubtitle = !(subtitle?.isEmpty ?? true)

        return Button {
            viewModel.selectChat(chat)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? Theme.accent : Theme.separator.opacity(0.55))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(chat.name)
                            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text(relativeTimestamp(for: chat.updatedAt))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: timestampWidth, alignment: .trailing)
                    }

                    Text(hasSubtitle ? (subtitle ?? "") : "Preview")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .opacity(hasSubtitle ? 1 : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(minHeight: rowHeight, alignment: .leading)
            .background(rowBackground(isActive: isActive))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canManageChats && !isActive)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textTertiary)

            Text("No chats found")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    @ViewBuilder
    private func rowBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isActive ? Theme.accentSubtle.opacity(0.95) : Color.clear)
    }

    private func relativeTimestamp(for rawValue: String) -> String {
        guard let date = Self.date(from: rawValue) else { return "" }

        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }
        if interval < 3_600 {
            return "\(Int(interval / 60))m"
        }
        if interval < 86_400 {
            return "\(Int(interval / 3_600))h"
        }
        return "\(Int(interval / 86_400))d"
    }

    private static func date(from rawValue: String) -> Date? {
        fractionalFormatter.date(from: rawValue) ?? fallbackFormatter.date(from: rawValue)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter = ISO8601DateFormatter()
}
