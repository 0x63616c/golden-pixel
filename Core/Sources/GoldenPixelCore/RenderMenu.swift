/// The main menu, how to play, and settings. Behind them, a slow animated field of pixels:
/// blue blocks drifting in and out of the dark, a few balls bouncing through, and a gold pixel.
extension Renderer {
    /// The animated pixel field behind the menu screens. Pure function of time.
    /// Cells under and near `calm` (canvas pixels) are held to the deepest blues, a step paler
    /// per cell further out, so the logo, buttons and cards sit on a quiet patch of the same
    /// field rather than in a hole.
    func drawMenuBackground(_ g: Game, calm: Rect? = nil) {
        let c = canvas, t = g.time, cp = Tuning.cellPixels
        let cols = c.width / cp + 1, rows = c.height / cp + 1
        let ox = (c.width - cols * cp) / 2, oy = (c.height - rows * cp) / 2
        /// Whole cells between a cell and the calm rectangle (0 = touching or inside).
        func distance(_ cx: Int, _ cy: Int) -> Int {
            guard let k = calm else { return 99 }
            let x0 = ox + cx * cp, y0 = oy + cy * cp
            let dx = max(0, k.x - (x0 + cp), x0 - k.maxX), dy = max(0, k.y - (y0 + cp), y0 - k.maxY)
            return (max(dx, dy) + cp - 1) / cp
        }
        for cy in 0..<rows {
            for cx in 0..<cols {
                let x = Double(cx), y = Double(cy)
                let v = sin(x * 0.35 + t * 0.7) + sin(y * 0.45 - t * 0.5) + sin((x + y) * 0.21 + t * 0.9) + sin((x - y) * 0.17 - t * 0.4)
                guard v > 0.9 else { continue }
                let step = min(3, Int((v - 0.9) * 2.2), distance(cx, cy))
                c.fill(ox + cx * cp, oy + cy * cp, cp, cp, Palette.ladder[Palette.ladder.count - 1 - step])
            }
        }
        // A golden pixel that wanders slowly (hidden while it passes behind the content), and
        // a few balls bouncing across.
        let gx = Int((Double(cols - 6) * (0.5 + 0.42 * sin(t * 0.13)))) + 3
        let gy = Int((Double(rows - 6) * (0.5 + 0.42 * sin(t * 0.17 + 1)))) + 3
        if distance(gx, gy) > 1 { c.fill(ox + gx * cp, oy + gy * cp, cp, cp, Palette.gold.glowing(255)) }
        for (j, k) in [BallKind.basic, .fast, .heavy, .lightning, .bomb].enumerated() {
            let sp = 23.0 + Double(j) * 7
            func bounce(_ p: Double, _ span: Double) -> Int {
                let m = p.truncatingRemainder(dividingBy: 2 * span)
                return Int(m < span ? m : 2 * span - m)
            }
            let bx = bounce(t * sp + Double(j) * 97, Double(c.width - 6)) + 1
            let by = bounce(t * sp * 0.73 + Double(j) * 53, Double(c.height - 6)) + 1
            c.sprite(Sprites.ball(k), bx, by)
        }
    }

    // MARK: - Logo

    /// The two lines of the wordmark: GOLDEN in gold over a heavier PiXEL in white whose i is
    /// dotted with the golden pixel. Both lines come out the same width (45 units of 5 px,
    /// 32 units of 7 px), so the lockup is one block.
    static let logoLines: [(text: String, unit: Int, colour: Pixel)] = [
        ("GOLDEN", 5, Palette.gold.glowing(50)),
        ("PiXEL", 7, Palette.white),
    ]
    static let logoLineGap = 12
    static let logoOutline = 2

    func logoWidth(_ line: (text: String, unit: Int, colour: Pixel)) -> Int {
        let ws = line.text.compactMap { Sprites.logoGlyph($0)?.width }
        return (ws.reduce(0, +) + max(0, ws.count - 1)) * line.unit
    }

    var logoSize: (w: Int, h: Int) {
        let lines = Renderer.logoLines
        let w = lines.map { logoWidth($0) }.max() ?? 0
        let h = lines.map { 8 * $0.unit }.reduce(0, +) + (lines.count - 1) * Renderer.logoLineGap
        return (w, h)
    }

