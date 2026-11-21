/// The simulation step: ball movement and collisions, special abilities, effects and timers.
/// Physics runs in float cell units; the renderer snaps everything to the art grid.

extension Game {
    /// Advances the game by `dt` seconds (clamped, so a stall is not played back as one long step).
    public func update(_ dt: Double) {
        let dt = min(max(0, dt), 1.0 / 20)
        time += dt
        ui.camera.update(dt)
        ui.treeCamera.update(dt)
        if ui.screen != .game || ui.paused { return }
        if clearTimer == nil { progress.levelTime += dt }

        if let t = clearTimer {
            let left = t - dt
            if left <= 0 { advanceLevel() } else { clearTimer = left }
        }

        shake = max(0, shake - dt * 2.5)

        stepBalls(dt)
        stepEffects(dt)
        stepSonar(dt)
    }

    // MARK: Balls

    func stepBalls(_ dt: Double) {
        // Every ball of a type flies at the same speed, and working it out reads the tree by
        // name: once per run of one type, not once per ball.
        var pace: (kind: BallKind, mods: Double, speed: Double)?
        for i in balls.indices {
            var b = balls[i]
            if b.kind == .ghost {
                if b.phaseLeft > 0 {
                    b.phaseLeft -= dt
                    // Never surface inside a block.
                    if b.phaseLeft <= 0, solidAt(b.x, b.y) { b.phaseLeft = 0.05 }
                    if b.phaseLeft <= 0 { b.lastCell = -1 }
                } else {
                    b.phaseTimer -= dt
                    if b.phaseTimer <= 0 {
                        b.phaseLeft = special(.ghost)
                        b.phaseTimer = has("poltergeist") ? 2 : 4
                    }
                }
            }
            if pace?.kind != b.kind || pace?.mods != mods.speed { pace = (b.kind, mods.speed, speed(b.kind)) }
            var remaining = (pace?.speed ?? 0) * dt
            while remaining > 0 {
                let d = min(remaining, 0.2)
                remaining -= d
                move(&b, d)
            }
            b.trailTimer -= dt
            if b.trailTimer <= 0 {
                b.trailTimer = 1.0 / 30
                let p = Point(Int((b.x * Double(Tuning.cellPixels)).rounded(.down)), Int((b.y * Double(Tuning.cellPixels)).rounded(.down)))
                if b.trail.first != p {
                    b.trail.insert(p, at: 0)
                    if b.trail.count > 4 { b.trail.removeLast() }
                }
            }
            balls[i] = b
        }
    }

    func solidAt(_ x: Double, _ y: Double) -> Bool {
        let k = board.kindAt(Int(x.rounded(.down)), Int(y.rounded(.down)))
        return k != .empty
    }

    /// Flies a ball `d` cells along its direction, bouncing at the exact point where it first
    /// touches something. The touch is found from the path, not from where a step happens to
    /// end, so a shot bounces the same way at any frame rate and any ball speed.
    func move(_ b: inout Ball, _ d: Double) {
        let phasing = b.phaseLeft > 0
        // Belt and braces: a ball that is inside a solid cell goes back to the spawn.
        if !phasing, solidAt(b.x, b.y) { toSpawn(&b); return }
        var left = d
        // In an inside corner a ball touches two cells at once, so one step can hold a few bounces.
        var touches = 0
        while left > 0 {
            guard let c = firstContact(x: b.x, y: b.y, vx: b.vx, vy: b.vy, reach: left, wallsOnly: phasing) else {
                b.x += b.vx * left; b.y += b.vy * left
                break
            }
            b.x += b.vx * c.t; b.y += b.vy * c.t
            left -= c.t
            let k: CellKind = c.cell >= 0 ? board.kind[c.cell] : .wall
            if k == .wall {
                if c.cell >= 0 { revealWall(c.cell) }
            } else {
                b.wallBounces.removeAll(keepingCapacity: true)
                // A heavy ball carries on through a pixel it breaks.
                if hit(c.cell, by: b.kind), b.pierce > 0 { b.pierce -= 1; continue }
            }
            bounce(&b, nx: c.nx, ny: c.ny, offWall: k == .wall)
            touches += 1
            if touches == 4 { break }
        }
        if phasing { phaseThrough(&b) }
        if !phasing, solidAt(b.x, b.y) { toSpawn(&b) }
    }

    func toSpawn(_ b: inout Ball) {
        b.x = Double(board.spawn.x) + 0.5
        b.y = Double(board.spawn.y) + 0.5
        b.wallBounces.removeAll(keepingCapacity: true)
    }

