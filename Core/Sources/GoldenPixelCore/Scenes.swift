/// Staged game states for previews, screenshots and UI tests. The app opens one with the
/// launch argument `-GPScene <name>` (DEBUG builds and the screenshot job only).
public enum Scenes {
    public static let names = ["menu", "howto", "settings", "levelselect", "start", "early", "mid", "late", "full", "tree", "sheet", "launch", "pause", "restart",
                               "gold", "zoom", "zoomout", "portrait", "hero", "goldhunt", "aim", "goldbreak"]

    /// What a TestFlight build shows in place of the app's real build label.
    public static let sampleBuildLabel = "1.0.0 (202611201445) a1b2c3d"

    public static func make(_ name: String) -> Game {
        var p = Progress()
        switch name {
        case "menu", "howto", "settings":
            p.maxLevel = 4; p.level = 4; p.stars = 3; p.levelTime = 300; p.totalEarnings = 1
        case "levelselect":
            // Ten levels cleared and the eleventh under way: the card scrolls on a phone.
            p.maxLevel = 11; p.level = 11; p.stars = 10; p.levelTime = 300; p.runEarnings = 900; p.totalEarnings = 1
        case "start":
            break
        case "early":
            p.money = 180
            p.shards = 2
            p.balls[BallKind.basic.rawValue] = BallProgress(owned: 6)
        case "mid", "sheet", "launch", "pause", "restart", "portrait", "zoom", "zoomout", "aim":
            p.level = 3; p.maxLevel = 3; p.stars = 2
            p.money = 48_000
            p.shards = 3
            p.skillRanks = ["u-basic": 1, "core": 1, "sharp": 2, "momentum": 2, "u-fast": 1, "u-heavy": 1, "greed": 1, "lantern": 1,
                            "basic-dmg": 2, "basic-spd": 1, "fast-dmg": 1]
            p.balls = [BallKind.basic.rawValue: BallProgress(owned: 24), BallKind.fast.rawValue: BallProgress(owned: 10),
                       BallKind.heavy.rawValue: BallProgress(owned: 5)]
        case "late", "full", "tree", "gold", "hero", "goldhunt", "goldbreak":
            p.level = 6; p.maxLevel = 6
            p.stars = 5
            p.money = 7_400_000
            p.shards = 6
            p.skillRanks = ["u-basic": 1, "core": 1, "sharp": 5, "momentum": 4, "u-fast": 1, "u-heavy": 1, "u-lightning": 1, "u-bomb": 1,
                            "u-sniper": 1, "greed": 3, "crit": 2, "lantern": 2, "radar": 2, "sonar": 1,
                            "basic-dmg": 5, "basic-spd": 3, "basic-sp": 2, "fast-dmg": 3, "fast-spd": 2, "heavy-dmg": 2, "heavy-spd": 1]
            p.balls = [BallKind.basic.rawValue: BallProgress(owned: 70), BallKind.fast.rawValue: BallProgress(owned: 40),
                       BallKind.heavy.rawValue: BallProgress(owned: 24), BallKind.lightning.rawValue: BallProgress(owned: 22),
                       BallKind.bomb.rawValue: BallProgress(owned: 18), BallKind.sniper.rawValue: BallProgress(owned: 12)]
            if name == "full" {
                // Every ball type unlocked: the panel at its fullest.
                p.skillRanks["u-ghost"] = 1
                p.balls[BallKind.ghost.rawValue] = BallProgress(owned: 7)
            }
        default: break
        }
        let g = Game(progress: p, seed: 7)
        switch name {
        case "menu": g.ui.screen = .menu
        case "howto": g.ui.screen = .howTo
        case "settings": g.ui.screen = .settings
        case "levelselect": g.perform(.levels); g.ui.pressed = .none
        default: g.ui.screen = .game
        }
        switch name {
        case "start": settle(g, 1.2)
        case "early": settle(g, 25)
        case "mid", "portrait": settle(g, 14)
        case "sheet": settle(g, 14); g.ui.sheet = .fast
        case "launch":
            settle(g, 14)
            let L = g.ui.layout
            g.ui.selected = .heavy
            let from = Point(L.board.x + L.board.w / 2, L.board.y + L.board.h / 2)
            g.ui.launch = LaunchDrag(from: from, to: Point(from.x + 30, from.y - 24), pulledAt: 0)
        case "pause": settle(g, 14); g.ui.paused = true
        case "restart": settle(g, 14); g.ui.paused = true; g.ui.confirmingRestart = true
        case "zoom":
            settle(g, 14)
            // Close-up on the spawn, as a double-tap would do.
            let cp = Double(Tuning.cellPixels)
            let v = g.ui.camera.toView((Double(g.board.spawn.x) + 0.5) * cp, (Double(g.board.spawn.y) + 0.5) * cp)
            g.ui.camera.toggle(at: v.x, v.y)
            settle(g, 1)
        case "zoomout":
            settle(g, 14)
            g.ui.camera.pinch(factor: 0.5, at: 160, 167)
            g.ui.camera.settle()
            settle(g, 1)
        case "late", "full": settle(g, 14)
        case "tree":
            // Opened the way a tap on the tree button does, so the camera frames the selection.
            settle(g, 4); g.ui.selectedSkill = "u-ghost"; g.perform(.openSkills); g.ui.pressed = .none
        case "gold", "goldbreak":
            settle(g, 8)
            // The gold in view, then broken straight through for the celebration frame.
            exposeGold(g)
            let i = g.board.index(g.board.gold.x, g.board.gold.y)
            g.damageCell(i, g.board.hp[i] + 1)
            settle(g, 0.35)
        case "hero":
            // Late game on an active dig: the camera on the busiest stretch of the dig face.
            settle(g, 20)
            lookAtDigFace(g)
            settle(g, 1)
            g.banners.removeAll()
        case "goldhunt":
            // The gold found and half drained, the radar box around it, balls closing in.
            settle(g, 12)
            exposeGold(g)
            let i = g.board.index(g.board.gold.x, g.board.gold.y)
            g.board.hp[i] = g.board.maxHP[i] * 0.45
            // A few balls already in the pocket, closing in.
            let gx = Double(g.board.gold.x) + 0.5, gy = Double(g.board.gold.y) + 0.5
            for (j, k) in [BallKind.basic, .heavy, .lightning, .sniper, .basic, .fast, .bomb, .basic].enumerated() {
                let a = Double(j) * 0.785
                g.launch(k, from: (gx + cos(a) * 2.2, gy + sin(a) * 2.2), direction: (cos(a + 2), sin(a + 2)))
            }
            g.ui.camera.toggle(at: Double(g.ui.camera.viewW) / 2, Double(g.ui.camera.viewH) / 2)
            settle(g, 0.8)
            g.banners.removeAll()
        case "aim":
            // Placing a heavy ball: the ghost on an open spot and the dots of its flight path.
            settle(g, 14)
            g.ui.selected = .heavy
            lookAtDigFace(g)
            g.ui.camera.toggle(at: Double(g.ui.camera.viewW) / 2, Double(g.ui.camera.viewH) / 2)
            settle(g, 1)
            g.banners.removeAll()
            // Held on the open spot nearest the middle of the view, pulled back away from the face.
            let cp = Double(Tuning.cellPixels), lp = g.launchPoint(), L = g.ui.layout
            let v = g.ui.camera.toView(lp.x * cp, lp.y * cp)
            let from = Point(L.board.x + Int(v.x), L.board.y + Int(v.y))
            g.ui.launch = LaunchDrag(from: from, to: Point(from.x - 30, from.y + 30), pulledAt: 0)
        default: settle(g, 0.6)
        }
        g.events.removeAll()
        g.buildLabel = sampleBuildLabel
        return g
    }

