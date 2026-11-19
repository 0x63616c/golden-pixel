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
    case tap
    case prestige
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
    public var combo = 0
    public var comboTimer = 0.0
    public var shake = 0.0
    /// Counting down after the gold breaks, then the next level starts.
    public var clearTimer: Double?
    public var ui = UIState()
    var rng: RNG
    var sonarTimer = 0.0
    var incomeWindow = 0.0
    var incomeClock = 0.0
    var goldSeen = false

    public init(progress: Progress = Progress(), seed: UInt64 = 1) {
        self.progress = progress
        mods = Mods.from(ranks: progress.skillRanks, stars: progress.stars)
        rng = RNG(seed: seed)
        board = LevelGen.make(level: progress.level)
        respawnBalls()
    }

    // MARK: - Save

    public func saveFile(now: Double) -> SaveFile {
        SaveFile(progress: progress, board: SaveCodec.snapshot(board, fresh: LevelGen.make(level: board.level)), savedAt: now)
    }

    /// Restores a save and credits offline earnings. Returns the offline amount.
    @discardableResult
    public func load(_ s: SaveFile, now: Double) -> Double {
        progress = s.progress
        progress.level = max(1, progress.level)
        refreshMods()
        board = LevelGen.make(level: progress.level, at: time)
        if let bs = s.board { SaveCodec.restore(bs, into: board) }
        if board.kind[board.index(board.gold.x, board.gold.y)] != .gold { advanceLevel() }
        respawnBalls()
        let away = Economy.offlineEarnings(incomePerSecond: progress.incomeRate, elapsed: now - s.savedAt, mods: mods)
        if away > 0 {
            earn(away, combo: false)
            banners.append(Banner(text: "AWAY +\(compact(away))", color: Palette.gold, life: 3, big: false))
        }
        return away
    }

    func refreshMods() { mods = Mods.from(ranks: progress.skillRanks, stars: progress.stars) }

    // MARK: - Derived stats

    public func speed(_ k: BallKind) -> Double {
        let p = progress.ball(k)
        var s = k.type.speed * mods.speed * (1 + 0.06 * Double(p.speed))
        if p.spec == "blur" { s *= 1.6 }
        return s
    }

    public func damage(_ k: BallKind) -> Double {
        let p = progress.ball(k)
        var d = k.type.damage * mods.damage * (1 + 0.25 * Double(p.damage))
        switch p.spec {
        case "veteran": d *= 3
        case "wrecking": d *= 3
        case "marksman": d *= 2
        default: break
        }
        return d
    }

    public func special(_ k: BallKind) -> Double { k.type.special(level: progress.ball(k).special) }

    public func tapDamage() -> Double { mods.tap * mods.damage * pow(Economy.levelHPScale(board.level), 0.75) }

    public func ballCost(_ k: BallKind) -> Double {
        let p = progress.ball(k)
        return Economy.ballCost(k, owned: p.owned, spec: p.spec)
    }

    public var totalBalls: Int { balls.count }

    // MARK: - Actions

    @discardableResult
    public func buyBall(_ k: BallKind) -> Bool {
        guard mods.unlocked.contains(k), balls.count < Tuning.maxBalls else { events.append(.denied); return false }
        let cost = ballCost(k)
        guard progress.money >= cost else { events.append(.denied); return false }
        progress.money -= cost
        progress.update(k) { $0.owned += 1 }
        spawnBall(k)
        events.append(.purchase)
        return true
    }

    @discardableResult
    public func upgrade(_ k: BallKind, _ s: Stat) -> Bool {
        let p = progress.ball(k)
        guard mods.unlocked.contains(k), p.owned > 0, let cost = Economy.upgradeCost(k, s, level: p.level(s)), progress.money >= cost else {
            events.append(.denied); return false
        }
        progress.money -= cost
        progress.update(k) { $0.bump(s) }
        events.append(.purchase)
        return true
    }

    @discardableResult
    public func specialize(_ k: BallKind, _ which: Int) -> Bool {
        let p = progress.ball(k)
        guard Economy.canSpecialize(p), which >= 0, which < k.type.specs.count else { events.append(.denied); return false }
        progress.update(k) { $0.spec = k.type.specs[which].id }
        events.append(.purchase)
        return true
    }

    @discardableResult
    public func buySkill(_ id: String) -> Bool {
        guard Skills.check(id, ranks: progress.skillRanks, points: progress.skillPoints) == .ok, let s = SkillNode.byID[id] else {
            events.append(.denied); return false
        }
        progress.skillPoints -= s.cost
        progress.skillRanks[id, default: 0] += 1
        refreshMods()
        if case .unlock(let k) = s.effect, progress.ball(k).owned == 0 {
            // An unlocked type arrives with one ball so it shows up straight away.
            progress.update(k) { $0.owned = 1 }
            spawnBall(k)
        }
        events.append(.purchase)
        return true
    }

    public var prestigeStars: Int { Economy.starsForPrestige(runEarnings: progress.runEarnings, maxLevel: progress.maxLevel) }

    @discardableResult
    public func prestige() -> Bool {
        let s = prestigeStars
        guard s > 0 else { events.append(.denied); return false }
        let keep = (progress.skillRanks, progress.skillPoints, progress.stars + s, progress.settings, progress.totalEarnings)
        progress = Progress()
        (progress.skillRanks, progress.skillPoints, progress.stars, progress.settings, progress.totalEarnings) = keep
        refreshMods()
        startLevel(1)
        events.append(.prestige)
        banners.append(Banner(text: "+\(s) STARS", color: Palette.gold, life: 2.5, big: true))
        return true
    }

    /// A tap on the board at cell (x, y). Works in the dark too.
    public func tap(cellX x: Int, cellY y: Int) {
        guard board.inside(x, y), clearTimer == nil else { return }
        let i = board.index(x, y)
        events.append(.tap)
        rings.append(Ring(x: Double(x) + 0.5, y: Double(y) + 0.5, maxRadius: 1.2, life: 0.18, maxLife: 0.18, color: Palette.white, overFog: true))
        switch board.kind[i] {
        case .block, .gold: _ = damageCell(i, tapDamage())
        case .wall: revealWall(i)
        case .empty: break
        }
    }

    // MARK: - Level flow

    func startLevel(_ level: Int) {
        progress.level = level
        progress.maxLevel = max(progress.maxLevel, level)
        board = LevelGen.make(level: level, at: time)
        goldSeen = false
        clearTimer = nil
        if mods.startCash > 0 { progress.money += mods.startCash }
        respawnBalls()
        events.append(.levelStart(level))
        banners.append(Banner(text: "\(level) \(board.name)", color: Palette.text, life: 2.2, big: false))
    }

    func advanceLevel() { startLevel(progress.level + 1) }

    func respawnBalls() {
        balls.removeAll()
        for k in BallKind.allCases {
            let n = min(progress.ball(k).owned, Tuning.maxBalls - balls.count)
            for _ in 0..<max(0, n) { spawnBall(k) }
        }
    }

    func spawnBall(_ k: BallKind) {
        let a = rng.range(0, 6.283185)
        let sx = Double(board.spawn.x) + 0.5 + rng.range(-0.6, 0.6)
        let sy = Double(board.spawn.y) + 0.5 + rng.range(-0.6, 0.6)
        var b = Ball(kind: k, x: sx, y: sy, vx: cos(a), vy: sin(a))
        b.pierce = basePierce(k)
        b.phaseTimer = rng.range(0.5, 3)
        balls.append(b)
    }

    func basePierce(_ k: BallKind) -> Int {
        guard k == .heavy else { return 0 }
        return progress.ball(.heavy).spec == "juggernaut" ? 1_000_000 : Int(special(.heavy))
    }

    // MARK: - Damage

    /// Applies damage; returns true if the cell broke.
    @discardableResult
    func damageCell(_ i: Int, _ amount: Double) -> Bool {
        let k = board.kind[i]
        guard k == .block || k == .gold else { return false }
        board.hp[i] -= amount
        board.hitAt[i] = time
        if board.hp[i] > 0 { return false }
        breakCell(i)
        return true
    }

    func breakCell(_ i: Int) {
        let x = i % board.size, y = i / board.size
        let wasGold = board.kind[i] == .gold
        let tier = Int(board.tier[i])
        let shown = board.revealed[i]
        comboTimer > 0 ? (combo += 1) : (combo = 1)
        comboTimer = mods.comboWindow
        var value = Economy.tierValue(tier, level: board.level) * (board.rich[i] ? Tuning.richMultiplier : 1)
        if wasGold { value *= Tuning.goldValueMultiplier }
        earn(value * mods.money, combo: true)
        board.kind[i] = .empty
        board.hp[i] = 0
        // A block breaks from its grey last step, so its dust is grey.
        let color = wasGold ? Palette.gold : (shown ? Palette.ladder[0] : Palette.text2)
        let fade = wasGold ? Palette.goldDim : (shown ? Palette.ladderDark[0] : Palette.border)
        for _ in 0..<(wasGold ? 40 : 5) {
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
        let sp = Economy.skillPointsForClear(board.level)
        progress.skillPoints += sp
        for r in 0..<3 {
            rings.append(Ring(x: Double(x) + 0.5, y: Double(y) + 0.5, maxRadius: 8 + Double(r) * 7,
                              life: 0.8 + Double(r) * 0.25, maxLife: 0.8 + Double(r) * 0.25, color: Palette.gold, overFog: true))
        }
        banners.append(Banner(text: "GOLD!", color: Palette.gold, life: Tuning.levelClearPause, big: true))
        banners.append(Banner(text: "+\(sp) SKILL", color: Palette.cyan, life: Tuning.levelClearPause, big: false))
        // The whole level lights up so you can see what you dug through.
        for i in 0..<board.revealed.count where !board.revealed[i] {
            board.revealed[i] = true
            let cx = Double(i % board.size - x), cy = Double(i / board.size - y)
            board.revealedAt[i] = time + (cx * cx + cy * cy).squareRoot() * 0.02
        }
        clearTimer = Tuning.levelClearPause
    }

    func earn(_ v: Double, combo useCombo: Bool) {
        let m = useCombo ? Economy.comboMultiplier(combo) : 1
        progress.money += v * m
        progress.runEarnings += v * m
        progress.totalEarnings += v * m
        incomeWindow += v * m
    }

    func revealWall(_ i: Int) {
        guard !board.revealed[i] else { return }
        board.revealed[i] = true
        board.revealedAt[i] = time
        events.append(.wallFound)
    }

    public var comboMultiplier: Double { comboTimer > 0 ? Economy.comboMultiplier(combo) : 1 }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
