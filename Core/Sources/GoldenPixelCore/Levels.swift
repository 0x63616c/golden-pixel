/// Level design. Each level is a place with its own outline and its own idea about space (an
/// open cave, a neck between two bulbs, a hub with four ways out, rooms, one long coil, a maze,
/// a castle), 80 to 100 cells across on a square board sized to fit it; the rest is solid rock,
/// hidden in the fog. Shard pixels are scattered through it, and their shards add up to the
/// whole skill tree.
///
/// Durability is laid out, not rolled: rock gets tougher the further the dig has to go to
/// reach it from the spawn, with soft pockets and hard clumps through it
/// (`LevelGen.durabilityScores`). A level's mix of tiers still follows a weighted table that
/// shifts tougher on later levels. Walls are the only unbreakable cells; the golden pixel is
/// its own kind.

public enum Shape: String, Sendable, CaseIterable { case cavern, hourglass, crossroads, honeycomb, nautilus, labyrinth, citadel }

public struct LevelSpec: Sendable {
    public let name: String
    public let shape: Shape
    /// Half the arena's width in cells.
    public let radius: Int

    public static let campaign: [LevelSpec] = [
        .init(name: "FIRST LIGHT", shape: .cavern, radius: 44),
        .init(name: "HOURGLASS", shape: .hourglass, radius: 45),
        .init(name: "CROSSROADS", shape: .crossroads, radius: 46),
        .init(name: "HONEYCOMB", shape: .honeycomb, radius: 47),
        .init(name: "NAUTILUS", shape: .nautilus, radius: 48),
        .init(name: "LABYRINTH", shape: .labyrinth, radius: 49),
        .init(name: "CITADEL", shape: .citadel, radius: 50),
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

/// A level being drawn. Shapes work in cells measured from the middle of the board (x to the
/// right, y down), so their geometry reads the same whatever the board size.
struct Plan {
    let size: Int
    /// The board's middle cell.
    let c: Int
    /// Half the arena's width: shapes keep within this of the middle.
    let R: Double
    /// Cells that are part of the level (everything else is solid rock).
    var arena: [Bool]
    /// Unbreakable cells inside the arena.
    var rock: [Bool]
    /// Cells that are the level's toughest blocks whatever is round them: walls a ball can
    /// break through if it keeps at it.
    var hard: [Bool]
    var spawn: Point
    /// Where the gold goes, for shapes that have a place for it; otherwise it is hidden far
    /// from the spawn.
    var gold: Point?
    /// Spots that deserve a shard: dead ends and side rooms, so exploring them pays.
    var treasures: [Point] = []

    init(size: Int, radius: Int) {
        self.size = size
        c = size / 2
        R = Double(min(radius, c - 2))
        arena = Array(repeating: false, count: size * size)
        rock = arena
        hard = arena
        spawn = Point(c, c)
    }

    func at(_ x: Double, _ y: Double) -> Point { Point(c + Int(x.rounded()), c + Int(y.rounded())) }

    /// Adds every cell `inside` says yes to to the arena (the board's outermost ring stays rock).
    mutating func dig(_ inside: (Double, Double) -> Bool) {
        for y in 1..<(size - 1) { for x in 1..<(size - 1) where inside(Double(x - c), Double(y - c)) {
            arena[y * size + x] = true
        } }
    }

    /// Turns every cell `inside` says yes to into rock.
    mutating func fill(_ inside: (Double, Double) -> Bool) {
        for y in 0..<size { for x in 0..<size where inside(Double(x - c), Double(y - c)) { rock[y * size + x] = true } }
    }

    /// One rock cell, by its whole-cell offset from the middle.
    mutating func fill(_ x: Int, _ y: Int) {
        let px = c + x, py = c + y
        if px >= 0, py >= 0, px < size, py < size { rock[py * size + px] = true }
    }

    /// One tough cell, by its whole-cell offset from the middle.
    mutating func harden(_ x: Int, _ y: Int) {
        let px = c + x, py = c + y
        if px >= 0, py >= 0, px < size, py < size { hard[py * size + px] = true }
    }

    /// A wall drawn through `points`: every cell whose center is within `reach` of the line.
    /// The default is the thinnest wall with no diagonal gaps (one cell thick along a row or
    /// column, a full staircase on a slope).
    mutating func wall(_ points: [(x: Double, y: Double)], reach: Double = 0.75) {
        guard points.count > 1 else { return }
        for k in 1..<points.count {
            let a = points[k - 1], b = points[k]
            let x0 = Int((min(a.x, b.x) - reach).rounded(.down)), x1 = Int((max(a.x, b.x) + reach).rounded(.up))
            let y0 = Int((min(a.y, b.y) - reach).rounded(.down)), y1 = Int((max(a.y, b.y) + reach).rounded(.up))
            let vx = b.x - a.x, vy = b.y - a.y, len2 = max(1e-9, vx * vx + vy * vy)
            for y in y0...y1 { for x in x0...x1 {
                let t = min(1, max(0, ((Double(x) - a.x) * vx + (Double(y) - a.y) * vy) / len2))
                let dx = Double(x) - (a.x + vx * t), dy = Double(y) - (a.y + vy * t)
                if dx * dx + dy * dy <= reach * reach { fill(x, y) }
            } }
        }
    }

    /// A circular wall of radius `r` round (x, y).
    mutating func ring(_ x: Double, _ y: Double, _ r: Double, reach: Double = 0.75) {
        let steps = max(16, Int(r * 8))
        wall((0...steps).map { k in
            let a = Double(k) / Double(steps) * 2 * Double.pi
            return (x + cos(a) * r, y + sin(a) * r)
        }, reach: reach)
    }

    /// A boulder: a solid oval of rock `r` cells across its half-width and `r * squash` its
    /// half-height, with no single cells sticking out of it.
    mutating func boulder(_ x: Double, _ y: Double, _ r: Double, squash: Double = 1) {
        var cells: [(Int, Int)] = []
        let reach = Int(r.rounded(.up)) + 1, mx = Int(x.rounded()), my = Int(y.rounded())
        for cy in (my - reach)...(my + reach) { for cx in (mx - reach)...(mx + reach) {
            let dx = (Double(cx) - x) / r, dy = (Double(cy) - y) / (r * squash)
            if dx * dx + dy * dy <= 1 { cells.append((cx, cy)) }
        } }
        for (cx, cy) in cells {
            let beside = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { d in cells.contains { $0 == (cx + d.0, cy + d.1) } }.count
            if beside >= 2 { fill(cx, cy) }
        }
    }

    /// A way through: clears the rock within `r` of (x, y).
    mutating func door(_ x: Double, _ y: Double, _ r: Double) {
        let x0 = Int((x - r).rounded(.down)), x1 = Int((x + r).rounded(.up))
        let y0 = Int((y - r).rounded(.down)), y1 = Int((y + r).rounded(.up))
        for cy in y0...y1 { for cx in x0...x1 {
            let dx = Double(cx) - x, dy = Double(cy) - y
            let px = c + cx, py = c + cy
            if dx * dx + dy * dy <= r * r, px >= 0, py >= 0, px < size, py < size { rock[py * size + px] = false }
        } }
    }
}

public enum LevelGen {
    /// Goes up whenever a level number starts generating a different board, so a dig saved on
    /// the old board is never laid over the new one (`Game.load` starts the level again).
    public static let layoutVersion = 2

    /// The level's shape, before anything is put in it: its outline, its walls, where the balls
    /// start and (for shapes with a place for it) the gold. `rng` is the level's seeded
    /// generator, as the shape left it.
    static func plan(level: Int) -> (plan: Plan, rng: RNG) {
        let spec = LevelSpec.forLevel(level)
        var rng = RNG(seed: UInt64(level) &* 0x2545_F491_4F6C_DD1D &+ 17)
        var plan = Plan(size: spec.boardSize, radius: spec.radius)
        switch spec.shape {
        case .cavern: cavern(&plan, rng: &rng)
        case .hourglass: hourglass(&plan, rng: &rng)
        case .crossroads: crossroads(&plan, rng: &rng)
        case .honeycomb: honeycomb(&plan, rng: &rng)
        case .nautilus: nautilus(&plan, rng: &rng)
        case .labyrinth: labyrinth(&plan, rng: &rng)
        case .citadel: citadel(&plan, rng: &rng)
        }
        return (plan, rng)
    }

    public static func make(level: Int, at t: Double = 0) -> Board {
        let spec = LevelSpec.forLevel(level)
        let size = spec.boardSize
        let b = Board(size: size, level: level, name: spec.name)

        // 1. The shape.
        var (plan, rng) = plan(level: level)
        for i in 0..<(size * size) where plan.arena[i] { b.kind[i] = plan.rock[i] ? .wall : .block }

        // 2. Clear a pocket for the balls to start in. It never eats a wall.
        let spawn = plan.spawn
        let pr = Tuning.spawnPocketRadius
        for dy in -pr...pr { for dx in -pr...pr where dx * dx + dy * dy <= pr * pr + 2 {
            let x = spawn.x + dx, y = spawn.y + dy
            if b.inside(x, y), b.kind[b.index(x, y)] == .block { b.kind[b.index(x, y)] = .empty }
        } }
        b.kind[b.index(spawn.x, spawn.y)] = .empty
        b.spawn = spawn
        // A fixed gold spot is never boxed in by walls.
        var gold = plan.gold
        if let g = gold {
            for (dx, dy) in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)] where b.inside(g.x + dx, g.y + dy) {
                let i = b.index(g.x + dx, g.y + dy)
                if plan.arena[i], b.kind[i] == .wall { b.kind[i] = .block }
            }
        }
        // Pockets the balls could never reach turn to rock, so every block, shard and the gold
        // can be dug to from the spawn.
        sealUnreachable(b, from: spawn)

        // 3. The gold: far down the dig from the spawn, never against a wall.
        let depth = depths(b)
        var blocks = (0..<(size * size)).filter { b.kind[$0] == .block }
        let deepest = blocks.reduce(1.0) { max($0, depth[$1]) }
        if gold == nil {
            var best = -1.0
            for i in blocks where depth[i] > deepest * 0.72 {
                let x = i % size, y = i / size
                // Keep it off the walls so it is fully surrounded by blocks.
                let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { b.kindAt(x + $0.0, y + $0.1) == .wall }
                if edge { continue }
                let score = depth[i] + rng.range(0, 6)
                if score > best { best = score; gold = Point(x, y) }
            }
        }
        let g = gold ?? Point(blocks.last.map { $0 % size } ?? spawn.x, blocks.last.map { $0 / size } ?? spawn.y)
        b.gold = g
        blocks.removeAll { $0 == b.index(g.x, g.y) }

        // 4. Durability: deeper is tougher, with patches. Every block gets a score (how far
        // the dig is from the spawn plus smooth noise); the softest-scoring share of the
        // blocks becomes tier 0, the next share tier 1, and so on, each share sized by the
        // level's tier weights. So the mix is exactly the table's, and only where it sits is
        // designed. A few cells are rich (sparkling, 5x payout), rolled per cell.
        let scores = durabilityScores(b, blocks: blocks, depth: depth, hard: plan.hard, rng: &rng)
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
        placeShards(b, treasures: plan.treasures, rng: &rng)

        // 5. Hit points.
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

    // MARK: - Shapes

    /// An open cave with a wobbly rim and a handful of boulders: nothing in the way but the
    /// odd rock to bounce off. The gold hides somewhere on the far side.
    static func cavern(_ p: inout Plan, rng: inout RNG) {
        let base = p.R - 3
        let ph = (0..<3).map { _ in rng.range(0, 6.28) }
        p.dig { x, y in
            let a = atan2(y, x)
            let r = base + 1.6 * sin(3 * a + ph[0]) + 1.0 * sin(5 * a + ph[1]) + 0.5 * sin(9 * a + ph[2])
            return x * x + y * y <= r * r
        }
        let sy = base - 8
        p.spawn = p.at(0, sy)
        // Boulders: well apart, clear of the spawn and the rim.
        var boulders: [(x: Double, y: Double, r: Double)] = []
        for _ in 0..<400 where boulders.count < 8 {
            let a = rng.range(0, 6.28), d = rng.unit().squareRoot() * (base - 9)
            let x = cos(a) * d, y = sin(a) * d, r = rng.range(1.4, 3.4)
            if hyp(x, y - sy) < 15 || boulders.contains(where: { hyp(x - $0.x, y - $0.y) < 14 }) { continue }
            boulders.append((x, y, r))
        }
        for k in boulders { p.boulder(k.x, k.y, k.r, squash: rng.range(0.7, 1)) }
    }

    /// Two bulbs joined by a neck nine cells wide. The balls start at the foot of the lower
    /// bulb and the gold sits at the head of the upper one, so everything has to get through
    /// the neck: the first level where it matters where you put a ball.
    static func hourglass(_ p: inout Plan, rng: inout RNG) {
        let H = p.R - 1, W = p.R - 1
        let neck = 4.5, waist = 0.5
        // Half the glass's width at height t (0 at the neck, 1 at either end): an S-curve out
        // from the neck, then a dome.
        func half(_ t: Double) -> Double {
            if t < waist { return neck + (W - neck) * (1 - cos(Double.pi * t / waist)) / 2 }
            let u = (t - waist) / (1 - waist)
            return W * max(0, 1 - u * u).squareRoot()
        }
        p.dig { x, y in
            let t = abs(y) / H
            // The two ends stop where the dome is still a few cells wide, not at a point.
            return t <= 1 && abs(x) <= half(t) && half(t) >= 3
        }
        p.spawn = p.at(0, H * 0.84)
        p.gold = p.at(0, -H * 0.84)
        // A few boulders in each bulb.
        var boulders: [(x: Double, y: Double, r: Double)] = []
        for side in [-1.0, 1.0] {
            var placed = 0
            for _ in 0..<200 where placed < 3 {
                let x = rng.range(-W * 0.7, W * 0.7), y = side * H * rng.range(0.36, 0.72), r = rng.range(1.5, 2.8)
                if abs(x) < 6 || boulders.contains(where: { hyp(x - $0.x, y - $0.y) < 12 }) { continue }
                boulders.append((x, y, r)); placed += 1
            }
        }
        for k in boulders { p.boulder(k.x, k.y, k.r) }
    }

    /// Four round petals off a round hub. The balls start at the tip of the bottom petal; each
    /// of the other three has a walled shrine whose door faces away from the hub, with the
    /// gold in one and a rich shard in the other two. So the hub is where you choose which
    /// way to dig.
    static func crossroads(_ p: inout Plan, rng: inout RNG) {
        let r = (p.R * 0.41).rounded(), d = p.R - r
        let hub = 12.0, shrine = 7.0
        let dirs: [(x: Double, y: Double)] = [(0, -1), (1, 0), (-1, 0), (0, 1)]
        p.dig { x, y in x * x + y * y <= hub * hub || dirs.contains { hyp(x - $0.x * d, y - $0.y * d) <= r } }
        // The hub is open to all four petals, round a boulder in the middle.
        p.boulder(0, 0, 2.6)
        let goldPetal = rng.int(3)
        for (i, k) in dirs.prefix(3).enumerated() {
            let s = d + shrine
            p.ring(k.x * s, k.y * s, shrine)
            p.door(k.x * (s + shrine), k.y * (s + shrine), 2.8)
            if i == goldPetal { p.gold = p.at(k.x * s, k.y * s) } else { p.treasures.append(p.at(k.x * s, k.y * s)) }
        }
        p.spawn = p.at(0, d + shrine)
    }

    /// Nineteen six-sided rooms packed like a comb. Most walls have a door in the middle, but
    /// not all, so the way through winds a little. The balls start in the bottom room and the gold is
    /// in one of the three top ones.
    static func honeycomb(_ p: inout Plan, rng: inout RNG) {
        // A room is `a` cells from its middle to a wall. Rooms sit on a hex lattice (q, r);
        // two rooms away from the middle one in every direction makes nineteen.
        // A whole number, so the walls that run level are one cell thick.
        let a = ((p.R - 1) / 5.03).rounded(.down)
        let e1 = (x: 2 * a * 0.8660254, y: -a), e2 = (x: 2 * a * 0.8660254, y: a)
        func hexDist(_ q: Int, _ r: Int) -> Int { max(abs(q), abs(r), abs(q + r)) }
        func center(_ c: (q: Int, r: Int)) -> (x: Double, y: Double) {
            (Double(c.q) * e1.x + Double(c.r) * e2.x, Double(c.q) * e1.y + Double(c.r) * e2.y)
        }
        var lattice: [(q: Int, r: Int)] = []
        for q in -3...3 { for r in -3...3 where hexDist(q, r) <= 3 { lattice.append((q, r)) } }
        let rooms = lattice.filter { hexDist($0.q, $0.r) <= 2 }
        let centers = lattice.map(center)
        p.dig { x, y in
            var best = 0, bestD = Double.infinity
            for (i, c) in centers.enumerated() {
                let d = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
                if d < bestD { bestD = d; best = i }
            }
            return hexDist(lattice[best].q, lattice[best].r) <= 2
        }
        func index(_ q: Int, _ r: Int) -> Int? { rooms.firstIndex { $0.q == q && $0.r == r } }
        func neighbors(_ i: Int) -> [Int] {
            [(1, 0), (0, 1), (1, -1), (-1, 0), (0, -1), (-1, 1)].compactMap { index(rooms[i].q + $0.0, rooms[i].r + $0.1) }
        }
        let start = index(-2, 2)!
        // Doors: a random walk from the start room reaches every room, then some extra doors
        // so there is more than one way round.
        var doors = Set<Int>()
        func key(_ i: Int, _ j: Int) -> Int { min(i, j) * rooms.count + max(i, j) }
        var seen = Array(repeating: false, count: rooms.count)
        var stack = [start]
        seen[start] = true
        while let cur = stack.last {
            let options = neighbors(cur).filter { !seen[$0] }
            if options.isEmpty { stack.removeLast(); continue }
            let next = options[rng.int(options.count)]
            doors.insert(key(cur, next)); seen[next] = true; stack.append(next)
        }
        var gaps: [(x: Double, y: Double)] = []
        for i in rooms.indices { for j in neighbors(i) where j > i {
            let A = center(rooms[i]), B = center(rooms[j])
            let mx = (A.x + B.x) / 2, my = (A.y + B.y) / 2
            // The shared wall runs across the line between the two rooms.
            let len = hyp(B.x - A.x, B.y - A.y), tx = -(B.y - A.y) / len, ty = (B.x - A.x) / len
            let L = a / 3.0.squareRoot()
            p.wall([(mx - tx * L, my - ty * L), (mx + tx * L, my + ty * L)])
            if doors.contains(key(i, j)) || rng.unit() < 0.7 { gaps.append((mx, my)) }
        } }
        for gap in gaps { p.door(gap.x, gap.y, 2.0) }
        let s = center(rooms[start])
        p.spawn = p.at(s.x, s.y)
        let top = [(2, -2), (2, 0), (0, -2)][rng.int(3)]
        let g = center((top.0, top.1))
        p.gold = p.at(g.x, g.y)
    }

    /// A shell: one passage coiling two and three-quarter times inward, halving in width with
    /// every turn, crossed by curved walls that leave the middle half of it open. The balls start
    /// in the wide mouth and the gold sits at the very middle of the coil.
    static func nautilus(_ p: inout Plan, rng: inout RNG) {
        // The shell wall is r = S / 2^(turns), measured from the coil's middle (ox, oy), which
        // sits off the board's middle so the whole shell is centered.
        let S = (2 * p.R - 1) / 1.712
        let mouth = Double.pi / 2
        let spin: Double = rng.unit() < 0.5 ? 1 : -1
        let u = (x: cos(mouth), y: sin(mouth)), v = (x: cos(mouth + spin * Double.pi / 2), y: sin(mouth + spin * Double.pi / 2))
        let ox = -0.144 * S * u.x - 0.124 * S * v.x, oy = -0.144 * S * u.y - 0.124 * S * v.y
        let turn = 2 * Double.pi
        func shell(_ th: Double) -> Double { S * pow(2, -th / turn) }
        func point(_ rho: Double, _ th: Double) -> (x: Double, y: Double) {
            (ox + rho * cos(mouth + spin * th), oy + rho * sin(mouth + spin * th))
        }
        p.dig { x, y in
            let dx = x - ox, dy = y - oy
            var th = (spin * (atan2(dy, dx) - mouth)).truncatingRemainder(dividingBy: turn)
            if th < 0 { th += turn }
            return dx * dx + dy * dy <= shell(th) * shell(th)
        }
        // The inner turns of the shell (the first turn is the outline itself).
        let end = turn * 2.75
        var coil: [(x: Double, y: Double)] = []
        var th = turn
        while th <= end { coil.append(point(shell(th), th)); th += 0.01 }
        p.wall(coil)
        // The chamber walls, six to a turn: each bows toward the middle and leaves the center
        // half of the passage open (never less than four cells).
        let step = turn / 6
        var k = 1
        while Double(k) * step <= end - turn {
            let th = Double(k) * step
            let outer = shell(th), inner = shell(th + turn), width = outer - inner
            let gap = max(0.5, 4.6 / width)
            for span in [(0.0, 0.5 - gap / 2), (0.5 + gap / 2, 1.0)] {
                p.wall((0...24).map { n in
                    let f = span.0 + (span.1 - span.0) * Double(n) / 24
                    return point(inner + f * width, th + 0.16 * 4 * f * (1 - f))
                })
            }
            k += 1
        }
        let s = point(0.75 * shell(step / 2), step / 2)
        p.spawn = p.at(s.x, s.y)
        p.gold = p.at(ox, oy)
    }

    /// A square maze of wide corridors round a treasure room. The balls start in a corner; the
    /// room's one door is on the side of the maze furthest from them. Some dead ends are
    /// knocked through into loops, and the ones left each hold a shard.
    static func labyrinth(_ p: inout Plan, rng: inout RNG) {
        // Maze cells are `pitch` apart, with one-cell walls on the lines between them.
        let pitch = 9
        let n = (2 * Int(p.R) - 6) / pitch
        let o = -(n * pitch) / 2
        p.dig { x, y in max(abs(x), abs(y)) <= Double(-o) }
        let mid = [(n - 1) / 2, n / 2]
        func inRoom(_ i: Int) -> Bool { mid.contains(i % n) && mid.contains(i / n) }
        func neighbors(_ i: Int) -> [Int] {
            var out: [Int] = []
            if i % n + 1 < n { out.append(i + 1) }
            if i % n > 0 { out.append(i - 1) }
            if i / n + 1 < n { out.append(i + n) }
            if i / n > 0 { out.append(i - n) }
            return out
        }
        // The wall between two neighboring cells: the lower cell's right (0) or bottom (1).
        func key(_ i: Int, _ j: Int) -> Int { min(i, j) * 2 + (abs(i - j) == 1 ? 0 : 1) }
        var open = Set<Int>()
        let start = (n - 1) * n
        // Carve the corridors with a depth-first walk that keeps out of the room.
        var seen = (0..<(n * n)).map(inRoom)
        var stack = [start]
        seen[start] = true
        while let cur = stack.last {
            let options = neighbors(cur).filter { !seen[$0] }
            if options.isEmpty { stack.removeLast(); continue }
            let next = options[rng.int(options.count)]
            open.insert(key(cur, next)); seen[next] = true; stack.append(next)
        }
        func exits(_ i: Int) -> [Int] { neighbors(i).filter { open.contains(key(i, $0)) } }
        // Half the dead ends break through into a neighbor, making loops.
        for i in 0..<(n * n) where !inRoom(i) && i != start && exits(i).count == 1 && rng.unit() < 0.5 {
            let shut = neighbors(i).filter { !inRoom($0) && !open.contains(key(i, $0)) }
            if !shut.isEmpty { open.insert(key(i, shut[rng.int(shut.count)])) }
        }
        let deadEnds = (0..<(n * n)).filter { !inRoom($0) && $0 != start && exits($0).count == 1 }
        // Corridor steps from the start to every cell, to find the far side of the maze.
        var steps = Array(repeating: -1, count: n * n)
        var frontier = [start]
        steps[start] = 0
        while !frontier.isEmpty {
            var next: [Int] = []
            for i in frontier { for j in exits(i) where steps[j] < 0 { steps[j] = steps[i] + 1; next.append(j) } }
            frontier = next
        }
        // The room: open inside, with one door from the corridor cell furthest from the start.
        var door = (cell: -1, from: -1)
        for i in 0..<(n * n) where inRoom(i) {
            for j in neighbors(i) {
                if inRoom(j) { open.insert(key(i, j)) } else if door.from < 0 || steps[j] > steps[door.from] { door = (i, j) }
            }
        }
        // The maze's walls are its toughest rock, not solid: a ball can break through one, it
        // just takes far longer than following the corridor. Only the posts where walls meet
        // and the treasure room's own walls are unbreakable.
        func segment(_ i: Int, _ j: Int, from: Int, to: Int, solid: Bool) {
            let lo = min(i, j), gx = lo % n, gy = lo / n
            for k in from...to {
                let x = abs(i - j) == 1 ? o + (gx + 1) * pitch : o + gx * pitch + k
                let y = abs(i - j) == 1 ? o + gy * pitch + k : o + (gy + 1) * pitch
                if solid { p.fill(x, y) } else { p.harden(x, y) }
            }
        }
        for i in 0..<(n * n) { for j in neighbors(i) where j > i && !open.contains(key(i, j)) {
            if (i, j) == (min(door.cell, door.from), max(door.cell, door.from)) {
                // The room's door: four cells in the middle of its wall.
                segment(i, j, from: 0, to: pitch / 2 - 2, solid: true)
                segment(i, j, from: pitch / 2 + 3, to: pitch, solid: true)
            } else if inRoom(i) || inRoom(j) {
                segment(i, j, from: 0, to: pitch, solid: true)
            } else {
                segment(i, j, from: 1, to: pitch - 1, solid: false)
                // A post at each end of every wall.
                segment(i, j, from: 0, to: 0, solid: true)
                segment(i, j, from: pitch, to: pitch, solid: true)
            }
        } }
        func middle(_ i: Int) -> Point { p.at(Double(o + (i % n) * pitch + pitch / 2 + 1), Double(o + (i / n) * pitch + pitch / 2 + 1)) }
        p.spawn = middle(start)
        let roomMid = o + (mid[0] + mid[1] + 1) * pitch / 2 + (n % 2 == 0 ? 0 : 1)
        p.gold = p.at(Double(roomMid), Double(roomMid))
        p.treasures = deadEnds.map(middle)
    }

    /// A castle: a square with a round bastion on each corner, and inside it two walls and a
    /// keep, each two cells thick. The gates never line up, so the way in goes round: through
    /// the corner towers to the side gates, round to the far gate, back round to the keep's
    /// door, and the gold in the middle of the keep.
    static func citadel(_ p: inout Plan, rng: inout RNG) {
        let s = Int(p.R) - 12
        let tower = 11.0
        let sd = Double(s)
        p.dig { x, y in max(abs(x), abs(y)) <= sd || hyp(abs(x) - sd, abs(y) - sd) <= tower }
        // Three square walls, two cells thick: the outer ward, the inner ward, the keep.
        let walls = [s - 11, s - 22, 6]
        for w in walls {
            p.fill { x, y in
                let m = max(abs(x), abs(y))
                return m == Double(w) || m == Double(w + 1)
            }
        }
        // The outer wall's lines run on to the rim, boxing in each corner: a tower room with a
        // round bastion, a door to the ward on either side of it and a shard in the middle.
        let w = walls[0]
        for t in 0...1 { for k in (w + 2)...s where !(s - 6...s - 3).contains(k) {
            for side in [-1, 1] { for end in [-1, 1] {
                p.fill(side * (w + t), end * k)
                p.fill(end * k, side * (w + t))
            } }
        } }
        for (cx, cy) in [(1.0, 1.0), (1, -1), (-1, 1), (-1, -1)] { p.treasures.append(p.at(cx * sd, cy * sd)) }
        // Gates, four cells wide: east and west through the outer wall, north through the
        // inner one, south into the keep.
        func gate(_ wall: Int, _ dx: Int, _ dy: Int) {
            for k in -2...1 { for t in 0...1 {
                let x = dx * (wall + t) + abs(dy) * k, y = dy * (wall + t) + abs(dx) * k
                p.rock[(p.c + y) * p.size + p.c + x] = false
            } }
        }
        gate(walls[0], 1, 0); gate(walls[0], -1, 0)
        gate(walls[1], 0, -1)
        gate(walls[2], 0, 1)
        p.spawn = p.at(0, sd - 4)
        p.gold = p.at(0, 0)
    }

    // MARK: - Depth, durability, shards

    /// How far the dig has to go from the spawn to reach each cell, in cells, going round
    /// walls (straight steps cost 1, diagonal ones 1.4, and a diagonal never cuts a wall's
    /// corner). Walls and anything cut off read infinity.
    static func depths(_ b: Board) -> [Double] {
        let n = b.size
        var dist = Array(repeating: Int.max, count: n * n)
        // Steps cost 5 or 7, so cells queue up in whole-numbered buckets.
        var buckets: [[Int]] = [[b.index(b.spawn.x, b.spawn.y)]]
        dist[buckets[0][0]] = 0
        var k = 0
        while k < buckets.count {
            for i in buckets[k] where dist[i] == k {
                let x = i % n, y = i / n
                for dy in -1...1 { for dx in -1...1 where (dx != 0 || dy != 0) && b.inside(x + dx, y + dy) {
                    let j = b.index(x + dx, y + dy)
                    if b.kind[j] == .wall { continue }
                    if dx != 0, dy != 0, b.kind[b.index(x + dx, y)] == .wall || b.kind[b.index(x, y + dy)] == .wall { continue }
                    let d = k + (dx != 0 && dy != 0 ? 7 : 5)
                    if d < dist[j] {
                        dist[j] = d
                        while buckets.count <= d { buckets.append([]) }
                        buckets[d].append(j)
                    }
                } }
            }
            k += 1
        }
        return dist.map { $0 == Int.max ? Double.infinity : Double($0) / 5 }
    }

    /// How tough each of `blocks` should be, relative to the others (higher = tougher): how far
    /// down the dig it is (0 at the spawn, 1 at the deepest block) blended with two octaves of
    /// smooth value noise, so there are soft pockets to dig toward and hard clumps to go
    /// round, plus a little per-cell grain so patch edges aren't clean lines. The shape's
    /// `hard` cells score above everything else, so they take the level's toughest tiers.
    static func durabilityScores(_ b: Board, blocks: [Int], depth: [Double], hard: [Bool], rng: inout RNG) -> [Double] {
        let coarse = valueNoise(size: b.size, cell: Tuning.durabilityPatchSize, rng: &rng)
        let fine = valueNoise(size: b.size, cell: Tuning.durabilityPatchSize / 2, rng: &rng)
        let deepest = blocks.reduce(1.0) { max($0, depth[$1]) }
        let w = Tuning.durabilityDepthWeight
        return blocks.map { i in
            let patch = 0.7 * coarse[i] + 0.3 * fine[i]
            return w * depth[i] / deepest + (1 - w) * patch + Tuning.durabilityGrain * rng.unit() + (hard[i] ? 2 : 0)
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
    /// always sense a couple straight away; then one on each of the shape's `treasures` (its
    /// dead ends and side rooms); the rest fan out, and you sense each one as your digging gets
    /// within `Tuning.shardSenseRadius` of it.
    static func placeShards(_ b: Board, treasures: [Point], rng: inout RNG) {
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
        // The rest never sit inside the starting light.
        func dark(_ p: Point) -> Bool { cheb(p, b.spawn) >= Tuning.revealRadius + 4 }
        for p in treasures where b.inside(p.x, p.y) && b.kind[b.index(p.x, p.y)] == .block && dark(p) && ok(p) { spots.append(p) }
        let far = candidates.filter(dark)
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

    static func hyp(_ x: Double, _ y: Double) -> Double { (x * x + y * y).squareRoot() }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
