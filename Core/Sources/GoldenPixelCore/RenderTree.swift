/// The skill tree: a full-screen map you pinch (resting at 0.5x, 1x or 2x) and drag. It is one
/// tree grown from the Core node, on a grid, with right-angled links only (`SkillTree.route`).
/// Only nodes you own or could buy next are shown; locked ones stay hidden, and since a node
/// shows only once everything it needs is owned, every shown node hangs off a shown parent.
/// Tap a node to select it; the card says what it does and has the BUY button.
extension Renderer {
    /// Node box size at a tree zoom: 9 px (no icon), 21 px (7-px icon and rank pips inside),
    /// 42 px (2x icon and pips).
    static func nodeSize(_ zoom: Double) -> Int { zoom < 0.75 ? 9 : (zoom < 1.5 ? 21 : 42) }

    func drawTree(_ g: Game) {
        let c = canvas
        c.fill(0, 0, c.width, c.height, Palette.black)
        hit(Rect(0, 0, c.width, c.height), .tree)
        var cam = g.ui.treeCamera
        cam.setSizes(boardW: SkillTree.size.w, boardH: SkillTree.size.h, viewW: c.width, viewH: c.height)
        g.ui.treeCamera = cam
        let ranks = g.progress.skillRanks
        let size = Renderer.nodeSize(cam.zoom)
        // Links are 1 px, 2 px at 2x, centred on the node centres.
        let thick = size >= 42 ? 2 : 1
        func view(_ p: Point) -> Point {
            let v = cam.toView(Double(p.x), Double(p.y))
            return Point(Int(v.x.rounded(.down)), Int(v.y.rounded(.down)))
        }
        let shown = SkillNode.all.filter { Skills.visible($0.id, ranks: ranks) }
        let shownIDs = Set(shown.map(\.id))
        let o = view(Point(0, 0))

        // Links: dotted grey into anything not owned yet, solid blue between owned nodes (drawn
        // second, so a shared stub is solid as soon as one branch off it is).
        for solid in [false, true] {
            for s in shown {
                let owned = (ranks[s.id] ?? 0) > 0
                for rq in s.requires where shownIDs.contains(rq) {
                    guard let q = SkillNode.byID[rq] else { continue }
                    let lit = owned && (ranks[rq] ?? 0) > 0
                    guard lit == solid else { continue }
                    let path = SkillTree.route(from: q, to: s).map(view)
                    for (a, b) in zip(path, path.dropFirst()) {
                        link(a, b, thick: thick, solid: lit, origin: o, lit ? Palette.accent.glowing(120) : Palette.muted)
                    }
                }
            }
        }

        for s in shown {
            let p = view(SkillTree.point(s))
            let r = Rect(p.x - size / 2, p.y - size / 2, size, size)
            let rank = ranks[s.id] ?? 0
            let state = Skills.check(s.id, ranks: ranks, shards: g.progress.shards)
            if g.ui.selectedSkill == s.id { c.fill(r.x - 2, r.y - 2, r.w + 4, r.h + 4, Palette.white) }
            drawNode(s, r, rank: rank, state: state)
            let hs = max(Tuning.minTouch, size + 4)
            hit(Rect(p.x - hs / 2, p.y - hs / 2, hs, hs), .selectSkill(s.id))
        }

        // Header: the shards to spend, and the way out (both clear of the corners).
        let hx = Tuning.cornerRadius + 6
        let count = "\(g.progress.shards)"
        c.sprite(Sprites.shard, hx, 8, scale: 2)
        let w = 18 + c.text(count, hx + 18, 8, Palette.mint, scale: 2)
        hit(Rect(hx - 4, 4, w + 8, 22), .none, ["SHARDS", "Break mint shard pixels for more"])
        let close = Rect(c.width - Tuning.cornerRadius - 34, 4, 30, 26)
        button(g, close, "", .closeSkills, style: .bare, icon: Sprites.close, tintIcon: true)

        drawSkillCard(g)
    }

