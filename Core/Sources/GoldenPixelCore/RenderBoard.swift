/// The board: cells, fog, effects and balls into the board canvas, then through the camera
/// into the frame; plus the HUD that floats over the board.
///
/// The board canvas is kept between frames. A cell's pixels are decided by its `CellLook`
/// alone, so a frame repaints only the cells whose look differs from the one they were last
/// painted with (a hit, a reveal dithering in, a sparkle moving on), wherever the change came
/// from. Balls, particles and the other effects are drawn over the cells through the canvas's
/// journal and come back off before the next frame.
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
    ///
    /// It goes a row at a time: a view row is black (off the board), a copy of the view row
    /// above it (zoomed in, both show the same board row), a straight copy of a board row
    /// (zoom 1), or a pick of that row's pixels through `columns`. Every pixel of the board's
    /// part of the frame is written, so the frame needs no clear first.
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
        // The part of the board's view that is on the canvas: all of it, in any real layout.
        let vx0 = max(0, -L.board.x), vx1 = min(L.board.w, c.width - L.board.x)
        let vy0 = max(0, -L.board.y), vy1 = min(L.board.h, c.height - L.board.y)
        guard vx0 < vx1, vy0 < vy1 else { return }
        // The board column each view column shows. They only step forward, so the view
        // columns that are on the board are one run, first..<end; `straight` when that run
        // is the board's columns one for one.
        if columns.count < vx1 { columns = [Int](repeating: 0, count: vx1) }
        var first = vx1, end = vx0, straight = true
        for vx in vx0..<vx1 {
            let bx = Int(((Double(vx) - ox) / z).rounded(.down))
            guard bx >= 0, bx < b.width else { continue }
            if first == vx1 { first = vx } else if bx != columns[vx - 1] + 1 { straight = false }
            columns[vx] = bx
            end = vx + 1
        }
        let cw = c.width, bw = b.width, bh = b.height, black = Palette.black
        let left = L.board.x, top = L.board.y
        columns.withUnsafeBufferPointer { col in
            b.pixels.withUnsafeBufferPointer { src in
                c.pixels.withUnsafeMutableBufferPointer { dst in
                    // The board row the view row above shows, while that is one.
                    var above = -1
                    for vy in vy0..<vy1 {
                        let by = Int(((Double(vy) - oy) / z).rounded(.down))
                        let row = dst.baseAddress! + ((top + vy) * cw + left)
                        guard by >= 0, by < bh, first < end else {
                            (row + vx0).update(repeating: black, count: vx1 - vx0)
                            above = -1
                            continue
                        }
                        if by == above {
                            (row + vx0).update(from: row - cw + vx0, count: vx1 - vx0)
                            continue
                        }
                        above = by
                        if first > vx0 { (row + vx0).update(repeating: black, count: first - vx0) }
                        if end < vx1 { (row + end).update(repeating: black, count: vx1 - end) }
                        let line = src.baseAddress! + by * bw
                        if straight {
                            (row + first).update(from: line + col[first], count: end - first)
                        } else {
                            for vx in first..<end { row[vx] = line[col[vx]] }
                        }
                    }
                }
            }
        }
    }

    func drawBoard(_ g: Game, _ L: Layout) {
        let b = g.board, t = g.time
        if boardCanvas.width != b.pixelSize || boardCanvas.height != b.pixelSize || cellLooks.count != b.size * b.size {
            boardCanvas = Canvas(width: b.pixelSize, height: b.pixelSize)
            cellLooks = [CellLook](repeating: 0, count: b.size * b.size)
        }
        let c = boardCanvas
        let cp = Tuning.cellPixels
        let vis = visibleBoardRect(g, L)
        c.clip = nil
        // Last frame's balls and effects come off: the canvas is the cells alone again.
        let inkedBefore = c.inked
        var touched = false
        c.rewind()
        let goldIndex = b.index(b.gold.x, b.gold.y)
        // The gold only glows once you've dug within `Tuning.goldSenseRadius` of it.
        let goldAlive = b.kind[goldIndex] == .gold && Fog.goldSensed(b)
        let shards = shownShards(b)
        let frame = LookFrame(t: t, level: b.level, goldAlive: goldAlive, goldIndex: goldIndex, gold: b.gold,
                              glow: Fog.goldPulse(at: t), shard0: shards.first ?? -1, shard1: shards.count > 1 ? shards[1] : -1,
                              moreShards: shards.count > 2 ? shards : [])

        // Only what the camera can see is brought up to date; the rest keeps the look it was
        // last painted with and catches up when it scrolls into view.
        let kind = b.kind, hp = b.hp, maxHP = b.maxHP, rich = b.rich
        let revealed = b.revealed, revealedAt = b.revealedAt, hitAt = b.hitAt
        var looks = cellLooks
        cellLooks = []
        for y in (vis.y0 / cp)..<min(b.size, (vis.y1 + cp - 1) / cp) {
            for x in (vis.x0 / cp)..<min(b.size, (vis.x1 + cp - 1) / cp) {
                let i = y * b.size + x
                let look = frame.look(i, x, y, kind: kind[i], hp: hp[i], maxHP: maxHP[i], rich: rich[i],
                                      revealed: revealed[i], revealedAt: revealedAt[i], hitAt: hitAt[i])
                if look != looks[i] {
                    looks[i] = look
                    paintCell(look, x * cp, y * cp)
                    touched = true
                }
            }
        }
        cellLooks = looks

        c.recording = true
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
        c.recording = false
        // A cell repainted, or different balls and effects drawn than last frame's.
        boardChanged = touched || c.inked != inkedBefore
    }

    /// The sensed shards to show in the dark (`Fog.shownShards`), worked out again only when
    /// the board's cells or its fog have changed.
    func shownShards(_ b: Board) -> [Int] {
        if let s = shardCache, s.board === b, s.version == b.fogVersion { return s.shown }
        let shown = Fog.shownShards(b)
        shardCache = (b, b.fogVersion, shown)
        return shown
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

    /// Paints a cell from its look: every one of its pixels, so whatever was there is gone.
    func paintCell(_ look: CellLook, _ px: Int, _ py: Int) {
        let c = boardCanvas, cp = Tuning.cellPixels
        let cover = Int(look >> CellLookBits.cover) & 31
        guard cover > 0 else { paintDarkCell(look, px, py); return }
        let base = Pixel(truncatingIfNeeded: look)
        let detail = Int(look >> CellLookBits.detail) & 3
        if cover == CellLookBits.full && detail == CellLookBits.flat {
            c.fill(px, py, cp, cp, base)
            // Rich: a single white pixel that blinks on its own beat.
            if (look >> CellLookBits.blink) & 1 != 0 { c.fill(px + 2, py + 2, 2, 2, Palette.white.glowing(255)) }
            return
        }
        // Reveal: the cell dithers in, pixel by pixel, from black.
        let dithered = cover < CellLookBits.full
        if dithered { c.fill(px, py, cp, cp, Palette.black) }
        let phase = Int(look >> CellLookBits.phase) & 31, drained = Int(look >> CellLookBits.drained) & 15
        for ly in 0..<cp {
            for lx in 0..<cp {
                let ax = px + lx, ay = py + ly
                if dithered && Bayer.at(ax, ay) >= cover { continue }
                var col = base
                if detail == CellLookBits.gold {
                    // Damage drains it from the top: the lost share of its HP shows dim.
                    if ly < drained { col = Palette.goldDim.glowing(120) }
                    // A shimmer line sweeping across.
                    else if ((ax + ay) - phase) % 24 == 0 { col = Palette.white.glowing(255) }
                } else if detail == CellLookBits.shard {
                    // A solid glowing mint cell, with a sparkle line sweeping over it.
                    if ((ax - ay) - phase) % 16 == 0 { col = Palette.white.glowing(255) }
                }
                c.set(ax, ay, col)
            }
        }
    }

    /// A cell still in the fog: pure black, except the gold's glow and a sensed shard (a
    /// dithered mint diamond that breathes).
    func paintDarkCell(_ look: CellLook, _ px: Int, _ py: Int) {
        let c = boardCanvas, cp = Tuning.cellPixels
        c.fill(px, py, cp, cp, Palette.black)
        let glow = Int(look >> CellLookBits.glowCover) & 31
        if glow > 0 {
            let isGold = (look >> CellLookBits.glowIsGold) & 1 != 0, bright = (look >> CellLookBits.glowBright) & 1 != 0
            let col = (isGold ? (bright ? Palette.gold : Palette.goldDim) : (bright ? Palette.goldDim : Palette.goldDeep))
                .glowing(UInt8(truncatingIfNeeded: look))
            for yy in 0..<cp {
                for xx in 0..<cp where Bayer.at(px + xx, py + yy) < glow { c.set(px + xx, py + yy, col) }
            }
        }
        let shard = Int(look >> CellLookBits.shardCover) & 31
        if shard > 0 {
            for y in 0..<8 { for x in 0..<8 where Renderer.diamond[y * 8 + x] {
                let ax = px + 1 + x, ay = py + 1 + y
                if Bayer.at(ax, ay) < shard { c.set(ax, ay, Palette.mintDim.glowing(120)) }
            } }
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

/// Everything that decides how a board cell is painted, packed into one number: two cells
/// (or one cell on two frames) with the same look have the same pixels, give or take where
/// the cell sits. `Renderer.paintCell` paints from the look and nothing else, so nothing a
/// cell shows can be missing from it. 0 is a cell in the fog with nothing showing: black.
///
/// A lit cell: its flat colour (bits 0-31), how much of it has dithered in (`cover`, 1...16
/// of the Bayer steps, or `full`), what moves on it (`detail`: the gold's shimmer and drain,
/// a shard's sparkle), and a rich block's blink. A cell in the fog (`cover` 0): the gold's
/// glow there (its dither, colour step and glow byte) and a sensed shard's dither.
typealias CellLook = UInt64

enum CellLookBits {
    static let cover: UInt64 = 32, detail: UInt64 = 37, phase: UInt64 = 39, drained: UInt64 = 44, blink: UInt64 = 48
    static let glowCover: UInt64 = 8, glowBright: UInt64 = 13, glowIsGold: UInt64 = 14, shardCover: UInt64 = 15
    static let full = 17
    static let flat = 0, gold = 1, shard = 2

    /// How many of the 16 Bayer steps are on at coverage `t`: pixel (x, y) is on
    /// (`Bayer.on(x, y, t)`) exactly when `Bayer.at(x, y)` is below this.
    @inline(__always) static func steps(_ t: Double) -> Int {
        let v = t * 16
        return v > 0 ? (v >= 16 ? 16 : Int(v.rounded(.up))) : 0
    }
}

/// What every cell's look shares on one frame.
struct LookFrame {
    let t: Double
    let level: Int
    /// The gold still stands and has been sensed, so the dark around it glows.
    let goldAlive: Bool
    let goldIndex: Int
    let gold: Point
    /// The glow's beat this frame (`Fog.goldPulse`).
    let glow: Double
    /// The sensed shards showing in the dark (`Fog.shownShards`, at most
    /// `Tuning.maxSensedShards`): the first two, and all of them if there are ever more.
    let shard0: Int, shard1: Int
    let moreShards: [Int]

    static let glowReach = Int(Tuning.goldGlowRadius.rounded(.up))

    @inline(__always)
    func look(_ i: Int, _ x: Int, _ y: Int, kind: CellKind, hp: Double, maxHP: Double, rich: Bool,
              revealed: Bool, revealedAt: Double, hitAt: Double) -> CellLook {
        let since = t - revealedAt
        guard revealed, since > 0 else {
            // Pure black, except the gold's glow and sensed shards in the dark.
            var look: CellLook = 0
            if goldAlive {
                let dx = x - gold.x, dy = y - gold.y
                if abs(dx) <= LookFrame.glowReach, abs(dy) <= LookFrame.glowReach {
                    let g = Fog.goldGlow(dx: dx, dy: dy, pulse: glow)
                    if g > 0 {
                        if i == goldIndex {
                            look = UInt64(UInt8(80 + g * 120)) | UInt64(CellLookBits.steps(0.35 + g * 0.6)) << CellLookBits.glowCover
                                | (g > 0.7 ? 1 : 0) << CellLookBits.glowBright | 1 << CellLookBits.glowIsGold
                        } else {
                            look = UInt64(UInt8(40 + g * 80)) | UInt64(CellLookBits.steps(g * 0.45)) << CellLookBits.glowCover
                                | (g > 0.6 ? 1 : 0) << CellLookBits.glowBright
                        }
                    }
                }
            }
            if i == shard0 || i == shard1 || (!moreShards.isEmpty && moreShards.contains(i)) {
                let pulse = 0.35 + 0.3 * sin(t * 3 + Double(i % 7))
                look |= UInt64(CellLookBits.steps(pulse)) << CellLookBits.shardCover
            }
            return look
        }
        // 0...1 as the cell dithers in (`Fog.coverage`).
        let shown = since / Fog.fadeTime
        let full = shown >= 1
        var base: Pixel
        switch kind {
        case .empty: base = Palette.floor
        case .wall: base = Palette.wall
        case .block:
            // Durability is brightness alone: the block's step on the blue ladder.
            base = Palette.ladder[Economy.ladderStep(hp: hp, level: level)].glowing(26)
        case .shard: base = Palette.mint.glowing(200)
        case .gold: base = Palette.gold.glowing(255)
        }
        // A hit flashes the cell white for one frame.
        let flash = kind.breakable && t - hitAt < 1.0 / 60
        if flash { base = Palette.white.glowing(200) }
        let cover = full ? CellLookBits.full : CellLookBits.steps(shown)
        var look = UInt64(base) | UInt64(cover) << CellLookBits.cover
        if full && (kind == .empty || kind == .wall || flash || (kind == .block && !rich)) { return look }
        switch kind {
        case .gold:
            let lost = 1 - hp / max(1, maxHP)
            let drained = hp < maxHP ? min(Tuning.cellPixels, max(0, Int((lost * Double(Tuning.cellPixels)).rounded(.up)))) : 0
            look |= UInt64(CellLookBits.gold) << CellLookBits.detail | UInt64(drained) << CellLookBits.drained
                | UInt64(LookFrame.wrap(Int(t * 12), 24)) << CellLookBits.phase
        case .shard:
            look |= UInt64(CellLookBits.shard) << CellLookBits.detail | UInt64(LookFrame.wrap(Int(t * 10), 16)) << CellLookBits.phase
        case .block:
            if rich && full {
                let beat = (t * 1.3 + Double(i % 17) * 0.37).truncatingRemainder(dividingBy: 2)
                if beat < 0.6 { look |= 1 << CellLookBits.blink }
            }
        default: break
        }
        return look
    }

    @inline(__always) static func wrap(_ v: Int, _ n: Int) -> Int { ((v % n) + n) % n }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
