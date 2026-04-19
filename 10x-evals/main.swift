import Foundation
import Darwin

struct EvalCLI {
    let reporter = StdoutReporter()

    @MainActor
    func run(arguments: [String]) async -> Int32 {
        do {
            let command = try ParsedCommand(arguments: arguments)
            switch command {
            case .help:
                printUsage()
                return 0
            case .run(let suiteURL, let caseID):
                let session = try AppSessionStore().load()
                let suite = try EvalSuite.load(from: suiteURL)
                let runner = EvalRunner(session: session, reporter: reporter)
                let results = try await runner.runSuite(suite, filterCaseID: caseID)
                printSummary(results)
                return 0
            }
        } catch {
            reporter.failure("cli", error.localizedDescription)
            printUsage()
            return 1
        }
    }

    private func printUsage() {
        reporter.line("Usage:")
        reporter.line("  10x-evals run <suite.yml> [--case <id>]")
    }

    private func printSummary(_ results: [EvalRunResult]) {
        reporter.line("")
        reporter.line("Summary")
        for result in results {
            let usedSkillsText = result.usedSkills.isEmpty
                ? "(none)"
                : result.usedSkills.joined(separator: ",")
            reporter.success(
                result.caseID,
                "project=\(result.projectName) path=\(result.projectDirectory.path) plan_saved=\(result.planSaved) preview_captured=\(result.previewCaptured) used_skills=\(usedSkillsText)"
            )
        }
    }
}

enum ParsedCommand {
    case help
    case run(URL, String?)

    init(arguments: [String]) throws {
        var args = arguments.dropFirst()
        guard let first = args.first else {
            self = .help
            return
        }

        if first == "--help" || first == "-h" {
            self = .help
            return
        }

        guard first == "run" else {
            throw CLIError.unsupportedCommand(String(first))
        }
        args = args.dropFirst()

        guard let suitePath = args.first else {
            throw CLIError.missingSuitePath
        }
        args = args.dropFirst()

        var caseID: String?
        while let argument = args.first {
            args = args.dropFirst()
            switch argument {
            case "--case":
                guard let value = args.first else {
                    throw CLIError.missingCaseID
                }
                caseID = String(value)
                args = args.dropFirst()
            default:
                throw CLIError.unexpectedArgument(String(argument))
            }
        }

        self = .run(URL(fileURLWithPath: String(suitePath)), caseID)
    }
}

enum CLIError: LocalizedError {
    case unsupportedCommand(String)
    case missingSuitePath
    case unexpectedArgument(String)
    case missingCaseID

    var errorDescription: String? {
        switch self {
        case .unsupportedCommand(let command):
            return "Unsupported command `\(command)`."
        case .missingSuitePath:
            return "A suite YAML path is required."
        case .unexpectedArgument(let argument):
            return "Unexpected argument `\(argument)`."
        case .missingCaseID:
            return "`--case` requires an id."
        }
    }
}

let exitCode = await EvalCLI().run(arguments: CommandLine.arguments)
Darwin.exit(exitCode)
