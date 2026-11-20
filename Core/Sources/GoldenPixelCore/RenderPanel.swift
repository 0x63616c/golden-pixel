/// The side panel (coins, shards, level, the TREE and MENU buttons, one row per ball type) and
/// the ball info sheet. Everything here stays clear of the screen's rounded corners and every
/// button is at least `Tuning.minTouch` art pixels square (UISafetyTests checks both).
extension Renderer {
    func drawPanel(_ g: Game, _ L: Layout) {
        let c = canvas, P = L.panel
        c.fill(P, Palette.panel0)
        hit(P, .panel)
        let x0 = P.x + 8, right = P.maxX - 8
        // In landscape the panel's right edge runs into the top- and bottom-right corners.
        let topY = L.landscape ? 8 : P.y + 6

        // Coins, big.
        c.sprite(Sprites.coin, x0, topY, scale: 2)
        c.text(compact(g.progress.money), x0 + 19, topY, Palette.white, scale: 2)
        hit(Rect(x0 - 2, topY - 2, 110, 18), .none, ["COINS", "Buy balls with them"])

        // Shards, stars, level.
        let y2 = topY + 21
        c.sprite(Sprites.shard, x0, y2)
        let sh = "\(g.progress.shards)"
        c.text(sh, x0 + 10, y2, g.progress.shards > 0 ? Palette.mint : Palette.text2)
        let sx = x0 + 10 + PixelFont.measure(sh) + 9
        c.sprite(Sprites.star, sx, y2)
        c.text("\(g.progress.stars)", sx + 10, y2, Palette.text2)
        let lv = "LV \(g.board.level)"
        c.text(lv, right - PixelFont.measure(lv) - (L.landscape ? 6 : 0), y2, Palette.text2)
        hit(Rect(x0 - 2, y2 - 2, P.w - 16, 12), .none, ["\(g.progress.shards) SHARDS, \(g.progress.stars) STARS",
                                                        "LEVEL \(g.board.level): \(g.board.name)"])

        // TREE and MENU.
        let by = y2 + 14
        let affordable = SkillNode.all.contains { Skills.check($0.id, ranks: g.progress.skillRanks, shards: g.progress.shards) == .ok }
        let treeW = (P.w - 16) * 3 / 5
        button(g, Rect(x0, by, treeW, 24), "TREE", .openSkills, style: affordable ? .primary : .secondary, icon: Sprites.tree, tintIcon: true)
        button(g, Rect(x0 + treeW + 4, by, right - x0 - treeW - 4, 24), "MENU", .openMenu)

        // Ball rows.
        let rowsTop = by + 30
        let cols = L.landscape ? 1 : 2
        let rowH = 28, gap = 2
        let colW = (P.w - 12 - (cols - 1) * 4) / cols
        for (j, k) in BallKind.allCases.enumerated() {
            let r = Rect(P.x + 6 + (j % cols) * (colW + 4), rowsTop + (j / cols) * (rowH + gap), colW, rowH)
            drawBallRow(g, k, r)
        }
        if L.landscape {
            let hy = rowsTop + 7 * (rowH + gap) + 4
            c.text("TAP A BALL: INFO", x0, hy, Palette.muted)
            c.text("DRAG A BALL: AIM", x0, hy + 10, Palette.muted)
        }
    }

