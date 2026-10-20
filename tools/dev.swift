import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum Profile: String {
    case dev
    case devFast = "dev-fast"

    var swiftArguments: [String] {
        switch self {
        case .dev:
            return ["-Xswiftc", "-gnone"]
        case .devFast:
            return [
                "-Xswiftc", "-O",
                "-Xswiftc", "-no-whole-module-optimization",
                "-Xswiftc", "-assert-config",
                "-Xswiftc", "Debug"
            ]
        }
    }
}

struct SourceFile: Equatable {
    let path: String
    let contents: Data?
}

struct ManagedApp {
    let process: Process
}

struct StuckLaunchError: LocalizedError {
    let process: Process
    let versionPath: URL
    let cleanupFailure: String

    var errorDescription: String? {
        "Nervegear failed readiness and remains running because cleanup failed: \(cleanupFailure)"
    }
}

enum DriverError: LocalizedError {
    case usage
    case initialBuildFailed
    case invalidExecutablePath
    case readinessTimeout(String)
    case exitedBeforeReady(Int32)
    case processDidNotStop(String)
    case signalFailure(String, Int32)
    case binPathFailure(Int32)
    case missingBinPath

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: .work/dev/driver --profile dev|dev-fast"
        case .initialBuildFailed:
            return "the initial Nervegear build failed"
        case .invalidExecutablePath:
            return "could not locate the repository root from the driver path"
        case .readinessTimeout(let path):
            return "Nervegear did not create its ready file before timeout: \(path)"
        case .exitedBeforeReady(let status):
            return "Nervegear exited before readiness with status \(status)"
        case .processDidNotStop(let name):
            return "\(name) did not exit after SIGTERM within the graceful shutdown timeout"
        case .signalFailure(let name, let code):
            return "could not signal \(name): errno \(code)"
        case .binPathFailure(let status):
            return "swift build --show-bin-path failed with status \(status)"
        case .missingBinPath:
            return "swift build --show-bin-path returned no binary directory"
        }
    }
}

final class DevDriver {
    private let root: URL
    private let profile: Profile
    private let fileManager = FileManager.default
    private let pollInterval: TimeInterval = 0.25
    private let debounceInterval: TimeInterval = 0.5
    private let readinessTimeout: TimeInterval = 20
    private let gracefulStopTimeout: TimeInterval = 8
    private let sessionPath = ".work/dev/session.json"
    private var activeApp: ManagedApp?
    private var activeVersionPath: URL?
    private var pendingRestoreVersion: URL?
    private var versionSequence: UInt64 = 0

    init(root: URL, profile: Profile) {
        self.root = root
        self.profile = profile
    }

    func run() throws {
        try prepareDirectories()
        var observedSignature = try sourceSignature()
        var lastChangeAt = Date()
        var attemptedSignature: [SourceFile]?

        while true {
            reportUnexpectedExit()
            let currentSignature = try sourceSignature()
            if currentSignature != observedSignature {
                observedSignature = currentSignature
                lastChangeAt = Date()
            }

            let initialBuild = attemptedSignature == nil
            let changedSinceAttempt = attemptedSignature != currentSignature
            let debounced = Date().timeIntervalSince(lastChangeAt) >= debounceInterval
            if initialBuild || (changedSinceAttempt && debounced) {
                attemptedSignature = currentSignature
                let buildSucceeded = runBuild()
                let afterBuild = try sourceSignature()

                if afterBuild != observedSignature {
                    observedSignature = afterBuild
                    lastChangeAt = Date()
                }

                if buildSucceeded && afterBuild == currentSignature {
                    do {
                        try installCurrentBuild(signature: currentSignature)
                    } catch {
                        writeError("could not install successful build: \(error.localizedDescription)")
                        guard activeApp != nil || activeVersionPath != nil else { throw error }
                    }
                } else if buildSucceeded {
                    writeError("build superseded by source changes; keeping the current app running")
                } else if initialBuild && afterBuild == currentSignature && activeVersionPath == nil {
                    throw DriverError.initialBuildFailed
                }
            }

            Thread.sleep(forTimeInterval: pollInterval)
        }
    }

