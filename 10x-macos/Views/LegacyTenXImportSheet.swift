import SwiftUI

/// Sheet for scanning and importing legacy 10x projects from the local Mac.
struct LegacyTenXImportSheet: View {
    @Environment(BuilderViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [URL] = []
    @State private var isScanning = true
    @State private var isImporting: Set<String> = []
    @State private var errorMessage: String?
    @State private var showReport = false
    @State private var reportForSheet: LegacyTenXImportReport?
    @State private var showErrorAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isScanning {
                    ProgressView("Scanning legacy 10x projects…")
                        .padding()
                } else if candidates.isEmpty {
                    emptyView
                } else {
                    candidateList
                }
            }
            .frame(minWidth: 520, minHeight: 340)
            .navigationTitle("Import from 10x")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        chooseFolderManually()
                    } label: {
                        Label("Choose Folder…", systemImage: "folder.badge.plus")
                    }
                }
            }
        }
        .task {
            await scan()
        }
        .sheet(isPresented: $showReport) {
            if let report = reportForSheet {
                LegacyTenXImportReportView(report: report)
            }
        }
        .alert("Import Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.spacingMD) {
            Image(systemName: "folder.circle")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textTertiary)
            Text("No legacy 10x projects found")
                .font(Theme.geist(15, weight: .semibold))
            Text("11x scans ~/Library/Developer/TenXApp/ automatically. You can also choose a legacy project folder manually.")
                .font(Theme.geist(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.spacingLG)
            Button("Choose Folder…") {
                chooseFolderManually()
            }
            .padding(.top, Theme.spacingSM)
        }
        .padding()
    }

    private var candidateList: some View {
        List(candidates, id: \.path) { url in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent)
                        .font(Theme.geist(13, weight: .semibold))
                    Text(url.path)
                        .font(Theme.geistMono(11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    importCandidate(url)
                } label: {
                    if isImporting.contains(url.path) {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Import")
                            .font(Theme.geist(11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isImporting.contains(url.path))
            }
            .padding(.vertical, 4)
        }
    }

    private func scan() async {
        isScanning = true
        candidates = await viewModel.scanLegacyProjects()
        isScanning = false
    }

    private func chooseFolderManually() {
        let panel = NSOpenPanel()
        panel.title = "Import Legacy 10x Project"
        panel.message = "Choose a legacy 10x project folder."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let importer = LegacyTenXProjectImporter()
        guard importer.isLegacyProjectCandidate(at: url) else {
            errorMessage = "The selected folder does not look like a legacy 10x project."
            showErrorAlert = true
            return
        }

        importCandidate(url)
    }

    private func importCandidate(_ url: URL) {
        isImporting.insert(url.path)
        errorMessage = nil

        Task {
            let report = await viewModel.importLegacyProject(from: url)
            await MainActor.run {
                isImporting.remove(url.path)
                if report.succeeded, !report.alreadyImported {
                    dismiss()
                } else if !report.errors.isEmpty {
                    errorMessage = report.errors.joined(separator: "\n")
                    showErrorAlert = true
                } else {
                    reportForSheet = report
                    showReport = true
                }
            }
        }
    }
}

/// Simple read-only summary of a legacy import.
private struct LegacyTenXImportReportView: View {
    let report: LegacyTenXImportReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingMD) {
                    if report.alreadyImported {
                        statusRow(icon: "checkmark.circle.fill", color: .orange, text: "Already imported")
                        if let previousId = report.previousProjectId {
                            Text("Existing 11x project id: \(previousId)")
                                .font(Theme.geistMono(11))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else if report.succeeded {
                        statusRow(icon: "checkmark.circle.fill", color: .green, text: "Import succeeded")
                    } else {
                        statusRow(icon: "exclamationmark.triangle.fill", color: .red, text: "Import failed")
                    }

                    if let project = report.project {
                        Text(project.name)
                            .font(Theme.geist(15, weight: .semibold))
                    }

                    Group {
                        Text("Copied source files: \(report.copiedSourceFiles.count)")
                        Text("Copied assets/docs: \(report.copiedAssetFiles.count)")
                        Text("Imported messages: \(report.importedMessageCount)")
                        Text("Imported plan: \(report.importedPlan ? "Yes" : "No")")
                        Text("Imported tasks: \(report.importedTasks ? "Yes" : "No")")
                    }
                    .font(Theme.geist(12))
                    .foregroundStyle(Theme.textSecondary)

                    if !report.unavailable.isEmpty {
                        Text("Unavailable")
                            .font(Theme.geist(12, weight: .semibold))
                            .padding(.top, Theme.spacingXS)
                        ForEach(report.unavailable, id: \.self) { item in
                            Text("• \(item)")
                                .font(Theme.geist(11))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    if !report.errors.isEmpty {
                        Text("Errors")
                            .font(Theme.geist(12, weight: .semibold))
                            .padding(.top, Theme.spacingXS)
                        ForEach(report.errors, id: \.self) { error in
                            Text("• \(error)")
                                .font(Theme.geist(11))
                                .foregroundStyle(Theme.error)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Import Report")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 320)
    }

    private func statusRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(Theme.geist(13, weight: .semibold))
            Spacer()
        }
    }
}
