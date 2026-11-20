/// The simulation step: ball movement and collisions, special abilities, effects and timers.
/// Physics runs in float cell units; the renderer snaps everything to the art grid.

extension Game {
    /// Advances the game by `dt` seconds (clamped, so a stall never tunnels balls).
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
            var remaining = speed(b.kind) * dt
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

    func move(_ b: inout Ball, _ d: Double) {
        let r = Tuning.ballRadius
        var nx = b.x + b.vx * d, ny = b.y + b.vy * d
        let phasing = b.phaseLeft > 0
        var bestPen = 0.0, bestN = (0.0, 0.0), bestCell = -2
        for cy in Int((ny - r).rounded(.down))...Int((ny + r).rounded(.down)) {
            for cx in Int((nx - r).rounded(.down))...Int((nx + r).rounded(.down)) {
                let inside = board.inside(cx, cy)
                let k: CellKind = inside ? board.kind[board.index(cx, cy)] : .wall
                if k == .empty { continue }
                let px = min(max(nx, Double(cx)), Double(cx + 1)), py = min(max(ny, Double(cy)), Double(cy + 1))
                let dx = nx - px, dy = ny - py, d2 = dx * dx + dy * dy
                guard d2 < r * r else { continue }
                if phasing && k != .wall {
                    let idx = board.index(cx, cy)
                    if idx != b.lastCell {
                        b.lastCell = idx
                        let mult = has("wraith") ? 3.0 : 1.0
                        _ = damageCell(idx, damage(.ghost) * mult)
                    }
                    continue
                }
                var n: (Double, Double), pen: Double
                if d2 > 1e-12 {
                    let dd = d2.squareRoot()
                    n = (dx / dd, dy / dd); pen = r - dd
                } else {
                    n = (-b.vx, -b.vy); pen = r
                }
                if pen > bestPen { bestPen = pen; bestN = n; bestCell = inside ? board.index(cx, cy) : -1 }
            }
        }
        if bestPen > 0 {
            let k: CellKind = bestCell >= 0 ? board.kind[bestCell] : .wall
            var bounce = true
            if k == .wall {
                if bestCell >= 0 { revealWall(bestCell) }
            } else {
                let broke = hit(bestCell, by: b.kind)
                if broke && b.pierce > 0 { b.pierce -= 1; bounce = false }
            }
            if bounce {
                let dot = b.vx * bestN.0 + b.vy * bestN.1
                if dot < 0 { b.vx -= 2 * dot * bestN.0; b.vy -= 2 * dot * bestN.1 }
                nx += bestN.0 * bestPen
                ny += bestN.1 * bestPen
                // A little scatter so balls never settle into a loop.
                let a = atan2(b.vy, b.vx) + rng.range(-0.06, 0.06)
                b.vx = cos(a); b.vy = sin(a)
                b.pierce = basePierce(b.kind)
                if b.kind == .sniper { aim(&b, fromX: nx, fromY: ny) }
            }
        }
        // Belt and braces: a ball that ends up inside a solid cell goes back to the spawn.
        if !phasing, solidAt(nx, ny) {
            nx = Double(board.spawn.x) + 0.5
            ny = Double(board.spawn.y) + 0.5
        }
        b.x = nx; b.y = ny
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
                    for dx in -r...r where (abs(dx) == r || abs(dy) == r) && ahead(dx, dy) {
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
