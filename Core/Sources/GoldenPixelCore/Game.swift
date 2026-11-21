/// The game: persistent progress plus the live level. Pure Swift with no platform imports, so
/// every rule here runs (and is tested) on any machine. Rendering lives in `Renderer`, and
/// the app only forwards touches, drains `events` for haptics and sound, and saves.

public struct Ball: Sendable {
    public var kind: BallKind
    /// Position in cells; (vx, vy) is a unit direction.
    public var x: Double, y: Double, vx: Double, vy: Double
    var pierce: Int = 0
    var phaseLeft: Double = 0
    var phaseTimer: Double = 0
    var lastCell: Int = -1
    /// The last few art-pixel positions, newest first, for the trail.
    public var trail: [Point] = []
    var trailTimer: Double = 0
}

public struct Particle: Sendable {
    public var x: Double, y: Double, vx: Double, vy: Double
    public var life: Double, maxLife: Double
    public var color: Pixel, fade: Pixel
}

/// A lightning bolt, already in board art pixels.
public struct Bolt: Sendable {
    public var points: [Point]
    public var life: Double
}

public struct Ring: Sendable {
    public var x: Double, y: Double
    public var maxRadius: Double
    public var life: Double, maxLife: Double
    public var color: Pixel
    /// Drawn over the fog (sonar pings).
    public var overFog: Bool
}

public struct Banner: Sendable {
    public var text: String
    public var color: Pixel
    public var life: Double
    public var big: Bool
}

public enum GameEvent: Equatable, Sendable {
    case blockBroken(tier: Int)
    case wallFound
    case goldSpotted
    case goldBroken
    case levelStart(Int)
    case purchase
    case denied
    case crit
    case explosion
    case zap
    /// A UI press (button, toggle, tab).
    case tap
    case shardBroken
}

public final class Game {
    public var progress: Progress
    public private(set) var mods: Mods
    public var board: Board
    public var balls: [Ball] = []
    public var particles: [Particle] = []
    public var bolts: [Bolt] = []
    public var rings: [Ring] = []
    public var banners: [Banner] = []
    public var events: [GameEvent] = []
    public var time: Double = 0
    public var shake = 0.0
    /// Counting down after the gold breaks, then the next level starts.
    public var clearTimer: Double?
    public var ui = UIState()
    var rng: RNG
    var sonarTimer = 0.0
    var goldSeen = false
    /// The direction the last ball was aimed (a unit vector); new balls default to it.
    public var lastAim: (x: Double, y: Double) = (0, -1)
    /// Which build this is (e.g. "1.0.0 (202611201445) a1b2c3d"), set by the app shell from its
    /// Info.plist so a tester can tell at a glance which TestFlight build is on the phone. Shown
    /// faintly on the main menu and at the foot of the settings card; empty draws nothing.
    public var buildLabel = ""

    public init(progress: Progress = Progress(), seed: UInt64 = 1) {
        self.progress = progress
        mods = Mods.from(ranks: progress.skillRanks, stars: progress.stars)
        rng = RNG(seed: seed)
        board = LevelGen.make(level: progress.level)
        centreCamera()
        respawnBalls()
    }

    // MARK: - Save

    public func saveFile() -> SaveFile {
        SaveFile(progress: progress, board: SaveCodec.snapshot(board, fresh: LevelGen.make(level: board.level)))
    }

    /// Restores a save. Nothing happens while the game is closed: it picks up where it stopped.
    public func load(_ s: SaveFile) {
        progress = s.progress
        progress.level = max(1, progress.level)
        // Shards spent on a node that no longer exists (Idle, 1 shard a rank) come back.
        for (id, r) in progress.skillRanks where SkillNode.byID[id] == nil {
            progress.shards += r
            progress.skillRanks[id] = nil
        }
        refreshMods()
        board = LevelGen.make(level: progress.level, at: time)
        if let bs = s.board { SaveCodec.restore(bs, into: board) }
        if board.kind[board.index(board.gold.x, board.gold.y)] != .gold { advanceLevel() }
        centreCamera()
        respawnBalls()
    }

    func refreshMods() { mods = Mods.from(ranks: progress.skillRanks, stars: progress.stars) }

    // MARK: - Derived stats

    /// A ball type's rank in one of its tree tracks.
    public func rank(_ k: BallKind, _ s: Stat) -> Int {
        let suffix: String
        switch s {
        case .damage: suffix = "dmg"
        case .speed: suffix = "spd"
        case .special: suffix = "sp"
        }
        return progress.skillRanks["\(k.rawValue)-\(suffix)"] ?? 0
    }

    /// True when the specialisation's tree node is owned.
    public func has(_ spec: String) -> Bool { (progress.skillRanks["spec-\(spec)"] ?? 0) > 0 }