    /// One axis-aligned link segment, `thick` px wide and centred on the a-b line. Dotted
    /// links step on the tree's own grid (relative to its origin `o`), so the dots move with
    /// the map instead of crawling as you pan, and links that share a stub dot in step.
    func link(_ a: Point, _ b: Point, thick t: Int, solid: Bool, origin o: Point, _ col: Pixel) {
        let c = canvas
        let h = t / 2
        // On for t px, off for t px, counted from the tree's origin.
        func dot(_ d: Int, _ t: Int) -> Bool { ((d % (2 * t)) + 2 * t) % (2 * t) < t }
        if a.y == b.y {
            let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
            if solid { c.fill(x0 - h, a.y - h, x1 - x0 + t, t, col); return }
            for x in (x0 - h)..<(x1 - h + t) where dot(x - o.x, t) { c.fill(x, a.y - h, 1, t, col) }
        } else {
            let y0 = min(a.y, b.y), y1 = max(a.y, b.y)
            if solid { c.fill(a.x - h, y0 - h, t, y1 - y0 + t, col); return }
            for y in (y0 - h)..<(y1 - h + t) where dot(y - o.y, t) { c.fill(a.x - h, y, t, 1, col) }
        }
    }

    /// A node box. Flat states: owned in blue (full blue once maxed), buyable outlined in mint,
    /// too dear in dark grey. Rank pips sit in a row inside the box.
    func drawNode(_ s: SkillNode, _ r: Rect, rank: Int, state: SkillCheck) {
        let c = canvas
        let size = r.w
        let fill: Pixel, ink: Pixel, pipOn: Pixel, pipOff: Pixel
        switch state {
        case .maxed: fill = Palette.accent; ink = Palette.white; pipOn = Palette.white; pipOff = Palette.accentDim
        case .ok: fill = rank > 0 ? Palette.accentDim : Palette.panel2; ink = Palette.white; pipOn = Palette.accentLight; pipOff = Palette.panel0
        case .poor, .locked:
            fill = rank > 0 ? Palette.accentDim : Palette.panel2
            ink = rank > 0 ? Palette.text : Palette.muted
            pipOn = Palette.accentLight; pipOff = Palette.panel0
        }
        if state == .ok {
            c.fill(r, Palette.mint)
            c.fill(r.x + 1, r.y + 1, r.w - 2, r.h - 2, fill)
        } else {
            c.fill(r, fill)
        }
        if size > 9 {
            let scale = size >= 42 ? 2 : 1
            let pips = s.ranks > 1
            // Icon centred; with ranks, nudged up to leave the pips a row inside the box.
            let ix = r.x + (size - 7 * scale) / 2
            let iy = pips ? r.y + 4 * scale : r.y + (size - 7 * scale) / 2
            var tint: Pixel? = ink
            if case .unlock = s.effect { tint = state == .poor || state == .locked ? Palette.muted : nil }
            c.sprite(Sprites.skillIcon(s.effect), ix, iy, tint: tint, scale: scale)
            if pips {
                let pw = s.ranks > 4 ? scale * 2 : scale * 3, ph = scale * 2, gap = scale
                let total = s.ranks * pw + (s.ranks - 1) * gap
                let x0 = r.x + (size - total) / 2, y0 = r.maxY - 3 * scale - ph + scale
                for j in 0..<s.ranks { c.fill(x0 + j * (pw + gap), y0, pw, ph, j < rank ? pipOn : pipOff) }
            }
        } else if case .unlock(let k) = s.effect {
            c.fill(r.x + 3, r.y + 3, 3, 3, k.color)
        }
    }

    /// The selected node's card: its icon in a tile, then its name (big), what it does, and its
    /// rank, with the price button on the right. Ball skills show the ball itself, as it looks
    /// on the board, after the name. No card until a node is picked: the tree speaks for itself.
    func drawSkillCard(_ g: Game) {
        let c = canvas
        let ranks = g.progress.skillRanks
        guard let id = g.ui.selectedSkill, let s = SkillNode.byID[id], Skills.visible(id, ranks: ranks) else { return }
        let rank = ranks[id] ?? 0
        let state = Skills.check(id, ranks: ranks, shards: g.progress.shards)
        let ball = s.effect.ball

        // Sizes first: a 44-px icon tile on the left, the price button on the right (as tall
        // as the tile), and the text between them, centred on the tile.
        let pad = 9, tileSize = 44, bw = 96
        let side = Tuning.cornerRadius + 8
        let cardW = c.width - 2 * side
        let tx = side + pad + tileSize + 10, tw = side + cardW - pad - bw - 10 - tx
        let name = s.name.uppercased()
        let nameScale = PixelFont.measure(name, scale: 2) + (ball == nil ? 0 : 16) <= tw ? 2 : 1
        let lines = wrap(s.text, width: tw)
        let showRank = s.ranks > 1 || rank > 0
        let nameH = PixelFont.capHeight * nameScale
        let textH = (lines.count - 1) * PixelFont.lineHeight + PixelFont.capHeight
        let blockH = nameH + 7 + textH + (showRank ? 9 + PixelFont.capHeight : 0)
        let innerH = max(tileSize, blockH)

        // Along the bottom, unless the selected node is under it: then along the top, below
        // the header.
        var card = Rect(side, c.height - 6 - innerH - 2 * pad, cardW, innerH + 2 * pad)
        let v = g.ui.treeCamera.toView(SkillTree.position(s).x, SkillTree.position(s).y)
        if Int(v.y) + Renderer.nodeSize(g.ui.treeCamera.zoom) / 2 + 4 >= card.y { card.y = 34 }
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)