    /// Mirrors the ball's direction in the surface it touched. Bounces are exact, so a level
    /// shot stays level; the one exception is a ball going round a loop that touches only
    /// walls, which would never earn again, so it is turned a little to break the loop.
    func bounce(_ b: inout Ball, nx: Double, ny: Double, offWall: Bool) {
        let dot = b.vx * nx + b.vy * ny
        if dot < 0 { b.vx -= 2 * dot * nx; b.vy -= 2 * dot * ny }
        // Keep the direction a unit vector: the contact math assumes one, and a rounding error
        // left in would grow from bounce to bounce. (An exactly level or upright one is untouched.)
        let len = (b.vx * b.vx + b.vy * b.vy).squareRoot()
        if len > 0 { b.vx /= len; b.vy /= len }
        if offWall {
            // The same place (within half an art pixel) and the same heading as a recent wall bounce.
            let looping = b.wallBounces.contains {
                abs($0.x - b.x) < 0.05 && abs($0.y - b.y) < 0.05 && abs($0.vx - b.vx) < 1e-3 && abs($0.vy - b.vy) < 1e-3
            }
            if b.wallBounces.count >= Tuning.loopMemory { b.wallBounces.removeFirst() }
            b.wallBounces.append(WallBounce(x: b.x, y: b.y, vx: b.vx, vy: b.vy))
            if looping {
                let a = atan2(b.vy, b.vx) + rng.range(-Tuning.loopNudge, Tuning.loopNudge)
                b.vx = cos(a); b.vy = sin(a)
            }
        }
        b.pierce = basePierce(b.kind)
        if b.kind == .sniper {
            let mirrored = (b.vx, b.vy)
            aim(&b, fromX: b.x, fromY: b.y)
            // An aim through something the ball is touching is no aim at all: keep the bounce.
            if firstContact(x: b.x, y: b.y, vx: b.vx, vy: b.vy, reach: 0, wallsOnly: false) != nil { (b.vx, b.vy) = mirrored }
        }
    }

    /// A phasing ghost damages each pixel it passes over, once as it enters it.
    func phaseThrough(_ b: inout Ball) {
        let r = Tuning.ballRadius
        for cy in Int((b.y - r).rounded(.down))...Int((b.y + r).rounded(.down)) {
            for cx in Int((b.x - r).rounded(.down))...Int((b.x + r).rounded(.down)) where board.inside(cx, cy) {
                let idx = board.index(cx, cy)
                guard board.kind[idx].breakable, idx != b.lastCell else { continue }
                let px = min(max(b.x, Double(cx)), Double(cx + 1)), py = min(max(b.y, Double(cy)), Double(cy + 1))
                let dx = b.x - px, dy = b.y - py
                guard dx * dx + dy * dy < r * r else { continue }
                b.lastCell = idx
                _ = damageCell(idx, damage(.ghost) * (has("wraith") ? 3.0 : 1.0))
            }
        }
    }

    /// The first touch on a ball's path: how far along it is, the surface's normal there, and
    /// the cell touched (-1 for the edge of the board).
    struct Contact {
        var t: Double, nx: Double, ny: Double, cell: Int
    }

    /// The first solid cell that a ball at (x, y), flying along the unit direction (vx, vy),
    /// touches within `reach` cells. A phasing ghost (`wallsOnly`) touches only walls.
    func firstContact(x: Double, y: Double, vx: Double, vy: Double, reach: Double, wallsOnly: Bool) -> Contact? {
        let r = Tuning.ballRadius
        let ex = x + vx * reach, ey = y + vy * reach
        // A hair wider than the ball, so a cell it is exactly touching is always looked at.
        let pad = r + 1e-6
        // Every ball asks this every step: read the grid once, not once per cell.
        let size = board.size, kinds = board.kind
        var best: Contact?
        for cy in Int((min(y, ey) - pad).rounded(.down))...Int((max(y, ey) + pad).rounded(.down)) {
            for cx in Int((min(x, ex) - pad).rounded(.down))...Int((max(x, ex) + pad).rounded(.down)) {
                let inside = cx >= 0 && cy >= 0 && cx < size && cy < size
                let k: CellKind = inside ? kinds[cy * size + cx] : .wall
                if k == .empty || (wallsOnly && k != .wall) { continue }
                guard let c = Game.touch(qx: x - Double(cx) - 0.5, qy: y - Double(cy) - 0.5, vx: vx, vy: vy, r: r, reach: reach),
                      c.t < (best?.t ?? .infinity) else { continue }
                best = Contact(t: c.t, nx: c.nx, ny: c.ny, cell: inside ? cy * size + cx : -1)
            }
        }
        return best
    }