    public func speed(_ k: BallKind) -> Double {
        var s = k.type.speed * mods.speed * (1 + 0.12 * Double(rank(k, .speed)))
        if k == .fast && has("blur") { s *= 1.6 }
        return s
    }

    public func damage(_ k: BallKind) -> Double {
        var d = k.type.damage * mods.damage * (1 + 0.5 * Double(rank(k, .damage)))
        if k == .basic && has("veteran") { d *= 3 }
        if k == .heavy && has("wrecking") { d *= 3 }
        if k == .sniper && has("marksman") { d *= 2 }
        return d
    }

    public func special(_ k: BallKind) -> Double { k.type.special(rank: rank(k, .special)) }

    public func ballCost(_ k: BallKind) -> Double {
        Economy.ballCost(k, owned: progress.ball(k).owned, swarm: has("swarm"))
    }

    public var totalBalls: Int { balls.count }

    // MARK: - Actions

    /// Buys a ball and launches it from the launch point along `direction` (any length),
    /// or along the last aimed direction.
    @discardableResult
    public func buyBall(_ k: BallKind, direction: (x: Double, y: Double)? = nil) -> Bool {
        guard mods.unlocked.contains(k), balls.count < Tuning.maxBalls else { events.append(.denied); return false }
        let cost = ballCost(k)
        guard progress.money >= cost else { events.append(.denied); return false }
        progress.money -= cost
        progress.update(k) { $0.owned += 1 }
        if let d = direction, d.x * d.x + d.y * d.y > 1e-9 { lastAim = d }
        launch(k, direction: lastAim)
        events.append(.purchase)
        return true
    }

    /// Buys a ball and places it at board position `at` (in cells, which must be an open cell)
    /// flying along `direction`, or along the last direction.
    @discardableResult
    public func buyBall(_ k: BallKind, at p: (x: Double, y: Double), direction: (x: Double, y: Double)?) -> Bool {
        let cx = Int(p.x.rounded(.down)), cy = Int(p.y.rounded(.down))
        guard board.inside(cx, cy), board.kind[board.index(cx, cy)] == .empty else { events.append(.denied); return false }
        guard mods.unlocked.contains(k), balls.count < Tuning.maxBalls else { events.append(.denied); return false }
        let cost = ballCost(k)
        guard progress.money >= cost else { events.append(.denied); return false }
        progress.money -= cost
        progress.update(k) { $0.owned += 1 }
        if let d = direction, d.x * d.x + d.y * d.y > 1e-9 { lastAim = d }
        // Keep the whole ball inside its cell so it never starts overlapping a block.
        let r = Tuning.ballRadius
        let x = min(Double(cx) + 1 - r, max(Double(cx) + r, p.x)), y = min(Double(cy) + 1 - r, max(Double(cy) + r, p.y))
        launch(k, from: (x, y), direction: lastAim)
        events.append(.purchase)
        return true
    }

    @discardableResult
    public func buySkill(_ id: String) -> Bool {
        guard Skills.check(id, ranks: progress.skillRanks, shards: progress.shards) == .ok, let s = SkillNode.byID[id] else {
            events.append(.denied); return false
        }
        progress.shards -= s.cost
        progress.skillRanks[id, default: 0] += 1
        refreshMods()
        switch s.effect {
        case .unlock(let k):
            // A new type is ready to place: it becomes the selected ball.
            ui.selected = k
        case .cash(let v):
            progress.money += v
        case .ballStat(.heavy, _), .ballSpec(.heavy, _):
            for i in balls.indices where balls[i].kind == .heavy { balls[i].pierce = basePierce(.heavy) }
        default: break
        }
        events.append(.purchase)
        return true
    }

    /// What a tap on the board says about cell (x, y): only ever what you can already see.
    /// Taps never damage anything; only balls break pixels.
    public func describe(cellX x: Int, cellY y: Int) -> [String]? {
        guard board.inside(x, y) else { return nil }
        let i = board.index(x, y)
        guard board.revealed[i] else { return nil }
        switch board.kind[i] {
        case .block: return ["PIXEL", "HP \(compact(board.hp[i].rounded(.up)))"]
        case .shard: return ["SHARD +\(board.shardValue[i])", "HP \(compact(board.hp[i].rounded(.up)))"]
        case .gold: return ["GOLDEN PIXEL", "HP \(compact(board.hp[i].rounded(.up)))"]
        case .wall: return ["ROCK", "UNBREAKABLE"]
        case .empty: return nil
        }
    }

    // MARK: - Level flow

