/// The main menu, how to play, settings, and level select. Behind them, a slow animated field of pixels:
/// blue blocks drifting in and out of the dark, a few balls bouncing through, and a gold pixel.
extension Renderer {
    /// The animated pixel field behind the menu screens. Pure function of time.
    /// Cells under and near the `calm` rectangles (canvas pixels) are held to the deepest blues,
    /// a step paler per cell further out, so the logo, buttons and cards sit on a quiet patch of
    /// the same field rather than in a hole.
    func drawMenuBackground(_ g: Game, calm: [Rect] = []) {
        let c = canvas, t = g.time, cp = Tuning.cellPixels
        let cols = c.width / cp + 1, rows = c.height / cp + 1
        let ox = (c.width - cols * cp) / 2, oy = (c.height - rows * cp) / 2
        /// Whole cells between a cell and the nearest calm rectangle (0 = touching or inside).
        func distance(_ cx: Int, _ cy: Int) -> Int {
            let x0 = ox + cx * cp, y0 = oy + cy * cp
            return calm.map { k in
                let dx = max(0, k.x - (x0 + cp), x0 - k.maxX), dy = max(0, k.y - (y0 + cp), y0 - k.maxY)
                return (max(dx, dy) + cp - 1) / cp
            }.min() ?? 99
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

    var logoSize: (w: Int, h: Int) { logoSize(lineGap: Renderer.logoLineGap) }

    /// The wordmark's size with `lineGap` art pixels between its two lines.
    func logoSize(lineGap: Int) -> (w: Int, h: Int) {
        let lines = Renderer.logoLines
        let w = lines.map { logoWidth($0) }.max() ?? 0
        let h = lines.map { 8 * $0.unit }.reduce(0, +) + (lines.count - 1) * lineGap
        return (w, h)
    }

    /// Draws the wordmark with its top edge at y, centred on cx. A 2-px black keyline hugs the
    /// letters (not a box), so the moving field never touches them, and the golden pixel
    /// breathes a dithered halo.
    func drawLogo(_ g: Game, cx: Int, y: Int, lineGap: Int = Renderer.logoLineGap) {
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
            ly += 8 * line.unit + lineGap
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
        // Gaps and button heights, roomiest first: a short screen gets the first set that fits
        // between the top of the safe area and the build tag (or the bottom, with no tag).
        let lineGaps = [Renderer.logoLineGap, 12, 12, 6, 4], logoGaps = [26, 14, 10, 6, 6]
        let heroes = [35, 31, 29, 27, 26], rows = [27, 25, 23, 22, 22], gaps = [7, 6, 5, 4, 4]
        func height(_ s: Int) -> Int { logoSize(lineGap: lineGaps[s]).h + logoGaps[s] + heroes[s] + gaps[s] + rows[s] }
        let S = layout.safeArea, top = S.y + 8
        var tag = buildTagRect(g.buildLabel, cx: c.width / 2, y: S.maxY - Renderer.buildTagBottom - PixelFont.capHeight)
        var bottom = tag.map { $0.y - 6 } ?? S.maxY - 8
        var s = fitStep(heroes.count - 1, into: bottom - top, height)
        if tag != nil, height(s) > bottom - top {
            // No room for both even at the tightest: the tag is on the settings card too.
            tag = nil
            bottom = S.maxY - 8
            s = fitStep(heroes.count - 1, into: bottom - top, height)
        }
        let logo = logoSize(lineGap: lineGaps[s])
        let heroH = heroes[s], rowH = rows[s], gap = gaps[s], logoGap = logoGaps[s]
        // Once a level is cleared, LEVELS joins the row under the hero; the stack widens past
        // the logo when three labels need it.
        var row: [(String, Action, Sprite)] = [("HOW TO PLAY", .howTo, Sprites.info), ("SETTINGS", .settings, Sprites.gear)]
        if p.maxLevel > 1 { row.insert(("LEVELS", .levels, Sprites.levels), at: 0) }
        let cell = row.map { PixelFont.measure($0.0) + 7 + 5 + 12 }.max() ?? 0
        let bw = max(logo.w, row.count * cell + (row.count - 1) * gap)
        let stackH = height(s)
        let x0 = layout.centred(bw, stackH).x
        var y = max(top, min(bottom - stackH, (c.height - stackH) / 2))
        drawMenuBackground(g, calm: [Rect(x0 - 6, y - 6, bw + 12, stackH + 12)] + (tag.map { [$0] } ?? []))
        hit(Rect(0, 0, c.width, c.height), .none)
        if let tag { drawBuildTag(g.buildLabel, tag, keyline: true) }

        drawLogo(g, cx: x0 + bw / 2, y: y, lineGap: lineGaps[s])
        y += logo.h + logoGap

        let hero = fresh ? "PLAY" : "CONTINUE LV \(p.level)"
        // Big type when it fits, with room for the icon and a margin.
        let big = PixelFont.measure(hero, scale: 2) + 24 + 24 <= bw
        button(g, Rect(x0, y, bw, heroH), hero, .play, style: .gold, icon: Sprites.play, tintIcon: true, scale: big ? 2 : 1)
        y += heroH + gap
        let n = row.count, each = (bw - (n - 1) * gap) / n
        for (j, (label, action, icon)) in row.enumerated() {
            // The last one ends flush with the hero, whatever the rounding.
            let x = j == n - 1 ? x0 + bw - each : x0 + j * (each + gap)
            button(g, Rect(x, y, each, rowH), label, action, icon: icon, tintIcon: true)
        }
    }

    // MARK: - Level select

    /// One tile per level up to the furthest reached, in rows. The current level is the gold
    /// tile (it carries on where it was); cleared levels wear a star; any other tile starts that
    /// level fresh. Leaving a level in progress asks for a second tap: the tile turns red.
    func drawLevels(_ g: Game) {
        let c = canvas, p = g.progress
        let n = max(1, p.maxLevel)
        let w = cardWidth(391), inner = w - 2 * (cardPad + 4)
        let gap = 6, minTile = 66, tileH = layout.short ? 34 : 40
        let cols = max(2, (inner + gap) / (minTile + gap))
        let tileW = (inner - (cols - 1) * gap) / cols
        let rows = (n + cols - 1) / cols
        let confirming = g.ui.confirmLevel.flatMap { g.time < g.ui.confirmLevelUntil ? $0 : nil }
        let note = confirming != nil
            ? "Tap again to leave level \(p.level). Its run is lost."
            : "Cleared levels start fresh and give no new star."
        let lines = wrap(note, width: inner)
        let noteGap = layout.short ? 8 : 12
        let gridH = rows * tileH + (rows - 1) * gap
        let contentH = gridH + noteGap + (lines.count - 1) * PixelFont.lineHeight + PixelFont.capHeight
        if g.ui.focusLevels {
            // Open with the current level in the middle of the body (menuCard clamps it).
            g.ui.focusLevels = false
            let body = layout.safeArea.h - 2 * Renderer.cardMargin - cardChrome
            let rowY = (p.level - 1) / cols * (tileH + gap)
            g.ui.scroll = max(0, rowY - (body - tileH) / 2)
        }
        let r = menuCard(g, title: "LEVELS", width: w, contentH: contentH)
        let x0 = r.x + (r.w - (cols * tileW + (cols - 1) * gap)) / 2
        for k in 1...n {
            let j = k - 1
            let tile = Rect(x0 + j % cols * (tileW + gap), r.y + j / cols * (tileH + gap), tileW, tileH)
            let style: ButtonStyle = confirming == k ? .danger : (k == p.level ? .gold : .secondary)
            let pressed = g.isPressed(.pickLevel(k))
            let (fill, edge, ink) = buttonColours(style, pressed: pressed)
            if let f = fill { box(tile, f, edge: edge) }
            let dy = pressed ? 1 : 0
            let sub = confirming == k ? "TAP AGAIN" : LevelSpec.forLevel(k).name
            let top = tile.y + (tileH - (2 * PixelFont.capHeight + 5 + PixelFont.capHeight) + 1) / 2 + dy
            centred("\(k)", tile.x + tileW / 2, top, ink, scale: 2)
            centred(sub, tile.x + tileW / 2, top + 2 * PixelFont.capHeight + 5, style == .secondary ? Palette.text2 : ink)
            if g.cleared(k) {
                c.sprite(Sprites.star, tile.maxX - 4 - Sprites.star.width, tile.y + 4 + dy, tint: style == .secondary ? nil : ink)
            }
            hit(tile, .pickLevel(k))
        }
        var y = r.y + gridH + noteGap
        for line in lines {
            centred(line, r.x + r.w / 2, y, confirming != nil ? Palette.text : Palette.muted)
            y += PixelFont.lineHeight
        }
        endMenuCard(g)
    }

    // MARK: - Build tag

    /// Gap between the menu's build tag and the bottom of the screen (bottom centre is clear of
    /// the rounded corners).
    static let buildTagBottom = 9

    /// Where a build label centred on cx with its cap top at y would sit, or nil when empty.
    func buildTagRect(_ label: String, cx: Int, y: Int) -> Rect? {
        guard !label.isEmpty else { return nil }
        let w = PixelFont.measure(label) - 1   // the last glyph's 1-px gap isn't ink
        return Rect(cx - w / 2, y, w, PixelFont.capHeight)
    }

    /// The build label in small muted type. Over the moving menu field it gets a 1-px black
    /// keyline, like the logo's, so drifting blocks never touch the letters.
    func drawBuildTag(_ label: String, _ r: Rect, keyline: Bool = false) {
        let c = canvas
        if keyline {
            for (dx, dy) in [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)] {
                c.text(label, r.x + dx, r.y + dy, Palette.black)
            }
        }
        c.text(label, r.x, r.y, Palette.muted)
    }

    // MARK: - Cards

    /// The least room between a menu card and the edge of the safe area.
    static let cardMargin = 2

    /// The widest a menu card may be: `width`, or what the safe area has room for.
    func cardWidth(_ width: Int) -> Int { min(width, layout.safeArea.w - 16) }

    /// Padding around a menu card's content, and the height of everything but the content
    /// (header, keyline, padding). Both tighten on a short screen.
    var cardPad: Int { layout.short ? 10 : 16 }
    var cardHeader: Int { layout.short ? 6 + 23 + 6 : 8 + 27 + 9 }
    var cardChrome: Int { cardHeader + 1 + 2 * cardPad }

    /// A centred card on the menu background: a header with a back button and the title, a
    /// keyline under it, then `contentH` pixels of content. Returns the content rectangle.
    ///
    /// Content taller than the screen scrolls under the header: the returned rectangle is
    /// shifted up by `ui.scroll`, drawing and hit regions are cut to the body until
    /// `endMenuCard`, and a drag anywhere on the body scrolls (`ui.scrollArea`).
    func menuCard(_ g: Game, title: String, width: Int, contentH: Int) -> Rect {
        let c = canvas, L = layout
        let pad = cardPad, header = cardHeader, back = L.short ? 23 : 27, top = L.short ? 6 : 8
        let w = cardWidth(width)
        let full = header + 1 + pad + contentH + pad
        let h = min(L.safeArea.h - 2 * Renderer.cardMargin, full)
        let card = L.centred(w, h, margin: Renderer.cardMargin)
        drawMenuBackground(g, calm: [card])
        hit(Rect(0, 0, c.width, c.height), .none)
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)
        button(g, Rect(card.x + top, card.y + top, back, back), "", .backToMenu, icon: Sprites.back, tintIcon: true)
        centred(title, card.x + w / 2, card.y + top + (back - 14) / 2, Palette.white, scale: 2)
        c.hline(card.x + 8, card.maxX - 9, card.y + header, Palette.panel3)
        let over = full - h
        g.ui.scrollMax = max(0, over)
        g.ui.scroll = max(0, min(g.ui.scrollMax, g.ui.scroll))
        if over > 0 {
            // The body: under the header's keyline, inside the card's own keyline.
            let view = Rect(card.x + 2, card.y + header + 1, w - 4, h - header - 1 - 2)
            g.ui.scrollArea = view
            scrolling = (view, pad + contentH + pad)
            c.clip = view
            hitClip = view
        }
        return Rect(card.x + pad + 4, card.y + header + 1 + pad - g.ui.scroll, w - 2 * (pad + 4), contentH)
    }

