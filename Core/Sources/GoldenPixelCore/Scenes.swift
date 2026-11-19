/// Staged game states for previews, screenshots and UI tests. The app opens one with the
/// launch argument `-GPScene <name>` (DEBUG builds and the screenshot job only).
public enum Scenes {
    public static let names = ["title", "start", "early", "mid", "late", "skills", "upgrades", "gold", "portrait", "zoom"]

    public static func make(_ name: String) -> Game {
        var p = Progress()
        switch name {
        case "title", "start":
            break
        case "early":
            p.money = 180
            p.balls[BallKind.basic.rawValue] = BallProgress(owned: 6)
        case "mid", "upgrades", "portrait", "zoom":
            p.level = 3; p.maxLevel = 3
            p.money = 48_000
            p.skillPoints = 3
            p.skillRanks = ["core": 1, "sharp": 2, "momentum": 2, "u-fast": 1, "u-heavy": 1, "greed": 1, "lantern": 1, "radar": 1]
            p.balls = [BallKind.basic.rawValue: bp(24, 4, 6, 2), BallKind.fast.rawValue: bp(10, 3, 3, 2), BallKind.heavy.rawValue: bp(5, 1, 4, 3)]
        case "late", "skills", "gold":
            p.level = 6; p.maxLevel = 6
            p.stars = 4
            p.money = 7_400_000
            p.skillPoints = 4
            p.skillRanks = ["core": 1, "sharp": 5, "momentum": 4, "u-fast": 1, "u-heavy": 1, "u-lightning": 1, "u-bomb": 1, "u-sniper": 1,
                            "greed": 3, "crit": 2, "lantern": 2, "radar": 2, "sonar": 1, "combo": 1]
            p.balls = [BallKind.basic.rawValue: bp(70, 8, 12, 5), BallKind.fast.rawValue: bp(40, 6, 8, 4), BallKind.heavy.rawValue: bp(24, 4, 9, 6),
                       BallKind.lightning.rawValue: bp(22, 3, 6, 5), BallKind.bomb.rawValue: bp(18, 2, 5, 4), BallKind.sniper.rawValue: bp(12, 2, 4, 3)]
        default: break
        }
        let g = Game(progress: p, seed: 7)
        if name != "title" { g.ui.started = true }
        switch name {
        case "start": settle(g, 1.2)
        case "early": settle(g, 25)
        case "mid": settle(g, 14)
        case "upgrades": settle(g, 30); g.ui.tab = .upgrades
        case "portrait": settle(g, 30)
        case "zoom":
            settle(g, 14)
            // Close-up on the spawn, as a double-tap would do.
            let cp = Double(Tuning.cellPixels)
            let v = g.ui.camera.toView((Double(g.board.spawn.x) + 0.5) * cp, (Double(g.board.spawn.y) + 0.5) * cp)
            g.ui.camera.toggle(at: v.x, v.y)
            settle(g, 1)
        case "late": settle(g, 14)
        case "skills": settle(g, 10); g.ui.skillsOpen = true
        case "gold":
            settle(g, 8)
            // Break straight through to the gold for the celebration frame.
            let i = g.board.index(g.board.gold.x, g.board.gold.y)
            g.board.hp[i] = 0.0001
            g.tap(cellX: g.board.gold.x, cellY: g.board.gold.y)
            settle(g, 0.35)
        case "title": settle(g, 0.6)
        default: break
        }
        g.events.removeAll()
        return g
    }

    /// Per-frame scripted input for animated captures.
    public static func script(_ name: String, _ g: Game, frame: Int) {
        if name == "start", frame % 9 == 0 {
            // A finger chipping around the spawn.
            let a = Double(frame) * 0.31
            g.tap(cellX: g.board.spawn.x + Int(cos(a) * 3.5), cellY: g.board.spawn.y + Int(sin(a) * 3.5))
        }
    }

    static func bp(_ owned: Int, _ s: Int, _ d: Int, _ sp: Int) -> BallProgress {
        var b = BallProgress(owned: owned)
        b.speed = s; b.damage = d; b.special = sp
        return b
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
