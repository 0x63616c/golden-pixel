/// Fog of war. The rule is one sentence: every cell within `Tuning.revealRadius` (3) cells,
/// Chebyshev distance, of an open cell (the spawn pocket or anything broken) is visible, and
/// everything else is pure black. So a level starts as the spawn pocket plus a 3-cell border,
/// and each break pushes the light 3 cells further. The Lantern skill widens the radius.
/// Balls bouncing off hidden walls reveal just that wall, so the arena's outline emerges.
public enum Fog {
    /// Seconds a cell takes to dither in, and the ripple delay per cell of distance.
    public static let fadeTime = 0.22
    public static let rippleDelay = 0.035

    /// Reveals every cell within `radius` cells (Chebyshev: a square) of (cx, cy), rippling
    /// outward one ring per `rippleDelay`. Returns the newly revealed indices, nearest first.
    @discardableResult
    public static func reveal(_ b: Board, _ cx: Int, _ cy: Int, radius: Int, at t: Double) -> [Int] {
        var out: [(Int, Int)] = []
        for dy in -radius...radius {
            for dx in -radius...radius {
                let x = cx + dx, y = cy + dy
                guard b.inside(x, y) else { continue }
                let i = b.index(x, y)
                if b.revealed[i] { continue }
                b.revealed[i] = true
                let d = max(abs(dx), abs(dy))
                b.revealedAt[i] = t + Double(d) * rippleDelay
                out.append((d * 1000 + dx * dx + dy * dy, i))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The level-start reveal: every open cell plus a `radius`-cell border, rippling out from
    /// the spawn.
    @discardableResult
    public static func revealOpen(_ b: Board, radius: Int, at t: Double) -> [Int] {
        var out: [Int] = []
        for i in b.kind.indices where b.kind[i] == .empty {
            let x = i % b.size, y = i / b.size
            let d = max(abs(x - b.spawn.x), abs(y - b.spawn.y))
            out += reveal(b, x, y, radius: radius, at: t + Double(d) * rippleDelay)
        }
        return out
    }

    /// Chebyshev distance from cell i to the nearest open cell, or nil when none is within
    /// `limit`. The fog invariant: revealed == (distance <= revealRadius).
    public static func distanceToOpen(_ b: Board, _ i: Int, limit: Int) -> Int? {
        let x = i % b.size, y = i / b.size
        var best: Int?
        for dy in -limit...limit {
            for dx in -limit...limit where b.inside(x + dx, y + dy) && b.kind[b.index(x + dx, y + dy)] == .empty {
                let d = max(abs(dx), abs(dy))
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }

    /// 0 (black) ... 1 (fully shown) for the dither-in at time `t`.
    public static func coverage(_ b: Board, _ i: Int, at t: Double) -> Double {
        guard b.revealed[i] else { return 0 }
        let since = t - b.revealedAt[i]
        if since <= 0 { return 0 }
        return min(1, since / fadeTime)
    }

    /// Whether you've dug close enough to sense the gold: a revealed cell within
    /// `Tuning.goldSenseRadius` cells of it (Chebyshev). Until then it gives nothing away.
    public static func goldSensed(_ b: Board, radius: Int = Tuning.goldSenseRadius) -> Bool {
        let g = b.gold
        for dy in -radius...radius {
            for dx in -radius...radius where b.inside(g.x + dx, g.y + dy) && b.revealed[b.index(g.x + dx, g.y + dy)] {
                return true
            }
        }
        return false
    }

    /// How strongly the golden pixel glows through the dark at cell (x, y), 0...1. Only once
    /// it's sensed (`goldSensed`), only hidden cells near the gold glow, and it pulses, so you
    /// spot it a few cells into the black as you close in.
    public static func goldGlow(_ b: Board, _ x: Int, _ y: Int, at t: Double) -> Double {
        guard b.kind[b.index(b.gold.x, b.gold.y)] == .gold, goldSensed(b) else { return 0 }
        return goldGlow(dx: x - b.gold.x, dy: y - b.gold.y, pulse: goldPulse(at: t))
    }

    /// The glow's beat at time `t`: the same for every cell.
    @inline(__always) static func goldPulse(at t: Double) -> Double { 0.55 + 0.45 * sin(t * 2.6) }

    /// The glow (dx, dy) cells from a gold that is standing and sensed.
    @inline(__always) static func goldGlow(dx: Int, dy: Int, pulse: Double) -> Double {
        let dx = Double(dx), dy = Double(dy)
        let d = (dx * dx + dy * dy).squareRoot()
        guard d <= Tuning.goldGlowRadius else { return 0 }
        return max(0, 1 - d / (Tuning.goldGlowRadius + 0.5)) * pulse
    }

    /// A hidden shard pixel shows through the dark once any revealed cell is within
    /// `Tuning.shardSenseRadius` cells of it (Chebyshev): you sense the next few as you dig
    /// toward them, never the whole level at once.
    public static func shardSensed(_ b: Board, _ i: Int, radius: Int = Tuning.shardSenseRadius) -> Bool {
        guard b.kind[i] == .shard, !b.revealed[i] else { return false }
        let x = i % b.size, y = i / b.size
        for dy in -radius...radius {
            for dx in -radius...radius where b.inside(x + dx, y + dy) && b.revealed[b.index(x + dx, y + dy)] {
                return true
            }
        }
        return false
    }

    /// The shards actually shown in the dark: of the sensed ones, only the `limit` closest to
    /// the light (ties broken by position), so the dark never fills up with mint.
    public static func shownShards(_ b: Board, limit: Int = Tuning.maxSensedShards, radius: Int = Tuning.shardSenseRadius) -> [Int] {
        var found: [(d: Int, i: Int)] = []
        for i in b.kind.indices where b.kind[i] == .shard && !b.revealed[i] {
            let x = i % b.size, y = i / b.size
            var best: Int?
            for dy in -radius...radius {
                for dx in -radius...radius where b.inside(x + dx, y + dy) && b.revealed[b.index(x + dx, y + dy)] {
                    let d = max(abs(dx), abs(dy))
                    if best == nil || d < best! { best = d }
                }
            }
            if let d = best { found.append((d, i)) }
        }
        return found.sorted { ($0.d, $0.i) < ($1.d, $1.i) }.prefix(limit).map(\.i)
    }

    /// The radar's hint square around the gold, or nil without the skill. Deterministic per
    /// level, and the gold is always inside it.
    public static func radarHint(_ b: Board, rank: Int) -> (center: Point, radius: Int)? {
        guard rank > 0, rank < Tuning.radarHintRadius.count else { return nil }
        let r = Tuning.radarHintRadius[rank]
        var rng = RNG(seed: UInt64(b.level * 131 + rank))
        let ox = rng.int(2 * r + 1) - r, oy = rng.int(2 * r + 1) - r
        let c = Point(min(b.size - 1, max(0, b.gold.x + ox / 2)), min(b.size - 1, max(0, b.gold.y + oy / 2)))
        return (c, r)
    }

    public static func revealedFraction(_ b: Board) -> Double {
        Double(b.revealed.reduce(0) { $0 + ($1 ? 1 : 0) }) / Double(b.revealed.count)
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
