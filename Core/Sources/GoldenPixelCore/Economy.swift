/// Prices, payouts and the modifiers skills and stars give. Plain values in, plain values out.

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct BallProgress: Codable, Equatable, Sendable {
    public var owned = 0
    public var speed = 0
    public var damage = 0
    public var special = 0
    public var spec: String?

    public init(owned: Int = 0) { self.owned = owned }

    public func level(_ s: Stat) -> Int {
        switch s {
        case .speed: return speed
        case .damage: return damage
        case .special: return special
        }
    }

    public mutating func bump(_ s: Stat) {
        switch s {
        case .speed: speed += 1
        case .damage: damage += 1
        case .special: special += 1
        }
    }

    public var upgradeTotal: Int { speed + damage + special }
}

public enum Economy {
    /// A type can pick one of its two specialisations once its upgrades add up to this.
    public static let specMilestone = 10

    public static func ballCost(_ k: BallKind, owned: Int, spec: String?) -> Double {
        let t = k.type
        // The free starting basic ball does not count towards its price.
        let n = k == .basic ? max(0, owned - 1) : owned
        let discount = (k == .basic && spec == "swarm") ? 0.6 : 1
        return (t.baseCost * pow(t.costGrowth, Double(n)) * discount).rounded()
    }

    static let statCost: [Stat: (mult: Double, growth: Double)] = [
        .speed: (2, 1.6), .damage: (3, 1.55), .special: (5, 1.8),
    ]

    /// nil when the stat is maxed.
    public static func upgradeCost(_ k: BallKind, _ s: Stat, level: Int) -> Double? {
        guard level < s.max, let c = statCost[s] else { return nil }
        return (k.type.baseCost * c.mult * pow(c.growth, Double(level))).rounded()
    }

    public static func canSpecialize(_ p: BallProgress) -> Bool { p.spec == nil && p.upgradeTotal >= specMilestone }

    public static func levelHPScale(_ level: Int) -> Double { pow(1.85, Double(level - 1)) }
    public static func levelValueScale(_ level: Int) -> Double { pow(1.75, Double(level - 1)) }
    public static func tierHP(_ tier: Int, level: Int) -> Double { Tuning.tierHP[tier] * levelHPScale(level) }
    public static func tierValue(_ tier: Int, level: Int) -> Double { Tuning.tierValue[tier] * levelValueScale(level) }
    public static func skillPointsForClear(_ level: Int) -> Int { 2 + level / 2 }

    /// Stars a prestige would award now. Nothing before level 3.
    public static func starsForPrestige(runEarnings: Double, maxLevel: Int) -> Int {
        guard maxLevel >= 3 else { return 0 }
        return Int(sqrt(max(0, runEarnings) / 40000).rounded(.down))
    }

    public static func comboMultiplier(_ streak: Int) -> Double {
        min(Tuning.comboMax, 1 + Double(max(0, streak - 1)) * Tuning.comboStep)
    }

    /// Offline earnings for `elapsed` seconds away, capped.
    public static func offlineEarnings(incomePerSecond: Double, elapsed: Double, mods: Mods) -> Double {
        guard elapsed > 60, incomePerSecond > 0 else { return 0 }
        return incomePerSecond * min(elapsed, Tuning.offlineCapSeconds) * mods.offline
    }
}

/// What skills and prestige stars add up to.
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
    public var startCash = 0.0
    public var comboWindow = 1.2
    public var tap = 4.0
    public var unlocked: Set<BallKind> = [.basic]

    public var revealRadius: Int { Tuning.revealRadius + lantern }

    public static func from(ranks: [String: Int], stars: Int) -> Mods {
        var m = Mods()
        m.damage += Double(stars) * 0.05
        m.money += Double(stars) * 0.1
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
            case .startCash(let p): m.startCash += p * rd
            case .combo(let p): m.comboWindow += p * rd
            case .tap(let p): m.tap += p * rd
            case .unlock(let k): m.unlocked.insert(k)
            }
        }
        return m
    }
}

public enum SkillCheck: Equatable { case ok, maxed, locked, poor }

public enum Skills {
    public static func check(_ id: String, ranks: [String: Int], points: Int) -> SkillCheck {
        guard let s = SkillNode.byID[id] else { return .locked }
        let r = ranks[id] ?? 0
        if r >= s.ranks { return .maxed }
        // Every prerequisite needs at least one rank.
        if !s.requires.allSatisfy({ (ranks[$0] ?? 0) > 0 }) { return .locked }
        return points >= s.cost ? .ok : .poor
    }
}
