import CoreAudio
import Darwin
import Foundation
import XCTest
@testable import KKvoice

final class DriverInstallerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("kkvoice-driver-installer-tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        try super.tearDownWithError()
    }

    private func makeDummyDriverBundle(at bundleURL: URL, marker: String) throws {
        let macOSDir = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)

        let executableURL = macOSDir.appendingPathComponent("BlackHole")
        try Data("#!/bin/sh\n# \(marker)\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        try Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>Marker</key><string>\(marker)</string></dict></plist>".utf8)
            .write(to: infoURL)
    }

    private static func runLocalShell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw DriverInstallerError.executionFailed(errText)
        }
    }

    private final class AtomicBoolBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Bool

        init(_ initial: Bool = false) {
            self.storage = initial
        }

        var value: Bool {
            get {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                storage = newValue
            }
        }
    }

    func testFreshInstallReinstallWithBackupAndUninstallInTempDirectory() async throws {
        let sourceBundle = tempRoot.appendingPathComponent("Source/KKvoiceMic.driver", isDirectory: true)
        let halDir = tempRoot.appendingPathComponent("HAL", isDirectory: true)
        try makeDummyDriverBundle(at: sourceBundle, marker: "v1-initial")

        let devicePresent = AtomicBoolBox(false)
        let installer1 = DriverInstaller(
            destinationDirectoryURL: halDir,
            bundledDriverURLProvider: { sourceBundle },
            devicePresenceProvider: { devicePresent.value },
            privilegedCommandRunner: { command in
                try Self.runLocalShell(command)
                devicePresent.value = true
            },
            backupTimestampProvider: { "20261116190000" },
            postInstallWaitIterations: 0
        )

        XCTAssertFalse(installer1.isBundleInstalled)
        XCTAssertFalse(installer1.isInstalled)

        // 1. Fresh install into temp HAL directory
        try await installer1.install()
        XCTAssertTrue(installer1.isBundleInstalled)
        XCTAssertTrue(installer1.isInstalled)

        let installedExec = halDir.appendingPathComponent("KKvoiceMic.driver/Contents/MacOS/BlackHole")
        let installedExecContent1 = try String(contentsOf: installedExec, encoding: .utf8)
        XCTAssertTrue(installedExecContent1.contains("v1-initial"))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installedExec.path))

        // 2. Re-install with updated source bundle -> backs up existing driver with timestamp
        try FileManager.default.removeItem(at: sourceBundle)
        try makeDummyDriverBundle(at: sourceBundle, marker: "v2-reinstalled")

        let installer2 = DriverInstaller(
            destinationDirectoryURL: halDir,
            bundledDriverURLProvider: { sourceBundle },
            devicePresenceProvider: { devicePresent.value },
            privilegedCommandRunner: { command in
                try Self.runLocalShell(command)
            },
            backupTimestampProvider: { "20261116190500" },
            postInstallWaitIterations: 0
        )

        try await installer2.install()
        XCTAssertTrue(installer2.isInstalled)

        let backupExec = halDir.appendingPathComponent(
            "KKvoiceMic.driver.previous-20261116190500/Contents/MacOS/BlackHole"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupExec.path))
        let backupContent = try String(contentsOf: backupExec, encoding: .utf8)
        XCTAssertTrue(backupContent.contains("v1-initial"))

        let installedExecContent2 = try String(contentsOf: installedExec, encoding: .utf8)
        XCTAssertTrue(installedExecContent2.contains("v2-reinstalled"))

        // 3. Uninstall removes active bundle while preserving backup
        let uninstaller = DriverInstaller(
            destinationDirectoryURL: halDir,
            bundledDriverURLProvider: { sourceBundle },
            devicePresenceProvider: { devicePresent.value },
            privilegedCommandRunner: { command in
                try Self.runLocalShell(command)
                devicePresent.value = false
            },
            postInstallWaitIterations: 0
        )
        try await uninstaller.uninstall()
        XCTAssertFalse(uninstaller.isBundleInstalled)
        XCTAssertFalse(uninstaller.isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupExec.path))
    }

    func testMissingBundledDriverThrowsBundledDriverNotFound() async {
        let halDir = tempRoot.appendingPathComponent("HAL", isDirectory: true)
        let missingURL = tempRoot.appendingPathComponent("NonExistent/KKvoiceMic.driver", isDirectory: true)
        let installer = DriverInstaller(
            destinationDirectoryURL: halDir,
            bundledDriverURLProvider: { missingURL },
            privilegedCommandRunner: { _ in
                XCTFail("Should not invoke privileged runner when bundled driver is missing")
            },
            postInstallWaitIterations: 0
        )

        do {
            try await installer.install()
            XCTFail("Expected bundledDriverNotFound error")
        } catch let error as DriverInstallerError {
            XCTAssertEqual(error, .bundledDriverNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBuiltBlackHoleDriverExposesExpectedKKvoiceIdentityAndFormat() throws {
        guard let driverURL = DriverInstaller.defaultBundledDriverURL() else {
            throw XCTSkip("KKvoiceMic.driver not built yet")
        }
        let binaryPath = driverURL.appendingPathComponent("Contents/MacOS/BlackHole").path
        guard let handle = dlopen(binaryPath, RTLD_LOCAL | RTLD_LAZY) else {
            XCTFail("Failed to dlopen \(binaryPath): \(String(cString: dlerror()))")
            return
        }
        defer { dlclose(handle) }

        typealias CreateFn = @convention(c) (CFAllocator?, CFUUID?) -> UnsafeMutableRawPointer?
        guard let sym = dlsym(handle, "BlackHole_Create") else {
            XCTFail("Missing BlackHole_Create symbol in \(binaryPath)")
            return
        }
        let create = unsafeBitCast(sym, to: CreateFn.self)
        let audioServerPlugInTypeUUID = CFUUIDGetConstantUUIDWithBytes(
            nil,
            0x44, 0x3A, 0xBA, 0xB8, 0xE7, 0xB3, 0x49, 0x1A,
            0xB9, 0x85, 0xBE, 0xB9, 0x18, 0x70, 0x30, 0xDB
        )
        guard let rawDriver = create(kCFAllocatorDefault, audioServerPlugInTypeUUID) else {
            XCTFail("BlackHole_Create returned nil")
            return
        }
        struct PlugInDriverVTable {
            var _reserved: UnsafeMutableRawPointer?
            var QueryInterface: UnsafeMutableRawPointer?
            var AddRef: UnsafeMutableRawPointer?
            var Release: UnsafeMutableRawPointer?
            var Initialize: UnsafeMutableRawPointer?
            var CreateDevice: UnsafeMutableRawPointer?
            var DestroyDevice: UnsafeMutableRawPointer?
            var AddDeviceClient: UnsafeMutableRawPointer?
            var RemoveDeviceClient: UnsafeMutableRawPointer?
            var PerformDeviceConfigurationChange: UnsafeMutableRawPointer?
            var AbortDeviceConfigurationChange: UnsafeMutableRawPointer?
            var HasProperty: UnsafeMutableRawPointer?
            var IsPropertySettable: UnsafeMutableRawPointer?
            var GetPropertyDataSize: UnsafeMutableRawPointer?
            var GetPropertyData: @convention(c) (
                UnsafeMutableRawPointer,
                AudioObjectID,
                pid_t,
                UnsafePointer<AudioObjectPropertyAddress>,
                UInt32,
                UnsafeRawPointer?,
                UInt32,
                UnsafeMutablePointer<UInt32>,
                UnsafeMutableRawPointer
            ) -> OSStatus
        }

        let driverRef = rawDriver.assumingMemoryBound(
            to: UnsafeMutablePointer<PlugInDriverVTable>?.self
        )
        guard let interfacePtr = driverRef.pointee else {
            XCTFail("Driver interface pointer is nil")
            return
        }

        let kObjectID_Device: AudioObjectID = 3
        let kObjectID_Stream_Input: AudioObjectID = 4
        let kObjectID_Stream_Output: AudioObjectID = 7

        func readCFString(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var outSize: UInt32 = 0
            var unmanaged: Unmanaged<CFString>?
            let status = withUnsafeMutablePointer(to: &unmanaged) { ptr in
                interfacePtr.pointee.GetPropertyData(
                    driverRef,
                    objectID,
                    0,
                    &address,
                    0,
                    nil,
                    UInt32(MemoryLayout<Unmanaged<CFString>?>.size),
                    &outSize,
                    ptr
                )
            }
            guard status == noErr, let cfStr = unmanaged?.takeRetainedValue() else {
                return nil
            }
            return cfStr as String
        }

        XCTAssertEqual(readCFString(kObjectID_Device, kAudioObjectPropertyName), "KKvoice Mic")
        XCTAssertEqual(readCFString(kObjectID_Device, kAudioDevicePropertyDeviceUID), "KKvoiceMi2ch_UID")
        XCTAssertEqual(readCFString(kObjectID_Device, kAudioDevicePropertyModelUID), "KKvoiceMi2ch_ModelUID")

        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var transportSize: UInt32 = 0
        let transportStatus = interfacePtr.pointee.GetPropertyData(
            driverRef,
            kObjectID_Device,
            0,
            &transportAddress,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &transportSize,
            &transportType
        )
        XCTAssertEqual(transportStatus, noErr)
        XCTAssertEqual(transportType, kAudioDeviceTransportTypeUSB)

        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var sampleRate: Float64 = 0
        var rateSize: UInt32 = 0
        let rateStatus = interfacePtr.pointee.GetPropertyData(
            driverRef,
            kObjectID_Device,
            0,
            &rateAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &rateSize,
            &sampleRate
        )
        XCTAssertEqual(rateStatus, noErr)
        XCTAssertEqual(sampleRate, 48_000.0)

        for streamID in [kObjectID_Stream_Input, kObjectID_Stream_Output] {
            var fmtAddress = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var format = AudioStreamBasicDescription()
            var fmtSize: UInt32 = 0
            let fmtStatus = interfacePtr.pointee.GetPropertyData(
                driverRef,
                streamID,
                0,
                &fmtAddress,
                0,
                nil,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                &fmtSize,
                &format
            )
            XCTAssertEqual(fmtStatus, noErr)
            XCTAssertEqual(format.mSampleRate, 48_000.0)
            XCTAssertEqual(format.mChannelsPerFrame, 2)
            XCTAssertEqual(format.mBitsPerChannel, 32)
        }
    }
}
