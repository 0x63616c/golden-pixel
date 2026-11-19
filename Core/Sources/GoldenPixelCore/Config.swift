/// Data tables: ball types, the skill tree and durability tiers. New content is a new row.
/// Balance numbers live in `Tuning`.

public enum BallKind: String, CaseIterable, Codable, Sendable {
    case basic, fast, heavy, lightning, bomb, sniper, ghost

    public var index: Int { BallKind.allCases.firstIndex(of: self)! }
    public var type: BallType { BallType.all[index] }

    public var color: Pixel {
        switch self {
        case .basic: return rgb(0xffffff)
        case .fast: return rgb(0x00d8ff)
        case .heavy: return rgb(0xff6a00)
        case .lightning: return rgb(0x50fff0)
        case .bomb: return rgb(0xff2bd6)
        case .sniper: return rgb(0x8b5cff)
        case .ghost: return rgb(0x0070f3)
        }
    }

    /// The darker step of the ball's colour, for corners and trails.
    public var shade: Pixel {
        switch self {
        case .basic: return rgb(0xa1a1a1)
        case .fast: return rgb(0x0088a3)
        case .heavy: return rgb(0xa34400)
        case .lightning: return rgb(0x23a399)
        case .bomb: return rgb(0xa31b89)
        case .sniper: return rgb(0x583aa3)
        case .ghost: return rgb(0x00479b)
        }
    }
}

public enum Stat: String, CaseIterable, Codable, Sendable {
    case speed, damage, special
    public var max: Int {
        switch self {
        case .speed: return 15
        case .damage: return 25
        case .special: return 10
        }
    }
}

public struct Specialization: Sendable {
    public let id: String
    public let name: String
    public let text: String
}

public struct BallType: Sendable {
    public let kind: BallKind
    public let name: String
    public let blurb: String
    public let baseCost: Double
    public let costGrowth: Double
    /// Cells per second.
    public let speed: Double
    public let damage: Double
    public let specialName: String
    public let specialBase: Double
    public let specialPerLevel: Double
    public let specs: [Specialization]

    public func special(level: Int) -> Double { specialBase + specialPerLevel * Double(level) }

    public static let all: [BallType] = [
        BallType(kind: .basic, name: "Basic", blurb: "Reliable bouncer", baseCost: 25, costGrowth: 1.15, speed: 9, damage: 1,
                 specialName: "Crit", specialBase: 0, specialPerLevel: 0.03,
                 specs: [.init(id: "swarm", name: "Swarm", text: "40% cheaper"), .init(id: "veteran", name: "Veteran", text: "3x damage")]),
        BallType(kind: .fast, name: "Fast", blurb: "Quick light hits", baseCost: 150, costGrowth: 1.17, speed: 17, damage: 1,
                 specialName: "Twin hit", specialBase: 0, specialPerLevel: 0.06,
                 specs: [.init(id: "blur", name: "Blur", text: "+60% speed"), .init(id: "flurry", name: "Flurry", text: "Twin hits x2")]),
        BallType(kind: .heavy, name: "Heavy", blurb: "Pierces what it breaks", baseCost: 500, costGrowth: 1.2, speed: 7, damage: 5,
                 specialName: "Pierce", specialBase: 1, specialPerLevel: 1,
                 specs: [.init(id: "juggernaut", name: "Jugger", text: "Endless pierce"), .init(id: "wrecking", name: "Wreck", text: "+200% damage")]),
        BallType(kind: .lightning, name: "Volt", blurb: "Chains to nearby pixels", baseCost: 1200, costGrowth: 1.22, speed: 10, damage: 1.5,
                 specialName: "Chains", specialBase: 2, specialPerLevel: 1,
                 specs: [.init(id: "storm", name: "Storm", text: "+4 chains"), .init(id: "overcharge", name: "Surge", text: "Chains x2.5")]),
        BallType(kind: .bomb, name: "Bomb", blurb: "Explodes on impact", baseCost: 2500, costGrowth: 1.24, speed: 8, damage: 3,
                 specialName: "Blast", specialBase: 1.3, specialPerLevel: 0.22,
                 specs: [.init(id: "cluster", name: "Cluster", text: "3 mini blasts"), .init(id: "nuke", name: "Nuke", text: "Blast x1.6")]),
        BallType(kind: .sniper, name: "Sniper", blurb: "Aims after each bounce", baseCost: 5000, costGrowth: 1.26, speed: 14, damage: 4,
                 specialName: "Range", specialBase: 8, specialPerLevel: 3,
                 specs: [.init(id: "seeker", name: "Seeker", text: "Hunts the gold"), .init(id: "marksman", name: "Marks", text: "x2 damage")]),
        BallType(kind: .ghost, name: "Ghost", blurb: "Phases through pixels", baseCost: 12000, costGrowth: 1.3, speed: 9, damage: 3,
                 specialName: "Phase", specialBase: 0.8, specialPerLevel: 0.2,
                 specs: [.init(id: "poltergeist", name: "Polter", text: "Phases 2x often"), .init(id: "wraith", name: "Wraith", text: "x3 phase damage")]),
    ]
}

public enum SkillEffect: Sendable, Equatable {
    case damage(Double), speed(Double), money(Double), crit(Double), critDamage(Double)
    case radar, offline(Double), startCash(Double), combo(Double), tap(Double)
    /// Fog: +1 reveal radius per rank.
    case lantern
    /// Fog: the golden pixel pings a ring through the dark, more often per rank.
    case sonar
    case unlock(BallKind)
}

public struct SkillNode: Sendable {
    public let id: String
    public let name: String
    public let text: String
    public let cost: Int
    public let ranks: Int
    public let requires: [String]
    /// Layout in the graph, 0...1 in both axes.
    public let x: Double
    public let y: Double
    public let effect: SkillEffect

