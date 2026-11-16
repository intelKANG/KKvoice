import AppKit
import Combine
import Foundation

public struct SemanticVersion: Comparable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public let components: [Int]
    public let prerelease: String?

    public init(components: [Int], prerelease: String? = nil) {
        self.components = Self.trimTrailingZeros(components)
        let trimmedPre = prerelease?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prerelease = (trimmedPre?.isEmpty == false) ? trimmedPre : nil
    }

    public init?(_ rawString: String) {
        var cleaned = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        // Strip build metadata (+...)
        if let plusIndex = cleaned.firstIndex(of: "+") {
            cleaned = String(cleaned[..<plusIndex])
        }

        // Split pre-release (-...)
        var prereleasePart: String? = nil
        if let dashIndex = cleaned.firstIndex(of: "-") {
            let afterDash = String(cleaned[cleaned.index(after: dashIndex)...])
            guard !afterDash.isEmpty else { return nil }
            prereleasePart = afterDash
            cleaned = String(cleaned[..<dashIndex])
        }

        let rawParts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard !rawParts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(rawParts.count)
        for part in rawParts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part), value >= 0 else {
                return nil
            }
            parsed.append(value)
        }

        self.init(components: parsed, prerelease: prereleasePart)
    }

    public var description: String {
        let base = (components.isEmpty ? [0] : components).map(String.init).joined(separator: ".")
        if let prerelease {
            return "\(base)-\(prerelease)"
        }
        return base
    }

    private static func trimTrailingZeros(_ values: [Int]) -> [Int] {
        var result = values
        while result.count > 3 && result.last == 0 {
            result.removeLast()
        }
        while result.count < 3 {
            result.append(0)
        }
        return result
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.components == rhs.components && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let maxCount = max(lhs.components.count, rhs.components.count)
        for idx in 0..<maxCount {
            let l = idx < lhs.components.count ? lhs.components[idx] : 0
            let r = idx < rhs.components.count ? rhs.components[idx] : 0
            if l != r {
                return l < r
            }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            // Pre-release has lower precedence than normal release (e.g. 0.1.0-beta < 0.1.0)
            return true
        case (nil, .some):
            return false
        case (.some(let lPre), .some(let rPre)):
            return lPre.localizedStandardCompare(rPre) == .orderedAscending
        }
    }
}

public struct ReleaseInfo: Equatable, Sendable {
    public let version: String
    public let tagName: String
    public let downloadURL: URL
    public let assetName: String
    public let notes: String
    public let htmlURL: URL

    public init(
        version: String,
        tagName: String,
        downloadURL: URL,
        assetName: String = "KKvoice.zip",
        notes: String,
        htmlURL: URL
    ) {
        self.version = version
        self.tagName = tagName
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.notes = notes
        self.htmlURL = htmlURL
    }
}

public enum AppUpdaterError: LocalizedError, Equatable {
    case invalidReleaseResponse
    case noDownloadAssetFound
    case downloadFailed(String)
    case extractionFailed(String)
    case appBundleNotFoundInArchive
    case bundleIdentifierMismatch(found: String?)
    case codeSignatureVerificationFailed(String)
    case teamIdentifierMismatch(expected: String, found: String?)
    case relaunchScriptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReleaseResponse:
            return "无法解析 GitHub 版本信息。"
        case .noDownloadAssetFound:
            return "未在发布版本中找到可下载的 .zip 安装包。"
        case .downloadFailed(let message):
            return "下载更新包失败：\(message)"
        case .extractionFailed(let message):
            return "解压更新包失败：\(message)"
        case .appBundleNotFoundInArchive:
            return "更新压缩包中未找到 KKvoice.app。"
        case .bundleIdentifierMismatch(let found):
            return "更新包校验未通过（Bundle ID 不匹配：\(found ?? "未知")）。"
        case .codeSignatureVerificationFailed(let message):
            return "更新包签名校验未通过：\(message)"
        case .teamIdentifierMismatch(let expected, let found):
            return "更新包开发者团队签名不匹配（期望 \(expected)，实际 \(found ?? "无")）。"
        case .relaunchScriptFailed(let message):
            return "启动更新替换流程失败：\(message)"
        }
    }
}

