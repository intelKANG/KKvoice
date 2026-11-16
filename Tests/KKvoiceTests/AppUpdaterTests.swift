import Foundation
import XCTest
@testable import KKvoice

@MainActor
final class AppUpdaterTests: XCTestCase {
    private var tempRoot: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kkvoice-app-updater-tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        suiteName = "local.kkvoice.updatertests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    func testSemanticVersionParsingAndComparison() {
        XCTAssertEqual(SemanticVersion("v0.1.0"), SemanticVersion(components: [0, 1, 0]))
        XCTAssertEqual(SemanticVersion("V0.1"), SemanticVersion("0.1.0"))
        XCTAssertEqual(SemanticVersion("0.1.0+build42"), SemanticVersion("0.1.0"))

        XCTAssertLessThan(SemanticVersion("0.1.0")!, SemanticVersion("0.1.1")!)
        XCTAssertLessThan(SemanticVersion("0.1.9")!, SemanticVersion("0.2.0")!)
        XCTAssertLessThan(SemanticVersion("0.9.99")!, SemanticVersion("1.0.0")!)
        XCTAssertLessThan(SemanticVersion("0.1.0-beta.1")!, SemanticVersion("0.1.0")!)
        XCTAssertLessThan(SemanticVersion("0.1.0-beta.1")!, SemanticVersion("0.1.0-beta.2")!)

        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("v"))
        XCTAssertNil(SemanticVersion("0.1.a"))
        XCTAssertNil(SemanticVersion("1..0"))
        XCTAssertNil(SemanticVersion("0.1.0-"))
    }

    func testParseLatestReleasePrioritizesKKvoiceZipAsset() throws {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/intelKANG/KKvoice/releases/tag/v0.2.0",
          "body": "新增自动更新与蓝牙配对提示",
          "assets": [
            {
              "name": "debug-symbols.zip",
              "browser_download_url": "https://example.com/debug-symbols.zip"
            },
            {
              "name": "KKvoice-0.2.0.zip",
              "browser_download_url": "https://example.com/KKvoice-0.2.0.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        let info = try AppUpdater.parseLatestRelease(from: json)
        XCTAssertEqual(info.version, "0.2.0")
        XCTAssertEqual(info.tagName, "v0.2.0")
        XCTAssertEqual(info.assetName, "KKvoice-0.2.0.zip")
        XCTAssertEqual(info.downloadURL.absoluteString, "https://example.com/KKvoice-0.2.0.zip")
        XCTAssertEqual(info.notes, "新增自动更新与蓝牙配对提示")
        XCTAssertEqual(info.htmlURL.absoluteString, "https://github.com/intelKANG/KKvoice/releases/tag/v0.2.0")
    }

    func testParseLatestReleaseThrowsWhenNoZipAssetPresent() {
        let json = """
        {
          "tag_name": "v0.2.0",
          "html_url": "https://github.com/intelKANG/KKvoice/releases/tag/v0.2.0",
          "body": "No zip",
          "assets": [
            {
              "name": "README.md",
              "browser_download_url": "https://example.com/README.md"
            }
          ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try AppUpdater.parseLatestRelease(from: json)) { error in
            XCTAssertEqual(error as? AppUpdaterError, .noDownloadAssetFound)
        }
    }

    func testUserDefaultsPersistenceAndCheckForUpdatesLifecycle() async {
        let releaseJSON = """
        {
          "tag_name": "v0.1.1",
          "html_url": "https://github.com/intelKANG/KKvoice/releases/tag/v0.1.1",
          "body": "修复问题并支持一键更新",
          "assets": [
            {
              "name": "KKvoice-0.1.1.zip",
              "browser_download_url": "https://example.com/KKvoice-0.1.1.zip"
            }
          ]
        }
        """.data(using: .utf8)!

        var promptedRelease: ReleaseInfo?
        let updater = AppUpdater(
            userDefaults: defaults,
            currentVersionProvider: { "0.1.0" },
            releaseDataFetcher: { _ in releaseJSON },
            alertPresenter: { info in
                promptedRelease = info
                return false // User clicks "稍后"
            },
            enablePeriodicTimer: false
        )

        // Defaults: autoCheckUpdates = true, autoInstallUpdates = false
        XCTAssertTrue(updater.autoCheckEnabled)
        XCTAssertFalse(updater.autoDownloadAndInstall)

        updater.autoCheckEnabled = false
        updater.autoDownloadAndInstall = true
        XCTAssertFalse(defaults.bool(forKey: AppUpdater.autoCheckKey))
        XCTAssertTrue(defaults.bool(forKey: AppUpdater.autoInstallKey))

        updater.autoDownloadAndInstall = false
        await updater.checkForUpdatesAsync(userInitiated: true)

        XCTAssertEqual(promptedRelease?.version, "0.1.1")
        XCTAssertTrue(updater.hasUpdateAvailable)
        XCTAssertEqual(updater.availableRelease?.version, "0.1.1")
        if case .updateAvailable(let info) = updater.state {
            XCTAssertEqual(info.version, "0.1.1")
        } else {
            XCTFail("Expected .updateAvailable state, got \(updater.state)")
        }

        // When current version matches remote version -> .upToDate
        let upToDateUpdater = AppUpdater(
            userDefaults: defaults,
            currentVersionProvider: { "0.1.1" },
            releaseDataFetcher: { _ in releaseJSON },
            alertPresenter: { _ in
                XCTFail("Should not prompt when already up to date")
                return false
            },
            enablePeriodicTimer: false
        )
        await upToDateUpdater.checkForUpdatesAsync(userInitiated: true)
        XCTAssertEqual(upToDateUpdater.state, .upToDate(version: "0.1.1"))
        XCTAssertFalse(upToDateUpdater.hasUpdateAvailable)
    }

    func testInstallUpdateExtractsVerifiesBundleAndLaunchesReplacement() async throws {
        // Create a valid signed dummy KKvoice.app inside a zip archive
        let buildArea = tempRoot.appendingPathComponent("build-area", isDirectory: true)
        let dummyApp = buildArea.appendingPathComponent("KKvoice.app", isDirectory: true)
        let macOSDir = dummyApp.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let execURL = macOSDir.appendingPathComponent("KKvoice")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: execURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: execURL.path)

        let infoPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleExecutable</key><string>KKvoice</string>
        <key>CFBundleIdentifier</key><string>local.kkvoice.app</string>
        <key>CFBundleName</key><string>KKvoice</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleShortVersionString</key><string>0.2.0</string>
        <key>CFBundleVersion</key><string>2</string>
        </dict></plist>
        """
        try Data(infoPlist.utf8).write(to: dummyApp.appendingPathComponent("Contents/Info.plist"))

        // Sign dummyApp ad-hoc so codesign --verify --deep --strict passes
        let signProc = Process()
        signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProc.arguments = ["--force", "--deep", "--sign", "-", "--timestamp=none", dummyApp.path]
        try signProc.run()
        signProc.waitUntilExit()
        XCTAssertEqual(signProc.terminationStatus, 0)

        let zipURL = tempRoot.appendingPathComponent("KKvoice-0.2.0.zip")
        let dittoProc = Process()
        dittoProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        dittoProc.arguments = ["-c", "-k", "--keepParent", dummyApp.path, zipURL.path]
        try dittoProc.run()
        dittoProc.waitUntilExit()
        XCTAssertEqual(dittoProc.terminationStatus, 0)

        let currentAppURL = tempRoot.appendingPathComponent("Current/KKvoice.app", isDirectory: true)
        final class LaunchCapture: @unchecked Sendable {
            var launchedTargetPath: String?
            var verifiedStagedAppExists = false
        }
        let capture = LaunchCapture()

        let rootForDownload = tempRoot!
        let updater = AppUpdater(
            userDefaults: defaults,
            currentVersionProvider: { "0.1.0" },
            currentBundleURLProvider: { currentAppURL },
            releaseDataFetcher: { _ in Data() },
            archiveDownloader: { _, onProgress in
                onProgress(0.5)
                onProgress(1.0)
                let copyURL = rootForDownload.appendingPathComponent("downloaded-\(UUID().uuidString).zip")
                try FileManager.default.copyItem(at: zipURL, to: copyURL)
                return copyURL
            },
            bundleVerifier: AppUpdater.verifyExtractedAppBundle,
            installerLauncher: { stagedApp, targetApp, stageRoot in
                capture.verifiedStagedAppExists = FileManager.default.fileExists(
                    atPath: stagedApp.appendingPathComponent("Contents/MacOS/KKvoice").path
                )
                capture.launchedTargetPath = targetApp.path
                let script = AppUpdater.makeRelaunchScript(
                    currentPID: 99999,
                    stagedAppPath: stagedApp.path,
                    targetAppPath: targetApp.path,
                    stagingRootPath: stageRoot.path
                )
                XCTAssertTrue(script.contains("/usr/bin/ditto"))
                XCTAssertTrue(script.contains("/usr/bin/open"))
                try? FileManager.default.removeItem(at: stageRoot)
            },
            enablePeriodicTimer: false
        )

        let releaseInfo = ReleaseInfo(
            version: "0.2.0",
            tagName: "v0.2.0",
            downloadURL: URL(string: "https://example.com/KKvoice-0.2.0.zip")!,
            assetName: "KKvoice-0.2.0.zip",
            notes: "Update notes",
            htmlURL: AppUpdater.releasesPageURL
        )

        await updater.installUpdateAsync(releaseInfo)
        XCTAssertTrue(capture.verifiedStagedAppExists)
        XCTAssertEqual(capture.launchedTargetPath, currentAppURL.path)
        XCTAssertEqual(updater.state, .installing(version: "0.2.0"))
    }

    func testVerifyExtractedAppBundleRejectsWrongBundleIdentifier() throws {
        let wrongApp = tempRoot.appendingPathComponent("Wrong.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: wrongApp.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        let wrongPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.malicious.other</string>
        </dict></plist>
        """
        try Data(wrongPlist.utf8).write(to: wrongApp.appendingPathComponent("Contents/Info.plist"))

        XCTAssertThrowsError(
            try AppUpdater.verifyExtractedAppBundle(
                at: wrongApp,
                currentBundleURL: URL(fileURLWithPath: "/Applications/KKvoice.app")
            )
        ) { error in
            XCTAssertEqual(error as? AppUpdaterError, .bundleIdentifierMismatch(found: "com.malicious.other"))
        }
    }
}
