/// The board: cells, fog, effects and balls into the board canvas, then through the camera
/// into the frame; plus the HUD that floats over the board.
extension Renderer {
    /// The board-pixel rectangle the camera can see, padded by a cell.
    func visibleBoardRect(_ g: Game, _ L: Layout) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        let cam = g.ui.camera
        let a = cam.toBoard(0, 0), b = cam.toBoard(Double(L.board.w), Double(L.board.h))
        let cp = Tuning.cellPixels, size = g.board.pixelSize
        let x0 = max(0, Int(a.x.rounded(.down)) - cp), y0 = max(0, Int(a.y.rounded(.down)) - cp)
        let x1 = min(size, Int(b.x.rounded(.up)) + cp), y1 = min(size, Int(b.y.rounded(.up)) + cp)
        return (x0, y0, max(x0, x1), max(y0, y1))
    }

    /// Copies the board canvas into the frame through the camera. At rest the zoom is a level
    /// and the origin is a whole pixel, so each board pixel becomes an exact zoom x zoom block
    /// (or, at 0.5, every other board pixel is shown).
    func present(_ g: Game, _ L: Layout) {
        let c = canvas, b = boardCanvas, cam = g.ui.camera
        var ox = cam.origin.x, oy = cam.origin.y
        if g.shake > 0 {
            let m = Double(Int((g.shake * 2).rounded()))
            ox += (sin(g.time * 91) * m).rounded(); oy += (cos(g.time * 73) * m).rounded()
        }
        if cam.isAtRest { ox = ox.rounded(); oy = oy.rounded() }
        let z = cam.zoom
        hit(L.board, .board)
        var srcX = [Int](repeating: -1, count: L.board.w)
        for vx in 0..<L.board.w {
            let bx = Int(((Double(vx) - ox) / z).rounded(.down))
            srcX[vx] = bx >= 0 && bx < b.width ? bx : -1
        }
        b.pixels.withUnsafeBufferPointer { src in
            c.pixels.withUnsafeMutableBufferPointer { dst in
                for vy in 0..<L.board.h {
                    let by = Int(((Double(vy) - oy) / z).rounded(.down))
                    let dy = L.board.y + vy
                    guard dy >= 0, dy < c.height else { continue }
                    let rowOK = by >= 0 && by < b.height
                    for vx in 0..<L.board.w {
                        let dx = L.board.x + vx
                        guard dx >= 0, dx < c.width else { continue }
                        let sx = srcX[vx]
                        dst[dy * c.width + dx] = rowOK && sx >= 0 ? src[by * b.width + sx] : Palette.black
                    }
                }
            }
        }
    }

    func drawBoard(_ g: Game, _ L: Layout) {
        let b = g.board, t = g.time
        if boardCanvas.width != b.pixelSize || boardCanvas.height != b.pixelSize {
            boardCanvas = Canvas(width: b.pixelSize, height: b.pixelSize)
        }
        let c = boardCanvas
        let cp = Tuning.cellPixels
        let vis = visibleBoardRect(g, L)
        c.clip = nil
        c.fill(vis.x0, vis.y0, vis.x1 - vis.x0, vis.y1 - vis.y0, Palette.black)
        let goldIndex = b.index(b.gold.x, b.gold.y)
        // The gold only glows once you've dug within `Tuning.goldSenseRadius` of it.
        let goldAlive = b.kind[goldIndex] == .gold && Fog.goldSensed(b)
        let shownShards = Set(Fog.shownShards(b))

        for y in (vis.y0 / cp)..<min(b.size, (vis.y1 + cp - 1) / cp) {
            for x in (vis.x0 / cp)..<min(b.size, (vis.x1 + cp - 1) / cp) {
                let i = b.index(x, y)
                let px = x * cp, py = y * cp
                let cov = Fog.coverage(b, i, at: t)
                if cov <= 0 {
                    // Pure black, except the gold's glow and sensed shards in the dark.
                    if goldAlive {
                        let gl = Fog.goldGlow(b, x, y, at: t)
                        if gl > 0 { darkGlow(px, py, gl, isGold: i == goldIndex) }
                    }
                    if shownShards.contains(i) { sensedShard(px, py, t, i) }
                    continue
                }
                drawCell(g, i, x, y, px, py, cov)
            }
        }

        // Radar: a marching-ants square that always contains the gold.
        if goldAlive, let hint = Fog.radarHint(b, rank: g.mods.radar) {
            let r = Rect((hint.center.x - hint.radius) * cp, (hint.center.y - hint.radius) * cp,
                         (2 * hint.radius + 1) * cp, (2 * hint.radius + 1) * cp)
            let phase = Int(t * 8)
            let col = Palette.goldDim.glowing(90)
            c.dottedLine(r.x, r.y, r.maxX - 1, r.y, col, phase: phase)
            c.dottedLine(r.maxX - 1, r.y, r.maxX - 1, r.maxY - 1, col, phase: phase)
            c.dottedLine(r.maxX - 1, r.maxY - 1, r.x, r.maxY - 1, col, phase: phase)
            c.dottedLine(r.x, r.maxY - 1, r.x, r.y, col, phase: phase)
        }

        // Particles: a 2x2 art-pixel chip each (so they survive the 0.5 subsample), stepping
        // to a darker colour instead of fading.
        for p in g.particles {
            let col = p.life / p.maxLife > 0.45 ? p.color : p.fade
            let x = Int((p.x * Double(cp)).rounded(.down)) & ~1, y = Int((p.y * Double(cp)).rounded(.down)) & ~1
            c.fill(x, y, 2, 2, col.glowing(140))
        }

        for r in g.rings {
            let k = 1 - r.life / r.maxLife
            let rad = (r.maxRadius * Double(cp) * k).rounded()
            let col = (r.life / r.maxLife > 0.35 ? r.color : Palette.dimmer(r.color)).glowing(r.overFog ? 200 : 255)
            c.ring(r.x * Double(cp), r.y * Double(cp), rad, col)
        }

        for bolt in g.bolts {
            for j in 1..<bolt.points.count {
                let a = bolt.points[j - 1], e = bolt.points[j]
                c.line(a.x, a.y, e.x, e.y, Palette.white.glowing(255))
                c.line(a.x + 1, a.y, e.x + 1, e.y, BallKind.lightning.color.glowing(255))
            }
        }

        for ball in g.balls {
            // The sprite's centre pixel sits on the ball's snapped position, and every trail
            // dot is a past centre pixel, so the tail lines up with the ball's middle.
            let bx = Int((ball.x * Double(cp)).rounded(.down)), by = Int((ball.y * Double(cp)).rounded(.down))
            for (j, tp) in ball.trail.enumerated() where j > 0 && j < 3 {
                c.set(tp.x, tp.y, ball.kind.shade.glowing(j == 1 ? 110 : 60))
            }
            let s = Sprites.ball(ball.kind)
            if ball.phaseLeft > 0 {
                for sy in 0..<s.height { for sx in 0..<s.width where (sx + sy + Int(t * 20)) & 1 == 0 {
                    if let p = s.pixels[sy * s.width + sx] { c.set(bx - 2 + sx, by - 2 + sy, p) }
                } }
            } else {
                c.sprite(s, bx - 2, by - 2)
            }
        }
    }

    func darkGlow(_ px: Int, _ py: Int, _ g: Double, isGold: Bool) {
        let c = boardCanvas
        for yy in 0..<Tuning.cellPixels {
            for xx in 0..<Tuning.cellPixels {
                let ax = px + xx, ay = py + yy
                if isGold {
                    if Bayer.on(ax, ay, 0.35 + g * 0.6) { c.set(ax, ay, (g > 0.7 ? Palette.gold : Palette.goldDim).glowing(UInt8(80 + g * 120))) }
                } else if Bayer.on(ax, ay, g * 0.45) {
                    c.set(ax, ay, (g > 0.6 ? Palette.goldDim : Palette.goldDeep).glowing(UInt8(40 + g * 80)))
                }
            }
        }
    }

    /// The 8x8 diamond inside a shard cell (offset 1 in its 10x10 cell).
    static let diamond: [Bool] = {
        var m = [Bool](repeating: false, count: 64)
        for y in 0..<8 { for x in 0..<8 {
            let dx = abs(2 * x - 7), dy = abs(2 * y - 7)
            m[y * 8 + x] = dx + dy <= 8
        } }
        return m
    }()

    /// A shard sensed through the fog: a dithered mint diamond that breathes.
    func sensedShard(_ px: Int, _ py: Int, _ t: Double, _ i: Int) {
        let c = boardCanvas
        let pulse = 0.35 + 0.3 * sin(t * 3 + Double(i % 7))
        for y in 0..<8 { for x in 0..<8 where Renderer.diamond[y * 8 + x] {
            let ax = px + 1 + x, ay = py + 1 + y
            if Bayer.on(ax, ay, pulse) { c.set(ax, ay, Palette.mintDim.glowing(120)) }
        } }
    }

    func drawCell(_ g: Game, _ i: Int, _ x: Int, _ y: Int, _ px: Int, _ py: Int, _ cov: Double) {
        let c = boardCanvas, b = g.board, t = g.time
        let cp = Tuning.cellPixels
        let kind = b.kind[i]
        var base: Pixel
        switch kind {
        case .empty: base = Palette.floor
        case .wall: base = Palette.wall
        case .block:
            // Durability is brightness alone: the block's step on the blue ladder.
            base = Palette.ladder[Economy.ladderStep(hp: b.hp[i], level: b.level)].glowing(26)
        case .shard: base = Palette.mint.glowing(200)
        case .gold: base = Palette.gold.glowing(255)
        }
        // A hit flashes the cell white for one frame.
        let flash = kind.breakable && t - b.hitAt[i] < 1.0 / 60
        if flash { base = Palette.white.glowing(200) }

        let plain = cov >= 1 && (kind == .empty || kind == .wall || flash || (kind == .block && !b.rich[i]))
        if plain {
            c.fill(px, py, cp, cp, base)
            return
        }
        for ly in 0..<cp {
            for lx in 0..<cp {
                let ax = px + lx, ay = py + ly
                // Reveal: the cell dithers in, pixel by pixel, from black.
                if cov < 1 && !Bayer.on(ax, ay, cov) { continue }
                var col = base
                switch kind {
                case .gold:
                    // Damage drains it from the top: the lost share of its HP shows dim.
                    let lost = 1 - b.hp[i] / max(1, b.maxHP[i])
                    if ly < Int((lost * Double(cp)).rounded(.up)) && b.hp[i] < b.maxHP[i] { col = Palette.goldDim.glowing(120) }
                    // A shimmer line sweeping across.
                    else if ((ax + ay) - Int(t * 12)) % 24 == 0 { col = Palette.white.glowing(255) }
                case .shard:
                    // A solid glowing mint cell, with a sparkle line sweeping over it.
                    if ((ax - ay) - Int(t * 10)) % 16 == 0 { col = Palette.white.glowing(255) }
                default: break
                }
                c.set(ax, ay, col)
            }
        }
        if kind == .block && b.rich[i] && cov >= 1 {
            // Rich: a single white pixel that blinks on its own beat.
            let beat = (t * 1.3 + Double(i % 17) * 0.37).truncatingRemainder(dividingBy: 2)
            if beat < 0.6 { c.fill(px + 2, py + 2, 2, 2, Palette.white.glowing(255)) }
        }
    }

    // MARK: - Launch preview

    /// Placing a ball: a ghost of the selected ball where the finger went down, inside a ring
    /// wide enough to show around the finger that hides it. Once the finger pulls away the
    /// ring fades out and four dots show in front of the ghost, on the side away from the
    /// finger (the way it will fly). With no balls yet, a ghost blinks
    /// at the spawn with a short prompt.
    func drawLaunchPreview(_ g: Game, _ L: Layout) {
        guard g.ui.sheet == nil, !g.ui.skillsOpen, !g.ui.paused, g.clearTimer == nil else { return }
        let c = canvas, cam = g.ui.camera
        let k = g.mods.unlocked.contains(g.ui.selected) ? g.ui.selected : .basic
        let s = max(1, Int(cam.zoom.rounded(.down)))
        c.clip = L.board
        if let l = g.ui.launch {
            let fx = Double(l.from.x) + 0.5, fy = Double(l.from.y) + 0.5
            // The hold ring: it appears the moment the hold takes, around the finger, and
            // dithers away once the finger pulls out to aim.
            let cover = l.pulledAt.map { 1 - (g.time - $0) / Tuning.holdRingFade } ?? 1
            c.ring(fx, fy, Double(Tuning.holdRingRadius), k.color.glowing(160), cover: cover)
            // A thin ring in the ball's colour marks the ball being placed apart from the rest.
            c.ring(fx, fy, 2.5 * Double(s) + 3, Palette.dimmer(k.color).glowing(120))
            c.sprite(Sprites.ball(k), l.from.x - 2 * s, l.from.y - 2 * s, scale: s)
            if let d = l.direction {
                // Four dots of one size: the way it will fly.
                let len = (d.x * d.x + d.y * d.y).squareRoot()
                for j in 0..<Tuning.aimDots {
                    let r = 2.5 * Double(s) + 6 + Double(j * 4)
                    let x = l.from.x + Int((d.x / len * r).rounded()), y = l.from.y + Int((d.y / len * r).rounded())
                    c.fill(x - 1, y - 1, 2, 2, k.color.glowing(160))
                }
            }
            c.clip = nil
            return
        }
        guard g.balls.isEmpty else { c.clip = nil; return }
        let cp = Double(Tuning.cellPixels)
        let sp = g.board.spawn
        let v = cam.toView((Double(sp.x) + 0.5) * cp, (Double(sp.y) + 0.5) * cp)
        let lx = L.board.x + Int(v.x.rounded(.down)), ly = L.board.y + Int(v.y.rounded(.down))
        if Int(g.time * 2) & 1 == 0 { c.sprite(Sprites.ball(k), lx - 2 * s, ly - 2 * s, scale: s) }
        c.clip = nil
        let label = "HOLD AN OPEN SPOT, DRAG TO AIM"
        let w = PixelFont.measure(label)
        let A = L.boardContent
        let tx = A.x + (A.w - w) / 2, ty = min(L.board.maxY - 34, A.maxY - 15)
        c.fill(tx - 4, ty - 4, w + 8, 15, Palette.black)
        c.text(label, tx, ty, Palette.text2)
    }

    // MARK: - HUD over the board

    func drawBoardHUD(_ g: Game, _ L: Layout) {
        let c = canvas
        let z = g.ui.camera
        if z.isAtRest && z.zoom != 1 {
            let s = z.zoom < 1 ? "0.5x" : "\(Int(z.zoom))x"
            let w = PixelFont.measure(s)
            let A = L.boardContent
            c.fill(A.maxX - w - 12, A.y + 4, w + 8, 15, Palette.black)
            c.text(s, A.maxX - w - 8, A.y + 8, Palette.text2)
        }
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
