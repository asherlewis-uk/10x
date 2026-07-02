import Foundation

extension BuilderViewModel {
    /// Scan the known legacy 10x project root for importable projects.
    func scanLegacyProjects() async -> [URL] {
        let importer = LegacyTenXProjectImporter()
        return await importer.scanLegacyProjects()
    }

    /// Import a single legacy 10x project folder into 11x.
    func importLegacyProject(from sourceURL: URL) async -> LegacyTenXImportReport {
        do {
            let importer = LegacyTenXProjectImporter()
            let report = try await importer.importProject(from: sourceURL)
            if let project = report.project, !report.alreadyImported {
                projects.removeAll { $0.id == project.id }
                projects.insert(project, at: 0)
            }
            return report
        } catch {
            var report = LegacyTenXImportReport()
            report.errors.append(error.localizedDescription)
            return report
        }
    }

    /// Import a legacy 10x project by URL and then select it in the UI.
    func importAndSelectLegacyProject(from sourceURL: URL, accessToken: String) async -> LegacyTenXImportReport {
        let report = await importLegacyProject(from: sourceURL)
        if let project = report.project, !report.alreadyImported {
            selectProject(project, accessToken: accessToken)
        }
        return report
    }
}
