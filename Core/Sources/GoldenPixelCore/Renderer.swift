/// Draws a whole frame into one `Canvas` at art-pixel resolution and records the UI's hit
/// regions. Integer coordinates only: physics positions are snapped to the art grid here.
///
/// Light comes from one place, the top-left, for everything: blocks and walls get a 1-pixel
/// highlight on faces exposed to open space above or to the left and a 1-pixel shadow on
/// exposed faces below or to the right. Faces against another solid cell get nothing, so a
/// packed mass of cells reads as one seamless surface with no lines between cells. Cards,
/// buttons and sprites use the same rule.
///
/// The board is drawn into its own canvas at 1 board art pixel per canvas pixel, then copied
/// into the frame through the camera at a whole zoom (nearest neighbour), so zoomed pixels are
/// exact 2x2, 3x3 ... blocks of the same grid the UI uses.

public final class Renderer {
    public private(set) var canvas: Canvas
    let boardCanvas: Canvas
    var hits: [Hit] = []

    public init(width: Int = Tuning.canvasWidth, height: Int = Tuning.canvasHeight) {
        canvas = Canvas(width: width, height: height)
        let side = Tuning.boardCells * Tuning.cellPixels
        boardCanvas = Canvas(width: side, height: side)
    }

    public func resize(width: Int, height: Int) {
        guard width != canvas.width || height != canvas.height else { return }
        canvas = Canvas(width: max(1, width), height: max(1, height))
    }

    public func render(_ g: Game) {
        let c = canvas
        c.clear()
        c.clip = nil
        hits = []
        let layout = Layout.make(width: c.width, height: c.height, collapsed: g.ui.collapsed)
        g.ui.layout = layout
        g.ui.camera.setSizes(boardW: boardCanvas.width, boardH: boardCanvas.height, viewW: layout.board.w, viewH: layout.board.h)

        drawBoard(g)
        present(g, layout)
        if g.ui.started {
            drawPanel(g, layout)
            drawBoardHUD(g, layout)
            if g.ui.skillsOpen { drawSkills(g) }
        } else {
            drawTitle(g, layout)
        }
        drawBanners(g, layout)
        if let t = g.ui.tooltip { drawTooltip(t) }
        g.ui.hits = hits
    }

    func hit(_ r: Rect, _ a: Action, _ info: [String] = []) { hits.append(Hit(rect: r, action: a, info: info)) }

    /// 1-pixel top-left light and bottom-right shade around a UI box.
    func bevel(_ r: Rect, light: Pixel, dark: Pixel) {
        let c = canvas
        c.hline(r.x, r.maxX - 1, r.y, light); c.vline(r.x, r.y, r.maxY - 1, light)
        c.hline(r.x + 1, r.maxX - 1, r.maxY - 1, dark); c.vline(r.maxX - 1, r.y + 1, r.maxY - 1, dark)
    }

    // MARK: - Board

    /// Copies the board canvas into the frame through the camera. At rest the zoom is whole and
    /// the origin is a whole pixel, so each board pixel becomes an exact zoom x zoom block.
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
        // Column lookup once per frame.
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

