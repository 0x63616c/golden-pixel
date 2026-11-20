import AVFoundation
import GoldenPixelCore

/// Background music: one loop on the menus and a shuffled playlist in a level, faded wherever
/// one hands over to the other. The core says what should play (`Game.musicCue`, `Playlist`);
/// the tracks are the `.m4a` files in `App/Music` (sources and licences: `docs/music.md`).
@MainActor
final class Music {
    static let menuTrack = "menu-chill-fever"
    static let gameTracks = [
        "game-plains-of-luminescence", "game-one-cool-minute", "game-waiting-tttt", "game-once-more-with-you",
        "game-static-shoes", "game-napping-on-a-cloud", "game-optimistic-day", "game-synthwave-house",
        "game-calm-relax", "game-observing-the-star",
    ]
    /// Quiet enough to sit under the effects.
    private static let volume: Float = 0.4
    /// How long one level track overlaps the next.
    private static let crossfade = 3.0
    /// Menu to level and back, and the MUSIC switch.
    private static let switchFade = 1.2

    private var cue: MusicCue = .off
    private var menu: AVAudioPlayer?
    /// The level track playing now, or waiting where it stopped while the menu is up.
    private var game: AVAudioPlayer?
    /// Players on their way out, and when each has faded and can be paused.
    private var fading: [(player: AVAudioPlayer, done: Double)] = []
    private var playlist = Playlist(count: Music.gameTracks.count, seed: UInt64(Date().timeIntervalSince1970))
    private var suspended = false
    /// Another app's music or podcast is playing: stay silent rather than play over it.
    private var yielding = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint

    /// Called every frame with what the game wants to hear.
    func update(_ wanted: MusicCue, now: Double) {
        guard !suspended else { return }
        let want = yielding ? .off : wanted
        fading.removeAll { f in
            guard now >= f.done else { return false }
            f.player.pause()
            return true
        }
        if want != cue {
            if cue == .menu, let p = menu { fadeOut(p, over: Music.switchFade, now: now) }
            if cue == .game, let p = game { fadeOut(p, over: Music.switchFade, now: now) }
            cue = want
            switch want {
            case .menu:
                if menu == nil { menu = load(Music.menuTrack, loops: true) }
                if let p = menu { fadeIn(p, over: Music.switchFade) }
            case .game:
                // Back from the menu, the level's track carries on from where it left off.
                if let p = game { fadeIn(p, over: Music.switchFade) } else { startNextTrack(fade: Music.switchFade) }
            case .off: break
            }
        }
        // Near the end of a level track, the next one fades in over it.
        if cue == .game, let p = game, !p.isPlaying || p.duration - p.currentTime <= Music.crossfade {
            fadeOut(p, over: Music.crossfade, now: now)
            startNextTrack(fade: Music.crossfade)
        }
    }

    /// The app left the foreground: everything stops where it is.
    func suspend() {
        suspended = true
        for p in [menu, game].compactMap({ $0 }) + fading.map(\.player) {
            p.pause()
            p.volume = 0
        }
        fading.removeAll()
        cue = .off
    }

    /// Back in the foreground: the next `update` fades the right track back in.
    func resume() {
        suspended = false
        yielding = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
    }

    private func startNextTrack(fade: Double) {
        game = load(Music.gameTracks[playlist.next()], loops: false)
        if let p = game { fadeIn(p, over: fade) }
    }

    private func load(_ name: String, loops: Bool) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"), let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.numberOfLoops = loops ? -1 : 0
        p.volume = 0
        p.prepareToPlay()
        return p
    }

    private func fadeIn(_ p: AVAudioPlayer, over seconds: Double) {
        fading.removeAll { $0.player === p }
        p.play()
        p.setVolume(Music.volume, fadeDuration: seconds)
    }

    private func fadeOut(_ p: AVAudioPlayer, over seconds: Double, now: Double) {
        fading.removeAll { $0.player === p }
        p.setVolume(0, fadeDuration: seconds)
        fading.append((p, now + seconds))
    }
}
