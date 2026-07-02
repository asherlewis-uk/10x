import SwiftUI

/// Storage settings: show database, assets, and export paths with
/// Copy Path and Reveal in Finder actions.
struct StorageSettingsView: View {
    @State private var databasePath = ""
    @State private var assetStoragePath = ""
    @State private var exportPath = ""
    @State private var showLegacyImportSheet = false
    @State private var copiedKey: String? = nil

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader("Storage") {
                SettingsMetaChip(text: "Local")
            }

            LocalModeNote(
                icon: "internaldrive.fill",
                title: "Everything lives on this Mac",
                detail: "Database, assets, and exports are stored under the 11x Application Support directory."
            )

            SettingsPanel("Paths") {
                VStack(spacing: Theme.spacingSM) {
                    pathRow(
                        label: "Database",
                        path: databasePath,
                        key: "database"
                    )

                    pathRow(
                        label: "Assets",
                        path: assetStoragePath,
                        key: "assets"
                    )

                    pathRow(
                        label: "Exports",
                        path: exportPath,
                        key: "exports"
                    )
                }
            }

            SettingsPanel("Legacy Projects") {
                VStack(alignment: .leading, spacing: Theme.spacingSM) {
                    Text("Import projects created by the original 10x app from ~/Library/Developer/TenXApp/. Imported projects are copied; the originals are not modified.")
                        .font(Theme.geist(12))
                        .foregroundStyle(Theme.textSecondary)

                    Button {
                        showLegacyImportSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                            Text("Import Legacy 10x Projects")
                                .font(Theme.geist(12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.spacingMD)
                        .padding(.vertical, Theme.spacingSM)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                .fill(Theme.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.radiusSM, style: .continuous)
                                        .stroke(Theme.separator, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, Theme.spacingSM)
            }
        }
        .sheet(isPresented: $showLegacyImportSheet) {
            LegacyTenXImportSheet()
        }
        .task {
            await loadPaths()
        }
    }

    private func pathRow(label: String, path: String, key: String) -> some View {
        SettingsInsetRow {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: Theme.spacingLG) {
                    Text(label)
                        .font(Theme.geist(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)

                    Spacer()

                    HStack(spacing: Theme.spacingSM) {
                        copyPathButton(path: path, key: key)
                        revealButton(path: path)
                    }
                }

                Text(path.isEmpty ? "Unavailable" : path)
                    .font(Theme.geistMono(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private func copyPathButton(path: String, key: String) -> some View {
        Button {
            guard !path.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) {
                copiedKey = key
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.15)) {
                    if copiedKey == key { copiedKey = nil }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copiedKey == key ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                Text(copiedKey == key ? "Copied" : "Copy")
                    .font(Theme.geist(10, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .overlay(
                        Capsule()
                            .stroke(Theme.separator, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(path.isEmpty)
    }

    private func revealButton(path: String) -> some View {
        Button {
            guard !path.isEmpty,
                  FileManager.default.fileExists(atPath: path) else { return }
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                Text("Reveal")
                    .font(Theme.geist(10, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Theme.surfaceElevated)
                    .overlay(
                        Capsule()
                            .stroke(Theme.separator, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(path.isEmpty)
    }

    private func loadPaths() async {
        let dbURL = CockpitDatabase.defaultDatabaseURL()
        let assetURL = LocalAssetStorage.defaultAssetRootURL()
        let exportURL = AppIdentity.appSupportDirectory
            .appendingPathComponent(LocalAssetKind.export.directoryName, isDirectory: true)

        await MainActor.run {
            databasePath = dbURL.path
            assetStoragePath = assetURL.path
            exportPath = exportURL.path
        }
    }
}

#Preview {
    StorageSettingsView()
        .frame(width: 760, height: 400)
}