    /// Ends a menu card's content. A scrolling card gets a flat thumb on its right edge: as
    /// tall as the share of the content that shows, as far down as the scroll.
    func endMenuCard(_ g: Game) {
        let c = canvas
        c.clip = nil
        hitClip = nil
        guard let (view, total) = scrolling, g.ui.scrollMax > 0 else { return }
        scrolling = nil
        let th = max(8, view.h * view.h / max(1, total))
        let ty = view.y + (view.h - th) * g.ui.scroll / g.ui.scrollMax
        c.fill(view.maxX - 4, ty, 2, th, Palette.border)
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
        let w = cardWidth(391), chip = 17, textX = chip + 10, rowGap = 7
        let textW = w - 2 * (cardPad + 4) - textX
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
        endMenuCard(g)
    }

    func drawSettings(_ g: Game) {
        let c = canvas
        let s = g.progress.settings
        let rows: [(Sprite, String, Bool)] = [(Sprites.sound, "SOUND", s.sound), (Sprites.music, "MUSIC", s.music), (Sprites.haptic, "HAPTICS", s.haptics),
                                                (Sprites.glowIcon, "GLOW", s.glow)]
        // Row and button heights and the gaps, as designed and tight: tight when the card
        // would not fit the screen otherwise.
        let rowHs = [27, 22], rowGaps = [4, 2], sections = [12, 6], bhs = [27, 23], buttonGaps = [4, 2], noteGaps = [7, 4], tagGaps = [10, 6]
        let tagged = !g.buildLabel.isEmpty
        func content(_ t: Int) -> Int {
            rows.count * rowHs[t] + (rows.count - 1) * rowGaps[t] + sections[t] + 2 * bhs[t] + buttonGaps[t] + noteGaps[t] + PixelFont.capHeight
                + (tagged ? tagGaps[t] + PixelFont.capHeight : 0)
        }
        let t = fitStep(1, into: layout.safeArea.h - 2 * Renderer.cardMargin) { cardChrome + content($0) }
        let rowH = rowHs[t], rowGap = rowGaps[t], section = sections[t], bh = bhs[t], noteGap = noteGaps[t], tagGap = tagGaps[t]
        let contentH = content(t)
        let r = menuCard(g, title: "SETTINGS", width: 300, contentH: contentH)
        var y = r.y
        for (j, (icon, name, on)) in rows.enumerated() {
            let row = Rect(r.x, y, r.w, rowH)
            let pressed = g.isPressed(.setting(j))
            box(row, pressed ? Palette.panel3 : Palette.panel2)
            let ink = on ? Palette.white : Palette.text2
            c.sprite(icon, row.x + 12, row.y + (rowH - 7) / 2, tint: ink)
            c.text(name, row.x + 12 + 7 + 9, row.y + (rowH - 7) / 2, ink)
            // A flat switch: a notched track and a square knob, lit when on.
            let track = Rect(row.maxX - 12 - 29, row.y + (rowH - 15) / 2, 29, 15)
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
        // The App Store's review page, for anyone who wants to rate without being asked.
        button(g, Rect(r.x, y, r.w, bh), "RATE GOLDEN PIXEL", .rate, icon: Sprites.star)
        y += bh + buttonGaps[t]
        let confirming = g.time < g.ui.confirmResetUntil
        button(g, Rect(r.x, y, r.w, bh), confirming ? "TAP AGAIN TO WIPE EVERYTHING" : "RESET PROGRESS", .resetProgress,
               style: confirming ? .danger : .secondary, icon: Sprites.restart, tintIcon: true)
        centred("Wipes levels, stars and coins.", r.x + r.w / 2, y + bh + noteGap, Palette.muted)
        // Which build this is, last and quietest, so a tester can match it to TestFlight.
        if let tag = buildTagRect(g.buildLabel, cx: r.x + r.w / 2, y: y + bh + noteGap + PixelFont.capHeight + tagGap) {
            drawBuildTag(g.buildLabel, tag)
        }
        endMenuCard(g)
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