    /// Per-frame scripted input for animated captures.
    public static func script(_ name: String, _ g: Game, frame: Int) {
        if name == "launch", var l = g.ui.launch {
            let t = Double(frame) * 0.05
            l.to = Point(l.from.x + Int(36 * cos(t)), l.from.y + Int(36 * sin(t)))
            g.ui.launch = l
        }
    }

    /// Clears a pocket around the gold (so it is visible) and points the camera at it.
    static func exposeGold(_ g: Game) {
        let b = g.board, gx = b.gold.x, gy = b.gold.y
        for dy in -3...3 { for dx in -3...3 where max(abs(dx), abs(dy)) >= 2 && b.inside(gx + dx, gy + dy) {
            let i = b.index(gx + dx, gy + dy)
            if b.kind[i] == .block { b.kind[i] = .empty; b.hp[i] = 0 }
        } }
        _ = Fog.reveal(b, gx, gy, radius: g.mods.revealRadius, at: g.time - 5)
        let cp = Double(Tuning.cellPixels)
        g.ui.camera.look(at: (Double(gx) + 0.5) * cp, (Double(gy) + 0.5) * cp)
    }

    /// Points the camera at the visible block with the most balls nearby: where the digging is.
    static func lookAtDigFace(_ g: Game) {
        let b = g.board
        var best = (score: -1, x: b.spawn.x, y: b.spawn.y)
        for i in b.kind.indices where b.kind[i] == .block && b.revealed[i] {
            let x = i % b.size, y = i / b.size
            let near = g.balls.filter { abs($0.x - Double(x)) < 9 && abs($0.y - Double(y)) < 9 }.count
            if near > best.score { best = (near, x, y) }
        }
        let cp = Double(Tuning.cellPixels)
        g.ui.camera.look(at: (Double(best.x) + 0.5) * cp, (Double(best.y) + 0.5) * cp)
    }

    static func settle(_ g: Game, _ seconds: Double) {
        var t = 0.0
        while t < seconds { g.update(1.0 / 60); t += 1.0 / 60 }
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
