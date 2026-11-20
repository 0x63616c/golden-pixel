/// The main menu, how to play, and settings. Behind them, a slow animated field of pixels:
/// blue blocks drifting in and out of the dark, a few balls bouncing through, and a gold pixel.
extension Renderer {
    /// The animated pixel field behind the menu screens. Pure function of time.
    /// `keepOut` (in background cells) stays black, so cards sit in a clean hole whose edges
    /// follow the cell grid.
    func drawMenuBackground(_ g: Game, keepOut: (x0: Int, y0: Int, x1: Int, y1: Int)? = nil) {
        let c = canvas, t = g.time, cp = Tuning.cellPixels
        let cols = c.width / cp + 1, rows = c.height / cp + 1
        let ox = (c.width - cols * cp) / 2, oy = (c.height - rows * cp) / 2
        for cy in 0..<rows {
            for cx in 0..<cols {
                if let k = keepOut, cx >= k.x0, cx < k.x1, cy >= k.y0, cy < k.y1 { continue }
                let x = Double(cx), y = Double(cy)
                let v = sin(x * 0.35 + t * 0.7) + sin(y * 0.45 - t * 0.5) + sin((x + y) * 0.21 + t * 0.9) + sin((x - y) * 0.17 - t * 0.4)
                guard v > 0.9 else { continue }
                let step = min(3, Int((v - 0.9) * 2.2))
                c.fill(ox + cx * cp, oy + cy * cp, cp, cp, Palette.ladder[step])
            }
        }
        // A golden pixel that wanders slowly, and a few balls bouncing across.
        let gx = Int((Double(cols - 6) * (0.5 + 0.42 * sin(t * 0.13)))) + 3
        let gy = Int((Double(rows - 6) * (0.5 + 0.42 * sin(t * 0.17 + 1)))) + 3
        c.fill(ox + gx * cp, oy + gy * cp, cp, cp, Palette.gold.glowing(255))
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

    func drawMenu(_ g: Game) {
        let c = canvas
        let cols = c.width / Tuning.cellPixels + 1
        // A black hole in the field, on its cell grid, behind the logo and buttons.
        drawMenuBackground(g, keepOut: (cols / 2 - 12, 2, cols / 2 + 13, 32))
        hit(Rect(0, 0, c.width, c.height), .none)
        let cx = c.width / 2
        let s = 5
        centred("GOLDEN", cx, 40, Palette.white, scale: s)
        centred("PIXEL", cx, 40 + 7 * s + 8, Palette.gold.glowing(220), scale: s)
        let p = g.progress
        let best = "BEST LEVEL \(p.maxLevel)"
        let stars = "\(p.stars)"
        let w = PixelFont.measure(best) + 14 + PixelFont.measure(stars) + 10
        let sx = cx - w / 2, sy = 40 + 14 * s + 22
        c.text(best, sx, sy, Palette.text2)
        c.sprite(Sprites.star, sx + PixelFont.measure(best) + 14, sy)
        c.text(stars, sx + PixelFont.measure(best) + 24, sy, Palette.gold)

        let bw = 200
        var y = sy + 20
        let fresh = p.level == 1 && p.levelTime < 1 && p.totalEarnings == 0
        button(g, Rect(cx - bw / 2, y, bw, 34), fresh ? "PLAY" : "CONTINUE  LV \(p.level)", .play, style: .gold, icon: Sprites.play, tintIcon: true)
        y += 40
        button(g, Rect(cx - bw / 2, y, bw, 26), "HOW TO PLAY", .howTo, icon: Sprites.info, tintIcon: true)
        y += 30
        button(g, Rect(cx - bw / 2, y, bw, 26), "SETTINGS", .settings, icon: Sprites.gear, tintIcon: true)
    }

    /// A centred card on the menu background, with a title. Returns the content rectangle.
    func menuCard(_ g: Game, title: String) -> Rect {
        let c = canvas
        drawMenuBackground(g)
        hit(Rect(0, 0, c.width, c.height), .none)
        let card = Rect(Tuning.cornerRadius + 22, 14, c.width - 2 * (Tuning.cornerRadius + 22), c.height - 28)
        c.fill(card, Palette.panel0)
        hit(card, .none)
        centred(title, c.width / 2, card.y + 12, Palette.white, scale: 2)
        button(g, Rect(card.x + (card.w - 140) / 2, card.maxY - 36, 140, 28), "BACK", .backToMenu)
        return Rect(card.x + 16, card.y + 38, card.w - 32, card.h - 38 - 44)
    }

    func drawHowTo(_ g: Game) {
        let c = canvas
        let r = menuCard(g, title: "HOW TO PLAY")
        let rows: [(Sprite, String)] = [
            (Sprites.ballIcon(.basic), "Balls break pixels. You never do: tapping only looks."),
            (Sprites.coin, "Broken pixels pay coins. Coins buy more balls."),
            (Sprites.aim, "Tap a ball in the panel to read about it. Drag it to aim, release to buy."),
            (Sprites.shard, "Mint pixels hold shards. You sense them through the dark when you dig close."),
            (Sprites.tree, "Shards buy the skill tree: upgrades, and new kinds of ball."),
            (Sprites.coin, "Somewhere in the dark is the golden pixel. Break it to clear the level."),
            (Sprites.star, "Each gold is a star for good: more damage and coins. Each level starts fresh."),
            (Sprites.statSpeed, "Pinch to zoom, drag to look around, double-tap to zoom in."),
        ]
        var y = r.y
        for (icon, text) in rows {
            c.sprite(icon, r.x, y, tint: icon.pixels.contains { $0 == Palette.text } ? Palette.text2 : nil)
            for line in wrap(text, width: r.w - 14) {
                c.text(line, r.x + 14, y, Palette.text)
                y += PixelFont.lineHeight
            }
            y += 5
        }
    }

    func drawSettings(_ g: Game) {
        let c = canvas
        let r = menuCard(g, title: "SETTINGS")
        let s = g.progress.settings
        let rows: [(Sprite, String, Bool)] = [(Sprites.sound, "SOUND", s.sound), (Sprites.haptic, "HAPTICS", s.haptics), (Sprites.glowIcon, "GLOW", s.glow)]
        var y = r.y
        for (j, (icon, name, on)) in rows.enumerated() {
            let row = Rect(r.x, y, r.w, 28)
            c.fill(row, g.isPressed(.setting(j)) ? Palette.panel3 : Palette.panel1)
            c.sprite(icon, row.x + 10, row.y + 10, tint: on ? Palette.white : Palette.muted)
            c.text(name, row.x + 26, row.y + 10, on ? Palette.white : Palette.muted)
            // A flat switch.
            let sw = Rect(row.maxX - 40, row.y + 8, 30, 12)
            c.fill(sw, on ? Palette.accent : Palette.panel3)
            c.fill(on ? sw.maxX - 12 : sw.x, sw.y, 12, 12, on ? Palette.white : Palette.muted)
            hit(row, .setting(j))
            y += 32
        }
        y += 10
        let confirming = g.time < g.ui.confirmResetUntil
        button(g, Rect(r.x, y, r.w, 28), confirming ? "TAP AGAIN TO WIPE EVERYTHING" : "RESET PROGRESS", .resetProgress, style: confirming ? .danger : .secondary)
        c.text("Reset wipes levels, stars and coins.", r.x, y + 34, Palette.muted)
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
