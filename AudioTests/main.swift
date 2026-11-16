import Foundation
import CoreAudio
import AudioToolbox

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func approximately(_ lhs: Float, _ rhs: Float) -> Bool { abs(lhs - rhs) < 0.0001 }
func pcm(_ samples: [Int16]) -> Data {
    var bytes: [UInt8] = []
    for sample in samples {
        let value = UInt16(bitPattern: sample)
        bytes.append(UInt8(value & 0xff)); bytes.append(UInt8(value >> 8))
    }
    return Data(bytes)
}

final class FakeOutput: RemoteAudioOutput {
    var selectedUID = ""
    var render: ((Int) -> [Float])?
    var stopCount = 0
    var fail = false
    func start(deviceUID: String, sampleRate: Int, channels: Int,
               render: @escaping (Int) -> [Float]) throws {
        selectedUID = deviceUID
        expect(sampleRate == 48_000 && channels == 2, "output format")
        self.render = render
        if fail { throw NSError(domain: "test", code: 1) }
    }
    func stop() { stopCount += 1; render = nil }
}

// Keep the same session active across many packet boundaries and render cycles.
do {
    let sink = FakeOutput()
    let bridge = RemoteAudioBridge(output: sink)
    let session = try bridge.start(deviceUID: "test.loopback")
    let packet = pcm(Array(repeating: Int16(8192), count: 320))
    for _ in 0..<500 {
        expect(bridge.receive(packet, session: session), "continuous packet accepted")
        let output = sink.render!(960)
        expect(output.count == 1920 && output.allSatisfy { approximately($0, 0.25) }, "continuous output remains audible")
    }
    expect(bridge.stop(session: session), "continuous session stops")
    print("PASS: ten-second continuous PCM bridge")
}

do {
    let sink = FakeOutput()
    let bridge = RemoteAudioBridge(output: sink, capacityFrames: 6)
    let first = try bridge.start(deviceUID: "user.selected.device")
    expect(sink.selectedUID == "user.selected.device", "selected output passed through")
    expect(bridge.receive(pcm([0, 16384]), session: first), "first packet accepted")
    let six = sink.render!(6)
    expect(six.count == 12, "stereo frame count")
    expect(approximately(six[6], 1.0 / 6.0) && approximately(six[10], 0.5), "linear conversion")
    expect(six[6] == six[7] && six[10] == six[11], "stereo channels")
    expect(sink.render!(2).allSatisfy { $0 == 0 }, "underrun silence")
    expect(!bridge.receive(Data([1]), session: first), "reject incomplete PCM")
    expect(bridge.receive(pcm([16384]), session: first), "packet continuity")
    expect(sink.render!(1).allSatisfy { approximately($0, 0.5) }, "preserve interpolation across packets")
    let oldRender = sink.render!
    expect(bridge.stop(session: first), "first stop")
    expect(oldRender(4).allSatisfy { $0 == 0 }, "stopped callback returns silence")
    expect(!bridge.receive(pcm([32000]), session: first), "late first packet rejected")
    let second = try bridge.start(deviceUID: "user.selected.device")
    expect(!bridge.stop(session: first), "stale stop must not cancel new session")
    expect(sink.render!(5).allSatisfy { $0 == 0 }, "new session starts empty")
    expect(bridge.receive(pcm([32767]), session: second), "new packet accepted")
    expect(oldRender(1).allSatisfy { $0 == 0 }, "stale callback cannot consume new session")
    expect(sink.render!(1)[0] > 0.99, "new session audio flows")
    expect(bridge.stop(session: second), "new session stops")
    do { _ = try bridge.start(deviceUID: " "); fatalError("empty UID accepted") }
    catch RemoteAudioBridgeError.missingDeviceUID {}
    sink.fail = true
    do { _ = try bridge.start(deviceUID: "device"); fatalError("failed output accepted") }
    catch { expect(sink.stopCount == 3, "partially started output cleaned up") }
    sink.fail = false
    let third = try bridge.start(deviceUID: "device")
    expect(bridge.receive(pcm([0, 1000, 2000, 3000]), session: third), "overflow packet accepted")
    let newest = sink.render!(6)
    expect(newest.count == 12 && newest[10] > 0.08, "overflow preserves newest frames")
    expect(bridge.stop(session: third), "final cleanup")
    print("PASS: conversion, continuity, bounded buffering, session isolation, silence and cleanup")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}

