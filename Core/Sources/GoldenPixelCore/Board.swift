/// The level grid: struct-of-arrays so the simulation and renderer can walk it quickly.

public enum CellKind: UInt8, Codable, Sendable {
    case empty, wall, block, gold
    /// A glowing shard pixel: breaking it pays skill-tree shards.
    case shard
    /// Blocks, shards and the gold: anything a hit can damage.
    public var breakable: Bool { self == .block || self == .gold || self == .shard }
}

/// SplitMix64: small, fast and deterministic on every platform.
public struct RNG: Sendable {
    public var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// 0..<1
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(next() % UInt64(n)) }
    public mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
}

public final class Board {
    public let size: Int
    public var kind: [CellKind]
    public var tier: [UInt8]
    public var rich: [Bool]
    /// Shards paid by each shard pixel (0 elsewhere).
    public var shardValue: [Int]
    public var hp: [Double]
    public var maxHP: [Double]
    public var revealed: [Bool]
    /// When each cell was revealed (game time), for the dither-in animation. -1 if never.
    public var revealedAt: [Double]
    /// When each cell was last hit, for the flash.
    public var hitAt: [Double]
    public var spawn: Point
    public var gold: Point
    public var level: Int
    public var name: String

    public init(size: Int, level: Int, name: String) {
        self.size = size
        self.level = level
        self.name = name
        let n = size * size
        kind = Array(repeating: .wall, count: n)
        tier = Array(repeating: 0, count: n)
        rich = Array(repeating: false, count: n)
        shardValue = Array(repeating: 0, count: n)
        hp = Array(repeating: 0, count: n)
        maxHP = Array(repeating: 0, count: n)
        revealed = Array(repeating: false, count: n)
        revealedAt = Array(repeating: -1, count: n)
        hitAt = Array(repeating: -10, count: n)
        spawn = Point(size / 2, size / 2)
        gold = Point(0, 0)
    }

    @inline(__always) public func index(_ x: Int, _ y: Int) -> Int { y * size + x }
    @inline(__always) public func inside(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < size && y < size }

    public func kindAt(_ x: Int, _ y: Int) -> CellKind { inside(x, y) ? kind[index(x, y)] : .wall }

    public var blocksLeft: Int { kind.reduce(0) { $0 + ($1 == .block ? 1 : 0) } }
    public var shardsLeft: Int { kind.reduce(0) { $0 + ($1 == .shard ? 1 : 0) } }
    /// Board size in art pixels.
    public var pixelSize: Int { size * Tuning.cellPixels }
}
