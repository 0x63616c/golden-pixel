/// The side panel (coins, shards, level, the TREE and pause buttons, one row per unlocked ball
/// type, the selected one highlighted) and the ball info sheet. Everything here stays inside
/// the safe area and clear of the screen's rounded corners, and every button is at least
/// `Tuning.minTouch` art pixels square (UISafetyTests checks all three on every device).
///
/// The panel's background runs to the screen edge; its content sits in `Layout.panelContent`.
/// On a short screen the header tightens up and the ball rows share the height that is left:
/// one column while every row stays touch-sized, then two columns of tiles.
extension Renderer {
    /// A ball row at least this wide has room for the name and the coin; a narrower one is a
    /// tile (icon, price over count).
    static let fullRowWidth = 110

    /// Everything the panel shows. While it is the same as when the panel was last painted,
    /// the panel is the same pixels and the same hit regions.
    struct PanelKey: Equatable {
        var layout: Layout
        var money: Double
        var shards: Int
        var stars: Int
        var level: Int
        var name: String
        /// The tree: what is affordable, which balls are unlocked, what a ball costs.
        var ranks: [String: Int]
        var unlocked: Set<BallKind>
        var balls: [String: BallProgress]
        var selected: BallKind
        /// The control being pressed right now, if any (`Game.isPressed`).
        var pressed: Action
    }

