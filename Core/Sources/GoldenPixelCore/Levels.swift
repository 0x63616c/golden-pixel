/// Level design. Each level is a big arena (40 to 60+ cells across, far more than one screen)
/// on a square board sized to fit it; the rest is solid wall, hidden in the fog. Shard pixels
/// are scattered through it, and their shards add up to the whole skill tree.
///
/// Durability is laid out, not rolled: rock gets tougher the further it is from the spawn, with
/// soft pockets and hard clumps through it (`LevelGen.durabilityScores`). A level's mix of
/// tiers still follows a weighted table that shifts tougher on later levels. Walls are the only
/// unbreakable cells; the golden pixel is its own kind.

public enum Shape: String, Sendable, CaseIterable { case blob, canyon, ring, pillars, spiral, labyrinth, core }

public struct LevelSpec: Sendable {
    public let name: String
    public let shape: Shape
    /// Arena radius in cells.
    public let radius: Int

    public static let campaign: [LevelSpec] = [
        .init(name: "FIRST LIGHT", shape: .blob, radius: 44),
        .init(name: "TWIN RIDGE", shape: .canyon, radius: 45),
        .init(name: "THE RING", shape: .ring, radius: 46),
        .init(name: "PILLARS", shape: .pillars, radius: 47),
        .init(name: "SPIRAL", shape: .spiral, radius: 48),
        .init(name: "LABYRINTH", shape: .labyrinth, radius: 49),
        .init(name: "THE CORE", shape: .core, radius: 50),
    ]

    public static func forLevel(_ level: Int) -> LevelSpec {
        if level >= 1 && level <= campaign.count { return campaign[level - 1] }
        let n = level - campaign.count
        let shapes = Shape.allCases
        return LevelSpec(name: "DEEP \(n)", shape: shapes[(n * 3) % shapes.count], radius: 51)
    }

    /// The board is the arena plus a wall rim.
    public var boardSize: Int { 2 * radius + 5 }
}

