import SwiftUI

/// Provider configuration for the local OpenAI-compatible adapter.
/// Secrets are stored in the system keychain and never appear in UI state or exports.
struct ProviderSettingsView: View {
    @State private var config: ProviderConfig?
    @State private var hasAPIKey = false
    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var lastError: String?
    @State private var lastStatus: String?
    @State private var isLoading = true

    private var repository = ProviderConfigRepository()

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Provider") {
                SettingsMetaChip(text: statusChipText)
            }

            statusPanel

            SettingsPanel("OpenAI-Compatible Endpoint") {
                VStack(alignment: .leading, spacing: Theme.spacingLG) {
                    labeledField(
                        label: "Base URL",
                        prompt: "https://api.openai.com/v1",
                        text: $baseURL
                    )

                    labeledField(
                        label: "Model",
                        prompt: "gpt-4o",
                        text: $model
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(Theme.geist(12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.geistMono(12))
                    }

                    if let lastError, !lastError.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.error)
                            Text(lastError)
                                .font(Theme.geist(12))
                                .foregroundStyle(Theme.error)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let lastStatus, !lastStatus.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.accent)
                            Text(lastStatus)
                                .font(Theme.geist(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    HStack {
                        Spacer()

                        Button {
                            Task { await save() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Save Provider Settings")
                                    .font(Theme.geist(12, weight: .semibold))
                            }
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            SettingsPanel("Local Cockpit") {
                LocalModeNote(
                    icon: "lock.fill",
                    title: "Provider secrets stay in Keychain",
                    detail: "API keys are stored in the system keychain and never exposed to the UI, exports, or a vendor backend."
                )
            }
        }
        .task {
            await load()
        }
    }

    private var statusChipText: String {
        guard !isLoading else { return "Loading" }
        let configured = config != nil && hasAPIKey && !baseURL.isEmpty && !model.isEmpty
        return configured ? "Configured" : "Setup Required"
    }

    @ViewBuilder
    private var statusPanel: some View {
        if isLoading {
            SettingsPanel("Status") {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading provider configuration...")
                        .font(Theme.geist(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } else {
            SettingsPanel("Status") {
                VStack(spacing: Theme.spacingSM) {
                    statusRow(label: "Base URL", value: config?.baseURL ?? "Not set", monospace: true)
                    statusRow(label: "Model", value: config?.model ?? "Not set", monospace: true)
                    statusRow(
                        label: "API Key",
                        value: hasAPIKey ? "Configured" : "Missing",
                        valueColor: hasAPIKey ? Theme.accent : Theme.error
                    )
                }
            }
        }
    }

    private func statusRow(label: String, value: String, monospace: Bool = false, valueColor: Color? = nil) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingLG) {
            Text(label)
                .font(Theme.geist(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)

            Spacer(minLength: Theme.spacingLG)

            Text(value)
                .font(monospace ? Theme.geistMono(12, weight: .semibold) : Theme.geist(12, weight: .semibold))
                .foregroundStyle(valueColor ?? Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func labeledField(label: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.geist(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.geistMono(12))
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let loaded = await repository.loadOrCreateDefaultConfig()
        let keyPresent = await repository.apiKey() != nil

        await MainActor.run {
            self.config = loaded
            self.baseURL = loaded.baseURL
            self.model = loaded.model
            self.hasAPIKey = keyPresent
            self.apiKey = ""
            self.lastError = nil
            self.lastStatus = nil
        }
    }

    private func save() async {
        lastError = nil
        lastStatus = nil

        guard !baseURL.isEmpty, URL(string: baseURL) != nil else {
            lastError = "Enter a valid provider base URL."
            return
        }

        guard !model.isEmpty else {
            lastError = "Enter a model name."
            return
        }

        var next = config ?? ProviderConfig.defaultConfig()
        next.baseURL = baseURL
        next.model = model
        next.updatedAt = ISO8601DateFormatter().string(from: Date())

        do {
            try await repository.save(next)
            if !apiKey.isEmpty {
                await repository.setAPIKey(apiKey)
            }
            await load()
            lastStatus = "Provider settings saved."
        } catch {
            lastError = "Failed to save provider settings: \(error.localizedDescription)"
        }
    }
}
