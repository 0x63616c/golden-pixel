/// Data tables: ball types, the skill tree and level tuning. New content is a new row.
/// Balance numbers live in `Tuning`.

public enum BallKind: String, CaseIterable, Codable, Sendable {
    case basic, fast, heavy, lightning, bomb, sniper, ghost

    public var index: Int { BallKind.allCases.firstIndex(of: self)! }
    public var type: BallType { BallType.all[index] }

    /// Flat ball colour. Chosen to stand apart from the blue blocks, the gold and the mint shards.
    public var color: Pixel {
        switch self {
        case .basic: return rgb(0xffffff)
        case .fast: return rgb(0xff8fd8)
        case .heavy: return rgb(0xff8a3d)
        case .lightning: return rgb(0xc6ff4d)
        case .bomb: return rgb(0xff4f5e)
        case .sniper: return rgb(0xc58bff)
        case .ghost: return rgb(0x9aa6c4)
        }
    }

    /// A darker step of the ball's colour, for trails.
    public var shade: Pixel {
        switch self {
        case .basic: return rgb(0x8f97b8)
        case .fast: return rgb(0x9c4f84)
        case .heavy: return rgb(0x9c5124)
        case .lightning: return rgb(0x6f9a22)
        case .bomb: return rgb(0x9a2a35)
        case .sniper: return rgb(0x6f4d99)
        case .ghost: return rgb(0x56607a)
        }
    }
}

