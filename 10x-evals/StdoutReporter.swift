import Foundation

struct StdoutReporter {
    func line(_ text: String = "") {
        print(text)
    }

    func heading(_ text: String) {
        line(text)
    }

    func caseEvent(_ caseID: String, _ text: String) {
        line("[\(caseID)] \(text)")
    }

    func success(_ caseID: String, _ text: String) {
        line("[\(caseID)] success: \(text)")
    }

    func failure(_ caseID: String, _ text: String) {
        fputs("[\(caseID)] error: \(text)\n", stderr)
    }
}