    public static let all: [SkillNode] = [
        .init(id: "core", name: "Core", text: "+10% damage", cost: 1, ranks: 1, requires: [], x: 0.5, y: 0.5, effect: .damage(0.1)),
        .init(id: "sharp", name: "Sharp", text: "+20% damage", cost: 1, ranks: 5, requires: ["core"], x: 0.36, y: 0.38, effect: .damage(0.2)),
        .init(id: "momentum", name: "Momentum", text: "+10% speed", cost: 1, ranks: 5, requires: ["core"], x: 0.64, y: 0.38, effect: .speed(0.1)),
        .init(id: "greed", name: "Greed", text: "+25% money", cost: 1, ranks: 5, requires: ["core"], x: 0.5, y: 0.66, effect: .money(0.25)),
        .init(id: "u-fast", name: "Fast ball", text: "Unlock", cost: 1, ranks: 1, requires: ["momentum"], x: 0.78, y: 0.26, effect: .unlock(.fast)),
        .init(id: "u-heavy", name: "Heavy ball", text: "Unlock", cost: 1, ranks: 1, requires: ["sharp"], x: 0.22, y: 0.26, effect: .unlock(.heavy)),
        .init(id: "u-lightning", name: "Volt ball", text: "Unlock", cost: 2, ranks: 1, requires: ["sharp", "momentum"], x: 0.5, y: 0.2, effect: .unlock(.lightning)),
        .init(id: "u-bomb", name: "Bomb ball", text: "Unlock", cost: 2, ranks: 1, requires: ["u-heavy"], x: 0.1, y: 0.12, effect: .unlock(.bomb)),
        .init(id: "u-sniper", name: "Sniper ball", text: "Unlock", cost: 2, ranks: 1, requires: ["u-fast"], x: 0.9, y: 0.12, effect: .unlock(.sniper)),
        .init(id: "u-ghost", name: "Ghost ball", text: "Unlock", cost: 3, ranks: 1, requires: ["u-lightning"], x: 0.5, y: 0.05, effect: .unlock(.ghost)),
        .init(id: "crit", name: "Precision", text: "+4% crit", cost: 1, ranks: 5, requires: ["sharp"], x: 0.18, y: 0.5, effect: .crit(0.04)),
        .init(id: "critdmg", name: "Brutal", text: "+50% crit dmg", cost: 2, ranks: 3, requires: ["crit"], x: 0.06, y: 0.38, effect: .critDamage(0.5)),
        .init(id: "combo", name: "Flow", text: "Longer combos", cost: 1, ranks: 3, requires: ["momentum"], x: 0.82, y: 0.5, effect: .combo(0.4)),
        .init(id: "tap", name: "Finger", text: "+10 tap damage", cost: 1, ranks: 5, requires: ["combo"], x: 0.94, y: 0.38, effect: .tap(10)),
        .init(id: "lantern", name: "Lantern", text: "Wider reveals", cost: 1, ranks: 3, requires: ["greed"], x: 0.5, y: 0.8, effect: .lantern),
        .init(id: "radar", name: "Radar", text: "Narrows gold hint", cost: 2, ranks: 3, requires: ["lantern"], x: 0.66, y: 0.9, effect: .radar),
        .init(id: "sonar", name: "Sonar", text: "Gold pings", cost: 2, ranks: 3, requires: ["radar"], x: 0.84, y: 0.8, effect: .sonar),
        .init(id: "offline", name: "Idle", text: "+15% offline", cost: 1, ranks: 4, requires: ["greed"], x: 0.34, y: 0.9, effect: .offline(0.15)),
        .init(id: "cash", name: "Head start", text: "+150 per level", cost: 1, ranks: 5, requires: ["offline"], x: 0.16, y: 0.8, effect: .startCash(150)),
    ]

    public static let byID: [String: SkillNode] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

/// Every balance number, named.
public enum Tuning {
    /// Device pixels per art pixel on the iPhone Duo's inner screen (2853 x 2007 px), and the
    /// art canvas that gives: 475 x 334 (2850 x 2004 px, a 1.5 px margin per side).
    public static let artScale = 6
    public static let canvasWidth = 475
    public static let canvasHeight = 334

    /// Ball diameter is 5/8 of a cell (a 5x5 sprite on an 8x8 block).
    public static let ballRadius = 0.3125
    /// Art pixels per smashable block.
    public static let cellPixels = 8
    /// The board is always this many blocks square; levels shape the playable area inside it.
    /// 41 x 8 = 328 art pixels, which fits the Duo canvas's 334-pixel height.
    public static let boardCells = 41
    /// Durability (hits at 1 damage) and payout of each tier on level 1.
    public static let tierHP: [Double] = [1, 2, 3, 4, 5]
    public static let tierValue: [Double] = [1, 3, 7, 15, 32]
    public static let richMultiplier = 5.0
    /// Odds that a block is rich.
    public static let richChance = 0.02
    public static let goldHPMultiplier = 3.0
    public static let goldValueMultiplier = 40.0
    /// Fog: cells within this many cells (Chebyshev) of an open cell are visible.
    public static let revealRadius = 3
    public static let goldGlowRadius = 3.5
    public static let sonarIntervals: [Double] = [0, 18, 11, 6]
    public static let radarHintRadius: [Int] = [0, 11, 6, 3]
    /// Combo multiplier: +5% per streak step, up to 3x.
    public static let comboStep = 0.05
    public static let comboMax = 3.0
    public static let offlineCapSeconds = 8.0 * 3600
    public static let levelClearPause = 2.2
    public static let maxBalls = 400
}
