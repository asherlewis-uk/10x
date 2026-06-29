import Foundation
import AppKit

struct PreviewViewEntry: Sendable {
    let viewName: String
    let timestamp: Double
}

struct PreviewLaunchResult: Sendable {
    let screenshotURL: URL
    let initialView: PreviewViewEntry?
}

/// Manages an iOS Simulator for in-app preview: boot, build, install, launch, and screenshot.
actor SimulatorPreviewService {
    static let shared = SimulatorPreviewService()
    private static let minimumIOSMajorVersion = 26
    private static let preferredDeviceNames = ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 17", "iPhone Air"]
    private static let initialViewPollAttempts = 16
    private static let initialViewPollDelayMs = 125
    private static let initialScreenshotSettlingDelayMs = 1500
    private static let initialScreenshotRetryCount = 3
    private static let initialScreenshotRetryDelayMs = 200
    private static let buildCheckTimeoutMs = 90_000
    private static let simulatorBuildTimeoutMs = 150_000
    private static let simulatorLaunchTimeoutMs = 15_000
    private static let simulatorProcessQueryTimeoutMs = 5_000

    private var simulatorUDID: String?
    private var hasAttemptedStartupPrewarm = false
    private var activeProcess: Process?

    /// Resolved path to Xcode's developer directory.
    /// Needed because xcode-select may point to CommandLineTools which lacks simctl.
    private let developerDir: String = {
        let xcodeApp = "/Applications/Xcode.app/Contents/Developer"
        if FileManager.default.fileExists(atPath: xcodeApp) {
            return xcodeApp
        }
        // Fallback to whatever xcode-select reports
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? xcodeApp).trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    // MARK: - Public API

    /// Full preview pipeline: boot sim → build project → install → launch → screenshot.
    /// If `skipBuild` is true, assumes build artifacts are already available (from a prior checkBuild call).
    /// Waits for the first usable frame after launch using view tracking when available.
    func runPreview(
        containerURL: URL,
        containerKind: XcodeContainerKind,
        scheme: String,
        derivedDataURL: URL,
        bundleId: String? = nil,
        environment: [String: String] = [:],
        skipBuild: Bool = false,
        onStatus: (@Sendable (String) async -> Void)? = nil
    ) async throws -> PreviewLaunchResult {
        // Build for simulator (skip if already built via checkBuild)
        if !skipBuild {
            await onStatus?("Building app...")
            try await buildForSimulator(
                containerURL: containerURL,
                containerKind: containerKind,
                scheme: scheme,
                derivedDataURL: derivedDataURL
            )
        }

        await onStatus?("Booting simulator...")
        let simulator = try await findPreferredSimulator()
        try await boot(simulator)
        simulatorUDID = simulator.udid

        // Find the built .app
        let appURL = try findBuiltApp(
            derivedDataURL: derivedDataURL,
            preferredBundleId: bundleId
        )
        let resolvedBundleId = bundleId ?? bundleIdentifier(forBuiltAppAt: appURL)
        guard let resolvedBundleId, !resolvedBundleId.isEmpty else {
            throw SimulatorError.launchFailed("Could not determine the app bundle identifier for launch.")
        }

        // Install and launch
        await onStatus?("Installing app...")
        try await install(appURL: appURL, simulatorUDID: simulator.udid)
        await onStatus?("Launching app...")
        let launchTimestamp = Date().timeIntervalSince1970
        try await launch(
            bundleId: resolvedBundleId,
            simulatorUDID: simulator.udid,
            environment: environment
        )

        await onStatus?("Capturing preview...")
        return try await captureInitialPreview(
            bundleId: resolvedBundleId,
            simulatorUDID: simulator.udid,
            minimumViewTimestamp: launchTimestamp
        )
    }

    /// Best-effort startup warmup so the first preview click does not also pay the full
    /// simulator boot + Simulator.app launch cost. Errors are intentionally swallowed.
    func prewarmOnAppLaunchIfNeeded() async {
        guard !hasAttemptedStartupPrewarm else { return }
        hasAttemptedStartupPrewarm = true

        do {
            let simulator = try await findPreferredSimulator()
            try await boot(simulator)
            simulatorUDID = simulator.udid
        } catch {
            // Preview keeps the user-facing error handling path.
        }
    }

    /// Capture a fresh screenshot of the currently running simulator.
    func captureCurrentScreen() async throws -> URL {
        guard let udid = simulatorUDID else {
            throw SimulatorError.notBooted
        }
        return try await captureScreenshot(simulatorUDID: udid)
    }

    func cancelActiveCommands() {
        guard let activeProcess else { return }
        if activeProcess.isRunning {
            activeProcess.terminate()
        }
        self.activeProcess = nil
    }

    /// Read the current view name written by TenX preview support inside the running app.
    /// Returns (viewName, timestamp) or nil if the log file doesn't exist yet.
    func readCurrentViewName(
        bundleId: String,
        minimumTimestamp: Double? = nil
    ) async -> PreviewViewEntry? {
        guard let udid = simulatorUDID else { return nil }
        guard await isAppRunning(bundleId: bundleId, simulatorUDID: udid) else { return nil }
        guard let logURL = await viewLogURL(bundleId: bundleId, simulatorUDID: udid) else {
            return nil
        }
        return previewViewEntry(at: logURL, minimumTimestamp: minimumTimestamp)
    }

    // MARK: - Simulator Management

    private func boot(_ device: SimulatorDevice) async throws {
        // Boot the simulator
        if device.state != "Booted" {
            let bootResult = try await xcrun(["simctl", "boot", device.udid])
            if bootResult.exitCode != 0 && !bootResult.stderr.contains("current state: Booted") {
                throw SimulatorError.bootFailed(bootResult.stderr)
            }
        }

        let bootStatusResult = try await xcrun(["simctl", "bootstatus", device.udid, "-b"])
        if bootStatusResult.exitCode != 0 {
            throw SimulatorError.bootFailed(bootStatusResult.stderr)
        }

        // Open Simulator.app focused on the selected device instead of whichever device
        // happened to be visible last time the app was launched.
        try await openSimulatorApp(for: device.udid)
    }

    private func findPreferredSimulator() async throws -> SimulatorDevice {
        // List available simulators
        let result = try await xcrun(["simctl", "list", "devices", "available", "-j"])
        guard result.exitCode == 0,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]]
        else {
            throw SimulatorError.noSimulatorFound
        }

        let compatibleDevices = devices
            .flatMap { runtimeIdentifier, deviceList in
                deviceList.compactMap { device -> SimulatorDevice? in
                    guard let name = device["name"] as? String,
                          let udid = device["udid"] as? String,
                          let isAvailable = device["isAvailable"] as? Bool,
                          let state = device["state"] as? String
                    else {
                        return nil
                    }

                    return SimulatorDevice(
                        udid: udid,
                        name: name,
                        runtimeIdentifier: runtimeIdentifier,
                        state: state,
                        isAvailable: isAvailable
                    )
                }
            }
            .filter(isCompatibleIOSSimulator(_:))
            .sorted(by: Self.compareDevices(_:_:))

        if let device = compatibleDevices.first {
            return device
        }

        throw SimulatorError.requiresiOS26
    }

    /// Extract (major, minor) from a runtime identifier like "com.apple.CoreSimulator.SimRuntime.iOS-18-5".
    private static func runtimeVersion(from identifier: String) -> (Int, Int) {
        guard let range = identifier.range(of: "iOS-") else { return (0, 0) }
        let parts = identifier[range.upperBound...].split(separator: "-").compactMap { Int($0) }
        return (parts.count > 0 ? parts[0] : 0, parts.count > 1 ? parts[1] : 0)
    }

    // MARK: - Build

    /// Quick compile check — returns error string if build fails, nil if OK.
    /// Uses `build` with `-destination generic/platform=iOS Simulator` so it doesn't need a booted sim.
    func checkBuild(
        containerURL: URL,
        containerKind: XcodeContainerKind,
        scheme: String,
        derivedDataURL: URL
    ) async throws -> String? {
        let result = try await runXcodebuild(
            containerURL: containerURL,
            containerKind: containerKind,
            scheme: scheme,
            derivedDataURL: derivedDataURL,
            timeoutMs: Self.buildCheckTimeoutMs
        )

        if result.exitCode != 0 {
            let combined = result.stdout + "\n" + result.stderr
            let errorLines = combined
                .components(separatedBy: "\n")
                .filter { $0.contains("error:") }
            return errorLines.isEmpty ? result.stderr : errorLines.joined(separator: "\n")
        }

        return nil
    }

    private func buildForSimulator(
        containerURL: URL,
        containerKind: XcodeContainerKind,
        scheme: String,
        derivedDataURL: URL
    ) async throws {
        let result = try await runXcodebuild(
            containerURL: containerURL,
            containerKind: containerKind,
            scheme: scheme,
            derivedDataURL: derivedDataURL,
            timeoutMs: Self.simulatorBuildTimeoutMs
        )

        if result.exitCode != 0 {
            // Extract meaningful error lines from both stdout and stderr
            let combined = result.stdout + "\n" + result.stderr
            let errors = combined
                .components(separatedBy: "\n")
                .filter { $0.contains("error:") }
                .joined(separator: "\n")
            throw SimulatorError.buildFailed(errors.isEmpty ? result.stderr : errors)
        }
    }

    private func runXcodebuild(
        containerURL: URL,
        containerKind: XcodeContainerKind,
        scheme: String,
        derivedDataURL: URL,
        timeoutMs: Int
    ) async throws -> ShellResult {
        let derivedDataPath = derivedDataURL.path
        let containerArguments: [String]
        switch containerKind {
        case .project:
            containerArguments = ["-project", containerURL.path]
        case .workspace:
            containerArguments = ["-workspace", containerURL.path]
        }

        return try await xcrun([
            "xcodebuild",
            ] + containerArguments + [
            "-scheme", scheme,
            "-sdk", "iphonesimulator",
            "-arch", "arm64",
            "-configuration", "Debug",
            "-derivedDataPath", derivedDataPath,
            "-quiet",
            "build"
        ], timeoutMs: timeoutMs)
    }

    private func findBuiltApp(
        derivedDataURL: URL,
        preferredBundleId: String?
    ) throws -> URL {
        let buildDir = derivedDataURL
            .appendingPathComponent("Build/Products/Debug-iphonesimulator")

        guard let enumerator = FileManager.default.enumerator(
            at: buildDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SimulatorError.appNotFound
        }

        var fallbackAppURL: URL?
        for case let candidate as URL in enumerator {
            guard candidate.pathExtension == "app" else { continue }
            fallbackAppURL = fallbackAppURL ?? candidate
            if let preferredBundleId,
               bundleIdentifier(forBuiltAppAt: candidate) == preferredBundleId {
                return candidate
            }
            enumerator.skipDescendants()
        }

        if let fallbackAppURL {
            return fallbackAppURL
        }

        throw SimulatorError.appNotFound
    }

    private func bundleIdentifier(forBuiltAppAt appURL: URL) -> String? {
        let infoPlistURL = appURL.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any],
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        else {
            return nil
        }

        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Install & Launch

    private func install(appURL: URL, simulatorUDID: String) async throws {
        let result = try await xcrun([
            "simctl", "install", simulatorUDID, appURL.path
        ])
        if result.exitCode != 0 {
            let msg = result.stderr
            if msg.contains("Newer Version") || msg.contains("need 26") {
                throw SimulatorError.requiresiOS26
            }
            throw SimulatorError.installFailed(msg)
        }
    }

    private func launch(
        bundleId: String,
        simulatorUDID: String,
        environment: [String: String]
    ) async throws {
        // Terminate if already running
        _ = try? await xcrun([
            "simctl", "terminate", simulatorUDID, bundleId
        ])

        let simctlChildEnvironment = environment.reduce(into: [String: String]()) { partialResult, entry in
            partialResult["SIMCTL_CHILD_\(entry.key)"] = entry.value
        }
        do {
            let result = try await xcrun(
                ["simctl", "launch", simulatorUDID, bundleId],
                environment: simctlChildEnvironment,
                timeoutMs: Self.simulatorLaunchTimeoutMs
            )
            if result.exitCode == 0 {
                return
            }
            throw SimulatorError.launchFailed(result.stderr)
        } catch {
            if await isAppRunning(bundleId: bundleId, simulatorUDID: simulatorUDID),
               let simulatorError = error as? SimulatorError,
               case .commandTimedOut = simulatorError {
                return
            }
            throw error
        }
    }

    private func isAppRunning(bundleId: String, simulatorUDID: String) async -> Bool {
        guard let result = try? await xcrun(
            ["simctl", "spawn", simulatorUDID, "launchctl", "list"],
            timeoutMs: Self.simulatorProcessQueryTimeoutMs
        ), result.exitCode == 0 else {
            return false
        }

        return result.stdout.contains("UIKitApplication:\(bundleId)[")
            || result.stdout.contains(bundleId)
    }

    // MARK: - Screenshot

    private func captureScreenshot(simulatorUDID: String) async throws -> URL {
        let screenshotDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ElevenX-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshotDir, withIntermediateDirectories: true)

        let screenshotPath = screenshotDir
            .appendingPathComponent("preview-\(UUID().uuidString).png")

        let result = try await xcrun([
            "simctl", "io", simulatorUDID, "screenshot",
            "--type=png",
            screenshotPath.path
        ])

        if result.exitCode != 0 {
            throw SimulatorError.screenshotFailed(result.stderr)
        }

        return screenshotPath
    }

    private func captureInitialPreview(
        bundleId: String,
        simulatorUDID: String,
        minimumViewTimestamp: Double
    ) async throws -> PreviewLaunchResult {
        var initialView = await pollInitialView(
            bundleId: bundleId,
            minimumViewTimestamp: minimumViewTimestamp
        )
        let screenshotURL = try await captureSettledInitialScreenshot(
            bundleId: bundleId,
            simulatorUDID: simulatorUDID,
            minimumViewTimestamp: minimumViewTimestamp,
            initialView: &initialView
        )

        return PreviewLaunchResult(screenshotURL: screenshotURL, initialView: initialView)
    }

    private func viewLogURL(bundleId: String, simulatorUDID: String) async -> URL? {
        let result = try? await xcrun([
            "simctl", "get_app_container", simulatorUDID, bundleId, "data"
        ])
        guard let result, result.exitCode == 0 else { return nil }

        let containerPath = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !containerPath.isEmpty else { return nil }

        return URL(fileURLWithPath: containerPath)
            .appendingPathComponent("Documents/tenx-view-log.json")
    }

    private func previewViewEntry(
        at logURL: URL,
        minimumTimestamp: Double? = nil
    ) -> PreviewViewEntry? {
        guard let data = try? Data(contentsOf: logURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let viewName = json["view"] as? String,
              let timestamp = json["timestamp"] as? Double
        else {
            return nil
        }

        let trimmedViewName = viewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedViewName.isEmpty else { return nil }
        if let minimumTimestamp, timestamp < minimumTimestamp {
            return nil
        }

        return PreviewViewEntry(viewName: trimmedViewName, timestamp: timestamp)
    }

    private func pollInitialView(
        bundleId: String,
        minimumViewTimestamp: Double
    ) async -> PreviewViewEntry? {
        for attempt in 0..<Self.initialViewPollAttempts {
            if let entry = await readCurrentViewName(
                bundleId: bundleId,
                minimumTimestamp: minimumViewTimestamp
            ) {
                return entry
            }
            guard attempt + 1 < Self.initialViewPollAttempts else { break }
            try? await Task.sleep(for: .milliseconds(Self.initialViewPollDelayMs))
        }

        return nil
    }

    private func captureSettledInitialScreenshot(
        bundleId: String,
        simulatorUDID: String,
        minimumViewTimestamp: Double,
        initialView: inout PreviewViewEntry?
    ) async throws -> URL {
        // Let the first screen settle before capturing the preview so we avoid
        // grabbing a mid-transition frame right as the app enters.
        try? await Task.sleep(for: .milliseconds(Self.initialScreenshotSettlingDelayMs))
        if initialView == nil {
            initialView = await readCurrentViewName(
                bundleId: bundleId,
                minimumTimestamp: minimumViewTimestamp
            )
        }

        var screenshotURL = try await captureScreenshot(simulatorUDID: simulatorUDID)
        if initialView == nil {
            initialView = await readCurrentViewName(
                bundleId: bundleId,
                minimumTimestamp: minimumViewTimestamp
            )
        }
        for _ in 0..<Self.initialScreenshotRetryCount {
            guard let image = NSImage(contentsOf: screenshotURL),
                  PreviewScreenHeuristics.shouldIgnore(image) else {
                return screenshotURL
            }

            try? await Task.sleep(for: .milliseconds(Self.initialScreenshotRetryDelayMs))
            screenshotURL = try await captureScreenshot(simulatorUDID: simulatorUDID)
            if initialView == nil {
                initialView = await readCurrentViewName(
                    bundleId: bundleId,
                    minimumTimestamp: minimumViewTimestamp
                )
            }
        }

        return screenshotURL
    }

    // MARK: - Shell Helper

    private struct ShellResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    private final class ShellCaptureState: @unchecked Sendable {
        private let lock = NSLock()
        private var stdoutData = Data()
        private var stderrData = Data()
        private var didResume = false

        func appendStdout(_ chunk: Data) {
            lock.lock()
            stdoutData.append(chunk)
            lock.unlock()
        }

        func appendStderr(_ chunk: Data) {
            lock.lock()
            stderrData.append(chunk)
            lock.unlock()
        }

        func finalize(remainingStdout: Data, remainingStderr: Data) -> (stdout: String, stderr: String) {
            lock.lock()
            stdoutData.append(remainingStdout)
            stderrData.append(remainingStderr)
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            lock.unlock()
            return (stdout, stderr)
        }

        func claimResume() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didResume else { return false }
            didResume = true
            return true
        }
    }

    /// Run xcrun with DEVELOPER_DIR set to Xcode.app so simctl/xcodebuild are found
    /// even when xcode-select points to CommandLineTools.
    private func xcrun(
        _ arguments: [String],
        environment: [String: String] = [:],
        timeoutMs: Int? = nil
    ) async throws -> ShellResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["DEVELOPER_DIR": developerDir].merging(environment) { _, new in new }
            ) { _, new in new }
            process.standardInput = FileHandle.nullDevice

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let captureState = ShellCaptureState()

            @Sendable func finish(_ result: Result<ShellResult, Error>) {
                guard captureState.claimResume() else { return }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                Task { await self.clearActiveProcessIfNeeded(process.processIdentifier) }
                continuation.resume(with: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                captureState.appendStdout(chunk)
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    return
                }
                captureState.appendStderr(chunk)
            }

            process.terminationHandler = { terminatedProcess in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = captureState.finalize(
                    remainingStdout: remainingStdout,
                    remainingStderr: remainingStderr
                )

                finish(.success(
                    ShellResult(
                        stdout: output.stdout,
                        stderr: output.stderr,
                        exitCode: terminatedProcess.terminationStatus
                    )
                ))
            }

            do {
                try process.run()
                self.activeProcess = process
            } catch {
                finish(.failure(error))
                return
            }

            if let timeoutMs {
                DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                    guard process.isRunning else { return }
                    process.terminate()
                    let command = (["xcrun"] + arguments).joined(separator: " ")
                    finish(.failure(SimulatorError.commandTimedOut(command: command, seconds: timeoutMs / 1000)))
                }
            }
        }
    }

    private func clearActiveProcessIfNeeded(_ processIdentifier: Int32) {
        guard activeProcess?.processIdentifier == processIdentifier else { return }
        activeProcess = nil
    }

    private func openSimulatorApp(for udid: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-a",
            "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
            "--args",
            "-CurrentDeviceUDID",
            udid
        ]

        try process.run()
        process.waitUntilExit()
    }

    private func isCompatibleIOSSimulator(_ device: SimulatorDevice) -> Bool {
        let version = Self.runtimeVersion(from: device.runtimeIdentifier)
        return device.isAvailable &&
            device.name.contains("iPhone") &&
            version.0 >= Self.minimumIOSMajorVersion
    }

    private static func compareDevices(_ lhs: SimulatorDevice, _ rhs: SimulatorDevice) -> Bool {
        if lhs.state == "Booted" && rhs.state != "Booted" { return true }
        if lhs.state != "Booted" && rhs.state == "Booted" { return false }

        let lhsVersion = runtimeVersion(from: lhs.runtimeIdentifier)
        let rhsVersion = runtimeVersion(from: rhs.runtimeIdentifier)
        if lhsVersion.0 != rhsVersion.0 { return lhsVersion.0 > rhsVersion.0 }
        if lhsVersion.1 != rhsVersion.1 { return lhsVersion.1 > rhsVersion.1 }

        let lhsPreferred = preferredDeviceNames.firstIndex(where: { lhs.name.contains($0) }) ?? Int.max
        let rhsPreferred = preferredDeviceNames.firstIndex(where: { rhs.name.contains($0) }) ?? Int.max
        if lhsPreferred != rhsPreferred { return lhsPreferred < rhsPreferred }

        return lhs.name < rhs.name
    }
}

