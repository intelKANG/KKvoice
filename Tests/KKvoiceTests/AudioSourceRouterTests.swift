import XCTest
import CoreAudio
import RemoteAudio
@testable import KKvoice

private final class MockOutput: RemoteAudioOutput {
    var selectedUID: String?
    var renderCallback: ((Int) -> [Float])?
    var startCount = 0
    var stopCount = 0

    func start(
        deviceUID: String,
        sampleRate: Int,
        channels: Int,
        render: @escaping (Int) -> [Float]
    ) throws {
        selectedUID = deviceUID
        renderCallback = render
        startCount += 1
    }

    func stop() {
        stopCount += 1
        renderCallback = nil
        selectedUID = nil
    }
}

private final class MockInputDriver: MacMicrophoneInputDriver {
    var startedUID: String?
    var startCount = 0
    var stopCount = 0
    var lastStopError: String? = nil
    var onInputCallback: ((UnsafePointer<AudioBufferList>, AudioStreamBasicDescription) -> Void)?

    func start(
        deviceUID: String,
        onInput: @escaping (UnsafePointer<AudioBufferList>, AudioStreamBasicDescription) -> Void
    ) throws {
        startedUID = deviceUID
        startCount += 1
        onInputCallback = onInput
    }

    func stop() {
        stopCount += 1
        startedUID = nil
        onInputCallback = nil
    }
}