public enum LevelGen {
    public static func make(level: Int, at t: Double = 0) -> Board {
        let spec = LevelSpec.forLevel(level)
        let size = spec.boardSize
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
            // Two ridges, each broken by a two-cell pass every 14 cells (staggered), so the
            // land beyond them can be dug too.
            for x in (c - R)...(c + R) {
                let off = 3.0 * sin(Double(x) * 0.23 + phase)
                let along = x - (c - R)
                if along % 14 >= 2 { wall(x, c - 5 + Int(off.rounded())) }
                if (along + 7) % 14 >= 2 { wall(x, c + 5 + Int(off.rounded())) }
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
            while a < 6.28 * 2.2 {
                let r = 2.5 + a * Double(R - 3) / (6.28 * 2.2)
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
        let pr = Tuning.spawnPocketRadius
        for dy in -pr...pr { for dx in -pr...pr where dx * dx + dy * dy <= pr * pr + 2 {
            let x = spawn.x + dx, y = spawn.y + dy
            if b.inside(x, y), mask[b.index(x, y)] { b.kind[b.index(x, y)] = .empty }
        } }
        b.spawn = spawn
        // A fixed gold spot is never boxed in by walls.
        if let g = gold {
            for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] where b.inside(g.x + dx, g.y + dy) {
                let i = b.index(g.x + dx, g.y + dy)
                if mask[i], b.kind[i] == .wall { b.kind[i] = .block }
            }
        }
        // Pockets the balls could never reach turn to rock, so every block, shard and the gold
        // can be dug to from the spawn.
        sealUnreachable(b, from: spawn)

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

        // 5. Durability: deeper is tougher, with patches. Every block gets a score (distance
        // from the spawn plus smooth noise); the softest-scoring share of the blocks becomes
        // tier 0, the next share tier 1, and so on, each share sized by the level's tier
        // weights. So the mix is exactly the table's, and only where it sits is designed.
        // A few cells are rich (sparkling, 5x payout), rolled per cell.
        let blocks = (0..<(size * size)).filter { b.kind[$0] == .block }
        let scores = durabilityScores(b, blocks: blocks, rng: &rng)
        let ranked = blocks.indices.sorted { scores[$0] < scores[$1] }
        let weights = tierWeights(level: level)
        let total = weights.reduce(0, +)
        var tier = 0, upTo = weights[0] / total
        for (rank, k) in ranked.enumerated() {
            while tier < weights.count - 1, Double(rank) / Double(ranked.count) >= upTo {
                tier += 1; upTo += weights[tier] / total
            }
            b.tier[blocks[k]] = UInt8(tier)
        }
        for i in blocks { b.rich[i] = rng.unit() < Tuning.richChance }
        b.kind[b.index(g.x, g.y)] = .gold
        b.tier[b.index(g.x, g.y)] = 4
        b.rich[b.index(g.x, g.y)] = false
        placeShards(b, rng: &rng)

        // 6. Hit points.
        for i in 0..<(size * size) {
            switch b.kind[i] {
            case .block:
                let h = Economy.tierHP(Int(b.tier[i]), level: level)
                b.hp[i] = h; b.maxHP[i] = h
            case .gold:
                let h = Economy.goldHP(level: level)
                b.hp[i] = h; b.maxHP[i] = h
            case .shard:
                let h = Tuning.shardHP
                b.hp[i] = h; b.maxHP[i] = h
            default: break
            }
        }

        Fog.revealOpen(b, radius: Tuning.revealRadius, at: t)
        return b
    }

    /// How tough each of `blocks` should be, relative to the others (higher = tougher): its
    /// straight-line distance from the spawn (0 at the spawn, 1 at the farthest block) blended
    /// with two octaves of smooth value noise, so there are soft pockets to dig toward and hard
    /// clumps to go round, plus a little per-cell grain so patch edges aren't clean lines.
    static func durabilityScores(_ b: Board, blocks: [Int], rng: inout RNG) -> [Double] {
        let coarse = valueNoise(size: b.size, cell: Tuning.durabilityPatchSize, rng: &rng)
        let fine = valueNoise(size: b.size, cell: Tuning.durabilityPatchSize / 2, rng: &rng)
        func depth(_ i: Int) -> Double { dist(Point(i % b.size, i / b.size), b.spawn) }
        let deepest = max(1, blocks.map(depth).max() ?? 1)
        let w = Tuning.durabilityDepthWeight
        return blocks.map { i in
            let patch = 0.7 * coarse[i] + 0.3 * fine[i]
            return w * depth(i) / deepest + (1 - w) * patch + Tuning.durabilityGrain * rng.unit()
        }
    }

    /// Smooth noise in 0...1 over a size x size board: random values on a lattice `cell`
    /// cells apart, blended between with smoothstep.
    static func valueNoise(size: Int, cell: Int, rng: inout RNG) -> [Double] {
        let g = size / cell + 2
        let lattice = (0..<(g * g)).map { _ in rng.unit() }
        func s(_ t: Double) -> Double { t * t * (3 - 2 * t) }
        var out = [Double](repeating: 0, count: size * size)
        for y in 0..<size { for x in 0..<size {
            let ix = x / cell, iy = y / cell
            let tx = s(Double(x % cell) / Double(cell)), ty = s(Double(y % cell) / Double(cell))
            let a = lattice[iy * g + ix], c = lattice[iy * g + ix + 1]
            let d = lattice[(iy + 1) * g + ix], e = lattice[(iy + 1) * g + ix + 1]
            out[y * size + x] = (a + (c - a) * tx) * (1 - ty) + (d + (e - d) * tx) * ty
        } }
        return out
    }

    /// Relative odds of tiers 0...4 on a level: mostly soft on level 1, sliding toward the
    /// hard end until level 13, then fixed.
    public static func tierWeights(level: Int) -> [Double] {
        let early: [Double] = [40, 30, 18, 9, 3]
        let late: [Double] = [8, 17, 25, 28, 22]
        let s = min(1, Double(max(0, level - 1)) / 12)
        return zip(early, late).map { $0 + ($1 - $0) * s }
    }

    /// Scatters the level's shard pixels through the arena: spaced apart, away from the spawn
    /// and the gold, never on a wall. The first two sit just past the starting light so you
    /// always sense a couple straight away; the rest fan out, and you sense each one as your
    /// digging gets within `Tuning.shardSenseRadius` of it.
    static func placeShards(_ b: Board, rng: inout RNG) {
        var spots: [Point] = []
        let candidates = b.kind.indices.filter { b.kind[$0] == .block }.map { Point($0 % b.size, $0 / b.size) }
        func cheb(_ a: Point, _ c: Point) -> Int { max(abs(a.x - c.x), abs(a.y - c.y)) }
        func ok(_ p: Point) -> Bool {
            cheb(p, b.gold) > 3 && spots.allSatisfy { cheb($0, p) >= Tuning.shardSpacing }
        }
        // Two near starters, a few cells from the spawn with nothing but blocks in between.
        let steps = stepsFrom(b, b.spawn, limit: 12)
        let near = candidates.filter {
            let d = cheb($0, b.spawn)
            return Tuning.starterShardRange.contains(d) && steps[b.index($0.x, $0.y)] <= d + 2
        }
        for _ in 0..<200 where spots.count < 2 && !near.isEmpty {
            let p = near[rng.int(near.count)]
            if ok(p) { spots.append(p) }
        }
        // The rest anywhere, but not inside the starting light.
        let far = candidates.filter { cheb($0, b.spawn) >= Tuning.revealRadius + 4 }
        var tries = 0
        while spots.count < Tuning.shardsPerLevel && tries < 20_000 && !far.isEmpty {
            tries += 1
            let p = far[rng.int(far.count)]
            if ok(p) { spots.append(p) }
        }
        // Deeper shards pay more (`Tuning.shardDepthBias`).
        let values = Economy.shardValues(weights: spots.map { pow(Double(cheb($0, b.spawn)), Tuning.shardDepthBias) })
        for (p, v) in zip(spots, values) {
            let i = b.index(p.x, p.y)
            b.kind[i] = .shard
            b.shardValue[i] = v
            b.rich[i] = false
        }
    }

    /// Steps (up, down, left or right, never through a wall) from `p` to every cell, counted
    /// up to `limit`; cells further away read `Int.max`.
    static func stepsFrom(_ b: Board, _ p: Point, limit: Int) -> [Int] {
        var steps = Array(repeating: Int.max, count: b.kind.count)
        var frontier = [b.index(p.x, p.y)]
        steps[frontier[0]] = 0
        for d in 1...limit {
            var next: [Int] = []
            for i in frontier {
                let x = i % b.size, y = i / b.size
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where b.inside(x + dx, y + dy) {
                    let j = b.index(x + dx, y + dy)
                    if steps[j] == Int.max, b.kind[j] != .wall { steps[j] = d; next.append(j) }
                }
            }
            frontier = next
        }
        return steps
    }

    /// Turns every open or breakable cell that can't be reached from `p` (stepping up, down,
    /// left or right, never through a wall) into wall.
    static func sealUnreachable(_ b: Board, from p: Point) {
        var seen = Array(repeating: false, count: b.kind.count)
        var stack = [b.index(p.x, p.y)]
        seen[stack[0]] = true
        while let i = stack.popLast() {
            let x = i % b.size, y = i / b.size
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where b.inside(x + dx, y + dy) {
                let j = b.index(x + dx, y + dy)
                if !seen[j], b.kind[j] != .wall { seen[j] = true; stack.append(j) }
            }
        }
        for i in b.kind.indices where !seen[i] { b.kind[i] = .wall }
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

    /// A coarse maze: cells of 9 blocks with one-block walls, carved by a depth-first walk.
    /// Only maze cells wholly inside the arena disc take part; the clipped ones round the rim
    /// stay open, so the walk can never wall the gold off from the spawn.
    static func maze(_ b: Board, _ mask: [Bool], c: Int, R: Int, rng: inout RNG) {
        let cell = 9
        let n = (2 * R) / cell
        let origin = c - (n * cell) / 2
        let inDisc: [Bool] = (0..<(n * n)).map { i in
            let x0 = origin + (i % n) * cell, y0 = origin + (i / n) * cell
            return [(x0, y0), (x0 + cell, y0), (x0, y0 + cell), (x0 + cell, y0 + cell)].allSatisfy { p in
                (p.0 - c) * (p.0 - c) + (p.1 - c) * (p.1 - c) <= R * R
            }
        }
        // Cells outside the disc count as visited, so the walk stays inside.
        var visited = inDisc.map { !$0 }
        // Open wall segments between cells: right[i] and down[i].
        var openRight = Array(repeating: false, count: n * n)
        var openDown = Array(repeating: false, count: n * n)
        guard let first = inDisc.firstIndex(of: true) else { return }
        var stack = [first]
        visited[first] = true
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
                if gx + 1 < n, inDisc[i] && inDisc[i + 1] {
                    for y in y0...(y0 + cell) where !(openRight[i] && y > y0 + 1 && y < y0 + cell - 1) {
                        setWall(b, mask, x0 + cell, y)
                    }
                }
                if gy + 1 < n, inDisc[i] && inDisc[i + n] {
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