private struct SimulatorDevice {
    let udid: String
    let name: String
    let runtimeIdentifier: String
    let state: String
    let isAvailable: Bool
}

// MARK: - Errors

enum SimulatorError: LocalizedError {
    case notBooted
    case noSimulatorFound
    case requiresiOS26
    case commandTimedOut(command: String, seconds: Int)
    case bootFailed(String)
    case buildFailed(String)
    case appNotFound
    case installFailed(String)
    case launchFailed(String)
    case screenshotFailed(String)

    var errorDescription: String? {
        switch self {
        case .notBooted: return "Simulator is not booted"
        case .noSimulatorFound: return "No iPhone simulator found. Install one via Xcode > Settings > Platforms."
        case .requiresiOS26: return """
            iOS 26 Simulator required. To install it:
            1. Open Xcode
            2. Go to Xcode → Settings → Platforms
            3. Click “+” and download the iOS 26 Simulator
            """
        case .commandTimedOut(let command, let seconds):
            return "Timed out after \(seconds) seconds while running: \(command)"
        case .bootFailed(let msg): return "Failed to boot simulator: \(msg)"
        case .buildFailed(let msg): return "Build failed: \(msg)"
        case .appNotFound: return "Built .app not found in DerivedData"
        case .installFailed(let msg): return "Failed to install app: \(msg)"
        case .launchFailed(let msg): return "Failed to launch app: \(msg)"
        case .screenshotFailed(let msg): return "Failed to capture screenshot: \(msg)"
        }
    }
}