@MainActor
public final class AppUpdater: ObservableObject {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate(version: String)
        case updateAvailable(ReleaseInfo)
        case downloading(progress: Double, version: String)
        case installing(version: String)
        case failed(String)
    }

    public nonisolated static let autoCheckKey = "autoCheckUpdates"
    public nonisolated static let autoInstallKey = "autoInstallUpdates"
    public nonisolated static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/intelKANG/KKvoice/releases/latest")!
    public nonisolated static let releasesPageURL = URL(string: "https://github.com/intelKANG/KKvoice/releases")!
    public nonisolated static let expectedBundleIdentifier = "local.kkvoice.app"
    public nonisolated static let periodicCheckInterval: TimeInterval = 6 * 3600

    public static let shared = AppUpdater()

    @Published public var autoCheckEnabled: Bool {
        didSet {
            userDefaults.set(autoCheckEnabled, forKey: Self.autoCheckKey)
            if autoCheckEnabled {
                startPeriodicTimer()
            } else {
                stopPeriodicTimer()
            }
        }
    }

    @Published public var autoDownloadAndInstall: Bool {
        didSet {
            userDefaults.set(autoDownloadAndInstall, forKey: Self.autoInstallKey)
        }
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var latestAvailableRelease: ReleaseInfo? = nil

    /// Optional hook set by AppModel so background update prompts/installs do not interrupt active voice recording.
    public var canPresentOrAutoInstall: (() -> Bool)?

    private let userDefaults: UserDefaults
    private let currentVersionProvider: @Sendable () -> String
    private let currentBundleURLProvider: @Sendable () -> URL
    private let releaseDataFetcher: @Sendable (URL) async throws -> Data
    private let archiveDownloader: @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> URL
    private let bundleVerifier: @Sendable (URL, URL) throws -> Void
    private let installerLauncher: @Sendable (URL, URL, URL) throws -> Void
    private let alertPresenter: (@MainActor (ReleaseInfo) -> Bool)?
    private let upToDateAlertPresenter: (@MainActor (String) -> Void)?

    private var periodicTimer: Timer?
    private var activeTask: Task<Void, Never>?

    public init(
        userDefaults: UserDefaults = .standard,
        currentVersionProvider: @escaping @Sendable () -> String = AppUpdater.defaultCurrentVersion,
        currentBundleURLProvider: @escaping @Sendable () -> URL = { Bundle.main.bundleURL },
        releaseDataFetcher: @escaping @Sendable (URL) async throws -> Data = AppUpdater.defaultFetchReleaseData,
        archiveDownloader: @escaping @Sendable (URL, @escaping @Sendable (Double) -> Void) async throws -> URL = AppUpdater.defaultDownloadArchive,
        bundleVerifier: @escaping @Sendable (URL, URL) throws -> Void = AppUpdater.verifyExtractedAppBundle,
        installerLauncher: @escaping @Sendable (URL, URL, URL) throws -> Void = AppUpdater.defaultLaunchReplacementAndTerminate,
        alertPresenter: (@MainActor (ReleaseInfo) -> Bool)? = nil,
        upToDateAlertPresenter: (@MainActor (String) -> Void)? = nil,
        enablePeriodicTimer: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.currentVersionProvider = currentVersionProvider
        self.currentBundleURLProvider = currentBundleURLProvider
        self.releaseDataFetcher = releaseDataFetcher
        self.archiveDownloader = archiveDownloader
        self.bundleVerifier = bundleVerifier
        self.installerLauncher = installerLauncher
        self.alertPresenter = alertPresenter
        self.upToDateAlertPresenter = upToDateAlertPresenter

        if userDefaults.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckEnabled = true
            userDefaults.set(true, forKey: Self.autoCheckKey)
        } else {
            self.autoCheckEnabled = userDefaults.bool(forKey: Self.autoCheckKey)
        }

        if userDefaults.object(forKey: Self.autoInstallKey) == nil {
            self.autoDownloadAndInstall = false
        } else {
            self.autoDownloadAndInstall = userDefaults.bool(forKey: Self.autoInstallKey)
        }

        if enablePeriodicTimer && self.autoCheckEnabled {
            startPeriodicTimer()
        }
    }

    // MARK: - Convenience State Properties for UI

    public var currentVersionString: String {
        currentVersionProvider()
    }

    public var hasUpdateAvailable: Bool {
        if case .updateAvailable = state { return true }
        return latestAvailableRelease != nil
    }

    public var availableRelease: ReleaseInfo? {
        if case .updateAvailable(let info) = state {
            return info
        }
        return latestAvailableRelease
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing:
            return true
        case .idle, .upToDate, .updateAvailable, .failed:
            return false
        }
    }

    public var statusSummaryText: String {
        switch state {
        case .idle:
            return "当前版本 v\(currentVersionString)"
        case .checking:
            return "正在检查更新…"
        case .upToDate(let version):
            return "已是最新版本（v\(version)）"
        case .updateAvailable(let info):
            return "发现新版本 v\(info.version)"
        case .downloading(let progress, let version):
            let pct = Int((min(max(progress, 0.0), 1.0) * 100.0).rounded())
            return "正在下载 v\(version)（\(pct)%）…"
        case .installing(let version):
            return "正在安装 v\(version) 并重启…"
        case .failed(let message):
            return message
        }
    }

    // MARK: - Periodic & Launch Check

    public func scheduleLaunchCheckIfNeeded(delaySeconds: TimeInterval = 3.0) {
        guard autoCheckEnabled else { return }
        Task { @MainActor [weak self] in
            let ns = UInt64(max(delaySeconds, 0) * 1_000_000_000)
            if ns > 0 {
                try? await Task.sleep(nanoseconds: ns)
            }
            guard let self, self.autoCheckEnabled else { return }
            if let canProceed = self.canPresentOrAutoInstall, !canProceed() {
                return
            }
            await self.checkForUpdatesAsync(userInitiated: false)
        }
    }

    private func startPeriodicTimer() {
        stopPeriodicTimer()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: Self.periodicCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoCheckEnabled else { return }
                if let canProceed = self.canPresentOrAutoInstall, !canProceed() {
                    return
                }
                await self.checkForUpdatesAsync(userInitiated: false)
            }
        }
    }

    private func stopPeriodicTimer() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    // MARK: - Check For Updates

    public func checkForUpdates(userInitiated: Bool = true, showUpToDateAlert: Bool = false) {
        guard !isBusy else { return }
        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            await self?.checkForUpdatesAsync(userInitiated: userInitiated, showUpToDateAlert: showUpToDateAlert)
        }
    }

    public func checkForUpdatesAsync(userInitiated: Bool = true, showUpToDateAlert: Bool = false) async {
        guard !isBusy else { return }
        state = .checking
        let currentVersionRaw = currentVersionProvider()
        let currentSemVer = SemanticVersion(currentVersionRaw) ?? SemanticVersion(components: [0, 2, 0])

        do {
            let data = try await releaseDataFetcher(Self.latestReleaseAPIURL)
            let releaseInfo = try Self.parseLatestRelease(from: data)
            guard let remoteSemVer = SemanticVersion(releaseInfo.tagName) ?? SemanticVersion(releaseInfo.version) else {
                throw AppUpdaterError.invalidReleaseResponse
            }

            if remoteSemVer > currentSemVer {
                latestAvailableRelease = releaseInfo
                state = .updateAvailable(releaseInfo)

                let allowedToAct = canPresentOrAutoInstall?() ?? true
                if !userInitiated && autoDownloadAndInstall && allowedToAct {
                    await installUpdateAsync(releaseInfo)
                } else if userInitiated || allowedToAct {
                    let shouldInstall: Bool
                    if let alertPresenter {
                        shouldInstall = alertPresenter(releaseInfo)
                    } else {
                        shouldInstall = presentUpdateAlert(for: releaseInfo)
                    }
                    if shouldInstall {
                        await installUpdateAsync(releaseInfo)
                    }
                }
            } else {
                latestAvailableRelease = nil
                state = .upToDate(version: currentSemVer.description)
                if userInitiated && showUpToDateAlert {
                    if let upToDateAlertPresenter {
                        upToDateAlertPresenter(currentSemVer.description)
                    } else {
                        presentUpToDateAlert(version: currentSemVer.description)
                    }
                }
            }
        } catch {
            if userInitiated {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                state = .failed("检查更新失败：\(message)")
            } else {
                // Silent background checks should not leave an alarming error banner on transient offline states.
                state = latestAvailableRelease.map(State.updateAvailable) ?? .idle
            }
        }
    }

    // MARK: - Install Update

    public func installUpdate(_ info: ReleaseInfo? = nil) {
        guard !isBusy else { return }
        guard let targetInfo = info ?? availableRelease else { return }
        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            await self?.installUpdateAsync(targetInfo)
        }
    }

    public func installUpdateAsync(_ info: ReleaseInfo) async {
        guard !isBusy else { return }
        state = .downloading(progress: 0.0, version: info.version)

        let stageRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kkvoice-update.\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: stageRoot, withIntermediateDirectories: true)

            let zipURL = try await archiveDownloader(info.downloadURL) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: min(max(fraction, 0.0), 1.0), version: info.version)
                    }
                }
            }

            state = .installing(version: info.version)

            let extractDir = stageRoot.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let currentBundleURL = currentBundleURLProvider()
            let verifier = self.bundleVerifier
            let stagedAppURL = try await Task.detached(priority: .userInitiated) {
                try Self.extractZipArchive(zipURL: zipURL, destinationDirectoryURL: extractDir)
                guard let appURL = Self.locateAppBundle(in: extractDir) else {
                    throw AppUpdaterError.appBundleNotFoundInArchive
                }
                try verifier(appURL, currentBundleURL)
                Self.stripQuarantineAttribute(at: appURL)
                return appURL
            }.value

            if zipURL.deletingLastPathComponent().standardizedFileURL != stageRoot.standardizedFileURL {
                try? FileManager.default.removeItem(at: zipURL)
            }

            let targetBundleURL = Self.resolveTargetAppBundleURL(from: currentBundleURL)
            try installerLauncher(stagedAppURL, targetBundleURL, stageRoot)
        } catch {
            try? FileManager.default.removeItem(at: stageRoot)
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
        }
    }

    // MARK: - Release JSON Parsing

    nonisolated public static func parseLatestRelease(from data: Data) throws -> ReleaseInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagNameRaw = json["tag_name"] as? String else {
            throw AppUpdaterError.invalidReleaseResponse
        }
        let tagName = tagNameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let semVer = SemanticVersion(tagName) else {
            throw AppUpdaterError.invalidReleaseResponse
        }

        let notes = (json["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let htmlURLString = (json["html_url"] as? String) ?? releasesPageURL.absoluteString
        let htmlURL = URL(string: htmlURLString) ?? releasesPageURL

        guard let assets = json["assets"] as? [[String: Any]] else {
            throw AppUpdaterError.noDownloadAssetFound
        }

        struct CandidateAsset {
            let name: String
            let url: URL
        }

        let zipAssets: [CandidateAsset] = assets.compactMap { asset in
            guard let name = asset["name"] as? String,
                  name.lowercased().hasSuffix(".zip"),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else {
                return nil
            }
            return CandidateAsset(name: name, url: url)
        }

        let chosen = zipAssets.first(where: { $0.name.lowercased().hasPrefix("kkvoice") }) ?? zipAssets.first
        guard let chosen else {
            throw AppUpdaterError.noDownloadAssetFound
        }

        return ReleaseInfo(
            version: semVer.description,
            tagName: tagName,
            downloadURL: chosen.url,
            assetName: chosen.name,
            notes: notes,
            htmlURL: htmlURL
        )
    }

    // MARK: - Bundle Verification & Replacement Helpers

    @Sendable
    nonisolated public static func verifyExtractedAppBundle(at extractedAppURL: URL, currentBundleURL: URL) throws {
        let infoPlistURL = extractedAppURL.appendingPathComponent("Contents/Info.plist")
        let plist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
        let bundleID = plist?["CFBundleIdentifier"] as? String
        guard bundleID == expectedBundleIdentifier else {
            throw AppUpdaterError.bundleIdentifierMismatch(found: bundleID)
        }

        let verifyResult = try runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", extractedAppURL.path]
        )
        guard verifyResult.exitCode == 0 else {
            let detail = verifyResult.stderr.isEmpty ? verifyResult.stdout : verifyResult.stderr
            throw AppUpdaterError.codeSignatureVerificationFailed(
                detail.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        // If the currently running .app has a valid Apple TeamIdentifier, enforce matching TeamIdentifier.
        if currentBundleURL.pathExtension == "app",
           let currentTeamID = readCodeSignTeamIdentifier(for: currentBundleURL),
           !currentTeamID.isEmpty {
            let newTeamID = readCodeSignTeamIdentifier(for: extractedAppURL)
            guard newTeamID == currentTeamID else {
                throw AppUpdaterError.teamIdentifierMismatch(expected: currentTeamID, found: newTeamID)
            }
        }
    }

    nonisolated public static func readCodeSignTeamIdentifier(for bundleURL: URL) -> String? {
        guard let output = try? runProcess(
            executablePath: "/usr/bin/codesign",
            arguments: ["-dv", "--verbose=2", bundleURL.path]
        ) else {
            return nil
        }
        let combined = output.stderr + "\n" + output.stdout
        for line in combined.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("TeamIdentifier=") {
                let value = String(line.dropFirst("TeamIdentifier=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty && value != "not set" {
                    return value
                }
                return nil
            }
        }
        return nil
    }

    nonisolated internal static func extractZipArchive(zipURL: URL, destinationDirectoryURL: URL) throws {
        let result = try runProcess(
            executablePath: "/usr/bin/ditto",
            arguments: ["-x", "-k", zipURL.path, destinationDirectoryURL.path]
        )
        guard result.exitCode == 0 else {
            throw AppUpdaterError.extractionFailed(
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    nonisolated internal static func locateAppBundle(in directoryURL: URL) -> URL? {
        let fm = FileManager.default
        let direct = directoryURL.appendingPathComponent("KKvoice.app", isDirectory: true)
        if fm.fileExists(atPath: direct.appendingPathComponent("Contents/Info.plist").path) {
            return direct
        }

        guard let enumerator = fm.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }
        for case let candidate as URL in enumerator {
            if candidate.pathExtension == "app",
               fm.fileExists(atPath: candidate.appendingPathComponent("Contents/Info.plist").path) {
                return candidate
            }
        }
        return nil
    }

    nonisolated internal static func stripQuarantineAttribute(at appURL: URL) {
        _ = try? runProcess(
            executablePath: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", appURL.path]
        )
    }

    nonisolated internal static func resolveTargetAppBundleURL(from currentBundleURL: URL) -> URL {
        if currentBundleURL.pathExtension == "app" {
            return currentBundleURL
        }
        return URL(fileURLWithPath: "/Applications/KKvoice.app", isDirectory: true)
    }

    nonisolated internal static func makeRelaunchScript(
        currentPID: Int32,
        stagedAppPath: String,
        targetAppPath: String,
        stagingRootPath: String
    ) -> String {
        let staged = DriverInstaller.shellSingleQuoted(stagedAppPath)
        let target = DriverInstaller.shellSingleQuoted(targetAppPath)
        let targetDir = DriverInstaller.shellSingleQuoted((targetAppPath as NSString).deletingLastPathComponent)
        let stageRoot = DriverInstaller.shellSingleQuoted(stagingRootPath)

        let adminCommand = "/bin/rm -rf \(target) && /usr/bin/ditto \(staged) \(target) && (/usr/bin/xattr -dr com.apple.quarantine \(target) || true)"
        let escapedAdminCommand = DriverInstaller.appleScriptStringEscaped(adminCommand)

        return """
        #!/bin/zsh
        set -euo pipefail
        pid=\(currentPID)
        for _ in {1..60}; do
          if ! kill -0 "$pid" 2>/dev/null; then
            break
          fi
          /bin/sleep 0.25
        done
        if [ -w \(targetDir) ] && ( [ ! -e \(target) ] || [ -w \(target) ] ); then
          /bin/rm -rf \(target)
          /usr/bin/ditto \(staged) \(target)
          /usr/bin/xattr -dr com.apple.quarantine \(target) 2>/dev/null || true
        else
          /usr/bin/osascript -e "do shell script \\"\(escapedAdminCommand)\\" with administrator privileges"
        fi
        /bin/rm -rf \(stageRoot) 2>/dev/null || true
        /usr/bin/open \(target)
        """
    }

    @Sendable
    nonisolated public static func defaultLaunchReplacementAndTerminate(
        stagedAppURL: URL,
        targetAppURL: URL,
        stageRootURL: URL
    ) throws {
        let scriptURL = stageRootURL.appendingPathComponent("relaunch-update.sh")
        let scriptContent = makeRelaunchScript(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            stagedAppPath: stagedAppURL.path,
            targetAppPath: targetAppURL.path,
            stagingRootPath: stageRootURL.path
        )
        try Data(scriptContent.utf8).write(to: scriptURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        process.arguments = ["/bin/zsh", scriptURL.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AppUpdaterError.relaunchScriptFailed(error.localizedDescription)
        }

        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Default Network & Version Providers

    @Sendable
    nonisolated public static func defaultCurrentVersion() -> String {
        if let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return short.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Native/Info.plist")
        if let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
           let short = dict["CFBundleShortVersionString"] as? String {
            return short.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "0.2.1"
    }

    @Sendable
    nonisolated public static func defaultFetchReleaseData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("KKvoice", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdaterError.invalidReleaseResponse
        }
        return data
    }

    @Sendable
    nonisolated public static func defaultDownloadArchive(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("KKvoice", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdaterError.downloadFailed("HTTP 状态异常")
        }

        let expectedLength = response.expectedContentLength
        let destURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("KKvoice-download-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destURL)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(65_536)
        var receivedBytes: Int64 = 0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 65_536 {
                try handle.write(contentsOf: buffer)
                receivedBytes += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expectedLength > 0 {
                    onProgress(Double(receivedBytes) / Double(expectedLength))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            receivedBytes += Int64(buffer.count)
            buffer.removeAll()
        }
        onProgress(1.0)
        return destURL
    }

    // MARK: - Alerts

    @discardableResult
    public func presentUpdateAlert(for info: ReleaseInfo) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 KKvoice v\(info.version)"
        let trimmedNotes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPreview: String
        if trimmedNotes.isEmpty {
            notesPreview = "包含功能改进与问题修复。"
        } else if trimmedNotes.count > 360 {
            notesPreview = String(trimmedNotes.prefix(360)) + "…"
        } else {
            notesPreview = trimmedNotes
        }
        alert.informativeText = "当前版本：v\(currentVersionString)\n最新版本：v\(info.version)\n\n\(notesPreview)"
        alert.addButton(withTitle: "一键更新")
        alert.addButton(withTitle: "稍后")
        alert.window.appearance = AppModel.currentWindowAppearance
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    public func presentUpToDateAlert(version: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "当前已是最新版本"
        alert.informativeText = "KKvoice v\(version) 已是最新发布的版本。"
        alert.addButton(withTitle: "好")
        alert.window.appearance = AppModel.currentWindowAppearance
        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = alert.runModal()
    }

    // MARK: - Subprocess Helper

    private struct ProcessOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    nonisolated private static func runProcess(executablePath: String, arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
