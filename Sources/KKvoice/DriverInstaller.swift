import AppKit
import Foundation
import RemoteAudio

public enum DriverInstallerError: LocalizedError, Equatable {
    case bundledDriverNotFound
    case userCancelled
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bundledDriverNotFound:
            return "未找到内置的 KKvoice Mic 驱动，请重新下载完整应用。"
        case .userCancelled:
            return "已取消管理员授权。"
        case .executionFailed(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "驱动操作失败。" : "驱动操作失败：\(trimmed)"
        }
    }
}

public struct DriverInstaller: Sendable {
    public static let driverBundleName = "KKvoiceMic.driver"
    public static let executableRelativePath = "Contents/MacOS/BlackHole"
    public static let deviceUID = "KKvoiceMi2ch_UID"
    public static let deviceName = "KKvoice Mic"
    public static let defaultDestinationDirectoryURL = URL(
        fileURLWithPath: "/Library/Audio/Plug-Ins/HAL",
        isDirectory: true
    )

    public static let shared = DriverInstaller()

    public let destinationDirectoryURL: URL
    private let bundledDriverURLProvider: @Sendable () -> URL?
    private let devicePresenceProvider: (@Sendable () -> Bool)?
    private let privilegedCommandRunner: @Sendable (String) async throws -> Void
    private let backupTimestampProvider: @Sendable () -> String
    private let postInstallWaitIterations: Int

    public init(
        destinationDirectoryURL: URL = DriverInstaller.defaultDestinationDirectoryURL,
        bundledDriverURLProvider: @escaping @Sendable () -> URL? = DriverInstaller.defaultBundledDriverURL,
        devicePresenceProvider: (@Sendable () -> Bool)? = nil,
        privilegedCommandRunner: @escaping @Sendable (String) async throws -> Void = DriverInstaller.runAdminShellCommand,
        backupTimestampProvider: @escaping @Sendable () -> String = DriverInstaller.defaultTimestampString,
        postInstallWaitIterations: Int = 25
    ) {
        self.destinationDirectoryURL = destinationDirectoryURL
        self.bundledDriverURLProvider = bundledDriverURLProvider
        self.devicePresenceProvider = devicePresenceProvider
        self.privilegedCommandRunner = privilegedCommandRunner
        self.backupTimestampProvider = backupTimestampProvider
        self.postInstallWaitIterations = postInstallWaitIterations
    }

    public var destinationURL: URL {
        destinationDirectoryURL.appendingPathComponent(Self.driverBundleName, isDirectory: true)
    }

    public var bundledDriverURL: URL? {
        bundledDriverURLProvider()
    }

