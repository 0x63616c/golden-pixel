/// Level design. Every board is 41x41 blocks, but each level shapes its own arena inside it
/// and the rest is solid wall, hidden in the fog until a ball finds it.
///
/// Durability is per cell: every breakable cell rolls its own tier from a seeded, weighted
/// table that shifts tougher on later levels, so the board is a mixed speckle of durability
/// colours. Walls are the only unbreakable cells; the golden pixel is its own kind.

public enum Shape: String, Sendable, CaseIterable { case blob, canyon, ring, pillars, spiral, labyrinth, core }

public struct LevelSpec: Sendable {
    public let name: String
    public let shape: Shape
    /// Arena radius in cells.
    public let radius: Int

    public static let campaign: [LevelSpec] = [
        .init(name: "FIRST LIGHT", shape: .blob, radius: 12),
        .init(name: "TWIN RIDGE", shape: .canyon, radius: 13),
        .init(name: "THE RING", shape: .ring, radius: 14),
        .init(name: "PILLARS", shape: .pillars, radius: 15),
        .init(name: "SPIRAL", shape: .spiral, radius: 16),
        .init(name: "LABYRINTH", shape: .labyrinth, radius: 17),
        .init(name: "THE CORE", shape: .core, radius: 18),
    ]

    public static func forLevel(_ level: Int) -> LevelSpec {
        if level >= 1 && level <= campaign.count { return campaign[level - 1] }
        let n = level - campaign.count
        let shapes = Shape.allCases
        return LevelSpec(name: "DEEP \(n)", shape: shapes[(n * 3) % shapes.count], radius: 19)
    }
}

