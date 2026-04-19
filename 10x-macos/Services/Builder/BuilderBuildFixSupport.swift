import Foundation

enum BuilderBuildFixSupport {
    static func automaticBuildFixErrorMessage(from error: Error) -> String? {
        guard let simulatorError = error as? SimulatorError else {
            return nil
        }

        switch simulatorError {
        case .buildFailed,
             .commandTimedOut,
             .appNotFound,
             .installFailed,
             .launchFailed:
            return simulatorError.localizedDescription
        case .notBooted,
             .noSimulatorFound,
             .requiresiOS26,
             .bootFailed,
             .screenshotFailed:
            return nil
        }
    }

    static func isBuildCheckCommand(_ inputPreview: String) -> Bool {
        let lowercased = inputPreview.lowercased()
        return lowercased.contains("xcodebuild")
            || lowercased.contains("swift build")
            || lowercased.contains("swiftc")
    }

    static func extractCompilerDiagnostics(from text: String) -> String? {
        let errorLines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter {
                !$0.isEmpty
                    && ($0.contains("error:")
                        || $0.contains("Build input file cannot be found")
                        || $0.contains("Command SwiftCompile failed"))
            }

        guard !errorLines.isEmpty else { return nil }
        return Array(errorLines.prefix(12)).joined(separator: "\n")
    }

    static func normalizedSignature(for error: String) -> String {
        error
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