    /// When a circle of radius `r` first touches a unit cell. The circle's center starts at
    /// (qx, qy), measured from the middle of the cell, and flies along the unit direction
    /// (vx, vy). Returns the distance flown (at most `reach`) and the cell's outward normal at
    /// the touch: straight out of a side, or out from a corner through the circle's center.
    /// A circle already touching the cell only counts if it is heading into it.
    static func touch(qx: Double, qy: Double, vx: Double, vy: Double, r: Double, reach: Double) -> (t: Double, nx: Double, ny: Double)? {
        let h = 0.5, slack = 1e-9
        let ax = max(abs(qx) - h, 0), ay = max(abs(qy) - h, 0)
        if ax * ax + ay * ay <= (r + slack) * (r + slack) {
            // Touching already. With its center inside the cell there is no side to bounce off: straight back.
            let d0 = (ax * ax + ay * ay).squareRoot()
            var nx = -vx, ny = -vy
            if d0 > slack { nx = (qx < 0 ? -ax : ax) / d0; ny = (qy < 0 ? -ay : ay) / d0 }
            return vx * nx + vy * ny < -slack ? (0, nx, ny) : nil
        }
        // Where the center crosses into the cell grown by r on every side.
        let e = h + r
        var enter = -Double.infinity, exit = Double.infinity, viaX = false
        if abs(vx) > 1e-12 {
            let a = (-e - qx) / vx, b = (e - qx) / vx
            enter = min(a, b); exit = max(a, b); viaX = true
        } else if abs(qx) >= e { return nil }
        if abs(vy) > 1e-12 {
            let a = (-e - qy) / vy, b = (e - qy) / vy
            if min(a, b) > enter { enter = min(a, b); viaX = false }
            exit = min(exit, max(a, b))
        } else if abs(qy) >= e { return nil }
        guard enter <= exit, exit >= 0, enter <= reach else { return nil }
        let from = max(enter, 0)
        let px = qx + vx * from, py = qy + vy * from
        // Crossing in beside a flat side is a hit on that side.
        if enter >= 0 {
            if viaX, abs(py) <= h { return (enter, vx > 0 ? -1 : 1, 0) }
            if !viaX, abs(px) <= h { return (enter, 0, vy > 0 ? -1 : 1) }
        }
        // Otherwise the center is beside a corner, and only that corner's round can be touched.
        let mx = qx - (px < 0 ? -h : h), my = qy - (py < 0 ? -h : h)
        let along = mx * vx + my * vy
        let disc = along * along - (mx * mx + my * my - r * r)
        guard disc > 0 else { return nil }
        let t = -along - disc.squareRoot()
        guard t >= 0, t <= reach else { return nil }
        let nx = mx + vx * t, ny = my + vy * t
        let len = (nx * nx + ny * ny).squareRoot()
        return (t, nx / len, ny / len)
    }

    /// A ball hit a block or the gold. Returns true if it broke.
    func hit(_ i: Int, by k: BallKind) -> Bool {
        var dmg = damage(k)
        var critChance = mods.crit
        if k == .basic { critChance += special(.basic) }
        if k == .sniper && has("marksman") { critChance += 0.25 }
        if rng.unit() < critChance { dmg *= mods.critDamage; events.append(.crit) }
        if k == .fast {
            let flurry = has("flurry")
            let chance = special(.fast) * (flurry ? 2 : 1)
            if rng.unit() < chance { dmg *= 2; if flurry && rng.unit() < chance { dmg *= 1.5 } }
        }
        let x = i % board.size, y = i / board.size
        let broke = damageCell(i, dmg)
        switch k {
        case .lightning:
            let storm = has("storm")
            chain(from: x, y, damage: dmg * 0.5 * (has("overcharge") ? 2.5 : 1),
                  count: Int(special(.lightning)) + (storm ? 4 : 0), range: storm ? 4.5 : 3)
        case .bomb:
            let radius = special(.bomb) * (has("nuke") ? 1.6 : 1)
            explode(Double(x) + 0.5, Double(y) + 0.5, radius: radius, damage: dmg * 0.6)
            if has("cluster") {
                for _ in 0..<3 {
                    explode(Double(x) + 0.5 + rng.range(-2, 2), Double(y) + 0.5 + rng.range(-2, 2), radius: radius * 0.5, damage: dmg * 0.3)
                }
            }
        default: break
        }
        return broke
    }

    func explode(_ x: Double, _ y: Double, radius: Double, damage dmg: Double) {
        let r = Int(radius.rounded(.up))
        let cx = Int(x.rounded(.down)), cy = Int(y.rounded(.down))
        for yy in (cy - r)...(cy + r) {
            for xx in (cx - r)...(cx + r) where board.inside(xx, yy) {
                let dx = Double(xx) + 0.5 - x, dy = Double(yy) + 0.5 - y
                if dx * dx + dy * dy <= radius * radius { damageCell(board.index(xx, yy), dmg) }
            }
        }
        rings.append(Ring(x: x, y: y, maxRadius: radius + 0.5, life: 0.28, maxLife: 0.28, color: BallKind.bomb.color, overFog: false))
        shake = max(shake, 0.25)
        events.append(.explosion)
    }