    func drawBoard(_ g: Game) {
        let c = boardCanvas, b = g.board, t = g.time
        let cp = Tuning.cellPixels
        c.clear()
        c.clip = nil
        let goldIndex = b.index(b.gold.x, b.gold.y)
        let goldAlive = b.kind[goldIndex] == .gold

        for y in 0..<b.size {
            for x in 0..<b.size {
                let i = b.index(x, y)
                let px = x * cp, py = y * cp
                let cov = Fog.coverage(b, i, at: t)
                if cov <= 0 {
                    // Pure black, except the golden pixel's glow seeping through the dark.
                    if goldAlive {
                        let gl = Fog.goldGlow(b, x, y, at: t)
                        if gl > 0 { darkGlow(px, py, gl, isGold: i == goldIndex) }
                    }
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

        // Particles: one art pixel each, stepping to a darker colour instead of fading.
        for p in g.particles {
            let col = p.life / p.maxLife > 0.45 ? p.color : p.fade
            c.set(Int((p.x * Double(cp)).rounded(.down)), Int((p.y * Double(cp)).rounded(.down)), col.glowing(140))
        }

        for r in g.rings {
            let k = 1 - r.life / r.maxLife
            let rad = (r.maxRadius * Double(cp) * k).rounded()
            let col = (r.life / r.maxLife > 0.35 ? r.color : dimmer(r.color)).glowing(r.overFog ? 200 : 255)
            // Centred on the exact point (a cell's centre falls between pixels on a 10-px
            // cell), so the ring is symmetric about it.
            c.ring(r.x * Double(cp), r.y * Double(cp), rad, col)
        }

        for bolt in g.bolts {
            for j in 1..<bolt.points.count {
                let a = bolt.points[j - 1], e = bolt.points[j]
                c.line(a.x + 1, a.y + 1, e.x + 1, e.y + 1, Palette.cyan.glowing(255))
                c.line(a.x, a.y, e.x, e.y, Palette.white.glowing(255))
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

    func dimmer(_ p: Pixel) -> Pixel {
        let r = (p & 0xff) / 2, gg = ((p >> 8) & 0xff) / 2, bb = ((p >> 16) & 0xff) / 2
        return r | (gg << 8) | (bb << 16)
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

    func drawCell(_ g: Game, _ i: Int, _ x: Int, _ y: Int, _ px: Int, _ py: Int, _ cov: Double) {
        let c = boardCanvas, b = g.board, t = g.time
        let cp = Tuning.cellPixels
        let kind = b.kind[i]
        var base: Pixel, light: Pixel, dark: Pixel
        switch kind {
        case .empty:
            // Explored floor is a flat step above the fog's pure black.
            base = Palette.panel1; light = base; dark = base
        case .wall:
            base = Palette.wall; light = Palette.wallLight; dark = Palette.wallShade
        case .block:
            // Durability is colour alone: the block's step on the ladder.
            let st = Economy.ladderStep(hp: b.hp[i], level: b.level)
            base = Palette.ladder[st].glowing(26); light = Palette.ladderLight[st].glowing(30); dark = Palette.ladderDark[st].glowing(14)
        case .gold:
            base = Palette.gold.glowing(255); light = Palette.goldLight.glowing(255); dark = Palette.goldDim.glowing(200)
        }
        // Faces open to dug space catch the light (top, left) or fall into shade (bottom, right).
        func open(_ nx: Int, _ ny: Int) -> Bool { b.inside(nx, ny) && b.kind[b.index(nx, ny)] == .empty }
        let solid = kind != .empty
        let up = solid && open(x, y - 1), left = solid && open(x - 1, y)
        let down = solid && open(x, y + 1), right = solid && open(x + 1, y)
        // A hit flashes the cell white for one frame.
        let flash = (kind == .block || kind == .gold) && t - b.hitAt[i] < 1.0 / 60
        // Reveal: a square iris opening from the cell's centre, its rim drawn in the light tone.
        let mid = Double(cp - 1) / 2
        let iris = cov >= 1 ? 99.0 : cov * (mid + 1)

        for ly in 0..<cp {
            for lx in 0..<cp {
                let ax = px + lx, ay = py + ly
                let d = max(abs(Double(lx) - mid), abs(Double(ly) - mid))
                if d > iris { continue }
                var col = base
                if (ly == 0 && up) || (lx == 0 && left) { col = light }
                if (ly == cp - 1 && down) || (lx == cp - 1 && right) { col = dark }
                if kind == .gold {
                    // A soft-edged highlight in the lit corner, and a shimmer line sweeping across.
                    if lx >= 1 && lx <= 2 && ly >= 1 && ly <= 2 { col = light }
                    if ((ax + ay) - Int(t * 12)) % 24 == 0 { col = Palette.white.glowing(255) }
                }
                if flash { col = Palette.white.glowing(200) }
                if d > iris - 0.6 && cov < 1 { col = kind == .empty ? Palette.border : light }
                c.set(ax, ay, col)
            }
        }
        if kind == .block && b.rich[i] && cov >= 1 {
            // Rich: a little plus-shaped sparkle that blinks on its own beat.
            let beat = (t * 1.3 + Double(i % 17) * 0.37).truncatingRemainder(dividingBy: 2)
            let sx = px + 2, sy = py + 2
            if beat < 0.6 {
                c.set(sx, sy, Palette.white.glowing(255))
                if beat < 0.3 {
                    let l = Palette.ladderLight[Economy.ladderStep(hp: b.hp[i], level: b.level)].glowing(160)
                    c.set(sx - 1, sy, l); c.set(sx + 1, sy, l); c.set(sx, sy - 1, l); c.set(sx, sy + 1, l)
                }
            } else {
                c.set(sx, sy, Palette.ladderLight[Economy.ladderStep(hp: b.hp[i], level: b.level)].glowing(120))
            }
        }
    }

    // MARK: - HUD over the board

    func drawBoardHUD(_ g: Game, _ L: Layout) {
        let c = canvas
        var y = L.board.y + 3
        let x = L.board.x + 3
        if g.ui.collapsed {
            let s = compact(g.progress.money)
            c.fill(x - 2, y - 2, PixelFont.measure(s) + 13, 11, Palette.black)
            c.sprite(Sprites.coin, x, y)
            c.text(s, x + 9, y, Palette.white)
            y += 11
        }
        let m = g.comboMultiplier
        if m > 1.04 {
            let s = "x" + format1(m)
            let col = m >= 2.5 ? Palette.tiers[3] : (m >= 1.8 ? Palette.tiers[2] : Palette.tiers[1])
            c.fill(x - 2, y - 2, PixelFont.measure(s) + 4, 11, Palette.black)
            c.text(s, x, y, col.glowing(200))
        }
        let z = g.ui.camera
        if z.isAtRest && z.zoom > 1 {
            let s = "\(Int(z.zoom))x"
            let w = PixelFont.measure(s)
            c.fill(L.board.maxX - w - 5, L.board.y + 1, w + 4, 11, Palette.black)
            c.text(s, L.board.maxX - w - 3, L.board.y + 3, Palette.text2)
        }
    }

    func format1(_ v: Double) -> String {
        let t = Int((v * 10).rounded())
        return "\(t / 10).\(t % 10)"
    }

    // MARK: - Panel

    func drawPanel(_ g: Game, _ L: Layout) {
        let c = canvas, P = L.panel
        c.fill(P, Palette.panel0)
        // The panel's exposed face toward the board catches the light.
        if L.landscape { c.vline(P.x, P.y, P.maxY - 1, Palette.border) } else { c.hline(P.x, P.maxX - 1, P.y, Palette.border) }
        hit(P, .panel)
        if g.ui.collapsed {
            let r = L.landscape ? Rect(P.x + 1, P.y, P.w - 1, 17) : Rect(P.maxX - 17, P.y + 1, 17, P.h - 1)
            c.sprite(Sprites.chevronLeft, r.x + (r.w - 7) / 2, r.y + 5)
            hit(r, .toggleCollapse)
            return
        }

        // Header: money and depth, then stars, skill points and balls. Icons and numbers only.
        let x0 = P.x + 5
        var y = P.y + 5
        c.sprite(Sprites.coin, x0, y)
        c.text(compact(g.progress.money), x0 + 10, y, Palette.white)
        let lv = "\(g.board.level)"
        let lvx = P.maxX - 5 - PixelFont.measure(lv)
        c.text(lv, lvx, y, Palette.text2)
        c.sprite(Sprites.depth, lvx - 10, y)
        hit(Rect(P.x, P.y, P.w, 14), .none, ["LEVEL \(g.board.level)", g.board.name])
        y += 13
        c.sprite(Sprites.star, x0, y)
        c.text("\(g.progress.stars)", x0 + 10, y, Palette.text2)
        let spx = x0 + 10 + PixelFont.measure("\(g.progress.stars)") + 8
        c.sprite(Sprites.skillPoint, spx, y)
        c.text("\(g.progress.skillPoints)", spx + 10, y, g.progress.skillPoints > 0 ? Palette.cyan : Palette.text2)
        let bc = "\(g.balls.count)"
        let bcx = P.maxX - 5 - PixelFont.measure(bc)
        c.text(bc, bcx, y, Palette.text2)
        c.sprite(Sprites.ballIcon(.basic), bcx - 10, y)
        y += 13

        // Tabs, plus the collapse chevron.
        let tabs: [(Tab, Sprite)] = [(.balls, Sprites.tabBalls), (.upgrades, Sprites.tabUpgrade), (.skills, Sprites.tabSkills), (.more, Sprites.tabStar)]
        let tabW = (P.w - 2 - 17) / tabs.count
        for (j, (tab, icon)) in tabs.enumerated() {
            let r = Rect(P.x + 1 + j * tabW, y, tabW, 17)
            let active = g.ui.tab == tab && !(tab == .skills)
            if active { c.fill(r, Palette.panel2); c.hline(r.x, r.maxX - 1, r.maxY - 1, Palette.blue.glowing(160)) }
            let tint: Pixel = active ? Palette.white : (tab == .skills && g.progress.skillPoints > 0 ? Palette.cyan : Palette.muted)
            let press = g.isPressed(.tab(tab)) ? 1 : 0
            c.sprite(icon, r.x + (r.w - 7) / 2, r.y + 5 + press, tint: tint)
            hit(r, .tab(tab))
        }
        let cr = Rect(P.maxX - 17, y, 17, 17)
        c.sprite(Sprites.chevronRight, cr.x + 5, cr.y + 5)
        hit(cr, .toggleCollapse)
        y += 18
        c.hline(P.x + 1, P.maxX - 1, y - 1, Palette.border)

        let content = Rect(P.x + 1, y, P.w - 1, P.maxY - y)
        c.clip = content
        var contentHeight = 0
        switch g.ui.tab {
        case .balls, .skills: contentHeight = drawBallCards(g, content)
        case .upgrades: contentHeight = drawUpgrades(g, content)
        case .more: contentHeight = drawMore(g, content)
        }
        g.ui.maxScroll = max(0, contentHeight - content.h)
        g.ui.scroll = min(g.ui.scroll, g.ui.maxScroll)
        c.clip = nil
    }

    func cardGrid(_ content: Rect, count: Int, cardH: Int) -> [Rect] {
        let cols = max(1, (content.w - 4) / 44)
        let gap = 2
        let cw = (content.w - 4 - gap * (cols - 1)) / cols
        return (0..<count).map { k in
            Rect(content.x + 2 + (k % cols) * (cw + gap), content.y + 3 + (k / cols) * (cardH + gap), cw, cardH)
        }
    }

    func clipped(_ r: Rect, _ content: Rect) -> Rect? {
        let y0 = max(r.y, content.y), y1 = min(r.maxY, content.maxY)
        return y1 > y0 ? Rect(r.x, y0, r.w, y1 - y0) : nil
    }

    func drawBallCards(_ g: Game, _ content: Rect) -> Int {
        let c = canvas
        let kinds = BallKind.allCases
        let rects = cardGrid(content, count: kinds.count, cardH: 33).map { Rect($0.x, $0.y - g.ui.scroll, $0.w, $0.h) }
        for (k, r0) in zip(kinds, rects) {
            let unlocked = g.mods.unlocked.contains(k)
            let press = g.isPressed(.buyBall(k)) ? 1 : 0
            let r = Rect(r0.x, r0.y + press, r0.w, r0.h)
            c.fill(r, Palette.panel1)
            if !unlocked {
                bevel(r, light: Palette.panel2, dark: Palette.black)
                c.sprite(Sprites.ballIcon(k), r.x + 4, r.y + 4, tint: Palette.border)
                c.sprite(Sprites.lock, r.maxX - 11, r.y + 4)
                if let hr = clipped(r0, content) { hit(hr, .tab(.skills), [k.type.name.uppercased(), "UNLOCK IN SKILLS"]) }
                continue
            }
            let cost = g.ballCost(k)
            let can = g.progress.money >= cost
            if can { bevel(r, light: k.color.glowing(90), dark: k.shade) } else { bevel(r, light: Palette.border, dark: Palette.black) }
            c.sprite(Sprites.ballIcon(k), r.x + 4, r.y + 4)
            let owned = "\(g.progress.ball(k).owned)"
            c.text(owned, r.maxX - 4 - PixelFont.measure(owned), r.y + 4, Palette.text2)
            c.sprite(Sprites.coin, r.x + 4, r.y + 15)
            c.text(compact(cost), r.x + 13, r.y + 15, can ? Palette.white : Palette.muted)
            // Level pips: how far this type's upgrades have gone.
            let total = g.progress.ball(k).upgradeTotal
            let maxTotal = Stat.allCases.reduce(0) { $0 + $1.max }
            let pips = 8, filled = Int((Double(total) / Double(maxTotal) * Double(pips)).rounded(.up))
            let pw = (r.w - 8 - (pips - 1)) / pips
            for j in 0..<pips {
                c.fill(r.x + 4 + j * (pw + 1), r.y + 27, pw, 2, j < filled ? k.color.glowing(120) : Palette.panel2)
            }
            let t = k.type
            if let hr = clipped(r0, content) {
                hit(hr, .buyBall(k), [t.name.uppercased(), t.blurb.uppercased(), "DMG \(compact(g.damage(k) * 10)) SPD \(Int(g.speed(k)))"])
            }
        }
        return (rects.last.map { $0.maxY + g.ui.scroll } ?? content.y) - content.y + 3
    }

    func drawUpgrades(_ g: Game, _ content: Rect) -> Int {
        let c = canvas
        var y = content.y + 4 - g.ui.scroll
        let x = content.x + 4, w = content.w - 8
        var any = false
        for k in BallKind.allCases where g.mods.unlocked.contains(k) && g.progress.ball(k).owned > 0 {
            any = true
            let p = g.progress.ball(k)
            c.sprite(Sprites.ballIcon(k), x, y)
            if let spec = p.spec, let s = k.type.specs.first(where: { $0.id == spec }) {
                c.text(s.name.uppercased(), x + 10, y, k.color.glowing(120))
            } else {
                c.text(k.type.name.uppercased(), x + 10, y, Palette.text2)
            }
            y += 11
            if Economy.canSpecialize(p) {
                let bw = (w - 2) / 2
                for (j, s) in k.type.specs.enumerated() {
                    let r = Rect(x + j * (bw + 2), y, bw, 13)
                    let press = g.isPressed(.specialize(k, j)) ? 1 : 0
                    let rr = Rect(r.x, r.y + press, r.w, r.h)
                    c.fill(rr, Palette.panel2)
                    bevel(rr, light: k.color.glowing(160), dark: k.shade)
                    c.text(s.name.uppercased(), rr.x + 3, rr.y + 3, Palette.white)
                    if let hr = clipped(r, content) { hit(hr, .specialize(k, j), [s.name.uppercased(), s.text.uppercased()]) }
                }
                y += 15
            }
            let stats: [(Stat, Sprite)] = [(.speed, Sprites.statSpeed), (.damage, Sprites.statDamage), (.special, Sprites.statSpecial)]
            for (s, icon) in stats {
                let r = Rect(x - 2, y - 2, w + 4, 11)
                let press = g.isPressed(.upgrade(k, s)) ? 1 : 0
                let level = p.level(s)
                let cost = Economy.upgradeCost(k, s, level: level)
                let can = cost.map { g.progress.money >= $0 } ?? false
                if press == 1 { c.fill(r, Palette.panel2) }
                c.sprite(icon, x, y + press, tint: can ? k.color : Palette.muted)
                let pips = 8, filled = Int((Double(level) / Double(s.max) * Double(pips)).rounded(.up))
                for j in 0..<pips { c.fill(x + 10 + j * 4, y + 2 + press, 3, 3, j < filled ? k.color.glowing(110) : Palette.panel2) }
                let label = cost.map { compact($0) } ?? "MAX"
                let lw = PixelFont.measure(label)
                c.text(label, x + w - lw, y + press, cost == nil ? Palette.gold : (can ? Palette.white : Palette.muted))
                if cost != nil { c.sprite(Sprites.coin, x + w - lw - 9, y + press) }
                let name = s == .special ? k.type.specialName.uppercased() : (s == .speed ? "SPEED" : "DAMAGE")
                if let hr = clipped(r, content) { hit(hr, .upgrade(k, s), [name, "LEVEL \(level)/\(s.max)"]) }
                y += 11
            }
            y += 5
        }
        if !any { c.text("BUY A BALL", x, y + 2, Palette.muted) }
        return y + g.ui.scroll - content.y
    }

    func drawMore(_ g: Game, _ content: Rect) -> Int {
        let c = canvas
        let x = content.x + 4, w = content.w - 8
        var y = content.y + 4 - g.ui.scroll
        // Prestige: what you'd get, and one button.
        let stars = g.prestigeStars
        c.sprite(Sprites.star, x, y)
        c.text("+\(stars)", x + 10, y, stars > 0 ? Palette.gold : Palette.muted)
        y += 12
        let r = Rect(x, y, w, 17)
        let confirming = g.time < g.ui.confirmPrestigeUntil
        let press = g.isPressed(.prestige) ? 1 : 0
        let br = Rect(r.x, r.y + press, r.w, r.h)
        c.fill(br, stars > 0 ? (confirming ? Palette.gold.glowing(120) : Palette.panel2) : Palette.panel1)
        if stars > 0 { bevel(br, light: Palette.goldLight.glowing(140), dark: Palette.goldDim) } else { bevel(br, light: Palette.border, dark: Palette.black) }
        let label = confirming ? "SURE?" : "PRESTIGE"
        c.text(label, br.x + (br.w - PixelFont.measure(label)) / 2, br.y + 5, confirming ? Palette.black : (stars > 0 ? Palette.white : Palette.muted))
        if let hr = clipped(r, content) {
            hit(hr, .prestige, ["RESET FOR STARS", "+5% DMG +10% $ EACH", g.progress.maxLevel < 3 ? "FROM LEVEL 3" : "TAP TWICE"])
        }
        y += 23
        let settings: [(Sprite, Bool)] = [(Sprites.sound, g.progress.settings.sound), (Sprites.haptic, g.progress.settings.haptics), (Sprites.glowIcon, g.progress.settings.glow)]
        let names = ["SOUND", "HAPTICS", "GLOW"]
        for (j, (icon, on)) in settings.enumerated() {
            let row = Rect(x - 2, y - 3, w + 4, 13)
            c.sprite(icon, x, y, tint: on ? Palette.white : Palette.muted)
            // A tiny pixel switch, lit from the top-left like everything else.
            let sx = x + w - 15
            c.fill(sx, y, 15, 7, on ? Palette.blue.glowing(120) : Palette.panel2)
            let knob = Rect(on ? sx + 8 : sx, y, 7, 7)
            c.fill(knob, on ? Palette.text : Palette.muted)
            bevel(knob, light: Palette.white, dark: on ? Palette.text2 : Palette.border)
            if let hr = clipped(row, content) { hit(hr, .setting(j), [names[j]]) }
            y += 13
        }
        return y + g.ui.scroll - content.y
    }

    // MARK: - Skills overlay

    func drawSkills(_ g: Game) {
        let c = canvas
        c.fill(0, 0, c.width, c.height, Palette.black)
        hit(Rect(0, 0, c.width, c.height), .none)
        let area = Rect(24 + g.ui.skillPan.x, 26 + g.ui.skillPan.y, c.width - 48, c.height - 50)
        func pos(_ s: SkillNode) -> Point { Point(area.x + Int(s.x * Double(area.w)), area.y + Int(s.y * Double(area.h))) }
        let ranks = g.progress.skillRanks
        for s in SkillNode.all {
            for rq in s.requires {
                guard let q = SkillNode.byID[rq] else { continue }
                let a = pos(s), e = pos(q)
                if (ranks[s.id] ?? 0) > 0 { c.line(a.x, a.y, e.x, e.y, Palette.cyan.glowing(150)) }
                else if (ranks[rq] ?? 0) > 0 { c.line(a.x, a.y, e.x, e.y, Palette.border) }
                else { c.dottedLine(a.x, a.y, e.x, e.y, Palette.panel2) }
            }
        }
        for s in SkillNode.all {
            let p = pos(s)
            let r = Rect(p.x - 8, p.y - 8, 17, 17)
            let rank = ranks[s.id] ?? 0
            let state = Skills.check(s.id, ranks: ranks, points: g.progress.skillPoints)
            let press = g.isPressed(.skill(s.id)) ? 1 : 0
            let rr = Rect(r.x, r.y + press, r.w, r.h)
            c.fill(rr, rank > 0 ? Palette.panel2 : Palette.panel0)
            let border: Pixel
            switch state {
            case .maxed: border = Palette.cyan.glowing(200)
            case .ok: border = (Int(g.time * 3) & 1 == 0 ? Palette.white : Palette.cyan).glowing(220)
            case .poor: border = rank > 0 ? Palette.cyan.glowing(120) : Palette.text2
            case .locked: border = Palette.border
            }
            bevel(rr, light: border, dark: state == .locked ? Palette.panel2 : dimmer(border))
            let icon = Sprites.skillIcon(s.effect)
            if case .unlock = s.effect { c.sprite(icon, rr.x + 5, rr.y + 5, tint: state == .locked && rank == 0 ? Palette.border : nil) }
            else { c.sprite(icon, rr.x + 5, rr.y + 5, tint: rank > 0 ? Palette.white : (state == .locked ? Palette.border : Palette.text2)) }
            if s.ranks > 1 {
                let x0 = rr.x + (17 - (s.ranks * 3 - 1)) / 2
                for j in 0..<s.ranks { c.fill(x0 + j * 3, rr.maxY + 2, 2, 2, j < rank ? Palette.cyan.glowing(160) : Palette.border) }
            }
            hit(r, .skill(s.id), [s.name.uppercased(), s.text.uppercased(), s.ranks > 1 ? "\(rank)/\(s.ranks)  COST \(s.cost)" : "COST \(s.cost)"])
        }
        // Points, and a way out.
        c.fill(2, 2, 40, 13, Palette.black)
        c.sprite(Sprites.skillPoint, 5, 5)
        c.text("\(g.progress.skillPoints)", 15, 5, Palette.cyan)
        let close = Rect(c.width - 19, 1, 18, 17)
        c.sprite(Sprites.close, close.x + 6, close.y + 5, tint: Palette.text)
        hit(close, .closeSkills)
    }

    // MARK: - Title, banners, tooltip

    func drawTitle(_ g: Game, _ L: Layout) {
        let c = canvas
        hits = [Hit(rect: Rect(0, 0, c.width, c.height), action: .start, info: [])]
        let cx = c.width / 2
        let a = "GOLDEN", b = "PIXEL"
        let s = 3
        let y = c.height / 2 - 34
        c.fill(0, y - 10, c.width, 86, Palette.black)
        c.text(a, cx - PixelFont.measure(a, scale: s) / 2, y, Palette.text.glowing(40), scale: s)
        c.text(b, cx - PixelFont.measure(b, scale: s) / 2, y + 27, Palette.gold.glowing(200), scale: s)
        if Int(g.time * 2) % 2 == 0 {
            let t = "TAP"
            c.text(t, cx - PixelFont.measure(t) / 2, y + 60, Palette.text2)
        }
    }

    func drawBanners(_ g: Game, _ L: Layout) {
        let c = canvas
        var y = L.board.y + L.board.h / 2 - 20
        for b in g.banners.prefix(3) {
            let scale = b.big ? 2 : 1
            let h = PixelFont.capHeight * scale
            // Banners blink in and out rather than fading.
            if b.life < 0.3 && Int(b.life * 20) % 2 == 0 { y += h + 8; continue }
            let w = PixelFont.measure(b.text, scale: scale)
            let x = L.board.x + (L.board.w - w) / 2
            c.fill(x - 3, y - 3, w + 6, h + 6 + scale, Palette.black)
            c.text(b.text, x, y, b.color.glowing(b.big ? 255 : 120), scale: scale)
            y += h + 8
        }
    }

    func drawTooltip(_ t: Tooltip) {
        let c = canvas
        let w = (t.lines.map { PixelFont.measure($0) }.max() ?? 0) + 8
        let h = t.lines.count * PixelFont.lineHeight + 5
        var x = t.at.x - w / 2, y = t.at.y - h - 8
        if y < 1 { y = t.at.y + 10 }
        x = max(1, min(c.width - w - 1, x))
        y = max(1, min(c.height - h - 1, y))
        let r = Rect(x, y, w, h)
        c.fill(r, Palette.panel2)
        bevel(r, light: Palette.muted, dark: Palette.black)
        for (j, line) in t.lines.enumerated() { c.text(line, x + 4, y + 4 + j * PixelFont.lineHeight, j == 0 ? Palette.white : Palette.text2) }
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