/// A ball type's three upgrade tracks in the skill tree.
public enum Stat: String, CaseIterable, Codable, Sendable {
    case damage, speed, special
    /// Ranks in the tree.
    public var max: Int {
        switch self {
        case .damage: return 5
        case .speed: return 3
        case .special: return 5
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
    /// One or two lines on what the ball does, for the info sheet.
    public let about: String
    public let baseCost: Double
    public let costGrowth: Double
    /// Cells per second.
    public let speed: Double
    public let damage: Double
    public let specialName: String
    public let specialBase: Double
    /// Added per special rank in the tree.
    public let specialPerRank: Double
    public let specs: [Specialization]

    public func special(rank: Int) -> Double { specialBase + specialPerRank * Double(rank) }

    public static let all: [BallType] = [
        BallType(kind: .basic, name: "Basic", blurb: "Reliable bouncer", about: "Bounces off everything and chips what it hits. Can crit.",
                 baseCost: 5, costGrowth: 1.3, speed: 9, damage: 1,
                 specialName: "Crit", specialBase: 0, specialPerRank: 0.06,
                 specs: [.init(id: "swarm", name: "Swarm", text: "Basic balls cost 40% less"), .init(id: "veteran", name: "Veteran", text: "Basic balls deal 3x damage")]),
        BallType(kind: .fast, name: "Fast", blurb: "Quick light hits", about: "Twice as fast as a basic ball. Sometimes hits twice.",
                 baseCost: 150, costGrowth: 1.34, speed: 17, damage: 1,
                 specialName: "Twin hit", specialBase: 0, specialPerRank: 0.12,
                 specs: [.init(id: "blur", name: "Blur", text: "Fast balls move 60% faster"), .init(id: "flurry", name: "Flurry", text: "Twin hits are twice as likely")]),
        BallType(kind: .heavy, name: "Heavy", blurb: "Pierces what it breaks", about: "Slow and strong. Keeps going through pixels it breaks.",
                 baseCost: 500, costGrowth: 1.4, speed: 7, damage: 5,
                 specialName: "Pierce", specialBase: 1, specialPerRank: 2,
                 specs: [.init(id: "juggernaut", name: "Juggernaut", text: "Pierces without limit"), .init(id: "wrecking", name: "Wrecking", text: "Heavy balls deal 3x damage")]),
        BallType(kind: .lightning, name: "Volt", blurb: "Chains to nearby pixels", about: "Every hit arcs lightning to the nearest pixels.",
                 baseCost: 1200, costGrowth: 1.44, speed: 10, damage: 1.5,
                 specialName: "Chains", specialBase: 2, specialPerRank: 2,
                 specs: [.init(id: "storm", name: "Storm", text: "+4 chains, longer reach"), .init(id: "overcharge", name: "Surge", text: "Chains hit 2.5x harder")]),
        BallType(kind: .bomb, name: "Bomb", blurb: "Explodes on impact", about: "Blows up on every hit, damaging a whole area.",
                 baseCost: 2500, costGrowth: 1.48, speed: 8, damage: 3,
                 specialName: "Blast", specialBase: 1.3, specialPerRank: 0.44,
                 specs: [.init(id: "cluster", name: "Cluster", text: "3 extra mini blasts"), .init(id: "nuke", name: "Nuke", text: "Blasts 60% bigger")]),
        BallType(kind: .sniper, name: "Sniper", blurb: "Aims after each bounce", about: "After every bounce it turns toward the nearest pixel.",
                 baseCost: 5000, costGrowth: 1.52, speed: 14, damage: 4,
                 specialName: "Range", specialBase: 8, specialPerRank: 6,
                 specs: [.init(id: "seeker", name: "Seeker", text: "Hunts the golden pixel"), .init(id: "marksman", name: "Marksman", text: "2x damage, +25% crit")]),
        BallType(kind: .ghost, name: "Ghost", blurb: "Phases through pixels", about: "Every few seconds it phases through pixels, hitting each one.",
                 baseCost: 12000, costGrowth: 1.6, speed: 9, damage: 3,
                 specialName: "Phase", specialBase: 0.8, specialPerRank: 0.4,
                 specs: [.init(id: "poltergeist", name: "Poltergeist", text: "Phases twice as often"), .init(id: "wraith", name: "Wraith", text: "3x damage while phasing")]),
    ]
}

public enum SkillEffect: Sendable, Equatable {
    case damage(Double), speed(Double), money(Double), crit(Double), critDamage(Double)
    case radar, offline(Double)
    /// Money straight away, per rank bought.
    case cash(Double)
    /// Fog: +1 reveal radius per rank.
    case lantern
    /// Fog: the golden pixel pings a ring through the dark, more often per rank.
    case sonar
    case unlock(BallKind)
    /// One rank of a ball type's damage, speed or special.
    case ballStat(BallKind, Stat)
    /// A ball type's specialisation (each one is its own node; both can be owned).
    case ballSpec(BallKind, String)

    /// The ball type this skill belongs to, if any.
    public var ball: BallKind? {
        switch self {
        case .unlock(let k), .ballStat(let k, _), .ballSpec(let k, _): return k
        default: return nil
        }
    }
}

public struct SkillNode: Sendable {
    public let id: String
    public let name: String
    public let text: String
    /// Shards per rank.
    public let cost: Int
    public let ranks: Int
    public let requires: [String]
    /// Position in the tree, in grid units (one unit = `SkillNode.unit` art pixels at zoom 1).
    /// The core node is at (0, 0); y grows downward.
    public let x: Int
    public let y: Int
    public let effect: SkillEffect

    public static let unit = 16

    /// Every node's full price (cost x ranks) added up: the shards a level holds.
    public static let totalCost: Int = all.reduce(0) { $0 + $1.cost * $1.ranks }

    public static let all: [SkillNode] = core + BallKind.allCases.flatMap(ballBranch)

    /// The general skills. The tree is one tree rooted at Core and laid out on a grid (rows two
    /// units apart) so every link is a straight or right-angled connector: Core sits in the
    /// middle of a horizontal spine (Sharp to the left, Momentum to the right), the ball types'
    /// branches grow up from that spine, crit hangs under Sharp and money and fog under Greed.
    static let core: [SkillNode] = [
        .init(id: "core", name: "Core", text: "+10% damage for every ball", cost: 1, ranks: 1, requires: [], x: 0, y: 0, effect: .damage(0.1)),
        .init(id: "sharp", name: "Sharp", text: "+20% damage per rank", cost: 1, ranks: 5, requires: ["core"], x: -4, y: 0, effect: .damage(0.2)),
        .init(id: "crit", name: "Precision", text: "+4% crit chance per rank", cost: 1, ranks: 5, requires: ["sharp"], x: -4, y: 2, effect: .crit(0.04)),
        .init(id: "critdmg", name: "Brutal", text: "+50% crit damage per rank", cost: 2, ranks: 3, requires: ["crit"], x: -4, y: 4, effect: .critDamage(0.5)),
        .init(id: "momentum", name: "Momentum", text: "+10% ball speed per rank", cost: 1, ranks: 5, requires: ["core"], x: 10, y: 0, effect: .speed(0.1)),
        .init(id: "greed", name: "Greed", text: "+25% coins per rank", cost: 1, ranks: 5, requires: ["core"], x: 0, y: 2, effect: .money(0.25)),
        .init(id: "offline", name: "Idle", text: "+15% coins while away", cost: 1, ranks: 4, requires: ["greed"], x: -1, y: 4, effect: .offline(0.15)),
        .init(id: "cash", name: "Windfall", text: "+500 coins now, per rank", cost: 1, ranks: 5, requires: ["offline"], x: -1, y: 6, effect: .cash(500)),
        .init(id: "lantern", name: "Lantern", text: "Breaks light up 1 cell further", cost: 1, ranks: 3, requires: ["greed"], x: 1, y: 4, effect: .lantern),
        .init(id: "radar", name: "Radar", text: "Boxes in the golden pixel", cost: 2, ranks: 3, requires: ["lantern"], x: 1, y: 6, effect: .radar),
        .init(id: "sonar", name: "Sonar", text: "The golden pixel pings", cost: 2, ranks: 3, requires: ["radar"], x: 1, y: 8, effect: .sonar),
    ]

    /// Where each ball type's branch sits (column x) and what unlocks it. The unlocks share
    /// one row just above the spine: Basic straight above Core, Heavy above Sharp (Bomb beside
    /// it), Lightning and Fast either side of Momentum (Ghost and Sniper beside them).
    static let ballColumn: [BallKind: (x: Int, requires: [String], cost: Int)] = [
        .bomb: (-8, ["u-heavy"], 3), .heavy: (-4, ["sharp"], 2), .basic: (0, ["core"], 0),
        .ghost: (4, ["u-lightning"], 4), .lightning: (8, ["momentum"], 3),
        .fast: (12, ["momentum"], 2), .sniper: (16, ["u-fast"], 3),
    ]

    /// A ball type's branch, growing up from its unlock: damage and speed side by side, then
    /// its special (needs both), then its two specialisations side by side.
    static func ballBranch(_ k: BallKind) -> [SkillNode] {
        let t = k.type, col = ballColumn[k]!, x = col.x, n = t.name
        let u = "u-\(k.rawValue)"
        // Later types' upgrades cost more per rank.
        let c = k.index < 3 ? 1 : 2
        return [
            .init(id: u, name: "\(n) ball", text: k == .basic ? "Your first ball" : "Unlock the \(n.lowercased()) ball",
                  cost: col.cost, ranks: 1, requires: col.requires, x: x, y: -2, effect: .unlock(k)),
            .init(id: "\(k.rawValue)-dmg", name: "\(n) damage", text: "\(n) balls: +50% damage per rank", cost: c, ranks: Stat.damage.max,
                  requires: [u], x: x - 1, y: -4, effect: .ballStat(k, .damage)),
            .init(id: "\(k.rawValue)-spd", name: "\(n) speed", text: "\(n) balls: +12% speed per rank", cost: c, ranks: Stat.speed.max,
                  requires: [u], x: x + 1, y: -4, effect: .ballStat(k, .speed)),
            .init(id: "\(k.rawValue)-sp", name: "\(n) \(t.specialName.lowercased())", text: "\(n) balls: more \(t.specialName.lowercased()) per rank",
                  cost: c, ranks: Stat.special.max, requires: ["\(k.rawValue)-dmg", "\(k.rawValue)-spd"], x: x, y: -6, effect: .ballStat(k, .special)),
            .init(id: "spec-\(t.specs[0].id)", name: t.specs[0].name, text: t.specs[0].text, cost: 3 * c, ranks: 1,
                  requires: ["\(k.rawValue)-sp"], x: x - 1, y: -8, effect: .ballSpec(k, t.specs[0].id)),
            .init(id: "spec-\(t.specs[1].id)", name: t.specs[1].name, text: t.specs[1].text, cost: 3 * c, ranks: 1,
                  requires: ["\(k.rawValue)-sp"], x: x + 1, y: -8, effect: .ballSpec(k, t.specs[1].id)),
        ]
    }

    public static let byID: [String: SkillNode] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The ranks every level starts with: the basic ball.
    public static let startingRanks: [String: Int] = ["u-basic": 1]
}

/// Every balance number, named.
public enum Tuning {
    /// Device pixels per art pixel on the iPhone Duo's inner screen (2853 x 2007 px), and the
    /// art canvas that gives: 475 x 334 (2850 x 2004 px, a 1.5 px margin per side).
    public static let artScale = 6
    public static let canvasWidth = 475
    public static let canvasHeight = 334
    /// The inner screen's rounded corners, in art pixels. Nothing you need to read or press may
    /// sit inside this radius of a screen corner (UISafetyTests checks it).
    public static let cornerRadius = 28
    /// The smallest thing you can press: 22 art pixels = 44 points.
    public static let minTouch = 22

    /// Ball diameter is half a cell: a 5x5 sprite (odd, so it has a true centre pixel) on a
    /// 10x10 block.
    public static let ballRadius = 0.25
    /// Art pixels per smashable block.
    public static let cellPixels = 10
    /// Durability (in hits from an unupgraded basic ball, one per shade) and payout of each
    /// tier. Tier t starts t + 1 steps up the colour ladder (t + 2 hits); the palest shade is
    /// the last hit.
    public static let tierHP: [Double] = [2, 3, 4, 5, 6]
    public static let tierValue: [Double] = [1, 3, 7, 15, 32]
    /// Coins per break on each campaign level (later levels use the last), set with `gp-sim`
    /// so each level takes a player about 15 to 30 minutes whatever its shape and size.
    public static let levelPayout: [Double] = [0.4, 0.3, 0.15, 0.25, 0.35, 0.3, 0.3]
    public static let richMultiplier = 5.0
    /// Odds that a block is rich.
    public static let richChance = 0.02
    /// Golden pixel HP on level 1, and its growth per level.
    public static let goldHP = 400.0
    public static let goldHPGrowth = 1.5
    public static let goldValueMultiplier = 40.0
    /// Shard pixels: how many a level hides (their values add up to the whole skill tree), how
    /// tough they are (as a tier), and how far into the dark you can sense them.
    public static let shardsPerLevel = 60
    /// Shard pixels break in one hit.
    public static let shardHP = 1.0
    public static let shardSenseRadius = 6
    /// At most this many sensed shards show through the dark at once (the closest ones).
    public static let maxSensedShards = 2
    /// Shards never sit closer than this to each other or the spawn.
    public static let shardSpacing = 4
    /// The two starter shards sit this many cells (Chebyshev) from the spawn, with no rock in
    /// the way.
    public static let starterShardRange = 7...8
    /// The open pocket the balls start in: a rounded square this many cells from the spawn.
    public static let spawnPocketRadius = 4
    /// A shard pixel's share of the level's shards grows with its distance from the spawn to
    /// this power: the ones near the start pay a shard or two, the deep ones pay a lot. This
    /// is what keeps the tree (and the snowball it brings) from arriving all at once.
    public static let shardDepthBias = 2.5
    /// Fog: cells within this many cells (Chebyshev) of an open cell are visible.
    public static let revealRadius = 3
    public static let goldGlowRadius = 3.5
    public static let sonarIntervals: [Double] = [0, 18, 11, 6]
    public static let radarHintRadius: [Int] = [0, 16, 9, 4]
    public static let offlineCapSeconds = 8.0 * 3600
    public static let levelClearPause = 2.2
    public static let maxBalls = 400
    /// Coins at the start of every level: exactly one basic ball, which you place yourself.
    public static let startCoins = 5.0
    /// Each star (one per golden pixel) adds this much damage and money, for good.
    public static let starDamage = 0.05
    public static let starMoney = 0.1
}