    /// The panel: its pixels (unless the tree is `covered` over it) and its hit regions.
    /// It is painted only when something it shows has changed; otherwise the pixels it was
    /// last painted with are copied back and its hit regions recorded again.
    func drawPanel(_ g: Game, _ L: Layout, covered: Bool = false) {
        let p = g.progress
        let key = PanelKey(layout: L, money: p.money, shards: p.shards, stars: p.stars, level: g.board.level, name: g.board.name,
                           ranks: p.skillRanks, unlocked: g.mods.unlocked, balls: p.balls, selected: g.ui.selected,
                           pressed: g.time < g.ui.pressedUntil ? g.ui.pressed : .none)
        let c = canvas
        // The panel's part of the canvas (all of it, in any real layout).
        let P = L.panel.intersection(Rect(0, 0, c.width, c.height))
        if key == panelKey, panelPixels.count == P.w * P.h {
            hits.append(contentsOf: panelHits)
            guard !covered, P.w > 0 else { return }
            panelPixels.withUnsafeBufferPointer { src in
                c.pixels.withUnsafeMutableBufferPointer { dst in
                    for y in 0..<P.h {
                        (dst.baseAddress! + ((P.y + y) * c.width + P.x)).update(from: src.baseAddress! + y * P.w, count: P.w)
                    }
                }
            }
            return
        }
        let first = hits.count
        paintPanel(g, L)
        panelKey = key
        panelHits = Array(hits[first...])
        if panelPixels.count != P.w * P.h { panelPixels = [Pixel](repeating: Palette.black, count: P.w * P.h) }
        guard P.w > 0 else { return }
        c.pixels.withUnsafeBufferPointer { src in
            panelPixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<P.h {
                    (dst.baseAddress! + y * P.w).update(from: src.baseAddress! + ((P.y + y) * c.width + P.x), count: P.w)
                }
            }
        }
    }

    func paintPanel(_ g: Game, _ L: Layout) {
        let c = canvas, P = L.panel, A = L.panelContent
        c.fill(P, Palette.panel0)
        hit(P, .panel)
        let x0 = A.x + 8, right = A.maxX - 8
        let tight = L.landscape && L.short
        // In landscape the panel's right edge runs into the top- and bottom-right corners.
        let topY = A.y + (tight ? 6 : (L.landscape ? 9 : 8))

        // Coins, big: the one number you watch.
        c.sprite(Sprites.coin, x0, topY, scale: 2)
        c.text(coins(g.progress.money), x0 + 20, topY, Palette.white, scale: 2)
        hit(Rect(x0 - 2, topY - 2, 110, 18), .none, ["COINS", "Buy balls with them"])

        // Shards and stars on the left, the level on the right, on one cap line.
        let y2 = topY + 14 + (tight ? 6 : 8)
        c.sprite(Sprites.shard, x0, y2)
        let sh = "\(g.progress.shards)"
        c.text(sh, x0 + 11, y2, g.progress.shards > 0 ? Palette.mint : Palette.text2)
        let sx = x0 + 11 + PixelFont.measure(sh) + 10
        c.sprite(Sprites.star, sx, y2)
        c.text("\(g.progress.stars)", sx + 11, y2, g.progress.stars > 0 ? Palette.gold : Palette.text2)
        let lv = "LV \(g.board.level)"
        c.text(lv, right - PixelFont.measure(lv) - (L.landscape ? 6 : 0), y2, Palette.text2)
        hit(Rect(x0 - 2, y2 - 2, A.w - 16, 12), .none, ["\(g.progress.shards) SHARDS, \(g.progress.stars) STARS",
                                                        "LEVEL \(g.board.level): \(g.board.name)"])

        // TREE (lit blue when something in it is affordable) and pause.
        let by = y2 + PixelFont.capHeight + (tight ? 6 : 9), bh = tight ? 23 : 25, pauseW = 29
        let affordable = SkillNode.all.contains { Skills.check($0.id, ranks: g.progress.skillRanks, shards: g.progress.shards) == .ok }
        let treeW = right - x0 - pauseW - 4
        button(g, Rect(x0, by, treeW, bh), "TREE", .openSkills, style: affordable ? .primary : .secondary, icon: Sprites.tree, tintIcon: true)
        button(g, Rect(right - pauseW, by, pauseW, bh), "", .pause, icon: Sprites.pause, tintIcon: true)

        // Ball rows: only the types you have unlocked, sharing the height under the header.
        // One column (two on a tall screen) while every row stays touch-sized; else two.
        let rowsTop = by + bh + (tight ? 7 : 10)
        let kinds = BallKind.allCases.filter { g.mods.unlocked.contains($0) }
        let gap = 3, avail = A.maxY - 4 - rowsTop
        var cols = L.landscape ? 1 : 2, rowH = Tuning.minTouch
        for n in cols...2 {
            cols = n
            rowH = min(29, (avail + gap) / max(1, (kinds.count + n - 1) / n) - gap)
            if rowH >= Tuning.minTouch { break }
        }
        rowH = max(Tuning.minTouch, rowH)
        let colW = (right - x0 - (cols - 1) * 4) / cols
        for (j, k) in kinds.enumerated() {
            let r = Rect(x0 + (j % cols) * (colW + 4), rowsTop + (j / cols) * (rowH + gap), colW, rowH)
            drawBallRow(g, k, r)
        }
    }

    func drawBallRow(_ g: Game, _ k: BallKind, _ r: Rect) {
        let c = canvas
        let cost = g.ballCost(k)
        let can = g.progress.money >= cost
        let selected = g.ui.selected == k
        let pressed = g.isPressed(.ballRow(k))
        // The selected type (what a launch buys) is the lit row with its colour bar.
        box(r, selected ? Palette.panel3 : (pressed ? Palette.panel2 : Palette.panel1))
        if selected { c.fill(r.x, r.y + 1, 3, r.h - 2, k.color) }
        let dy = pressed ? 1 : 0
        let owned = "x\(g.progress.ball(k).owned)"
        // Two lines of text as one block centred on the row.
        let ty = r.y + (r.h - 17) / 2 + dy
        hit(r, .ballRow(k))
        guard r.w >= Renderer.fullRowWidth else {
            // A tile: the ball, then its price over how many you own. The price drops to
            // short form (2.7K) when the full number is too wide.
            c.sprite(Sprites.ballIcon(k), r.x + 7, r.y + (r.h - 14) / 2 + dy, scale: 2)
            let tx = r.x + 26, tw = r.maxX - 4 - tx
            let full = coins(cost)
            c.text(PixelFont.measure(full) <= tw ? full : compact(cost), tx, ty, can ? Palette.white : Palette.muted)
            c.text(owned, tx, ty + 10, Palette.muted)
            return
        }
        c.sprite(Sprites.ballIcon(k), r.x + 9, r.y + (r.h - 14) / 2 + dy, scale: 2)
        // Name over count.
        c.text(k.type.name.uppercased(), r.x + 30, ty, selected ? Palette.white : Palette.text)
        c.text(owned, r.x + 30, ty + 10, Palette.muted)
        let s = coins(cost)
        let w = PixelFont.measure(s)
        let cy = r.y + (r.h - 7) / 2 + dy
        c.text(s, r.maxX - 7 - w, cy, can ? Palette.white : Palette.muted)
        c.sprite(Sprites.coin, r.maxX - 7 - w - 11, cy, tint: can ? nil : Palette.muted)
    }

    // MARK: - Ball sheet

    /// What a ball type does: big icon, its description, its numbers, how many you own, its
    /// upgrades in the tree, and a big BUY button (or the way to unlock it).
    func drawBallSheet(_ g: Game, _ k: BallKind) {
        let c = canvas
        c.dim()
        hit(Rect(0, 0, c.width, c.height), .closeSheet)
        let t = k.type
        let S = layout.safeArea
        let w = min(300, S.w - 16), tileH = 29
        // Padding, the gap between sections and the button height, roomiest first: a short
        // screen gets the first set that fits.
        let pads = [14, 10, 8, 6], gaps = [12, 8, 6, 4], buttons = [29, 27, 25, 23]
        let about = wrap(t.about, width: w - 2 * pads[0])
        let aboutH = (about.count - 1) * PixelFont.lineHeight + PixelFont.capHeight
        func height(_ s: Int) -> Int { 2 * pads[s] + 28 + 1 + aboutH + tileH + PixelFont.capHeight + buttons[s] + 5 * gaps[s] + 2 }
        let step = fitStep(pads.count - 1, into: S.h - 8, height)
        let pad = pads[step], gap = gaps[step], bh = buttons[step]
        let h = height(step)
        let card = layout.centred(w, h)
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)
        let unlocked = g.mods.unlocked.contains(k)
        let x = card.x + pad, inner = w - 2 * pad
        var y = card.y + pad

        // Header: the ball big, its name in its colour, its one-line blurb, and close.
        c.sprite(Sprites.ballIcon(k), x, y, tint: unlocked ? nil : Palette.border, scale: 4)
        c.text(t.name.uppercased(), x + 40, y + 1, unlocked ? k.color : Palette.text2, scale: 2)
        c.text(t.blurb, x + 40, y + 21, Palette.text2)
        let edge = min(8, pad)
        button(g, Rect(card.maxX - edge - 27, card.y + edge, 27, 27), "", .closeSheet, style: .bare, icon: Sprites.close, tintIcon: true)
        y += 28 + gap
        c.hline(card.x + 8, card.maxX - 9, y, Palette.panel3)
        y += 1 + gap

        for line in about {
            c.text(line, x, y, Palette.text)
            y += PixelFont.lineHeight
        }
        y += PixelFont.capHeight - PixelFont.lineHeight + gap

        // Four flat stat tiles: name over value.
        let stats: [(String, String)] = [
            ("DAMAGE", g.damage(k) < 100 ? format1(g.damage(k)) : compact(g.damage(k))),
            ("SPEED", "\(Int(g.speed(k).rounded()))"),
            (t.specialName.uppercased(), specialText(g, k)),
            ("OWNED", "\(g.progress.ball(k).owned)"),
        ]
        let tileGap = 4, tileW = (inner - 3 * tileGap) / 4
        for (j, (name, value)) in stats.enumerated() {
            let tx = x + j * (tileW + tileGap) + (j == 3 ? inner - (4 * tileW + 3 * tileGap) : 0)
            let tw = j == 3 ? x + inner - tx : tileW
            box(Rect(tx, y, tw, tileH), Palette.panel2)
            c.text(name, tx + 7, y + 6, Palette.muted)
            c.text(value, tx + 7, y + 16, Palette.white)
        }
        y += tileH + gap

        // Its upgrades, which live in the skill tree: one pip per rank.
        let tracks: [(String, Stat)] = [("DMG", .damage), ("SPD", .speed), (t.specialName.uppercased(), .special)]
        c.sprite(Sprites.tree, x, y, tint: Palette.muted)
        var tx = x + 7 + 8
        for (name, s) in tracks {
            c.text(name, tx, y, Palette.text2)
            tx += PixelFont.measure(name) + 5
            for j in 0..<s.max { box(Rect(tx + j * 5, y + 1, 4, 5), j < g.rank(k, s) ? k.color : Palette.panel3, notch: 0) }
            tx += s.max * 5 + 10
        }
        y += PixelFont.capHeight + gap + 2

        let br = Rect(x, y, inner, bh)
        if unlocked {
            let cost = g.ballCost(k)
            let can = g.progress.money >= cost
            button(g, br, "BUY  " + coins(cost), .buyBall(k), style: can ? .primary : .disabled, icon: Sprites.coin)
        } else {
            let id = "u-\(k.rawValue)"
            let cost = SkillNode.byID[id]?.cost ?? 0
            button(g, br, "UNLOCK IN THE TREE (\(cost) SHARDS)", .buyBall(k), style: .secondary, icon: Sprites.tree, tintIcon: true)
        }
    }

    func specialText(_ g: Game, _ k: BallKind) -> String {
        let v = g.special(k)
        switch k {
        case .basic: return "\(Int((v * 100).rounded()))%"
        case .fast: return "\(Int((v * 100).rounded()))%"
        case .heavy: return g.has("juggernaut") ? "ALL" : "\(Int(v))"
        case .lightning: return "\(Int(v))"
        case .bomb: return format1(v)
        case .sniper: return "\(Int(v))"
        case .ghost: return format1(v) + "S"
        }
    }
}
