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