        // Icon tile, coloured like the node: blue once owned.
        let tile = Rect(card.x + pad, card.y + pad + (innerH - tileSize) / 2, tileSize, tileSize)
        box(tile, state == .maxed ? Palette.accent : (rank > 0 ? Palette.accentDim : Palette.panel2))
        var tint: Pixel? = Palette.white
        if case .unlock = s.effect { tint = nil }
        c.sprite(Sprites.skillIcon(s.effect), tile.x + (tileSize - 28) / 2, tile.y + (tileSize - 28) / 2, tint: tint, scale: 4)

        drawBuyButton(g, s, Rect(card.maxX - pad - bw, tile.y, bw, tileSize), state)

        // Name (big), what it does, then the rank. A ball's skills wear its colour, as in its
        // info sheet, and show the ball itself as it looks on the board.
        var y = card.y + pad + (innerH - blockH) / 2
        let nameEnd = tx + c.text(name, tx, y, ball?.color ?? Palette.white, scale: nameScale)
        if let k = ball {
            c.sprite(Sprites.ball(k), nameEnd + 3 * nameScale, y + (nameH - 5 * nameScale) / 2, scale: nameScale)
        }
        y += nameH + 7
        for line in lines {
            c.text(line, tx, y, Palette.text2)
            y += PixelFont.lineHeight
        }
        guard showRank else { return }
        y += PixelFont.capHeight - PixelFont.lineHeight + 9
        if s.ranks > 1 {
            var x = tx
            let on = ball?.color ?? Palette.accent
            for j in 0..<s.ranks {
                box(Rect(x, y + 1, 7, 5), j < rank ? on : Palette.panel3, notch: 0)
                x += 9
            }
            c.text("RANK \(rank)/\(s.ranks)", x + 4, y, rank >= s.ranks ? Palette.accentLight : Palette.muted)
        } else {
            c.text("OWNED", tx, y, Palette.accentLight)
        }
    }

    /// BUY (blue) when you can afford it, NEED (grey) when you cannot, or a plain MAXED tag.
    func drawBuyButton(_ g: Game, _ s: SkillNode, _ r: Rect, _ state: SkillCheck) {
        let c = canvas
        let cost = "\(s.cost)"
        let word: String, ink: Pixel, icon: Sprite?
        switch state {
        case .ok:
            button(g, r, "", .buySkill(s.id), style: .primary)
            word = "BUY"; ink = Palette.white; icon = Sprites.shard
        case .poor:
            button(g, r, "", .buySkill(s.id), style: .disabled)
            word = "NEED"; ink = Palette.muted; icon = Sprites.shard
        case .maxed:
            hit(r, .none)
            word = "MAXED"; ink = Palette.accentLight; icon = nil
        case .locked:
            hit(r, .none)
            word = "LOCKED"; ink = Palette.muted; icon = nil
        }
        // One line at 2x: the word, then the shard and the price.
        let ww = PixelFont.measure(word, scale: 2)
        let price = state == .ok || state == .poor
        // The word, a gap, the 7-px shard, a gap, the price: 4 + 7 + 3 px between word and price.
        let pw = price ? 14 * 2 + PixelFont.measure(cost, scale: 2) : 0
        let scale = ww + pw <= r.w - 12 ? 2 : 1
        let total = PixelFont.measure(word, scale: scale) + (price ? 14 * scale + PixelFont.measure(cost, scale: scale) : 0)
        var x = r.x + (r.w - total) / 2
        let y = r.y + (r.h - PixelFont.capHeight * scale + 1) / 2 + (state == .ok && g.isPressed(.buySkill(s.id)) ? 1 : 0)
        x += c.text(word, x, y, ink, scale: scale)
        if price, let icon {
            x += 4 * scale
            c.sprite(icon, x, y, tint: state == .poor ? Palette.muted : nil, scale: scale)
            c.text(cost, x + 10 * scale, y, ink, scale: scale)
        }
    }
}