public enum LevelGen {
    public static func make(level: Int, size: Int = Tuning.boardCells, at t: Double = 0) -> Board {
        let spec = LevelSpec.forLevel(level)
        let b = Board(size: size, level: level, name: spec.name)
        var rng = RNG(seed: UInt64(level) &* 0x2545_F491_4F6C_DD1D &+ 17)
        let c = size / 2
        let R = min(spec.radius, c - 1)

        // 1. Arena mask: a disc, wobbly for the organic levels.
        var mask = Array(repeating: false, count: size * size)
        let wobble = spec.shape == .blob || spec.shape == .canyon ? 1.6 : 0.0
        let ph1 = rng.range(0, 6.28), ph2 = rng.range(0, 6.28)
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x - c), dy = Double(y - c)
                let a = atan2(dy, dx)
                let r = Double(R) + wobble * (sin(a * 3 + ph1) + 0.6 * sin(a * 5 + ph2))
                if dx * dx + dy * dy <= r * r, x > 0, y > 0, x < size - 1, y < size - 1 { mask[y * size + x] = true }
            }
        }
        for i in 0..<(size * size) where mask[i] { b.kind[i] = .block }

        func wall(_ x: Int, _ y: Int) {
            guard b.inside(x, y), mask[b.index(x, y)] else { return }
            b.kind[b.index(x, y)] = .wall
        }

        // 2. Shape features, spawn and (for centred shapes) the gold.
        // Start near the bottom of the arena so the gold has room to hide far away.
        var spawn = Point(c, c + R - 4)
        var gold: Point? = nil
        switch spec.shape {
        case .blob:
            for _ in 0..<5 {
                let a = rng.range(0, 6.28)
                let len = 2 + rng.int(4)
                for s in 0..<len {
                    let r = Double(R - s)
                    wall(c + Int((cos(a) * r).rounded()), c + Int((sin(a) * r).rounded()))
                }
            }
        case .canyon:
            let phase = rng.range(0, 6.28)
            for x in (c - R)...(c + R) {
                let off = 3.0 * sin(Double(x) * 0.23 + phase)
                wall(x, c - 5 + Int(off.rounded()))
                wall(x, c + 5 + Int(off.rounded()))
            }
            spawn = Point(c - R + 3, c + Int((3.0 * sin(Double(c - R + 3) * 0.23 + phase)).rounded()))
            gold = Point(c + R - 3, c + Int((3.0 * sin(Double(c + R - 3) * 0.23 + phase)).rounded()))
        case .ring:
            ringWall(b, mask, c, radius: Double(R) * 0.45, doors: 4, rng: &rng)
            spawn = Point(c, c + R - 3)
            gold = Point(c, c)
        case .pillars:
            var y = c - R + 3
            while y < c + R - 2 {
                var x = c - R + 3
                while x < c + R - 2 {
                    if abs(x - c) > 3 || abs(y - c) > 3 { wall(x, y); wall(x + 1, y); wall(x, y + 1); wall(x + 1, y + 1) }
                    x += 6
                }
                y += 6
            }
        case .spiral:
            // Archimedean spiral wall: balls have to work their way inward.
            var a = 0.0
            while a < 6.28 * 3.2 {
                let r = 2.5 + a * Double(R - 3) / (6.28 * 3.2)
                wall(c + Int((cos(a) * r).rounded()), c + Int((sin(a) * r).rounded()))
                a += 0.5 / max(1, r)
            }
            spawn = Point(c, c + R - 2)
            gold = Point(c, c)
        case .labyrinth:
            maze(b, mask, c: c, R: R, rng: &rng)
            spawn = Point(c - R / 2 - 2, c - R / 2 - 2)
            gold = Point(c + R / 2 + 2, c + R / 2 + 2)
        case .core:
            ringWall(b, mask, c, radius: Double(R) * 0.3, doors: 2, rng: &rng)
            ringWall(b, mask, c, radius: Double(R) * 0.62, doors: 3, rng: &rng)
            spawn = Point(c, c + R - 3)
            gold = Point(c, c)
        }

        // 3. Clear a pocket for the balls to start in.
        for dy in -2...2 { for dx in -2...2 where dx * dx + dy * dy <= 5 {
            let x = spawn.x + dx, y = spawn.y + dy
            if b.inside(x, y), mask[b.index(x, y)] { b.kind[b.index(x, y)] = .empty }
        } }
        b.spawn = spawn

        // 4. The gold: far from the spawn, never on a wall.
        let maxSpawnDist = maxDistance(mask, size, from: spawn)
        if gold == nil {
            var best = -1.0
            for y in 0..<size { for x in 0..<size where b.kind[b.index(x, y)] == .block {
                let d = dist(Point(x, y), spawn)
                guard d > maxSpawnDist * 0.72 else { continue }
                // Keep it off the arena edge so it is fully surrounded by blocks.
                let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { b.kindAt(x + $0.0, y + $0.1) == .wall }
                if edge { continue }
                let score = d + rng.range(0, 6)
                if score > best { best = score; gold = Point(x, y) }
            } }
        }
        let g = gold ?? Point(c, c)
        b.gold = g

        // 5. Durability: every breakable cell rolls its own tier, independently, from a weighted
        // table that leans tougher each level. No zones or clusters: the board is a speckle.
        // A few cells are rich (sparkling, 5x payout), also rolled per cell.
        let weights = tierWeights(level: level)
        let total = weights.reduce(0, +)
        for i in 0..<(size * size) where b.kind[i] == .block {
            var roll = rng.range(0, total), tier = 0
            while tier < weights.count - 1 && roll >= weights[tier] { roll -= weights[tier]; tier += 1 }
            b.tier[i] = UInt8(tier)
            b.rich[i] = rng.unit() < Tuning.richChance
        }
        b.kind[b.index(g.x, g.y)] = .gold
        b.tier[b.index(g.x, g.y)] = 4
        b.rich[b.index(g.x, g.y)] = false

        // 6. Hit points.
        for i in 0..<(size * size) {
            switch b.kind[i] {
            case .block:
                let h = Economy.tierHP(Int(b.tier[i]), level: level) * (b.rich[i] ? 1.5 : 1)
                b.hp[i] = h; b.maxHP[i] = h
            case .gold:
                let h = Economy.tierHP(4, level: level) * Tuning.goldHPMultiplier
                b.hp[i] = h; b.maxHP[i] = h
            default: break
            }
        }

        Fog.revealOpen(b, radius: Tuning.revealRadius, at: t)
        return b
    }

    /// Relative odds of tiers 0...4 on a level: mostly soft on level 1, sliding toward the
    /// hard end until level 13, then fixed.
    public static func tierWeights(level: Int) -> [Double] {
        let early: [Double] = [40, 30, 18, 9, 3]
        let late: [Double] = [8, 17, 25, 28, 22]
        let s = min(1, Double(max(0, level - 1)) / 12)
        return zip(early, late).map { $0 + ($1 - $0) * s }
    }

    static func ringWall(_ b: Board, _ mask: [Bool], _ c: Int, radius: Double, doors: Int, rng: inout RNG) {
        let doorAngles = (0..<doors).map { Double($0) * 6.28 / Double(doors) + rng.range(0, 1.2) }
        var a = 0.0
        while a < 6.283 {
            let nearDoor = doorAngles.contains { abs(angleDiff(a, $0)) * radius < 1.6 }
            if !nearDoor {
                let x = c + Int((cos(a) * radius).rounded()), y = c + Int((sin(a) * radius).rounded())
                if b.inside(x, y), mask[b.index(x, y)] { b.kind[b.index(x, y)] = .wall }
            }
            a += 0.4 / max(1, radius)
        }
    }

    /// A coarse maze: cells of 7 blocks with one-block walls, carved by a depth-first walk.
    static func maze(_ b: Board, _ mask: [Bool], c: Int, R: Int, rng: inout RNG) {
        let cell = 7
        let n = (2 * R) / cell
        let origin = c - (n * cell) / 2
        var visited = Array(repeating: false, count: n * n)
        // Open wall segments between cells: right[i] and down[i].
        var openRight = Array(repeating: false, count: n * n)
        var openDown = Array(repeating: false, count: n * n)
        var stack = [0]
        visited[0] = true
        while let cur = stack.last {
            let cx = cur % n, cy = cur / n
            var options: [(Int, Int)] = []
            if cx + 1 < n, !visited[cur + 1] { options.append((cur + 1, 0)) }
            if cx > 0, !visited[cur - 1] { options.append((cur - 1, 1)) }
            if cy + 1 < n, !visited[cur + n] { options.append((cur + n, 2)) }
            if cy > 0, !visited[cur - n] { options.append((cur - n, 3)) }
            if options.isEmpty { stack.removeLast(); continue }
            let (nx, d) = options[rng.int(options.count)]
            switch d {
            case 0: openRight[cur] = true
            case 1: openRight[nx] = true
            case 2: openDown[cur] = true
            default: openDown[nx] = true
            }
            visited[nx] = true
            stack.append(nx)
        }
        for gy in 0..<n {
            for gx in 0..<n {
                let i = gy * n + gx
                let x0 = origin + gx * cell, y0 = origin + gy * cell
                if gx + 1 < n {
                    for y in y0...(y0 + cell) where !(openRight[i] && y > y0 + 1 && y < y0 + cell - 1) {
                        setWall(b, mask, x0 + cell, y)
                    }
                }
                if gy + 1 < n {
                    for x in x0...(x0 + cell) where !(openDown[i] && x > x0 + 1 && x < x0 + cell - 1) {
                        setWall(b, mask, x, y0 + cell)
                    }
                }
            }
        }
    }

    static func setWall(_ b: Board, _ mask: [Bool], _ x: Int, _ y: Int) {
        guard b.inside(x, y), mask[b.index(x, y)] else { return }
        b.kind[b.index(x, y)] = .wall
    }

    static func angleDiff(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 6.283185)
        if d > 3.14159 { d -= 6.283185 }
        if d < -3.14159 { d += 6.283185 }
        return d
    }

    static func dist(_ a: Point, _ b: Point) -> Double {
        let dx = Double(a.x - b.x), dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func maxDistance(_ mask: [Bool], _ size: Int, from p: Point) -> Double {
        var m = 0.0
        for y in 0..<size { for x in 0..<size where mask[y * size + x] { m = max(m, dist(Point(x, y), p)) } }
        return m
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
