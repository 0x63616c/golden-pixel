/// Prices, payouts and the modifiers skills and stars give. Plain values in, plain values out.
///
/// Two currencies: coins (from breaking pixels) buy balls; shards (from the glowing shard
/// pixels) buy the skill tree, which holds every upgrade including each ball type's own.

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct BallProgress: Codable, Equatable, Sendable {
    public var owned = 0
    public init(owned: Int = 0) { self.owned = owned }
}

public enum Economy {
    public static func ballCost(_ k: BallKind, owned: Int, swarm: Bool = false) -> Double {
        let t = k.type
        let n = owned
        let discount = (k == .basic && swarm) ? 0.6 : 1
        return (t.baseCost * pow(t.costGrowth, Double(n)) * discount).rounded()
    }

    /// Durability is the same on every level: one shade of the ladder is one hit point, and an
    /// unupgraded basic ball deals exactly one per hit, so you can count a block's hits by its
    /// colour. Later levels get tougher through their tier mix, not bigger numbers.
    public static func levelHPScale(_ level: Int) -> Double { 1 }
    /// Coins per break on a level (`Tuning.levelPayout`): the dial that sets how long a level
    /// takes, since blocks are equally tough everywhere and ball prices don't change.
    public static func levelValueScale(_ level: Int) -> Double {
        let t = Tuning.levelPayout
        return t[min(t.count, max(1, level)) - 1]
    }
    public static func tierHP(_ tier: Int, level: Int) -> Double { Tuning.tierHP[tier] }

    /// The golden pixel: the level's boss, far tougher than any block, and tougher each level.
    public static func goldHP(level: Int) -> Double {
        (Tuning.goldHP * pow(Tuning.goldHPGrowth, Double(max(1, level) - 1))).rounded()
    }

    /// One step of the durability ladder: the HP of one shade (always 1).
    public static func hitUnit(level: Int) -> Double { 1 }

    /// Which shade a block shows: 0 = faintest (one step left) ... 5 = brightest (toughest).
    public static func ladderStep(hp: Double, level: Int) -> Int {
        let steps = Int((hp / hitUnit(level: level) - 1e-9).rounded(.up))
        return max(0, min(Palette.ladder.count - 1, steps - 1))
    }
    public static func tierValue(_ tier: Int, level: Int) -> Double { Tuning.tierValue[tier] * levelValueScale(level) }

    /// Splits the level's shards (the whole tree's price) across its shard pixels as evenly
    /// as whole numbers allow.
    public static func shardValues(count: Int, total: Int = SkillNode.totalCost) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).map { total / count + ($0 < total % count ? 1 : 0) }
    }

    /// Splits the level's shards across its shard pixels in proportion to `weights`, with
    /// every pixel paying at least one shard and the total exact.
    public static func shardValues(weights: [Double], total: Int = SkillNode.totalCost) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let spare = max(0, total - weights.count)
        let sum = max(1e-9, weights.reduce(0, +))
        let raw = weights.map { Double(spare) * $0 / sum }
        var v = raw.map { Int($0) }
        var left = spare - v.reduce(0, +)
        for i in raw.indices.sorted(by: { raw[$0] - Double(v[$0]) > raw[$1] - Double(v[$1]) }) where left > 0 {
            v[i] += 1
            left -= 1
        }
        return v.map { $0 + 1 }
    }

    /// Offline earnings for `elapsed` seconds away, capped.
    public static func offlineEarnings(incomePerSecond: Double, elapsed: Double, mods: Mods) -> Double {
        guard elapsed > 60, incomePerSecond > 0 else { return 0 }
        return incomePerSecond * min(elapsed, Tuning.offlineCapSeconds) * mods.offline
    }
}

/// What skills and stars add up to.
public struct Mods: Equatable, Sendable {
    public var damage = 1.0
    public var speed = 1.0
    public var money = 1.0
    public var crit = 0.02
    public var critDamage = 3.0
    public var radar = 0
    public var lantern = 0
    public var sonar = 0
    public var offline = 0.1
    public var unlocked: Set<BallKind> = [.basic]

    public var revealRadius: Int { Tuning.revealRadius + lantern }

    public static func from(ranks: [String: Int], stars: Int) -> Mods {
        var m = Mods()
        m.damage += Double(stars) * Tuning.starDamage
        m.money += Double(stars) * Tuning.starMoney
        for s in SkillNode.all {
            let r = ranks[s.id] ?? 0
            guard r > 0 else { continue }
            let rd = Double(r)
            switch s.effect {
            case .damage(let p): m.damage += p * rd
            case .speed(let p): m.speed += p * rd
            case .money(let p): m.money += p * rd
            case .crit(let p): m.crit += p * rd
            case .critDamage(let p): m.critDamage += p * rd
            case .radar: m.radar = r
            case .lantern: m.lantern = r
            case .sonar: m.sonar = r
            case .offline(let p): m.offline += p * rd
            case .unlock(let k): m.unlocked.insert(k)
            case .cash, .ballStat, .ballSpec: break
            }
        }
        return m
    }
}

public enum SkillCheck: Equatable { case ok, maxed, locked, poor }

public enum Skills {
    public static func check(_ id: String, ranks: [String: Int], shards: Int) -> SkillCheck {
        guard let s = SkillNode.byID[id] else { return .locked }
        let r = ranks[id] ?? 0
        if r >= s.ranks { return .maxed }
        // Every prerequisite needs at least one rank.
        if !s.requires.allSatisfy({ (ranks[$0] ?? 0) > 0 }) { return .locked }
        return shards >= s.cost ? .ok : .poor
    }

    /// Shown in the tree: anything owned, or anything you could buy next. Locked nodes stay
    /// hidden until their prerequisites are met.
    public static func visible(_ id: String, ranks: [String: Int]) -> Bool {
        (ranks[id] ?? 0) > 0 || check(id, ranks: ranks, shards: 0) != .locked
    }
}