    private func prepareDirectories() throws {
        for path in [
            ".work/tmp",
            ".work/build/\(profile.rawValue)",
            ".work/dev/versions",
            ".work/dev/ready"
        ] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private func sourceSignature() throws -> [SourceFile] {
        let packageURL = root.appendingPathComponent("Package.swift")
        var files = [SourceFile(path: "Package.swift", contents: try optionalContents(at: packageURL))]
        let sourcesURL = root.appendingPathComponent("Sources", isDirectory: true)

        if let enumerator = fileManager.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let relativePath = String(fileURL.path.dropFirst(root.path.count + 1))
                files.append(SourceFile(path: relativePath, contents: try optionalContents(at: fileURL)))
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func optionalContents(at url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func runBuild() -> Bool {
        writeOutput("building Nervegear (\(profile.rawValue))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "build",
            "--product", "Nervegear",
            "--scratch-path", ".work/build/\(profile.rawValue)",
            "--configuration", "debug"
        ] + profile.swiftArguments
        process.currentDirectoryURL = root
        process.environment = buildEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            writeError("could not start SwiftPM build: \(error.localizedDescription)")
            return false
        }

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            writeError("build failed with status \(process.terminationStatus); unchanged sources will not be retried")
            return false
        }
        return true
    }

    private func buildEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = ".work/tmp"
        return environment
    }

    private func installCurrentBuild(signature: [SourceFile]) throws {
        guard try sourceSignature() == signature else {
            writeError("build superseded before installation; keeping the current app running")
            return
        }

        guard let buildDirectory = try buildDirectory() else {
            throw DriverError.missingBinPath
        }
        let builtBinary = buildDirectory.appendingPathComponent("Nervegear")
        let versionPath = try saveImmutableVersion(from: builtBinary)

        guard try sourceSignature() == signature else {
            writeError("build superseded before restart; keeping the current app running")
            try removeVersion(versionPath)
            return
        }

        let previousVersion = activeVersionPath
        if let previousApp = activeApp {
            do {
                try stop(previousApp.process, name: "running Nervegear")
            } catch {
                try removeVersion(versionPath)
                throw error
            }
            activeApp = nil
        }

        do {
            let candidate = try launchAndWaitForReadiness(versionPath, name: "candidate Nervegear")
            activeApp = ManagedApp(process: candidate)
            activeVersionPath = versionPath
            pendingRestoreVersion = nil
            pruneVersions(keeping: [versionPath, previousVersion].compactMap { $0 })
            writeOutput("Nervegear ready from \(versionPath.path)")
        } catch {
            writeError("candidate failed: \(error.localizedDescription)")
            if let stuckLaunch = error as? StuckLaunchError {
                activeApp = ManagedApp(process: stuckLaunch.process)
                if let previousVersion {
                    pendingRestoreVersion = previousVersion
                    writeError("previous Nervegear will be restored after the failed candidate exits")
                } else {
                    writeError("no previous Nervegear version is available to restore")
                    throw error
                }
                return
            }
            guard let previousVersion else {
                throw error
            }
            do {
                let restored = try launchAndWaitForReadiness(previousVersion, name: "previous Nervegear")
                activeApp = ManagedApp(process: restored)
                pendingRestoreVersion = nil
                try removeVersion(versionPath)
                pruneVersions(keeping: [previousVersion])
                writeOutput("restored Nervegear from \(previousVersion.path)")
            } catch {
                if let stuckLaunch = error as? StuckLaunchError {
                    activeApp = ManagedApp(process: stuckLaunch.process)
                } else {
                    activeApp = nil
                    activeVersionPath = nil
                }
                writeError("could not restore previous Nervegear: \(error.localizedDescription)")
            }
        }
    }

