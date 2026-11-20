/// The skill tree: a full-screen map you pinch (resting at 0.5x, 1x or 2x) and drag. Only
/// nodes you own or could buy next are shown; locked ones stay hidden. Tap a node to select
/// it; the card at the bottom says what it does and has the BUY button.
extension Renderer {
    /// Node box size at a tree zoom: 9 px (no icon), 17 px (7-px icon), 34 px (2x icon).
    static func nodeSize(_ zoom: Double) -> Int { zoom < 0.75 ? 9 : (zoom < 1.5 ? 17 : 34) }

    func drawTree(_ g: Game) {
        let c = canvas
        c.fill(0, 0, c.width, c.height, Palette.black)
        hit(Rect(0, 0, c.width, c.height), .tree)
        var cam = g.ui.treeCamera
        cam.setSizes(boardW: SkillTree.size.w, boardH: SkillTree.size.h, viewW: c.width, viewH: c.height)
        g.ui.treeCamera = cam
        let ranks = g.progress.skillRanks
        let size = Renderer.nodeSize(cam.zoom)
        func view(_ s: SkillNode) -> Point {
            let p = SkillTree.position(s)
            let v = cam.toView(p.x, p.y)
            return Point(Int(v.x.rounded(.down)), Int(v.y.rounded(.down)))
        }
        let shown = SkillNode.all.filter { Skills.visible($0.id, ranks: ranks) }
        let shownIDs = Set(shown.map(\.id))

        // Links between shown nodes: solid accent once both ends are owned, dotted otherwise.
        for s in shown {
            for rq in s.requires where shownIDs.contains(rq) {
                guard let q = SkillNode.byID[rq] else { continue }
                let a = view(s), e = view(q)
                if (ranks[s.id] ?? 0) > 0 { c.line(a.x, a.y, e.x, e.y, Palette.accent.glowing(120)) }
                else { c.dottedLine(a.x, a.y, e.x, e.y, Palette.muted) }
            }
        }

        for s in shown {
            let p = view(s)
            let r = Rect(p.x - size / 2, p.y - size / 2, size, size)
            let rank = ranks[s.id] ?? 0
            let state = Skills.check(s.id, ranks: ranks, shards: g.progress.shards)
            let selected = g.ui.selectedSkill == s.id
            let fill: Pixel
            switch state {
            case .maxed: fill = Palette.accent
            case .ok: fill = Int(g.time * 3) & 1 == 0 ? Palette.mintDim : Palette.panel3
            case .poor, .locked: fill = rank > 0 ? Palette.accentDim : Palette.panel2
            }
            if selected { c.fill(r.x - 2, r.y - 2, r.w + 4, r.h + 4, Palette.white) }
            c.fill(r, fill)
            if size > 9 {
                let icon = Sprites.skillIcon(s.effect)
                let scale = size >= 34 ? 2 : 1
                let off = (size - 7 * scale) / 2
                var tint: Pixel? = Palette.white
                if case .unlock = s.effect { tint = nil }
                c.sprite(icon, r.x + off, r.y + off, tint: tint, scale: scale)
                if s.ranks > 1 {
                    let pip = scale * 2
                    let x0 = r.x + (size - (s.ranks * (pip + 1) - 1)) / 2
                    for j in 0..<s.ranks { c.fill(x0 + j * (pip + 1), r.maxY + 2, pip, pip, j < rank ? Palette.accent : Palette.border) }
                }
            } else if case .unlock(let k) = s.effect {
                c.fill(r.x + 3, r.y + 3, 3, 3, k.color)
            }
            let hs = max(Tuning.minTouch, size + 4)
            hit(Rect(p.x - hs / 2, p.y - hs / 2, hs, hs), .selectSkill(s.id))
        }

        // Header: shards to spend, a hint, and the way out (all clear of the corners).
        let hx = Tuning.cornerRadius + 6
        c.fill(hx - 4, 4, 160, 24, Palette.black)
        c.sprite(Sprites.shard, hx, 8, scale: 2)
        c.text("\(g.progress.shards)", hx + 19, 8, Palette.mint, scale: 2)
        c.text("SHARDS", hx + 23 + PixelFont.measure("\(g.progress.shards)", scale: 2), 15, Palette.text2)
        hit(Rect(hx - 4, 4, 160, 24), .none, ["SHARDS", "Break mint shard pixels for more"])
        let close = Rect(c.width - Tuning.cornerRadius - 34, 4, 30, 26)
        button(g, close, "", .closeSkills, icon: Sprites.close, tintIcon: true)

        drawSkillCard(g)
    }

    func drawSkillCard(_ g: Game) {
        let c = canvas
        let card = Rect(Tuning.cornerRadius + 8, c.height - 74, c.width - 2 * (Tuning.cornerRadius + 8), 68)
        c.fill(card, Palette.panel1)
        hit(card, .none)
        let x = card.x + 10
        guard let id = g.ui.selectedSkill, let s = SkillNode.byID[id], Skills.visible(id, ranks: g.progress.skillRanks) else {
            c.text("TAP A SKILL TO SEE WHAT IT DOES", x, card.y + 14, Palette.text)
            c.text("Pinch to zoom, drag to look around.", x, card.y + 28, Palette.muted)
            c.text("Shards come from the glowing mint pixels.", x, card.y + 40, Palette.muted)
            return
        }
        let rank = g.progress.skillRanks[id] ?? 0
        var tint: Pixel? = Palette.white
        if case .unlock = s.effect { tint = nil }
        c.fill(x, card.y + 10, 22, 22, Palette.panel2)
        c.sprite(Sprites.skillIcon(s.effect), x + 4, card.y + 14, tint: tint, scale: 2)
        let tx = x + 30
        let bw = 110
        c.text(s.name.uppercased(), tx, card.y + 10, Palette.white)
        var ly = card.y + 22
        for line in wrap(s.text, width: card.w - 30 - bw - 30).prefix(2) {
            c.text(line, tx, ly, Palette.text2)
            ly += PixelFont.lineHeight
        }
        let rankText = s.ranks > 1 ? "RANK \(rank)/\(s.ranks)" : (rank > 0 ? "OWNED" : "NOT OWNED")
        c.text(rankText, tx, card.maxY - 16, Palette.muted)
        let br = Rect(card.maxX - bw - 10, card.y + (card.h - 30) / 2, bw, 30)
        switch Skills.check(id, ranks: g.progress.skillRanks, shards: g.progress.shards) {
        case .ok: button(g, br, "BUY  \(s.cost)", .buySkill(id), style: .primary, icon: Sprites.shard)
        case .poor: button(g, br, "NEED \(s.cost)", .buySkill(id), style: .disabled, icon: Sprites.shard)
        case .maxed: button(g, br, "MAXED", .none, style: .disabled)
        case .locked: button(g, br, "LOCKED", .none, style: .disabled, icon: Sprites.lock)
        }
    }
}
