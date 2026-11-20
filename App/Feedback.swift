import AVFoundation
import GoldenPixelCore
import UIKit

/// Haptics for the moments that matter, throttled so a hundred balls don't buzz constantly.
@MainActor
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let select = UISelectionFeedbackGenerator()
    private let note = UINotificationFeedbackGenerator()
    private var lastBreak = 0.0

    func play(_ e: GameEvent) {
        let now = CACurrentMediaTime()
        switch e {
        case .tap: select.selectionChanged()
        case .purchase: light.impactOccurred(intensity: 0.8)
        case .denied: note.notificationOccurred(.warning)
        case .blockBroken(let tier):
            guard now - lastBreak > 0.07 else { return }
            lastBreak = now
            rigid.impactOccurred(intensity: 0.25 + 0.12 * CGFloat(tier))
        case .explosion: heavy.impactOccurred(intensity: 0.5)
        case .goldSpotted: note.notificationOccurred(.success)
        case .goldBroken: heavy.impactOccurred(intensity: 1); note.notificationOccurred(.success)
        case .shardBroken: note.notificationOccurred(.success)
        default: break
        }
    }
}

/// Soft synthesised effects: sine and triangle plucks on a pentatonic scale with a short
/// fade-in (no clicks), so a hundred breaks a second sound like rain on glass, not a buzzer.
/// Several variants per sound so they never repeat exactly.
@MainActor
final class Sound {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var bank: [String: [AVAudioPCMBuffer]] = [:]
    private var lastPlayed: [String: Double] = [:]
    private static let rate = 44_100.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: Sound.rate, channels: 1)!
    private var ready = false

    /// C major pentatonic, from C5 up two octaves.
    private static let scale: [Double] = [523.3, 587.3, 659.3, 784.0, 880.0, 1046.5, 1174.7, 1318.5, 1568.0, 1760.0]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<12 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.6
        let sc = Sound.scale
        bank["tap"] = [render(0.04, [Note(at: 0, freq: 1400, amp: 0.10, decay: 90, wave: .sine)])]
        bank["break"] = sc.prefix(8).map { render(0.12, [Note(at: 0, freq: $0, amp: 0.09, decay: 38, wave: .sine),
                                                         Note(at: 0, freq: $0 * 2, amp: 0.025, decay: 60, wave: .sine)]) }
        bank["buy"] = [render(0.22, [Note(at: 0, freq: sc[3], amp: 0.13, decay: 22, wave: .triangle),
                                     Note(at: 0.06, freq: sc[5], amp: 0.13, decay: 18, wave: .triangle)])]
        bank["deny"] = [render(0.18, [Note(at: 0, freq: 220, to: 165, amp: 0.16, decay: 20, wave: .sine)])]
        bank["zap"] = (0..<3).map { j in render(0.08, [Note(at: 0, freq: 2200 + 200 * Double(j), to: 900, amp: 0.05, decay: 45, wave: .sine)]) }
        bank["boom"] = [render(0.35, [Note(at: 0, freq: 110, to: 45, amp: 0.3, decay: 11, wave: .sine)])]
        bank["gold"] = [render(1.4, [0, 2, 4, 5, 7, 9].enumerated().map { j, n in
            Note(at: Double(j) * 0.09, freq: sc[n], amp: 0.14, decay: 4.5, wave: .triangle)
        })]
        bank["shard"] = [render(0.7, [Note(at: 0, freq: sc[5], amp: 0.12, decay: 7, wave: .sine),
                                      Note(at: 0.07, freq: sc[8], amp: 0.10, decay: 6, wave: .sine)])]
        bank["spot"] = [render(0.9, [Note(at: 0, freq: sc[2], amp: 0.11, decay: 5, wave: .triangle),
                                     Note(at: 0.12, freq: sc[4], amp: 0.11, decay: 5, wave: .triangle),
                                     Note(at: 0.24, freq: sc[7], amp: 0.11, decay: 5, wave: .triangle)])]
        do { try engine.start(); players.forEach { $0.play() }; ready = true } catch { ready = false }
    }

    func play(_ e: GameEvent) {
        switch e {
        case .tap: fire("tap", gap: 0.03)
        case .blockBroken: fire("break", gap: 0.06)
        case .purchase: fire("buy", gap: 0.05)
        case .denied: fire("deny", gap: 0.2)
        case .zap: fire("zap", gap: 0.08)
        case .explosion: fire("boom", gap: 0.15)
        case .goldBroken: fire("gold", gap: 0.5)
        case .shardBroken: fire("shard", gap: 0.3)
        case .goldSpotted: fire("spot", gap: 0.5)
        default: break
        }
    }

    private func fire(_ name: String, gap: Double) {
        guard ready, let variants = bank[name], !variants.isEmpty else { return }
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < gap { return }
        lastPlayed[name] = now
        let p = players[next]
        next = (next + 1) % players.count
        p.scheduleBuffer(variants.randomElement()!, at: nil, options: [.interrupts])
    }

    private enum Wave { case sine, triangle }

    /// One pluck: starts at `at` seconds, glides from `freq` to `to` (if set), fades in over
    /// 4 ms and decays exponentially at `decay` per second.
    private struct Note {
        var at: Double, freq: Double, to: Double? = nil, amp: Double, decay: Double, wave: Wave
    }

    private func render(_ dur: Double, _ notes: [Note]) -> AVAudioPCMBuffer {
        let n = Int(dur * Sound.rate)
        var out = [Float](repeating: 0, count: n)
        for note in notes {
            var phase = 0.0
            let start = Int(note.at * Sound.rate)
            guard start < n else { continue }
            for i in start..<n {
                let t = Double(i - start) / Sound.rate
                let f = note.to.map { note.freq + ($0 - note.freq) * min(1, t / max(0.001, dur - note.at)) } ?? note.freq
                phase += f / Sound.rate
                let ph = phase.truncatingRemainder(dividingBy: 1)
                let v = note.wave == .sine ? sin(2 * .pi * ph) : (ph < 0.5 ? 4 * ph - 1 : 3 - 4 * ph)
                let env = min(1, t / 0.004) * exp(-t * note.decay)
                out[i] += Float(v * env * note.amp)
            }
        }
        // A short fade-out so a cut-off tail never clicks.
        let fade = min(n, Int(0.01 * Sound.rate))
        for j in 0..<fade { out[n - 1 - j] *= Float(j) / Float(fade) }
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        b.frameLength = b.frameCapacity
        for (i, s) in out.enumerated() { b.floatChannelData![0][i] = s }
        return b
    }
}
