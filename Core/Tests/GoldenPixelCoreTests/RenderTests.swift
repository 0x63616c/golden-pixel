import XCTest
@testable import GoldenPixelCore

final class RenderTests: XCTestCase {
    /// The Duo's inner display renders at 2853 x 2007 px. At 6 device pixels per art pixel the
    /// canvas is 475 x 334 (2850 x 2004 px: 1.5 px spare per side). The board view fills the
    /// left and the panel takes the right.
    func testDuoLayoutFits() {
        let (w, h, s) = (Tuning.canvasWidth, Tuning.canvasHeight, Tuning.artScale)
        XCTAssertEqual(2853 / s, w); XCTAssertEqual(2007 / s, h)
        XCTAssertLessThan(2853 - w * s, s); XCTAssertLessThan(2007 - h * s, s)
        let L = Layout.make(width: w, height: h)
        XCTAssertEqual(L.board.x, 0); XCTAssertEqual(L.board.h, h)
        XCTAssertEqual(L.board.maxX, L.panel.x)
        XCTAssertEqual(L.panel.maxX, w)
        XCTAssertGreaterThanOrEqual(L.board.w, 300)
        let tall = Layout.make(width: h, height: w)
        XCTAssertFalse(tall.landscape)
        XCTAssertLessThanOrEqual(tall.board.maxY, tall.panel.y)
    }

    func testFontIsSevenPixelsTall() {
        XCTAssertEqual(PixelFont.capHeight, 7)
        let c = Canvas(width: 40, height: 12)
        c.text("H", 0, 0, Palette.white)
        var rows = Set<Int>()
        for y in 0..<12 { for x in 0..<40 where c.get(x, y) != Palette.black { rows.insert(y) } }
        XCTAssertEqual(rows, Set(0..<7))
        for s in ["0123456789", "1.2K", "7.4M", "999B", ":"] { XCTAssertGreaterThan(PixelFont.measure(s), 0) }
        XCTAssertNotNil(PixelFont.glyph("K")); XCTAssertNotNil(PixelFont.glyph("M"))
        let colon = Canvas(width: 8, height: 8)
        colon.text(":", 0, 0, Palette.white)
        XCTAssertTrue(colon.pixels.contains(Palette.white), "the colon has ink")
    }

    /// Board art pixel → canvas pixel at the camera's current (resting) zoom 1 view.
    func canvasPoint(_ g: Game, _ bx: Int, _ by: Int) -> Point {
        let o = g.ui.camera.origin, L = g.ui.layout
        return Point(L.board.x + Int(o.x) + bx, L.board.y + Int(o.y) + by)
    }

    func testUnrevealedCellsArePureBlackAwayFromTheGoldAndShards() {
        let g = Game(seed: 1)
        g.ui.started = true
        let r = Renderer()
        r.render(g)
        let b = g.board, L = g.ui.layout, cp = Tuning.cellPixels
        var checked = 0
        for y in 0..<b.size { for x in 0..<b.size where !b.revealed[b.index(x, y)] {
            let dg = hypot(Double(x - b.gold.x), Double(y - b.gold.y))
            guard dg > Tuning.goldGlowRadius + 1, !Fog.shardSensed(b, b.index(x, y)) else { continue }
            if g.balls.contains(where: { abs($0.x - Double(x)) < 2 && abs($0.y - Double(y)) < 2 }) { continue }
            for py in 0..<cp { for px in 0..<cp {
                let p = canvasPoint(g, x * cp + px, y * cp + py)
                guard L.board.contains(p) else { continue }
                XCTAssertEqual(r.canvas.get(p.x, p.y).rgbOnly, 0, "cell \(x),\(y)")
                checked += 1
            } }
        } }
        XCTAssertGreaterThan(checked, 1000)
    }

    /// Flat: a fully revealed block is one colour, edge to edge, whatever is around it.
    func testCellsAreFlat() {
        let g = Game(seed: 1)
        g.ui.started = true
        let b = g.board
        for i in b.revealed.indices { b.revealed[i] = true; b.revealedAt[i] = -10 }
        g.balls.removeAll(); g.particles.removeAll(); g.rings.removeAll()
        let r = Renderer()
        r.render(g)
        let cp = Tuning.cellPixels, L = g.ui.layout
        var checked = 0
        for y in 0..<b.size { for x in 0..<b.size {
            let i = b.index(x, y)
            guard b.kind[i] == .block || b.kind[i] == .wall, !b.rich[i] else { continue }
            let tl = canvasPoint(g, x * cp, y * cp), br = canvasPoint(g, x * cp + cp - 1, y * cp + cp - 1)
            guard L.board.contains(tl), L.board.contains(br) else { continue }
            var colours = Set<Pixel>()
            for py in 0..<cp { for px in 0..<cp { colours.insert(r.canvas.get(tl.x + px, tl.y + py).rgbOnly) } }
            XCTAssertEqual(colours.count, 1, "cell \(x),\(y)")
            let want = b.kind[i] == .wall ? Palette.wall : Palette.tier(Int(b.tier[i]))
            XCTAssertEqual(colours.first, want.rgbOnly)
            checked += 1
        } }
        XCTAssertGreaterThan(checked, 200)
    }