    /// Starts a level as a fresh run: no balls, just enough coins for the first basic ball,
    /// an empty tree, no shards. Stars, settings and lifetime totals carry over.
    func startLevel(_ level: Int) {
        progress.level = level
        progress.maxLevel = max(progress.maxLevel, level)
        progress.money = Tuning.startCoins
        progress.runEarnings = 0
        progress.shards = 0
        progress.levelTime = 0
        progress.skillRanks = SkillNode.startingRanks
        progress.balls = [:]
        refreshMods()
        board = LevelGen.make(level: level, at: time)
        goldSeen = false
        clearTimer = nil
        lastAim = (0, -1)
        ui.selected = .basic
        centreCamera()
        respawnBalls()
        events.append(.levelStart(level))
        banners.append(Banner(text: "\(level) \(board.name)", color: Palette.text, life: 2.2, big: false))
    }

    func advanceLevel() {
        progress.lastClearTime = progress.levelTime
        startLevel(progress.level + 1)
    }

    /// True while the current level has something to lose: time played or coins earned, and
    /// its gold still standing.
    public var levelInProgress: Bool {
        clearTimer == nil && (progress.levelTime >= 1 || progress.runEarnings > 0)
    }

    /// A tile on the level select card: any level up to the furthest reached. The current level
    /// carries on where it was; any other starts as a fresh run. Leaving a level in progress
    /// takes a second tap on the same tile within 3 seconds.
    public func pickLevel(_ level: Int) {
        guard level >= 1, level <= progress.maxLevel else { events.append(.denied); return }
        if level != progress.level, levelInProgress, ui.confirmLevel != level || time >= ui.confirmLevelUntil {
            ui.confirmLevel = level
            ui.confirmLevelUntil = time + 3
            events.append(.denied)
            return
        }
        ui.confirmLevel = nil
        ui.sheet = nil; ui.skillsOpen = false; ui.paused = false; ui.confirmingRestart = false
        if level != progress.level { startLevel(level) }
        ui.screen = .game
        events.append(.tap)
    }

    /// True once the level's gold has been broken (every level below the furthest reached).
    public func cleared(_ level: Int) -> Bool { level < progress.maxLevel }

    /// Starts the current level again from scratch (a fresh run, same layout).
    public func restartLevel() {
        startLevel(progress.level)
        banners.removeAll()
        banners.append(Banner(text: "RESTARTED", color: Palette.text, life: 1.6, big: false))
    }

    /// Wipes everything, settings aside, and starts again from level 1.
    public func resetProgress() {
        let settings = progress.settings
        progress = Progress()
        progress.settings = settings
        startLevel(1)
        banners.removeAll()
    }

    /// Points the camera at the spawn at zoom 1, where every level starts. The board camera
    /// may look past the board's edge, so the spawn sits in the middle of the view even
    /// when it is near the edge of the level.
    func centreCamera() {
        let L = ui.layout
        ui.camera = Camera(boardW: board.pixelSize, boardH: board.pixelSize, viewW: L.board.w, viewH: L.board.h, overscroll: 1)
        let cp = Double(Tuning.cellPixels)
        ui.camera.look(at: (Double(board.spawn.x) + 0.5) * cp, (Double(board.spawn.y) + 0.5) * cp)
    }

    func respawnBalls() {
        balls.removeAll()
        for k in BallKind.allCases {
            let n = min(progress.ball(k).owned, Tuning.maxBalls - balls.count)
            for j in 0..<max(0, n) {
                // Fan the starting balls out so they don't travel as one clump.
                let a = -Double.pi / 2 + Double(j) * 2.39996
                launch(k, direction: (cos(a), sin(a)))
            }
        }
    }