final class AudioSourceRouterTests: XCTestCase {
    func testInputDeviceCatalogExcludesVirtualDevicesAndFallsBackToBuiltIn() {
        let builtIn = KKAudioInputDevice(
            uid: "BuiltInMicrophoneDevice",
            name: "MacBook Pro麦克风",
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
        let externalUSB = KKAudioInputDevice(
            uid: "USB-Mic-1",
            name: "Shure MV7",
            transportType: kAudioDeviceTransportTypeUSB
        )
        let kkvoiceVirtual = KKAudioInputDevice(
            uid: "KKvoiceMi2ch_UID",
            name: "KKvoice Mic",
            transportType: kAudioDeviceTransportTypeVirtual
        )
        let blackHoleVirtual = KKAudioInputDevice(
            uid: "BlackHole2ch_UID",
            name: "BlackHole 2ch",
            transportType: kAudioDeviceTransportTypeVirtual
        )

        // When system default is KKvoice Mic, "系统默认" must fall back to built-in mic.
        let resolvedWhenDefaultIsKKvoice = KKInputDeviceCatalog.resolve(
            selectedUID: "",
            available: [externalUSB, builtIn, kkvoiceVirtual, blackHoleVirtual],
            systemDefaultUID: "KKvoiceMi2ch_UID"
        )
        XCTAssertEqual(resolvedWhenDefaultIsKKvoice, builtIn)

        // When system default is a physical USB mic, "系统默认" follows it.
        let resolvedWhenDefaultIsUSB = KKInputDeviceCatalog.resolve(
            selectedUID: "",
            available: [builtIn, externalUSB],
            systemDefaultUID: "USB-Mic-1"
        )
        XCTAssertEqual(resolvedWhenDefaultIsUSB, externalUSB)

        // When a specific physical UID is chosen, use it.
        let resolvedExplicit = KKInputDeviceCatalog.resolve(
            selectedUID: "USB-Mic-1",
            available: [builtIn, externalUSB],
            systemDefaultUID: "BuiltInMicrophoneDevice"
        )
        XCTAssertEqual(resolvedExplicit, externalUSB)
    }

    func testMacMicrophoneBufferResamplingAndZeroingOnStop() {
        let buffer = MacMicrophonePCMBuffer(capacityFrames: 48)
        let session = UUID()

        // 16 kHz mono -> 48 kHz stereo (3 stereo frames = 6 floats per input sample).
        buffer.start(session: session, inputSampleRate: 16_000)
        XCTAssertTrue(buffer.appendMonoFloats([0.0, 0.6], sampleRate: 16_000, session: session))
        let rendered = buffer.render(frameCount: 6, session: session)
        XCTAssertEqual(rendered.count, 12)
        XCTAssertEqual(rendered[6], 0.2, accuracy: 0.0001)
        XCTAssertEqual(rendered[7], 0.2, accuracy: 0.0001)
        XCTAssertEqual(rendered[10], 0.6, accuracy: 0.0001)
        XCTAssertEqual(rendered[11], 0.6, accuracy: 0.0001)

        // Stop clears buffer and rejects late frames.
        XCTAssertTrue(buffer.stop(session: session))
        XCTAssertTrue(buffer.render(frameCount: 4, session: session).allSatisfy { $0 == 0 })
        XCTAssertFalse(buffer.appendMonoFloats([1.0], sampleRate: 16_000, session: session))
    }

    func testRouterPersistsMacMicSelectionAndRoutesPerSessionWithoutHotSwap() throws {
        let suiteName = "local.kkvoice.routertests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let builtIn = KKAudioInputDevice(
            uid: "BuiltInMicrophoneDevice",
            name: "MacBook Pro麦克风",
            transportType: kAudioDeviceTransportTypeBuiltIn
        )
        let usbMic = KKAudioInputDevice(
            uid: "USB-Mic-1",
            name: "USB 麦克风",
            transportType: kAudioDeviceTransportTypeUSB
        )

        let output = MockOutput()
        let input = MockInputDriver()
        var permissionStatus: MacMicrophonePermissionStatus = .authorized
        let macSource = MacMicrophoneSource(
            input: input,
            output: output,
            permissionCheck: { permissionStatus },
            permissionRequest: { $0(true) }
        )

        let router = AudioSourceRouter(
            output: output,
            remoteBridge: RemoteAudioBridge(output: output),
            macSource: macSource,
            userDefaults: defaults,
            listDevices: { [builtIn, usbMic] },
            defaultUIDProvider: { "BuiltInMicrophoneDevice" },
            autoRefreshDevices: true
        )

        XCTAssertEqual(router.selectedMacMicUID, "")
        XCTAssertEqual(router.selectedMacMicTitle, "系统默认")
        router.selectMacMic(uid: "USB-Mic-1")
        XCTAssertEqual(defaults.string(forKey: "macMicrophoneUID"), "USB-Mic-1")
        XCTAssertEqual(router.selectedMacMicTitle, "USB 麦克风")

        // Idle: neither Mac mic nor virtual output is open.
        XCTAssertNil(input.startedUID)
        XCTAssertNil(output.selectedUID)
        XCTAssertNil(router.currentSource)

        // Start session when remote is NOT ready -> opens USB-Mic-1 and KKvoiceMi2ch_UID.
        let s1 = UUID()
        let src1 = try router.beginSession(session: s1, virtualDeviceUID: "KKvoiceMi2ch_UID", remoteReady: false)
        XCTAssertEqual(src1, .mac(uid: "USB-Mic-1", name: "USB 麦克风"))
        XCTAssertEqual(router.currentSource, src1)
        XCTAssertEqual(input.startedUID, "USB-Mic-1")
        XCTAssertEqual(output.selectedUID, "KKvoiceMi2ch_UID")

        // End session -> closes and releases both devices.
        _ = router.endSession(session: s1)
        XCTAssertNil(router.currentSource)
        XCTAssertNil(input.startedUID)
        XCTAssertNil(output.selectedUID)

        // Start session when remote IS ready -> uses remote path, never opens Mac mic.
        let s2 = UUID()
        let src2 = try router.beginSession(session: s2, virtualDeviceUID: "KKvoiceMi2ch_UID", remoteReady: true)
        XCTAssertEqual(src2, .remote)
        XCTAssertEqual(router.currentSource, .remote)
        XCTAssertNil(input.startedUID)
        XCTAssertEqual(output.selectedUID, "KKvoiceMi2ch_UID")
        _ = router.endSession(session: s2)
        XCTAssertNil(router.currentSource)

        // Denied permission -> throws 需要麦克风权限 without opening devices.
        permissionStatus = .denied
        XCTAssertThrowsError(
            try router.beginSession(session: UUID(), virtualDeviceUID: "KKvoiceMi2ch_UID", remoteReady: false)
        ) { error in
            XCTAssertEqual(error.localizedDescription, "需要麦克风权限")
        }
        XCTAssertNil(input.startedUID)
        XCTAssertNil(output.selectedUID)
    }
}
