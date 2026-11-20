import Foundation
import GoldenPixelCore
import QuartzCore

/// Owns the game, its save file and the platform feedback (haptics, sound).
@MainActor
final class GameHost {
    let game: Game
    let renderer = Renderer()
    var tracker = PointerTracker()
    var paused = false
    let haptics = Haptics()
    let sound = Sound()
    /// Staged scene for screenshots (`-GPScene mid`); never saved.
    let scene: String?
    private var lastSave = CACurrentMediaTime()

    init() {
        scene = UserDefaults.standard.string(forKey: "GPScene")
        if let s = scene, Scenes.names.contains(s) {
            game = Scenes.make(s)
        } else {
            game = Game(seed: UInt64(Date().timeIntervalSince1970))
            if let file = SaveStore.load() { game.load(file, now: Date().timeIntervalSince1970) }
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
        if scene == nil, now - lastSave > 10 { save(); lastSave = now }
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

    func save() {
        guard scene == nil else { return }
        SaveStore.save(game.saveFile(now: Date().timeIntervalSince1970))
    }

    private func drainEvents() {
        let s = game.progress.settings
        for e in game.events {
            if s.haptics { haptics.play(e) }
            if s.sound { sound.play(e) }
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

    static func save(_ s: SaveFile) {
        try? SaveCodec.encode(s).write(to: url, options: .atomic)
    }
}