    private func buildDirectory() throws -> URL? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "build",
            "--show-bin-path",
            "--scratch-path", ".work/build/\(profile.rawValue)",
            "--configuration", "debug"
        ]
        process.currentDirectoryURL = root
        process.environment = buildEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.standardError

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw DriverError.binPathFailure(process.terminationStatus)
        }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw DriverError.missingBinPath }
        return URL(fileURLWithPath: path, relativeTo: root).standardizedFileURL
    }

    private func saveImmutableVersion(from binary: URL) throws -> URL {
        versionSequence &+= 1
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let identifier = "\(ProcessInfo.processInfo.processIdentifier)-\(timestamp)-\(versionSequence)"
        let destination = root.appendingPathComponent(".work/dev/versions/Nervegear-\(profile.rawValue)-\(identifier)")
        try fileManager.copyItem(at: binary, to: destination)
        return destination
    }

    private func launchAndWaitForReadiness(_ versionPath: URL, name: String) throws -> Process {
        versionSequence &+= 1
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
        let identifier = "\(ProcessInfo.processInfo.processIdentifier)-\(timestamp)-\(versionSequence)"
        let relativeReadyPath = ".work/dev/ready/\(identifier).ready"
        let readyURL = root.appendingPathComponent(relativeReadyPath)
        let process = Process()
        process.executableURL = versionPath
        process.arguments = [
            "--session", sessionPath,
            "--ready-file", relativeReadyPath
        ]
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        let deadline = Date().addingTimeInterval(readinessTimeout)
        while Date() < deadline {
            if !process.isRunning {
                process.waitUntilExit()
                removeReadyFile(readyURL)
                throw DriverError.exitedBeforeReady(process.terminationStatus)
            }
            if fileManager.fileExists(atPath: readyURL.path) {
                removeReadyFile(readyURL)
                return process
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        if process.isRunning {
            do {
                try stop(process, name: name)
            } catch {
                removeReadyFile(readyURL)
                throw StuckLaunchError(
                    process: process,
                    versionPath: versionPath,
                    cleanupFailure: error.localizedDescription
                )
            }
        }
        removeReadyFile(readyURL)
        throw DriverError.readinessTimeout(relativeReadyPath)
    }

    private func stop(_ process: Process, name: String) throws {
        guard process.isRunning else {
            process.waitUntilExit()
            return
        }

        if kill(process.processIdentifier, SIGTERM) != 0 {
            let code = errno
            if code != ESRCH { throw DriverError.signalFailure(name, code) }
        }

        if waitForExit(process, timeout: gracefulStopTimeout) {
            process.waitUntilExit()
            return
        }

        throw DriverError.processDidNotStop(name)
    }

    private func waitForExit(_ process: Process, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !process.isRunning
    }

    private func reportUnexpectedExit() {
        guard let app = activeApp, !app.process.isRunning else { return }
        app.process.waitUntilExit()
        writeError("Nervegear exited with status \(app.process.terminationStatus)")
        activeApp = nil

        guard let previousVersion = pendingRestoreVersion else { return }
        pendingRestoreVersion = nil
        do {
            let restored = try launchAndWaitForReadiness(previousVersion, name: "previous Nervegear")
            activeApp = ManagedApp(process: restored)
            pruneVersions(keeping: [previousVersion])
            writeOutput("restored Nervegear from \(previousVersion.path)")
        } catch {
            if let stuckLaunch = error as? StuckLaunchError {
                activeApp = ManagedApp(process: stuckLaunch.process)
            }
            writeError("could not restore previous Nervegear: \(error.localizedDescription)")
        }
    }

    private func removeReadyFile(_ url: URL) {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            writeError("could not remove ready file \(url.path): \(error.localizedDescription)")
        }
    }

    private func removeVersion(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func pruneVersions(keeping paths: [URL]) {
        let directory = root.appendingPathComponent(".work/dev/versions", isDirectory: true)
        let keep = Set(paths.map(\.standardizedFileURL.path))
        do {
            let versions = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            for version in versions where version.lastPathComponent.hasPrefix("Nervegear-\(profile.rawValue)-") {
                guard !keep.contains(version.standardizedFileURL.path) else { continue }
                try removeVersion(version)
            }
        } catch {
            writeError("could not prune old Nervegear versions: \(error.localizedDescription)")
        }
    }

    private func writeOutput(_ message: String) {
        FileHandle.standardOutput.write(Data("dev: \(message)\n".utf8))
    }

    private func writeError(_ message: String) {
        FileHandle.standardError.write(Data("dev: \(message)\n".utf8))
    }
}

func parseArguments() throws -> (Profile, URL) {
    var profile: Profile?
    var index = 1

    while index < CommandLine.arguments.count {
        let flag = CommandLine.arguments[index]
        guard index + 1 < CommandLine.arguments.count else { throw DriverError.usage }
        let value = CommandLine.arguments[index + 1]
        switch flag {
        case "--profile":
            guard let parsed = Profile(rawValue: value), profile == nil else { throw DriverError.usage }
            profile = parsed
        default:
            throw DriverError.usage
        }
        index += 2
    }

    guard let profile else { throw DriverError.usage }

    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: workingDirectory).standardizedFileURL
    let root: URL
    if executable.lastPathComponent == "dev.swift" {
        root = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    } else {
        root = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
    guard root.path != "/" else { throw DriverError.invalidExecutablePath }
    return (profile, root)
}

do {
    let (profile, root) = try parseArguments()
    try DevDriver(root: root, profile: profile).run()
} catch {
    FileHandle.standardError.write(Data("dev: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
