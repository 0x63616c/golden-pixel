/// The in-game pause card (the panel's pause button) and its restart confirmation. The game
/// stands still underneath while it is open. Same card and button system as the menu screens:
/// a notched panel with a keyline, a scale-2 title, one gold hero action, the rest secondary.
extension Renderer {
    func drawPause(_ g: Game) {
        let c = canvas
        c.dim()
        hit(Rect(0, 0, c.width, c.height), .none)
        let w = 232, pad = 16, bw = w - 2 * pad, heroH = 31, bh = 27, gap = 6
        let titleH = 14, titleGap = 16
        if g.ui.confirmingRestart {
            let body = wrap("Level \(g.board.level) starts over. Coins, balls, shards and skills go back to the start.", width: bw)
            let bodyH = (body.count - 1) * PixelFont.lineHeight + PixelFont.capHeight
            let h = pad + 4 + titleH + titleGap + bodyH + 18 + bh + pad
            let card = Rect((c.width - w) / 2, (c.height - h) / 2, w, h)
            box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
            hit(card, .none)
            var y = card.y + pad + 4
            centred("RESTART?", c.width / 2, y, Palette.white, scale: 2)
            y += titleH + titleGap
            for line in body {
                centred(line, c.width / 2, y, Palette.text2)
                y += PixelFont.lineHeight
            }
            y += PixelFont.capHeight - PixelFont.lineHeight + 18
            let half = (bw - gap) / 2
            button(g, Rect(card.x + pad, y, half, bh), "CANCEL", .cancelRestart)
            button(g, Rect(card.maxX - pad - half, y, half, bh), "RESTART", .confirmRestart, style: .danger, icon: Sprites.restart, tintIcon: true)
            return
        }
        let h = pad + 4 + titleH + titleGap + heroH + gap + 2 * bh + gap + pad
        let card = Rect((c.width - w) / 2, (c.height - h) / 2, w, h)
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)
        var y = card.y + pad + 4
        centred("PAUSED", c.width / 2, y, Palette.white, scale: 2)
        y += titleH + titleGap
        button(g, Rect(card.x + pad, y, bw, heroH), "RESUME", .resume, style: .gold, icon: Sprites.play, tintIcon: true)
        y += heroH + gap
        button(g, Rect(card.x + pad, y, bw, bh), "RESTART LEVEL", .restartLevel, icon: Sprites.restart, tintIcon: true)
        y += bh + gap
        button(g, Rect(card.x + pad, y, bw, bh), "MAIN MENU", .openMenu, icon: Sprites.menu, tintIcon: true)
    }
}