    /// Revealing dithers each cell in from black (no growing squares that leave specks).
    func testRevealDithersIn() {
        let g = Game(seed: 1)
        g.ui.started = true
        let b = g.board
        g.balls.removeAll()
        let i = b.kind.indices.first { b.kind[$0] == .block && !b.revealed[$0] && Fog.distanceToOpen(b, $0, limit: 5) == 4 }!
        b.revealed[i] = true
        b.revealedAt[i] = g.time - Fog.fadeTime / 2
        let r = Renderer()
        g.ui.camera.look(at: Double((i % b.size) * 10), Double((i / b.size) * 10))
        r.render(g)
        let tl = canvasPoint(g, (i % b.size) * 10, (i / b.size) * 10)
        var lit = 0
        for py in 0..<10 { for px in 0..<10 where r.canvas.get(tl.x + px, tl.y + py).rgbOnly != 0 { lit += 1 } }
        XCTAssertGreaterThan(lit, 30); XCTAssertLessThan(lit, 70)
    }

    func testPNGHasTheRightSignature() {
        let c = Canvas(width: 3, height: 2)
        let png = PNG.encode(c, scale: 2)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// The ball is a 5x5 circle centred on its own pixel, and its trail runs through past
    /// centre pixels, so the tail lines up with the middle of the ball.
    func testBallAndTrailAreCentred() {
        let g = Game(seed: 1)
        g.ui.started = true
        let b = g.board
        for i in b.revealed.indices { b.revealed[i] = true; b.revealedAt[i] = -10 }
        let cp = Double(Tuning.cellPixels)
        let sx = Double(b.spawn.x) + 0.37, sy = Double(b.spawn.y) + 0.61
        var ball = Ball(kind: .basic, x: sx, y: sy, vx: 1, vy: 0)
        let centre = Point(Int(sx * cp), Int(sy * cp))
        ball.trail = [centre, Point(centre.x - 3, centre.y), Point(centre.x - 6, centre.y)]
        g.balls = [ball]
        g.particles.removeAll(); g.rings.removeAll()
        let r = Renderer()
        r.render(g)
        func px(_ x: Int, _ y: Int) -> Pixel { let p = canvasPoint(g, x, y); return r.canvas.get(p.x, p.y).rgbOnly }
        let s = Sprites.ball(.basic)
        XCTAssertEqual(s.width, 5); XCTAssertEqual(s.height, 5)
        XCTAssertEqual(px(centre.x, centre.y), s.pixels[12]!.rgbOnly, "sprite centre on the ball's pixel")
        XCTAssertNil(s.pixels[0]); XCTAssertNil(s.pixels[4]); XCTAssertNil(s.pixels[20]); XCTAssertNil(s.pixels[24])
        for k in 0..<5 { XCTAssertNotNil(s.pixels[2 * 5 + k]); XCTAssertNotNil(s.pixels[k * 5 + 2]) }
        XCTAssertEqual(px(centre.x - 3, centre.y), BallKind.basic.shade.rgbOnly)
        XCTAssertEqual(px(centre.x - 6, centre.y), BallKind.basic.shade.rgbOnly)
    }

    /// Placing a ball: a ring wider than a fingertip around the held spot (the finger hides
    /// the ghost). Once you pull, the ring fades to nothing and four dots show in front of
    /// the ghost, all the same size.
    func testLaunchPreviewShowsAHoldRingThenFourEqualDots() {
        let g = Scenes.make("mid")
        g.ui.selected = .heavy
        let L = g.ui.layout, r = Renderer()
        let from = Point(L.board.x + L.board.w / 2, L.board.y + L.board.h / 2)
        let ink = BallKind.heavy.color.glowing(160), R = Tuning.holdRingRadius
        XCTAssertGreaterThan(R * 2, Tuning.minTouch * 2, "wider than a fingertip")

        // Held, not pulled yet: the ring, and no dots.
        g.ui.launch = LaunchDrag(from: from, to: from)
        r.render(g)
        for (dx, dy) in [(R, 0), (-R, 0), (0, R), (0, -R)] {
            XCTAssertEqual(r.canvas.get(from.x + dx, from.y + dy), ink, "ring at \(dx),\(dy)")
        }
        let s = max(1, Int(g.ui.camera.zoom.rounded(.down)))
        let dotX = { (j: Int) in from.x + Int((2.5 * Double(s) + 6 + Double(j * 4)).rounded()) }
        XCTAssertNotEqual(r.canvas.get(dotX(0), from.y), ink, "no dots until the pull")

        // Pulled left: it flies right, with four 2x2 dots on that side.
        g.ui.launch = LaunchDrag(from: from, to: Point(from.x - 30, from.y), pulledAt: g.time - Tuning.holdRingFade)
        r.render(g)
        XCTAssertEqual(Tuning.aimDots, 4)
        for j in 0..<Tuning.aimDots {
            for (dx, dy) in [(-1, -1), (0, -1), (-1, 0), (0, 0)] {
                XCTAssertEqual(r.canvas.get(dotX(j) + dx, from.y + dy), ink, "dot \(j)")
            }
            XCTAssertNotEqual(r.canvas.get(dotX(j) + 1, from.y), ink, "dot \(j) is 2 wide")
            XCTAssertNotEqual(r.canvas.get(dotX(j), from.y + 1), ink, "dot \(j) is 2 tall")
        }
        XCTAssertNotEqual(r.canvas.get(dotX(Tuning.aimDots), from.y), ink, "and no fifth")
        // The ring is gone by then; halfway through the fade it is partly dithered away.
        let ringInk = { () -> Int in
            var n = 0
            for y in (from.y - R - 1)...(from.y + R + 1) { for x in (from.x - R - 1)...(from.x + R + 1) {
                let d = hypot(Double(x - from.x), Double(y - from.y))
                if abs(d - Double(R)) < 0.5, r.canvas.get(x, y) == ink { n += 1 }
            } }
            return n
        }
        XCTAssertEqual(ringInk(), 0, "the ring has faded to nothing")
        g.ui.launch?.pulledAt = nil
        r.render(g)
        let full = ringInk()
        XCTAssertGreaterThan(full, 150)
        g.ui.launch?.pulledAt = g.time - Tuning.holdRingFade / 2
        r.render(g)
        XCTAssertGreaterThan(ringInk(), full / 4)
        XCTAssertLessThan(ringInk(), full * 3 / 4, "half faded, as a dither")
    }

    /// Big boards only draw what the camera sees, and a level starts with the spawn in view.
    func testLevelsStartLookingAtTheSpawn() {
        for level in [1, 4, 7] {
            var p = Progress(); p.level = level
            let g = Game(progress: p)
            g.ui.started = true
            Renderer().render(g)
            let cp = Double(Tuning.cellPixels)
            let v = g.ui.camera.toView((Double(g.board.spawn.x) + 0.5) * cp, (Double(g.board.spawn.y) + 0.5) * cp)
            XCTAssertTrue(v.x > 0 && v.y > 0 && v.x < Double(g.ui.layout.board.w) && v.y < Double(g.ui.layout.board.h), "level \(level)")
            XCTAssertGreaterThan(g.board.pixelSize, g.ui.layout.board.w, "the level is bigger than the screen")
        }
    }

    /// The menu logo is a hand-built wordmark: every letter has a glyph, the two lines lock up
    /// to (nearly) one width, the golden pixel is the only glowing part of PiXEL, and it all
    /// sits clear of the screen's corners.
    func testMenuLogoLocksUp() {
        let r = Renderer()
        for line in Renderer.logoLines {
            for ch in line.text { XCTAssertNotNil(Sprites.logoGlyph(ch), "no logo glyph for \(ch)") }
        }
        let widths = Renderer.logoLines.map { r.logoWidth($0) }
        XCTAssertLessThanOrEqual((widths.max() ?? 0) - (widths.min() ?? 0), 2, "logo lines \(widths)")
        let dot = Sprites.logoGlyph("i")!
        XCTAssertEqual(dot.pixels.filter { $0?.glow == 255 }.count, 4, "the i is dotted with a 2x2 golden pixel")
        let g = Scenes.make("menu")
        r.render(g)
        let L = g.ui.layout, size = r.logoSize
        XCTAssertGreaterThanOrEqual((L.width - size.w) / 2 - Renderer.logoOutline, Tuning.cornerRadius)
        // Only three buttons on the menu: play, how to play, settings.
        let actions = g.ui.hits.map(\.action).filter { $0 != .none }
        XCTAssertEqual(actions.count, 3, "\(actions)")
    }
}