    func chain(from x: Int, _ y: Int, damage dmg: Double, count: Int, range: Double) {
        guard count > 0 else { return }
        let r = Int(range.rounded(.up))
        var targets: [(Int, Int)] = []
        for yy in (y - r)...(y + r) {
            for xx in (x - r)...(x + r) where board.inside(xx, yy) && !(xx == x && yy == y) {
                let k = board.kind[board.index(xx, yy)]
                guard k.breakable else { continue }
                let d2 = (xx - x) * (xx - x) + (yy - y) * (yy - y)
                if Double(d2) <= range * range { targets.append((d2, board.index(xx, yy))) }
            }
        }
        targets.sort { $0.0 < $1.0 }
        let cp = Tuning.cellPixels
        var from = Point(x * cp + cp / 2, y * cp + cp / 2)
        for (_, idx) in targets.prefix(count) {
            let to = Point((idx % board.size) * cp + cp / 2, (idx / board.size) * cp + cp / 2)
            bolts.append(Bolt(points: zigzag(from, to), life: 0.12))
            damageCell(idx, dmg)
            from = to
        }
        events.append(.zap)
    }

    func zigzag(_ a: Point, _ b: Point) -> [Point] {
        var pts = [a]
        let steps = 3
        for s in 1..<steps {
            let t = Double(s) / Double(steps)
            pts.append(Point(a.x + Int(Double(b.x - a.x) * t) + rng.int(5) - 2, a.y + Int(Double(b.y - a.y) * t) + rng.int(5) - 2))
        }
        pts.append(b)
        return pts
    }

    /// Sniper: after a bounce, turn toward the nearest pixel in range (or the gold, as Seeker).
    /// After a bounce, turn toward the nearest breakable pixel ahead. Only pixels in front of
    /// the bounced direction count, so a sniper never turns straight back into the pixel it
    /// just hit (which would hit it every physics step).
    func aim(_ b: inout Ball, fromX x: Double, fromY y: Double) {
        let range = min(24, Int(special(.sniper)))
        let cx = Int(x.rounded(.down)), cy = Int(y.rounded(.down))
        func ahead(_ dx: Int, _ dy: Int) -> Bool { Double(dx) * b.vx + Double(dy) * b.vy > 0 }
        var target: Point?
        if has("seeker"), board.kind[board.index(board.gold.x, board.gold.y)] == .gold {
            let dx = board.gold.x - cx, dy = board.gold.y - cy
            if dx * dx + dy * dy <= range * range && ahead(dx, dy) { target = board.gold }
        }
        if target == nil {
            ringSearch: for r in 1...max(1, range) {
                for dy in -r...r {
                    // Only the ring's own cells, left to right: all of its top and bottom
                    // rows, the two ends of each row between.
                    for dx in stride(from: -r, through: r, by: abs(dy) == r ? 1 : 2 * r) where ahead(dx, dy) {
                        let k = board.kindAt(cx + dx, cy + dy)
                        if k.breakable && board.inside(cx + dx, cy + dy) { target = Point(cx + dx, cy + dy); break ringSearch }
                    }
                }
            }
        }
        guard let t = target else { return }
        let dx = Double(t.x) + 0.5 - x, dy = Double(t.y) + 0.5 - y
        let len = (dx * dx + dy * dy).squareRoot()
        if len > 0.01 { b.vx = dx / len; b.vy = dy / len }
    }

    // MARK: Effects

    func stepEffects(_ dt: Double) {
        var write = 0
        for i in particles.indices {
            var p = particles[i]
            p.life -= dt
            guard p.life > 0 else { continue }
            p.x += p.vx * dt; p.y += p.vy * dt
            p.vy += 9 * dt
            p.vx *= 1 - 2 * dt
            particles[write] = p
            write += 1
        }
        particles.removeLast(particles.count - write)
        if particles.count > 1500 { particles.removeFirst(particles.count - 1500) }

        bolts = bolts.compactMap { var b = $0; b.life -= dt; return b.life > 0 ? b : nil }
        rings = rings.compactMap { var r = $0; r.life -= dt; return r.life > 0 ? r : nil }
        banners = banners.compactMap { var b = $0; b.life -= dt; return b.life > 0 ? b : nil }
    }

    func stepSonar(_ dt: Double) {
        guard mods.sonar > 0, mods.sonar < Tuning.sonarIntervals.count,
              board.kind[board.index(board.gold.x, board.gold.y)] == .gold else { return }
        sonarTimer -= dt
        if sonarTimer <= 0 {
            sonarTimer = Tuning.sonarIntervals[mods.sonar]
            rings.append(Ring(x: Double(board.gold.x) + 0.5, y: Double(board.gold.y) + 0.5, maxRadius: 7,
                              life: 1.4, maxLife: 1.4, color: Palette.gold, overFog: true))
        }
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