// Exercise actual CoreAudio buffer-list writing with synthetic memory, no device open.
do {
    let memorySize = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
    let raw = UnsafeMutableRawPointer.allocate(byteCount: memorySize, alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    list.initialize(to: AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer()))
    defer { list.deinitialize(count: 1) }
    let left = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    let right = UnsafeMutablePointer<Float>.allocate(capacity: 4)
    left.initialize(repeating: 7, count: 4); right.initialize(repeating: 7, count: 4)
    defer { left.deinitialize(count: 4); left.deallocate(); right.deinitialize(count: 4); right.deallocate() }

    list.pointee.mNumberBuffers = 1
    var buffers = UnsafeMutableAudioBufferListPointer(list)
    buffers[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 16, mData: UnsafeMutableRawPointer(left))
    KKCoreAudioOutput.write(list) { count in
        expect(count == 2, "interleaved frame count")
        return [0.1, 0.2, 0.3, 0.4]
    }
    expect(approximately(left[0], 0.1) && approximately(left[3], 0.4), "interleaved output")

    list.pointee.mNumberBuffers = 2
    buffers = UnsafeMutableAudioBufferListPointer(list)
    buffers[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: UnsafeMutableRawPointer(left))
    buffers[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 8, mData: UnsafeMutableRawPointer(right))
    KKCoreAudioOutput.write(list) { _ in [0.1, 0.2, 0.3, 0.4] }
    expect(approximately(left[0], 0.1) && approximately(left[1], 0.3), "planar left")
    expect(approximately(right[0], 0.2) && approximately(right[1], 0.4), "planar right")
    KKCoreAudioOutput.write(list) { _ in [1] }
    expect(left[0] == 0 && left[1] == 0 && right[0] == 0 && right[1] == 0, "malformed render clears output")
    print("PASS: synthetic interleaved and planar CoreAudio buffer output")
}

