/// The in-game pause card (the panel's pause button) and its restart confirmation. The game
/// stands still underneath while it is open. Same card and button system as the menu screens:
/// a notched panel with a keyline, a scale-2 title, one gold hero action, the rest secondary.
extension Renderer {
    func drawPause(_ g: Game) {
        let c = canvas
        c.dim()
        hit(Rect(0, 0, c.width, c.height), .none)
        // Padding, gaps and button heights, roomiest first: a short screen gets the first set
        // that fits.
        let pads = [16, 12, 8], titleGaps = [16, 10, 8], heroes = [31, 29, 27], rows = [27, 25, 23], gaps = [6, 5, 4], bodyGaps = [18, 12, 8]
        let w = 232, bw = w - 2 * pads[0]
        let titleH = 14, avail = layout.safeArea.h - 8
        if g.ui.confirmingRestart {
            let body = wrap("Level \(g.board.level) starts over. Coins, balls, shards and skills go back to the start.", width: bw)
            let bodyH = (body.count - 1) * PixelFont.lineHeight + PixelFont.capHeight
            func height(_ s: Int) -> Int { pads[s] + 4 + titleH + titleGaps[s] + bodyH + bodyGaps[s] + rows[s] + pads[s] }
            let s = fitStep(pads.count - 1, into: avail, height)
            let pad = pads[0], titleGap = titleGaps[s], bh = rows[s], gap = gaps[s]
            let h = height(s)
            let card = layout.centred(w, h)
            box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
            hit(card, .none)
            var y = card.y + pads[s] + 4
            centred("RESTART?", card.x + w / 2, y, Palette.white, scale: 2)
            y += titleH + titleGap
            for line in body {
                centred(line, card.x + w / 2, y, Palette.text2)
                y += PixelFont.lineHeight
            }
            y += PixelFont.capHeight - PixelFont.lineHeight + bodyGaps[s]
            let half = (bw - gap) / 2
            button(g, Rect(card.x + pad, y, half, bh), "CANCEL", .cancelRestart)
            button(g, Rect(card.maxX - pad - half, y, half, bh), "RESTART", .confirmRestart, style: .danger, icon: Sprites.restart, tintIcon: true)
            return
        }
        func height(_ s: Int) -> Int { pads[s] + 4 + titleH + titleGaps[s] + heroes[s] + gaps[s] + 2 * rows[s] + gaps[s] + pads[s] }
        let s = fitStep(pads.count - 1, into: avail, height)
        let pad = pads[0], titleGap = titleGaps[s], heroH = heroes[s], bh = rows[s], gap = gaps[s]
        let h = height(s)
        let card = layout.centred(w, h)
        box(card, Palette.panel1, edge: Palette.panel3, notch: 2)
        hit(card, .none)
        var y = card.y + pads[s] + 4
        centred("PAUSED", card.x + w / 2, y, Palette.white, scale: 2)
        y += titleH + titleGap
        button(g, Rect(card.x + pad, y, bw, heroH), "RESUME", .resume, style: .gold, icon: Sprites.play, tintIcon: true)
        y += heroH + gap
        button(g, Rect(card.x + pad, y, bw, bh), "RESTART LEVEL", .restartLevel, icon: Sprites.restart, tintIcon: true)
        y += bh + gap
        button(g, Rect(card.x + pad, y, bw, bh), "MAIN MENU", .openMenu, icon: Sprites.menu, tintIcon: true)
    }
}