    /// Draws the wordmark with its top edge at y, centred on cx. A 2-px black keyline hugs the
    /// letters (not a box), so the moving field never touches them, and the golden pixel
    /// breathes a dithered halo.
    func drawLogo(_ g: Game, cx: Int, y: Int) {
        let c = canvas, o = Renderer.logoOutline
        var placed: [(Sprite, Int, Int, Int, Pixel)] = []
        var ly = y
        for line in Renderer.logoLines {
            var x = cx - logoWidth(line) / 2
            for ch in line.text {
                guard let s = Sprites.logoGlyph(ch) else { continue }
                placed.append((s, x, ly, line.unit, line.colour))
                x += (s.width + 1) * line.unit
            }
            ly += 8 * line.unit + Renderer.logoLineGap
        }
        // The golden pixel twinkles: four short diagonal rays from its corners, growing and
        // shrinking in whole pixels.
        let gold = Palette.gold.rgbOnly
        var sparkles: [Rect] = []
        for (s, x, y, u, _) in placed {
            for sy in 0..<s.height {
                for sx in 0..<s.width where s.pixels[sy * s.width + sx]?.rgbOnly == gold {
                    // The dot is 2 x 2 units; seed from its top-left unit only.
                    guard sx == 0 || s.pixels[sy * s.width + sx - 1]?.rgbOnly != gold,
                          sy == 0 || s.pixels[(sy - 1) * s.width + sx]?.rgbOnly != gold else { continue }
                    sparkles.append(Rect(x + sx * u, y + sy * u, 2 * u, 2 * u))
                }
            }
        }
        // Keyline, then the letters (the rays run over the keyline, not the letters).
        for (s, x, y, u, _) in placed {
            for sy in 0..<s.height {
                for sx in 0..<s.width where s.pixels[sy * s.width + sx] != nil {
                    c.fill(x + sx * u - o, y + sy * u - o, u + 2 * o, u + 2 * o, Palette.black)
                }
            }
        }
        let phase = (sin(g.time * 1.7) + 1) / 2
        let rayLen = 1 + Int(phase * 3.99)
        for dot in sparkles {
            for (cx0, cy0, dx, dy) in [(dot.x - 1, dot.y - 1, -1, -1), (dot.maxX, dot.y - 1, 1, -1),
                                       (dot.x - 1, dot.maxY, -1, 1), (dot.maxX, dot.maxY, 1, 1)] {
                for k in 0..<(o + rayLen) {
                    c.set(cx0 + dx * k, cy0 + dy * k, (k < o + rayLen - 1 ? Palette.goldLight : Palette.goldDim).glowing(160))
                }
            }
        }
        for (s, x, y, u, colour) in placed {
            for sy in 0..<s.height {
                for sx in 0..<s.width {
                    guard let p = s.pixels[sy * s.width + sx] else { continue }
                    c.fill(x + sx * u, y + sy * u, u, u, p.rgbOnly == gold ? p : colour)
                }
            }
        }
    }

    // MARK: - Main menu

    func drawMenu(_ g: Game) {
        let c = canvas
        let p = g.progress
        let fresh = p.level == 1 && p.levelTime < 1 && p.totalEarnings == 0
        // The logo, then one hero button and a pair below it, all one width: the logo's.
        let logo = logoSize
        let bw = logo.w, heroH = 35, rowH = 27, gap = 7, logoGap = 26
        let stackH = logo.h + logoGap + heroH + gap + rowH
        let x0 = (c.width - bw) / 2
        var y = (c.height - stackH) / 2
        drawMenuBackground(g, calm: Rect(x0 - 6, y - 6, bw + 12, stackH + 12))
        hit(Rect(0, 0, c.width, c.height), .none)

        drawLogo(g, cx: c.width / 2, y: y)
        y += logo.h + logoGap

        let hero = fresh ? "PLAY" : "CONTINUE LV \(p.level)"
        // Big type when it fits, with room for the icon and a margin.
        let big = PixelFont.measure(hero, scale: 2) + 24 + 24 <= bw
        button(g, Rect(x0, y, bw, heroH), hero, .play, style: .gold, icon: Sprites.play, tintIcon: true, scale: big ? 2 : 1)
        y += heroH + gap
        let half = (bw - gap) / 2
        button(g, Rect(x0, y, half, rowH), "HOW TO PLAY", .howTo, icon: Sprites.info, tintIcon: true)
        button(g, Rect(x0 + bw - half, y, half, rowH), "SETTINGS", .settings, icon: Sprites.gear, tintIcon: true)
    }

    // MARK: - Cards