    func drawBallRow(_ g: Game, _ k: BallKind, _ r: Rect) {
        let c = canvas
        let unlocked = g.mods.unlocked.contains(k)
        let cost = g.ballCost(k)
        let can = unlocked && g.progress.money >= cost
        let aiming = g.ui.aim?.kind == k
        let pressed = g.isPressed(.ballRow(k)) || aiming
        c.fill(r, pressed ? Palette.panel3 : (can ? Palette.panel2 : Palette.panel1))
        if can { c.fill(r.x, r.y, 2, r.h, k.color) }
        let iy = r.y + (r.h - 14) / 2
        if unlocked {
            c.sprite(Sprites.ballIcon(k), r.x + 6, iy, scale: 2)
            c.text(k.type.name.uppercased(), r.x + 25, r.y + 5, Palette.text)
            c.text("x\(g.progress.ball(k).owned)", r.x + 25, r.y + 16, Palette.muted)
            let s = compact(cost)
            let w = PixelFont.measure(s)
            c.text(s, r.maxX - 6 - w, r.y + 10, can ? Palette.white : Palette.muted)
            c.sprite(Sprites.coin, r.maxX - 6 - w - 10, r.y + 10)
        } else {
            c.sprite(Sprites.ballIcon(k), r.x + 6, iy, tint: Palette.border, scale: 2)
            c.text(k.type.name.uppercased(), r.x + 25, r.y + 5, Palette.muted)
            c.text("IN THE TREE", r.x + 25, r.y + 16, Palette.border)
            c.sprite(Sprites.lock, r.maxX - 13, r.y + 10)
        }
        hit(r, .ballRow(k))
    }

    // MARK: - Ball sheet

    /// What a ball type does: big icon, its description, its numbers, how many you own, and a
    /// big BUY button (or the way to unlock it).
    func drawBallSheet(_ g: Game, _ k: BallKind) {
        let c = canvas
        c.dim()
        hit(Rect(0, 0, c.width, c.height), .closeSheet)
        let w = 300, h = 178
        let card = Rect((c.width - w) / 2, (c.height - h) / 2, w, h)
        c.fill(card, Palette.panel1)
        hit(card, .none)
        let t = k.type
        let unlocked = g.mods.unlocked.contains(k)
        let x = card.x + 12
        var y = card.y + 12
        c.sprite(Sprites.ballIcon(k), x, y, tint: unlocked ? nil : Palette.border, scale: 4)
        c.text(t.name.uppercased(), x + 38, y + 1, unlocked ? k.color : Palette.text2, scale: 2)
        c.text(t.blurb, x + 38, y + 19, Palette.text2)
        button(g, Rect(card.maxX - 32, card.y + 6, 26, 24), "", .closeSheet, icon: Sprites.close, tintIcon: true)
        y += 38
        for line in wrap(t.about, width: w - 24) {
            c.text(line, x, y, Palette.text)
            y += PixelFont.lineHeight + 1
        }
        y += 6
        let stats: [(String, String)] = [
            ("DAMAGE", g.damage(k) < 100 ? format1(g.damage(k)) : compact(g.damage(k))),
            ("SPEED", "\(Int(g.speed(k).rounded()))"),
            (t.specialName.uppercased(), specialText(g, k)),
            ("OWNED", "\(g.progress.ball(k).owned)"),
        ]
        for (j, (name, value)) in stats.enumerated() {
            let sx = x + (j % 2) * ((w - 24) / 2), sy = y + (j / 2) * 12
            c.text(name, sx, sy, Palette.muted)
            c.text(value, sx + 70, sy, Palette.text)
        }
        y += 26
        // Its upgrades, which live in the skill tree.
        let tracks: [(String, Stat)] = [("DMG", .damage), ("SPD", .speed), (t.specialName.uppercased(), .special)]
        var tx = x
        c.text("TREE", tx, y, Palette.muted)
        tx += 36
        for (name, s) in tracks {
            c.text(name, tx, y, Palette.text2)
            tx += PixelFont.measure(name) + 4
            for j in 0..<s.max { c.fill(tx + j * 4, y + 2, 3, 3, j < g.rank(k, s) ? k.color : Palette.border) }
            tx += s.max * 4 + 8
        }
        let br = Rect(x, card.maxY - 12 - 30, w - 24, 30)
        if unlocked {
            let cost = g.ballCost(k)
            let can = g.progress.money >= cost
            button(g, br, "BUY  " + compact(cost), .buyBall(k), style: can ? .primary : .disabled, icon: Sprites.coin, scale: 1)
            c.text("Or drag its row onto the board to aim it.", x, br.y - 12, Palette.muted)
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
