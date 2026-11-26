import AppKit
import Foundation

enum RecordingSoundTheme: String, CaseIterable, Identifiable {
    case crisp
    case droplet
    case woodblock
    case chime
    case synth
    case tap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crisp: return "清脆"
        case .droplet: return "水滴"
        case .woodblock: return "木鱼"
        case .chime: return "风铃"
        case .synth: return "未来"
        case .tap: return "轻叩"
        }
    }
}

/// Synthesizes 6 distinct, soft, in-memory chimes for voice recording state cues
/// without loading external audio assets or holding an audio engine open.
@MainActor
final class SoundCuePlayer {
    enum Cue {
        case start
        case stop
        case cancel
    }

    static let shared = SoundCuePlayer()

    private struct CacheKey: Hashable {
        let theme: RecordingSoundTheme
        let cue: Int
    }

    private var cache: [CacheKey: Data] = [:]
    private var activeSound: NSSound?

    private init() {}

    func play(_ cue: Cue, theme: RecordingSoundTheme = .crisp) {
        let cueID: Int
        switch cue {
        case .start: cueID = 0
        case .stop: cueID = 1
        case .cancel: cueID = 2
        }
        let key = CacheKey(theme: theme, cue: cueID)
        let data: Data
        if let cached = cache[key] {
            data = cached
        } else {
            data = Self.buildWAV(theme: theme, cue: cue)
            cache[key] = data
        }
        activeSound?.stop()
        guard let sound = NSSound(data: data) else { return }
        sound.volume = 0.78
        activeSound = sound
        sound.play()
    }

    private static func buildWAV(theme: RecordingSoundTheme, cue: Cue) -> Data {
        switch theme {
        case .crisp:
            switch cue {
            case .start: return makeTwoToneWAV(freq1: 587.33, freq2: 880.0, noteDuration: 0.055, gap: 0.012, amplitude: 0.16)
            case .stop: return makeTwoToneWAV(freq1: 783.99, freq2: 523.25, noteDuration: 0.055, gap: 0.012, amplitude: 0.14)
            case .cancel: return makeSingleToneWAV(freq: 329.63, duration: 0.075, amplitude: 0.13)
            }
        case .droplet:
            switch cue {
            case .start: return makeGlideWAV(startFreq: 560, endFreq: 1120, duration: 0.085, amplitude: 0.17)
            case .stop: return makeGlideWAV(startFreq: 960, endFreq: 520, duration: 0.085, amplitude: 0.15)
            case .cancel: return makeGlideWAV(startFreq: 480, endFreq: 280, duration: 0.09, amplitude: 0.14)
            }
        case .woodblock:
            switch cue {
            case .start: return makePercussiveWAV(freq: 740, harmonic: 1.5, duration: 0.07, decay: 55, amplitude: 0.22)
            case .stop: return makePercussiveWAV(freq: 540, harmonic: 1.5, duration: 0.07, decay: 55, amplitude: 0.20)
            case .cancel: return makePercussiveWAV(freq: 380, harmonic: 1.4, duration: 0.08, decay: 48, amplitude: 0.18)
            }
        case .chime:
            switch cue {
            case .start: return makeChordWAV(freqs: [1046.5, 1318.5, 1568.0], duration: 0.18, decay: 18, amplitude: 0.14)
            case .stop: return makeChordWAV(freqs: [783.99, 987.77, 1174.66], duration: 0.16, decay: 20, amplitude: 0.13)
            case .cancel: return makeChordWAV(freqs: [440.0, 523.25], duration: 0.14, decay: 22, amplitude: 0.12)
            }
        case .synth:
            switch cue {
            case .start: return makeSynthWAV(startFreq: 440, endFreq: 659.25, duration: 0.11, amplitude: 0.15)
            case .stop: return makeSynthWAV(startFreq: 659.25, endFreq: 440, duration: 0.11, amplitude: 0.14)
            case .cancel: return makeSynthWAV(startFreq: 349.23, endFreq: 261.63, duration: 0.10, amplitude: 0.13)
            }
        case .tap:
            switch cue {
            case .start: return makePercussiveWAV(freq: 1120, harmonic: 2.0, duration: 0.032, decay: 120, amplitude: 0.17)
            case .stop: return makePercussiveWAV(freq: 820, harmonic: 2.0, duration: 0.032, decay: 120, amplitude: 0.15)
            case .cancel: return makePercussiveWAV(freq: 520, harmonic: 1.8, duration: 0.04, decay: 95, amplitude: 0.14)
            }
        }
    }