    public var isBundleInstalled: Bool {
        let executableURL = destinationURL.appendingPathComponent(Self.executableRelativePath)
        return FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    public var isDeviceAvailable: Bool {
        if let devicePresenceProvider {
            return devicePresenceProvider()
        }
        if destinationDirectoryURL.standardizedFileURL == Self.defaultDestinationDirectoryURL.standardizedFileURL {
            return Self.defaultDevicePresence()
        }
        return isBundleInstalled
    }

    /// Returns true when the KKvoiceMic.driver bundle is installed and the KKvoiceMi2ch_UID virtual mic is available.
    public var isInstalled: Bool {
        isBundleInstalled && isDeviceAvailable
    }

    public static var isInstalled: Bool {
        shared.isInstalled
    }

    public static var isBundleInstalled: Bool {
        shared.isBundleInstalled
    }

    public static var isDeviceAvailable: Bool {
        shared.isDeviceAvailable
    }

    public static var bundledDriverURL: URL? {
        shared.bundledDriverURL
    }

    public static func install() async throws {
        try await shared.install()
    }

    public static func uninstall() async throws {
        try await shared.uninstall()
    }

    public func install() async throws {
        guard let sourceURL = bundledDriverURL,
              FileManager.default.fileExists(atPath: sourceURL.appendingPathComponent(Self.executableRelativePath).path) else {
            throw DriverInstallerError.bundledDriverNotFound
        }

        let stageRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kkvoice-driver.\(UUID().uuidString)", isDirectory: true)
        let stagedDriverURL = stageRoot.appendingPathComponent(Self.driverBundleName, isDirectory: true)

        try FileManager.default.createDirectory(
            at: stageRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        defer {
            try? FileManager.default.removeItem(at: stageRoot)
        }

        try Self.copyBundleWithDitto(from: sourceURL, to: stagedDriverURL)

        let timestamp = backupTimestampProvider()
        let backupURL = destinationDirectoryURL.appendingPathComponent(
            "\(Self.driverBundleName).previous-\(timestamp)",
            isDirectory: true
        )
        let isSystemDestination =
            destinationDirectoryURL.standardizedFileURL == Self.defaultDestinationDirectoryURL.standardizedFileURL

        let command = Self.makeInstallShellCommand(
            stagedDriverPath: stagedDriverURL.path,
            destinationDirectoryPath: destinationDirectoryURL.path,
            destinationPath: destinationURL.path,
            backupPath: backupURL.path,
            chownRootWheel: isSystemDestination,
            restartCoreAudio: isSystemDestination
        )

        try await privilegedCommandRunner(command)

        if isSystemDestination && postInstallWaitIterations > 0 {
            for _ in 0..<postInstallWaitIterations {
                if isDeviceAvailable {
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    public func uninstall() async throws {
        let isSystemDestination =
            destinationDirectoryURL.standardizedFileURL == Self.defaultDestinationDirectoryURL.standardizedFileURL
        guard hasAnyInstalledOrBackupBundles else {
            return
        }
        let command = Self.makeUninstallShellCommand(
            destinationDirectoryPath: destinationDirectoryURL.path,
            destinationPath: destinationURL.path,
            restartCoreAudio: isSystemDestination
        )
        try await privilegedCommandRunner(command)

        if isSystemDestination && postInstallWaitIterations > 0 {
            for _ in 0..<postInstallWaitIterations {
                if !isDeviceAvailable {
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private var hasAnyInstalledOrBackupBundles: Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            return true
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: destinationDirectoryURL.path) else {
            return false
        }
        return entries.contains { $0.hasPrefix("\(Self.driverBundleName).previous") }
    }

    // MARK: - Command Builders

    internal static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    internal static func appleScriptStringEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    internal static func makeInstallShellCommand(
        stagedDriverPath: String,
        destinationDirectoryPath: String,
        destinationPath: String,
        backupPath: String,
        chownRootWheel: Bool,
        restartCoreAudio: Bool
    ) -> String {
        let staged = shellSingleQuoted(stagedDriverPath)
        let destDir = shellSingleQuoted(destinationDirectoryPath)
        let dest = shellSingleQuoted(destinationPath)
        let backup = shellSingleQuoted(backupPath)
        let executable = shellSingleQuoted((destinationPath as NSString).appendingPathComponent(executableRelativePath))

        var steps: [String] = [
            "/bin/mkdir -p \(destDir)",
            "if [ -e \(dest) ]; then /bin/mv \(dest) \(backup) && { /usr/bin/ditto \(staged) \(dest) || { /bin/rm -rf \(dest); /bin/mv \(backup) \(dest); exit 1; }; }; else /usr/bin/ditto \(staged) \(dest); fi"
        ]

        if chownRootWheel {
            steps.append("/usr/sbin/chown -R root:wheel \(dest)")
        }

        steps.append("/usr/bin/find \(dest) -type d -exec /bin/chmod 755 {} \\;")
        steps.append("/usr/bin/find \(dest) -type f -exec /bin/chmod 644 {} \\;")
        steps.append("/bin/chmod 755 \(executable)")

        if restartCoreAudio {
            steps.append("(/usr/bin/killall -9 coreaudiod || /usr/bin/killall coreaudiod || true)")
        }

        return steps.joined(separator: " && ")
    }

    internal static func makeUninstallShellCommand(
        destinationDirectoryPath: String,
        destinationPath: String,
        restartCoreAudio: Bool
    ) -> String {
        let destDir = shellSingleQuoted(destinationDirectoryPath)
        let dest = shellSingleQuoted(destinationPath)
        let backupPattern = shellSingleQuoted("\(driverBundleName).previous*")
        var steps: [String] = [
            "/bin/rm -rf \(dest)",
            "if [ -d \(destDir) ]; then /usr/bin/find \(destDir) -maxdepth 1 -name \(backupPattern) -exec /bin/rm -rf {} +; fi"
        ]
        if restartCoreAudio {
            steps.append("(/usr/bin/killall -9 coreaudiod || /usr/bin/killall coreaudiod || true)")
        }
        return steps.joined(separator: " && ")
    }

    // MARK: - Default Providers

    @Sendable
    public static func defaultBundledDriverURL() -> URL? {
        let fm = FileManager.default
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent(driverBundleName, isDirectory: true)
            if fm.fileExists(atPath: bundled.appendingPathComponent(executableRelativePath).path) {
                return bundled
            }
        }

        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            repoRoot.appendingPathComponent("dist/KKvoice.app/Contents/Resources/\(driverBundleName)", isDirectory: true),
            repoRoot.appendingPathComponent(".build/\(driverBundleName)", isDirectory: true)
        ]

        for candidate in candidates {
            if fm.fileExists(atPath: candidate.appendingPathComponent(executableRelativePath).path) {
                return candidate
            }
        }
        return nil
    }

    @Sendable
    public static func defaultDevicePresence() -> Bool {
        guard let devices = try? KKAudioOutputDevices.list() else {
            return false
        }
        return devices.contains(where: { $0.uid == deviceUID })
    }

    @Sendable
    public static func defaultTimestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: Date())
    }

    private static func copyBundleWithDitto(from sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [sourceURL.path, destinationURL.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "ditto exit \(process.terminationStatus)"
            throw DriverInstallerError.executionFailed(errText)
        }
    }

    @Sendable
    public static func runAdminShellCommand(_ command: String) async throws {
        let escaped = appleScriptStringEscaped(command)
        let scriptSource = "do shell script \"\(escaped)\" with administrator privileges"

        try await Task.detached(priority: .userInitiated) {
            if let appleScript = NSAppleScript(source: scriptSource) {
                var errorDict: NSDictionary?
                _ = appleScript.executeAndReturnError(&errorDict)
                if errorDict == nil {
                    return
                }
                if let errorDict {
                    let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int
                    let errorMessage = (errorDict[NSAppleScript.errorMessage] as? String)
                        ?? (errorDict[NSAppleScript.errorBriefMessage] as? String)
                        ?? "未知错误"
                    if errorNumber == -128 || errorMessage.localizedCaseInsensitiveContains("cancel") || errorMessage.contains("取消") {
                        throw DriverInstallerError.userCancelled
                    }
                    throw DriverInstallerError.executionFailed(errorMessage)
                }
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", scriptSource]
            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errText = (String(data: errData, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if errText.contains("-128") || errText.localizedCaseInsensitiveContains("cancel") || errText.contains("取消") {
                    throw DriverInstallerError.userCancelled
                }
                throw DriverInstallerError.executionFailed(errText.isEmpty ? "osascript exit \(process.terminationStatus)" : errText)
            }
        }.value
    }
}
