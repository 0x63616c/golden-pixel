import Foundation
import GoldenPixelCore
import QuartzCore

/// Owns the game, its save file and the platform feedback (haptics, sound, music, the rating prompt).
@MainActor
final class GameHost {
    let game: Game
    let renderer = Renderer()
    var tracker = PointerTracker()
    var paused = false {
        didSet {
            guard paused != oldValue else { return }
            if paused { music.suspend() } else { music.resume() }
        }
    }
    let haptics = Haptics()
    let sound = Sound()
    let music = Music()
    /// Staged scene for screenshots (`-GPScene mid`); never saved.
    let scene: String?
    /// No music and no sound effects: staged scenes, and `-GPMute YES`, which ios/ios.sh passes
    /// on every simulator launch (simulators play through the Mac's speakers).
    let muted: Bool
    private var lastSave = CACurrentMediaTime()

    init() {
        scene = UserDefaults.standard.string(forKey: "GPScene")
        muted = scene != nil || UserDefaults.standard.bool(forKey: "GPMute")
        if let s = scene, Scenes.names.contains(s) {
            game = Scenes.make(s)
        } else {
            game = Game(seed: UInt64(Date().timeIntervalSince1970))
            if let file = SaveStore.load() { game.load(file) }
        }
        // App Store screenshots (`-GPStore YES`) show no build label.
        game.buildLabel = UserDefaults.standard.bool(forKey: "GPStore") ? "" : GameHost.buildLabel
    }

    /// "1.0.0 (202611201804) a1b2c3d": the version and build number exactly as TestFlight
    /// lists them, then the commit ios/ios.sh stamped in (GPCommit; "dev" from a plain Xcode
    /// build, a trailing "+" when built with uncommitted changes).
    static var buildLabel: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let commit = (info["GPCommit"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return "\(version) (\(build))" + (commit.isEmpty ? "" : " \(commit)")
    }

    func frame(dt: Double, now: Double) {
        guard !paused else { return }
        for g in tracker.tick(at: now) { game.handle(g) }
        game.update(dt)
        drainEvents()
        music.update(muted ? .off : game.musicCue, now: now)
        if scene == nil, now - lastSave > 10 { save(wait: false); lastSave = now }
    }

    func touch(_ phase: TouchPhase, _ p: Point, id: Int, now: Double) {
        let gestures: [Gesture]
        switch phase {
        case .began: gestures = tracker.began(p, id: id, at: now)
        case .moved: gestures = tracker.moved(p, id: id, at: now)
        case .ended: gestures = tracker.ended(p, id: id, at: now)
        }
        for g in gestures { game.handle(g) }
        drainEvents()
    }

    /// Saves the game. The autosave hands the file to a background queue; leaving the app
    /// waits for it to be on disk before the app can be suspended.
    func save(wait: Bool = true) {
        guard scene == nil else { return }
        SaveStore.save(game.saveFile(), wait: wait)
    }

    private func drainEvents() {
        let s = game.progress.settings
        for e in game.events {
            switch e {
            // Staged scenes are for screenshots: no system prompt over them.
            case .ratingMoment: if scene == nil { Rating.ask() }
            case .rateApp: Rating.openReviewPage()
            default: break
            }
            if s.haptics { haptics.play(e) }
            if s.sound, !muted { sound.play(e) }
        }
        game.events.removeAll(keepingCapacity: true)
    }

    enum TouchPhase { case began, moved, ended }
}

enum SaveStore {
    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("golden-pixel")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("save.json")
    }

    static func load() -> SaveFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let s = SaveCodec.decode(data) { return s }
        // Unreadable or from a newer build: keep it aside rather than overwrite it.
        let aside = url.deletingLastPathComponent().appendingPathComponent("save-unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return nil
    }

    /// Saves are encoded and written one at a time, in the order they were asked for, off the
    /// main thread.
    private static let queue = DispatchQueue(label: "co.worldwidewebb.goldenpixel.save", qos: .utility)

    static func save(_ s: SaveFile, wait: Bool) {
        let write = { _ = try? SaveCodec.encode(s).write(to: url, options: .atomic) }
        if wait { queue.sync(execute: write) } else { queue.async(execute: write) }
    }
}