    private static func makeSingleToneWAV(freq: Double, duration: Double, amplitude: Double) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let progress = Double(i) / Double(max(1, count - 1))
            let env = sin(.pi * progress)
            let val = sin(2.0 * .pi * freq * t) * amplitude * env
            samples[i] = clampSample(val)
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func makeTwoToneWAV(
        freq1: Double,
        freq2: Double,
        noteDuration: Double,
        gap: Double,
        amplitude: Double
    ) -> Data {
        let sampleRate = 44_100
        let n1 = Int(Double(sampleRate) * noteDuration)
        let ng = Int(Double(sampleRate) * gap)
        let n2 = Int(Double(sampleRate) * noteDuration)
        var samples = [Int16](repeating: 0, count: n1 + ng + n2)

        for i in 0..<n1 {
            let t = Double(i) / Double(sampleRate)
            let progress = Double(i) / Double(max(1, n1 - 1))
            let env = sin(.pi * progress)
            let val = (sin(2.0 * .pi * freq1 * t) * 0.85 + sin(2.0 * .pi * freq1 * 2.0 * t) * 0.15) * amplitude * env
            samples[i] = clampSample(val)
        }

        let offset = n1 + ng
        for i in 0..<n2 {
            let t = Double(i) / Double(sampleRate)
            let progress = Double(i) / Double(max(1, n2 - 1))
            let env = sin(.pi * progress)
            let val = (sin(2.0 * .pi * freq2 * t) * 0.85 + sin(2.0 * .pi * freq2 * 2.0 * t) * 0.15) * amplitude * env
            samples[offset + i] = clampSample(val)
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func makeGlideWAV(startFreq: Double, endFreq: Double, duration: Double, amplitude: Double) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let progress = Double(i) / Double(max(1, count - 1))
            let curved = progress * progress
            let freq = startFreq + (endFreq - startFreq) * curved
            phase += 2.0 * .pi * freq / Double(sampleRate)
            let attack = min(1.0, progress / 0.08)
            let release = pow(1.0 - progress, 1.4)
            let val = sin(phase) * amplitude * attack * release
            samples[i] = clampSample(val)
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func makePercussiveWAV(
        freq: Double,
        harmonic: Double,
        duration: Double,
        decay: Double,
        amplitude: Double
    ) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let attack = min(1.0, t / 0.002)
            let env = attack * exp(-decay * t)
            let fundamental = sin(2.0 * .pi * freq * t)
            let overtone = sin(2.0 * .pi * freq * harmonic * t) * 0.35 * exp(-decay * 1.4 * t)
            samples[i] = clampSample((fundamental + overtone) * amplitude * env)
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func makeChordWAV(freqs: [Double], duration: Double, decay: Double, amplitude: Double) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        let norm = Double(max(1, freqs.count))
        for i in 0..<count {
            let t = Double(i) / Double(sampleRate)
            let attack = min(1.0, t / 0.006)
            let env = attack * exp(-decay * t)
            var sum = 0.0
            for (idx, f) in freqs.enumerated() {
                let weight = idx == 0 ? 1.0 : 0.65
                sum += sin(2.0 * .pi * f * t) * weight
            }
            samples[i] = clampSample((sum / norm) * amplitude * env)
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func makeSynthWAV(startFreq: Double, endFreq: Double, duration: Double, amplitude: Double) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let progress = Double(i) / Double(max(1, count - 1))
            let freq = startFreq + (endFreq - startFreq) * progress
            phase += 2.0 * .pi * freq / Double(sampleRate)
            let env = sin(.pi * progress)
            // Soft triangle-tinted harmonic blend
            let val = (sin(phase) * 0.72 + sin(phase * 2.0) * 0.20 + sin(phase * 3.0) * 0.08) * amplitude * env
            samples[i] = clampSample(val)
        }
        return encodeWAV(samples: samples, sampleRate: sampleRate)
    }

    private static func clampSample(_ value: Double) -> Int16 {
        Int16(max(-32767.0, min(32767.0, value * 32767.0)))
    }

    private static func encodeWAV(samples: [Int16], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        let riffSize = 36 + dataSize

        var data = Data()
        data.reserveCapacity(Int(44 + dataSize))
        data.append(contentsOf: "RIFF".utf8)
        data.append(littleEndian: riffSize)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.append(littleEndian: UInt32(16))
        data.append(littleEndian: UInt16(1))
        data.append(littleEndian: numChannels)
        data.append(littleEndian: UInt32(sampleRate))
        data.append(littleEndian: byteRate)
        data.append(littleEndian: blockAlign)
        data.append(littleEndian: bitsPerSample)
        data.append(contentsOf: "data".utf8)
        data.append(littleEndian: dataSize)
        samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress)?.assumingMemoryBound(to: UInt8.self),
                count: Int(dataSize)
            ))
        }
        return data
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