    /// Where new balls start: the open cell nearest the middle of the view, so they appear
    /// where you're looking. Falls back to the spawn.
    public func launchPoint() -> (x: Double, y: Double) {
        let cp = Double(Tuning.cellPixels)
        let c = ui.camera.toBoard(Double(ui.camera.viewW) / 2, Double(ui.camera.viewH) / 2)
        let cx = Int(c.x / cp), cy = Int(c.y / cp)
        var best: (Int, Int)?
        for r in 0...12 {
            for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
                let x = cx + dx, y = cy + dy
                guard board.inside(x, y), board.kind[board.index(x, y)] == .empty else { continue }
                let d = dx * dx + dy * dy
                if best == nil || d < best!.0 { best = (d, board.index(x, y)) }
            } }
            if best != nil { break }
        }
        guard let (_, i) = best else { return (Double(board.spawn.x) + 0.5, Double(board.spawn.y) + 0.5) }
        return (Double(i % board.size) + 0.5, Double(i / board.size) + 0.5)
    }

    func launch(_ k: BallKind, from start: (x: Double, y: Double)? = nil, direction d: (x: Double, y: Double)) {
        let p = start ?? launchPoint()
        let len = max(1e-6, (d.x * d.x + d.y * d.y).squareRoot())
        var b = Ball(kind: k, x: p.x, y: p.y, vx: d.x / len, vy: d.y / len)
        b.pierce = basePierce(k)
        b.phaseTimer = rng.range(0.5, 3)
        balls.append(b)
    }

    func basePierce(_ k: BallKind) -> Int {
        guard k == .heavy else { return 0 }
        return has("juggernaut") ? 1_000_000 : Int(special(.heavy))
    }

    // MARK: - Damage

    /// Applies damage; returns true if the cell broke.
    @discardableResult
    func damageCell(_ i: Int, _ amount: Double) -> Bool {
        let k = board.kind[i]
        guard k.breakable else { return false }
        board.hp[i] -= amount
        board.hitAt[i] = time
        if board.hp[i] > 0 { return false }
        breakCell(i)
        return true
    }

    func breakCell(_ i: Int) {
        let x = i % board.size, y = i / board.size
        let wasGold = board.kind[i] == .gold
        let wasShard = board.kind[i] == .shard
        let tier = Int(board.tier[i])
        let shown = board.revealed[i]
        let value = Tuning.blockValue * (board.rich[i] ? Tuning.richMultiplier : 1)
        earn(value * mods.money)
        board.kind[i] = .empty
        board.hp[i] = 0
        if wasShard {
            let v = board.shardValue[i]
            board.shardValue[i] = 0
            progress.shards += v
            events.append(.shardBroken)
            banners.append(Banner(text: v == 1 ? "+1 SHARD" : "+\(v) SHARDS", color: Palette.mint, life: 1.6, big: false))
            rings.append(Ring(x: Double(x) + 0.5, y: Double(y) + 0.5, maxRadius: 3, life: 0.5, maxLife: 0.5, color: Palette.mint, overFog: true))
        }
        // A block breaks from its last, palest step, so its dust is that pale blue.
        let color = wasGold ? Palette.gold : (wasShard ? Palette.mint : (shown ? Palette.ladder[0] : Palette.muted))
        let fade = wasGold ? Palette.goldDim : (wasShard ? Palette.mintDim : (shown ? Palette.ladder[2] : Palette.border))
        for _ in 0..<(wasGold ? 40 : (wasShard ? 16 : 5)) {
            let a = rng.range(0, 6.283185), s = rng.range(2, wasGold ? 14 : 7)
            let life = rng.range(0.25, wasGold ? 1.4 : 0.55)
            particles.append(Particle(x: Double(x) + 0.5, y: Double(y) + 0.5, vx: cos(a) * s, vy: sin(a) * s - 2,
                                      life: life, maxLife: life, color: color, fade: fade))
        }
        let goldIndex = board.index(board.gold.x, board.gold.y)
        let newly = Fog.reveal(board, x, y, radius: mods.revealRadius, at: time)
        if !goldSeen, !wasGold, newly.contains(goldIndex) {
            goldSeen = true
            events.append(.goldSpotted)
            banners.append(Banner(text: "GOLD SPOTTED", color: Palette.gold, life: 1.6, big: false))
        }
        events.append(.blockBroken(tier: tier))
        if wasGold { goldBroken(x, y) }
    }

    func goldBroken(_ x: Int, _ y: Int) {
        events.append(.goldBroken)
        shake = 1
        // The win is never hidden: the tree or an info sheet closes so you see the gold go,
        // and neither opens again until the next level starts.
        ui.skillsOpen = false; ui.sheet = nil; ui.launch = nil
        // A star for the first clear only: replaying a cleared level (level select) is for fun.
        // The next level opens now, so leaving during the celebration never loses it.
        let first = !cleared(board.level)
        progress.maxLevel = max(progress.maxLevel, board.level + 1)
        if first { progress.stars += 1 }
        refreshMods()
        for r in 0..<3 {
            rings.append(Ring(x: Double(x) + 0.5, y: Double(y) + 0.5, maxRadius: 8 + Double(r) * 7,
                              life: 0.8 + Double(r) * 0.25, maxLife: 0.8 + Double(r) * 0.25, color: Palette.gold, overFog: true))
        }
        banners.append(Banner(text: "GOLD!", color: Palette.gold, life: Tuning.levelClearPause, big: true))
        if first { banners.append(Banner(text: "+1 STAR", color: Palette.goldLight, life: Tuning.levelClearPause, big: false)) }
        // The whole level lights up so you can see what you dug through.
        for i in 0..<board.revealed.count where !board.revealed[i] {
            board.revealed[i] = true
            let cx = Double(i % board.size - x), cy = Double(i / board.size - y)
            board.revealedAt[i] = time + (cx * cx + cy * cy).squareRoot() * 0.02
        }
        clearTimer = Tuning.levelClearPause
    }

    func earn(_ v: Double) {
        progress.money += v
        progress.runEarnings += v
        progress.totalEarnings += v
    }

    func revealWall(_ i: Int) {
        guard !board.revealed[i] else { return }
        board.revealed[i] = true
        board.revealedAt[i] = time
        events.append(.wallFound)
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
