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

/// Tiny synthesised chiptune effects with pitch variation, so they never repeat exactly.
@MainActor
final class Sound {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var bank: [String: [AVAudioPCMBuffer]] = [:]
    private var lastPlayed: [String: Double] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var ready = false

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.5
        bank["chip"] = (0..<5).map { tone(freq: 520 * pow(1.12, Double($0)), dur: 0.035, wave: .square, decay: 40) }
        bank["break"] = (0..<5).map { noise(dur: 0.06 + 0.01 * Double($0), pitch: 1 + Double($0) * 0.3) }
        bank["buy"] = [arp([660, 990], step: 0.045)]
        bank["deny"] = [tone(freq: 140, dur: 0.12, wave: .square, decay: 12)]
        bank["zap"] = (0..<3).map { tone(freq: 1400 + 300 * Double($0), dur: 0.05, wave: .saw, decay: 30) }
        bank["boom"] = [noise(dur: 0.25, pitch: 0.4)]
        bank["gold"] = [arp([523, 659, 784, 1047, 1319], step: 0.07)]
        bank["spot"] = [arp([784, 1175], step: 0.06)]
        do { try engine.start(); players.forEach { $0.play() }; ready = true } catch { ready = false }
    }

    func play(_ e: GameEvent) {
        switch e {
        case .tap: fire("chip", gap: 0.03)
        case .blockBroken: fire("break", gap: 0.045)
        case .purchase: fire("buy", gap: 0.05)
        case .denied: fire("deny", gap: 0.2)
        case .zap: fire("zap", gap: 0.06)
        case .explosion: fire("boom", gap: 0.12)
        case .goldBroken: fire("gold", gap: 0.5)
        case .goldSpotted, .shardBroken: fire("spot", gap: 0.3)
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

    private enum Wave { case square, saw }

    private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        b.frameLength = b.frameCapacity
        for (i, s) in samples.enumerated() { b.floatChannelData![0][i] = s }
        return b
    }

    private func tone(freq: Double, dur: Double, wave: Wave, decay: Double) -> AVAudioPCMBuffer {
        let n = Int(dur * 44_100)
        return buffer((0..<n).map { i in
            let t = Double(i) / 44_100
            let ph = (t * freq).truncatingRemainder(dividingBy: 1)
            let v = wave == .square ? (ph < 0.5 ? 1.0 : -1.0) : (ph * 2 - 1)
            return Float(v * exp(-t * decay) * 0.3)
        })
    }

    private func noise(dur: Double, pitch: Double) -> AVAudioPCMBuffer {
        let n = Int(dur * 44_100)
        var v = 0.0, hold = 0
        var seed: UInt32 = 12345
        return buffer((0..<n).map { i in
            if hold <= 0 {
                seed = seed &* 1_103_515_245 &+ 12345
                v = Double(seed >> 16 & 0x7fff) / 16_384 - 1
                hold = max(1, Int(8 / pitch))
            }
            hold -= 1
            let t = Double(i) / 44_100
            return Float(v * exp(-t * 18 / max(0.4, dur * 4)) * 0.25)
        })
    }

    private func arp(_ freqs: [Double], step: Double) -> AVAudioPCMBuffer {
        var out: [Float] = []
        for f in freqs {
            let n = Int(step * 44_100)
            out += (0..<n).map { i in
                let t = Double(i) / 44_100
                let ph = (t * f).truncatingRemainder(dividingBy: 1)
                return Float((ph < 0.5 ? 1.0 : -1.0) * exp(-t * 14) * 0.25)
            }
        }
        return buffer(out)
    }
}