    /// A centred card on the menu background: a header with a back button and the title, a
    /// keyline under it, then `contentH` pixels of content. Returns the content rectangle.
    func menuCard(_ g: Game, title: String, width w: Int, contentH: Int) -> Rect {
        let c = canvas
        let pad = 16, header = 8 + 27 + 9
        let h = min(c.height - 16, header + 1 + pad + contentH + pad)
        let card = Rect((c.width - w) / 2, (c.height - h) / 2, w, h)
        drawMenuBackground(g, calm: card)
        hit(Rect(0, 0, c.width, c.height), .none)
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)
        button(g, Rect(card.x + 8, card.y + 8, 27, 27), "", .backToMenu, icon: Sprites.back, tintIcon: true)
        centred(title, c.width / 2, card.y + 8 + (27 - 14) / 2, Palette.white, scale: 2)
        c.hline(card.x + 8, card.maxX - 9, card.y + header, Palette.panel3)
        return Rect(card.x + pad + 4, card.y + header + 1 + pad, w - 2 * (pad + 4), contentH)
    }

    /// A small square chip holding a 7x7 icon, so a column of icons lines up as one rhythm.
    func iconChip(_ icon: Sprite, _ x: Int, _ y: Int, size: Int = 17, tint: Pixel? = nil) {
        box(Rect(x, y, size, size), Palette.panel2)
        canvas.sprite(icon, x + (size - icon.width) / 2, y + (size - icon.height) / 2, tint: tint)
    }

    static let howToRows: [(Sprite, String)] = [
        (Sprites.ballIcon(.basic), "Balls break pixels; you never do.\nEach level starts with coins for one ball."),
        (Sprites.coin, "Broken pixels pay coins. Coins buy more balls."),
        (Sprites.aim, "Pick a ball. Hold an open spot, drag to aim, let go.\nA tap on an open spot repeats the last shot."),
        (Sprites.shard, "Mint pixels hold shards.\nYou sense them through the dark when you dig close."),
        (Sprites.tree, "Shards buy the skill tree: upgrades, and new kinds of ball."),
        (Sprites.goldPixel, "The golden pixel hides in the dark. Break it to clear the level."),
        (Sprites.star, "Each gold is a star for good: more damage and coins.\nEvery level starts fresh."),
        (Sprites.pan, "Drag to look around, pinch to zoom.\nHold a pixel or a ball row to read it."),
    ]

    func drawHowTo(_ g: Game) {
        let c = canvas
        let w = 391, chip = 17, textX = chip + 10, rowGap = 7
        let textW = w - 40 - textX
        // "\n" marks a chosen break, so lines come out balanced rather than with an orphan.
        let wrapped = Renderer.howToRows.map { $0.1.split(separator: "\n").flatMap { wrap(String($0), width: textW) } }
        func rowH(_ lines: Int) -> Int { max(chip, (lines - 1) * PixelFont.lineHeight + PixelFont.capHeight + 10) }
        let contentH = wrapped.map { rowH($0.count) }.reduce(0, +) + (wrapped.count - 1) * rowGap
        let r = menuCard(g, title: "HOW TO PLAY", width: w, contentH: contentH)
        var y = r.y
        for ((icon, _), lines) in zip(Renderer.howToRows, wrapped) {
            let h = rowH(lines.count)
            let tinted = icon.pixels.contains { $0 == Palette.text }
            iconChip(icon, r.x, y + (h - chip) / 2, tint: tinted ? Palette.text2 : nil)
            // The text block is centred on the chip's row.
            var ty = y + (h - ((lines.count - 1) * PixelFont.lineHeight + PixelFont.capHeight)) / 2
            for line in lines {
                c.text(line, r.x + textX, ty, Palette.text)
                ty += PixelFont.lineHeight
            }
            y += h + rowGap
        }
    }

    func drawSettings(_ g: Game) {
        let c = canvas
        let s = g.progress.settings
        let rows: [(Sprite, String, Bool)] = [(Sprites.sound, "SOUND", s.sound), (Sprites.haptic, "HAPTICS", s.haptics), (Sprites.glowIcon, "GLOW", s.glow)]
        let rowH = 31, rowGap = 5, section = 18, bh = 27
        let contentH = rows.count * rowH + (rows.count - 1) * rowGap + section + bh + 9 + PixelFont.capHeight
        let r = menuCard(g, title: "SETTINGS", width: 300, contentH: contentH)
        var y = r.y
        for (j, (icon, name, on)) in rows.enumerated() {
            let row = Rect(r.x, y, r.w, rowH)
            let pressed = g.isPressed(.setting(j))
            box(row, pressed ? Palette.panel3 : Palette.panel2)
            let ink = on ? Palette.white : Palette.text2
            c.sprite(icon, row.x + 12, row.y + 12, tint: ink)
            c.text(name, row.x + 12 + 7 + 9, row.y + 12, ink)
            // A flat switch: a notched track and a square knob, lit when on.
            let track = Rect(row.maxX - 12 - 29, row.y + 8, 29, 15)
            if on {
                box(track, Palette.accent)
                box(Rect(track.maxX - 13, track.y + 2, 11, 11), Palette.white)
            } else {
                box(track, Palette.panel0, edge: Palette.border)
                box(Rect(track.x + 2, track.y + 2, 11, 11), Palette.muted)
            }
            hit(row, .setting(j))
            y += rowH + rowGap
        }
        y += section - rowGap
        let confirming = g.time < g.ui.confirmResetUntil
        button(g, Rect(r.x, y, r.w, bh), confirming ? "TAP AGAIN TO WIPE EVERYTHING" : "RESET PROGRESS", .resetProgress,
               style: confirming ? .danger : .secondary, icon: Sprites.restart, tintIcon: true)
        centred("Wipes levels, stars and coins.", c.width / 2, y + bh + 9, Palette.muted)
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