// InputDeviceCatalog exclusions and fallback resolution (hardware-free).
do {
    expect(KKInputDeviceCatalog.isExcludedVirtualDevice(uid: "KKvoiceMi2ch_UID", name: "KKvoice Mic"), "exclude KKvoice Mic")
    expect(KKInputDeviceCatalog.isExcludedVirtualDevice(uid: "vRemoteDr2ch_UID", name: "vRemote"), "exclude vRemote")
    expect(KKInputDeviceCatalog.isExcludedVirtualDevice(uid: "BlackHole2ch_UID", name: "BlackHole 2ch"), "exclude BlackHole")
    expect(KKInputDeviceCatalog.isExcludedVirtualDevice(uid: "any", name: "Virtual", transportType: kAudioDeviceTransportTypeVirtual), "exclude virtual transport")
    expect(!KKInputDeviceCatalog.isExcludedVirtualDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro麦克风", transportType: kAudioDeviceTransportTypeBuiltIn), "keep built-in mic")

    let builtIn = KKAudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro麦克风", transportType: kAudioDeviceTransportTypeBuiltIn)
    let usbMic = KKAudioInputDevice(uid: "USB_Mic_UID", name: "Blue Yeti", transportType: kAudioDeviceTransportTypeUSB)
    let virtual = KKAudioInputDevice(uid: "KKvoiceMi2ch_UID", name: "KKvoice Mic", transportType: kAudioDeviceTransportTypeVirtual)

    // System default is physical USB mic -> follow system default.
    let resolvedUSB = KKInputDeviceCatalog.resolve(selectedUID: "", available: [builtIn, usbMic, virtual], systemDefaultUID: "USB_Mic_UID")
    expect(resolvedUSB == usbMic, "system default physical device selected")

    // System default is virtual KKvoice Mic -> fall back to built-in mic!
    let resolvedFallback = KKInputDeviceCatalog.resolve(selectedUID: "", available: [usbMic, builtIn, virtual], systemDefaultUID: "KKvoiceMi2ch_UID")
    expect(resolvedFallback == builtIn, "virtual system default falls back to built-in mic")

    // Explicit UID selection -> select that physical device.
    let explicit = KKInputDeviceCatalog.resolve(selectedUID: "USB_Mic_UID", available: [builtIn, usbMic], systemDefaultUID: "BuiltInMicrophoneDevice")
    expect(explicit == usbMic, "explicit UID selected")

    print("PASS: InputDeviceCatalog virtual exclusion and built-in fallback")
}

// MacMicrophoneSource & AudioSourceRouter per-session routing without hot-swap.
do {
    final class FakeInputDriver: MacMicrophoneInputDriver {
        var startedUID: String?
        var stopCount = 0
        var lastStopError: String? = nil
        var callback: ((UnsafePointer<AudioBufferList>, AudioStreamBasicDescription) -> Void)?
        func start(deviceUID: String, onInput: @escaping (UnsafePointer<AudioBufferList>, AudioStreamBasicDescription) -> Void) throws {
            startedUID = deviceUID
            callback = onInput
        }
        func stop() {
            stopCount += 1
            callback = nil
            startedUID = nil
        }
    }

    let sink = FakeOutput()
    let inputDriver = FakeInputDriver()
    var permission: MacMicrophonePermissionStatus = .authorized
    let macSource = MacMicrophoneSource(
        input: inputDriver,
        output: sink,
        permissionCheck: { permission },
        permissionRequest: { $0(true) }
    )
    let builtIn = KKAudioInputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro麦克风", transportType: kAudioDeviceTransportTypeBuiltIn)
    let suiteName = "local.kkvoice.audiotests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let router = AudioSourceRouter(
        output: sink,
        remoteBridge: RemoteAudioBridge(output: sink),
        macSource: macSource,
        userDefaults: defaults,
        listDevices: { [builtIn] },
        defaultUIDProvider: { "KKvoiceMi2ch_UID" }
    )

    // Session 1: remote not ready -> routes Mac mic into KKvoice Mic.
    let s1 = UUID()
    let source1 = try router.beginSession(session: s1, virtualDeviceUID: "KKvoiceMi2ch_UID", remoteReady: false)
    expect(source1 == .mac(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro麦克风"), "session 1 uses Mac mic")
    expect(router.currentSource == source1, "currentSource published")
    expect(inputDriver.startedUID == "BuiltInMicrophoneDevice", "physical mic opened")
    expect(sink.selectedUID == "KKvoiceMi2ch_UID", "virtual output opened")
    // Stray remote frames during Mac mic session must be ignored (no hot-swap).
    expect(!router.receiveRemotePCM(pcm([16384, 16384])), "remote PCM ignored during Mac mic session")
    _ = router.endSession(session: s1)
    expect(router.currentSource == nil && inputDriver.startedUID == nil && inputDriver.stopCount == 1, "Mac mic released on endSession")

    // Session 2: remote ready -> routes remote PCM into KKvoice Mic without opening Mac mic.
    let s2 = UUID()
    let source2 = try router.beginSession(session: s2, virtualDeviceUID: "KKvoiceMi2ch_UID", remoteReady: true)
    expect(source2 == .remote, "session 2 uses remote")
    expect(inputDriver.startedUID == nil, "Mac mic never opened during remote session")
    expect(router.receiveRemotePCM(pcm([16384, 16384])), "remote PCM accepted during remote session")
    _ = router.endSession(session: s2)

    // Permission denied -> throws clear Chinese error and never opens devices.
    permission = .denied
    do {
        _ = try router.beginSession(session: UUID(), virtualDeviceUID: "KKvoiceMi2ch_UID", remoteReady: false)
        fatalError("expected permissionDenied")
    } catch let error as MacMicrophoneError {
        expect(error == .permissionDenied && error.localizedDescription == "需要麦克风权限", "permission denied message")
    }
    expect(inputDriver.startedUID == nil, "no device opened when permission denied")
    print("PASS: MacMicrophoneSource and AudioSourceRouter session lifecycle")
} catch {
    fputs("FAIL: \(error)\n", stderr)
    exit(1)
}
