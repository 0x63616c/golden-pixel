/// The side panel (coins, shards, level, the TREE and pause buttons, one row per unlocked ball
/// type, the selected one highlighted) and the ball info sheet. Everything here stays clear of
/// the screen's rounded corners and every button is at least `Tuning.minTouch` art pixels
/// square (UISafetyTests checks both).
extension Renderer {
    func drawPanel(_ g: Game, _ L: Layout) {
        let c = canvas, P = L.panel
        c.fill(P, Palette.panel0)
        hit(P, .panel)
        let x0 = P.x + 8, right = P.maxX - 8
        // In landscape the panel's right edge runs into the top- and bottom-right corners.
        let topY = L.landscape ? 9 : P.y + 8

        // Coins, big: the one number you watch.
        c.sprite(Sprites.coin, x0, topY, scale: 2)
        c.text(coins(g.progress.money), x0 + 20, topY, Palette.white, scale: 2)
        hit(Rect(x0 - 2, topY - 2, 110, 18), .none, ["COINS", "Buy balls with them"])

        // Shards and stars on the left, the level on the right, on one cap line.
        let y2 = topY + 14 + 8
        c.sprite(Sprites.shard, x0, y2)
        let sh = "\(g.progress.shards)"
        c.text(sh, x0 + 11, y2, g.progress.shards > 0 ? Palette.mint : Palette.text2)
        let sx = x0 + 11 + PixelFont.measure(sh) + 10
        c.sprite(Sprites.star, sx, y2)
        c.text("\(g.progress.stars)", sx + 11, y2, g.progress.stars > 0 ? Palette.gold : Palette.text2)
        let lv = "LV \(g.board.level)"
        c.text(lv, right - PixelFont.measure(lv) - (L.landscape ? 6 : 0), y2, Palette.text2)
        hit(Rect(x0 - 2, y2 - 2, P.w - 16, 12), .none, ["\(g.progress.shards) SHARDS, \(g.progress.stars) STARS",
                                                        "LEVEL \(g.board.level): \(g.board.name)"])

        // TREE (lit blue when something in it is affordable) and pause.
        let by = y2 + PixelFont.capHeight + 9, bh = 25, pauseW = 29
        let affordable = SkillNode.all.contains { Skills.check($0.id, ranks: g.progress.skillRanks, shards: g.progress.shards) == .ok }
        let treeW = right - x0 - pauseW - 4
        button(g, Rect(x0, by, treeW, bh), "TREE", .openSkills, style: affordable ? .primary : .secondary, icon: Sprites.tree, tintIcon: true)
        button(g, Rect(right - pauseW, by, pauseW, bh), "", .pause, icon: Sprites.pause, tintIcon: true)

        // Ball rows: only the types you have unlocked.
        let rowsTop = by + bh + 10
        let cols = L.landscape ? 1 : 2
        let rowH = 29, gap = 3
        let colW = (right - x0 - (cols - 1) * 4) / cols
        for (j, k) in BallKind.allCases.filter({ g.mods.unlocked.contains($0) }).enumerated() {
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
        c.sprite(Sprites.ballIcon(k), r.x + 9, r.y + (r.h - 14) / 2 + dy, scale: 2)
        // Name over count, as one block centred on the row.
        let ty = r.y + (r.h - 17) / 2 + dy
        c.text(k.type.name.uppercased(), r.x + 30, ty, selected ? Palette.white : Palette.text)
        c.text("x\(g.progress.ball(k).owned)", r.x + 30, ty + 10, Palette.muted)
        let s = coins(cost)
        let w = PixelFont.measure(s)
        let cy = r.y + (r.h - 7) / 2 + dy
        c.text(s, r.maxX - 7 - w, cy, can ? Palette.white : Palette.muted)
        c.sprite(Sprites.coin, r.maxX - 7 - w - 11, cy, tint: can ? nil : Palette.muted)
        hit(r, .ballRow(k))
    }

    // MARK: - Ball sheet

    /// What a ball type does: big icon, its description, its numbers, how many you own, its
    /// upgrades in the tree, and a big BUY button (or the way to unlock it).
    func drawBallSheet(_ g: Game, _ k: BallKind) {
        let c = canvas
        c.dim()
        hit(Rect(0, 0, c.width, c.height), .closeSheet)
        let t = k.type
        let w = 300, pad = 14
        let about = wrap(t.about, width: w - 2 * pad)
        let tileH = 29, bh = 29
        let h = pad + 28 + 12 + 1 + 12 + (about.count - 1) * PixelFont.lineHeight + PixelFont.capHeight + 12 + tileH + 12 + PixelFont.capHeight + 14 + bh + pad
        let card = Rect((c.width - w) / 2, (c.height - h) / 2, w, h)
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)
        let unlocked = g.mods.unlocked.contains(k)
        let x = card.x + pad, inner = w - 2 * pad
        var y = card.y + pad

        // Header: the ball big, its name in its colour, its one-line blurb, and close.
        c.sprite(Sprites.ballIcon(k), x, y, tint: unlocked ? nil : Palette.border, scale: 4)
        c.text(t.name.uppercased(), x + 40, y + 1, unlocked ? k.color : Palette.text2, scale: 2)
        c.text(t.blurb, x + 40, y + 21, Palette.text2)
        button(g, Rect(card.maxX - 8 - 27, card.y + 8, 27, 27), "", .closeSheet, style: .bare, icon: Sprites.close, tintIcon: true)
        y += 28 + 12
        c.hline(card.x + 8, card.maxX - 9, y, Palette.panel3)
        y += 1 + 12

        for line in about {
            c.text(line, x, y, Palette.text)
            y += PixelFont.lineHeight
        }
        y += PixelFont.capHeight - PixelFont.lineHeight + 12

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
        y += tileH + 12

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
        y += PixelFont.capHeight + 14

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
