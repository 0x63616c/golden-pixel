import XCTest
@testable import GoldenPixelCore

final class RenderTests: XCTestCase {
    /// The Duo's inner display renders at 2853 x 2007 px. At 6 device pixels per art pixel the
    /// canvas is 475 x 334 (2850 x 2004 px: 1.5 px spare per side), the 41 x 41 board of 8x8
    /// cells (328 px) fits the height, and the panel takes the rest of the width.
    func testDuoLayoutFits() {
        let (w, h, s) = (Tuning.canvasWidth, Tuning.canvasHeight, Tuning.artScale)
        XCTAssertEqual(2853 / s, w); XCTAssertEqual(2007 / s, h)
        XCTAssertLessThan(2853 - w * s, s); XCTAssertLessThan(2007 - h * s, s)
        let L = Layout.make(width: w, height: h, collapsed: false)
        XCTAssertEqual(L.board.w, Tuning.boardCells * Tuning.cellPixels)
        XCTAssertEqual(L.board.w, 328)
        XCTAssertGreaterThanOrEqual(L.board.y, 0)
        XCTAssertLessThanOrEqual(L.board.maxY, h)
        XCTAssertLessThanOrEqual(L.board.maxX, L.panel.x)
        XCTAssertEqual(L.panel.maxX, w)
        XCTAssertGreaterThanOrEqual(L.panel.w, 136, "room for three 44-px cards")
        let tall = Layout.make(width: h, height: w, collapsed: false)
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
        for s in ["0123456789", "1.2K", "7.4M", "999B"] { XCTAssertGreaterThan(PixelFont.measure(s), 0) }
        XCTAssertNotNil(PixelFont.glyph("K")); XCTAssertNotNil(PixelFont.glyph("M"))
    }

    func testUnrevealedCellsArePureBlackAwayFromTheGold() {
        let g = Game(seed: 1)
        g.ui.started = true
        let r = Renderer()
        r.render(g)
        let b = g.board, L = g.ui.layout, cp = Tuning.cellPixels
        for y in 0..<b.size { for x in 0..<b.size where !b.revealed[b.index(x, y)] {
            let dg = hypot(Double(x - b.gold.x), Double(y - b.gold.y))
            guard dg > Tuning.goldGlowRadius + 1 else { continue }
            if g.balls.contains(where: { abs($0.x - Double(x)) < 2 && abs($0.y - Double(y)) < 2 }) { continue }
            for py in 0..<cp { for px in 0..<cp {
                XCTAssertEqual(r.canvas.get(L.board.x + x * cp + px, L.board.y + y * cp + py) & 0x00ff_ffff, 0, "cell \(x),\(y)")
            } }
        } }
    }

    /// Packed cells have no edges: shading only appears on faces open to dug space, so the
    /// seam between two solid neighbours is flat colour on both sides.
    func testNoLinesBetweenPackedCells() {
        let g = Game(seed: 1)
        g.ui.started = true
        let b = g.board
        for i in b.revealed.indices { b.revealed[i] = true; b.revealedAt[i] = -10 }
        let r = Renderer()
        r.render(g)
        let L = g.ui.layout, cp = Tuning.cellPixels
        var checked = 0
        for y in 1..<(b.size - 1) { for x in 1..<(b.size - 2) {
            let i = b.index(x, y), j = b.index(x + 1, y)
            guard b.kind[i] == .block, b.kind[j] == .block, !b.rich[i], !b.rich[j],
                  b.hp[i] == b.maxHP[i], b.hp[j] == b.maxHP[j] else { continue }
            if g.balls.contains(where: { abs($0.x - Double(x + 1)) < 2 && abs($0.y - Double(y)) < 2 }) { continue }
            let seamY = L.board.y + y * cp + cp / 2
            let left = r.canvas.get(L.board.x + x * cp + cp - 1, seamY), right = r.canvas.get(L.board.x + (x + 1) * cp, seamY)
            XCTAssertEqual(left & 0x00ff_ffff, Palette.tiers[Int(b.tier[i])] & 0x00ff_ffff, "no shadow on a covered right face")
            XCTAssertEqual(right & 0x00ff_ffff, Palette.tiers[Int(b.tier[j])] & 0x00ff_ffff, "no highlight on a covered left face")
            checked += 1
        } }
        XCTAssertGreaterThan(checked, 100)
    }

    /// One light, top-left: a block with open space above has a highlight on its top row, and
    /// a block with open space below has a shadow on its bottom row.
    func testExposedFacesAreLitFromTheTopLeft() {
        let g = Game(seed: 1)
        g.ui.started = true
        let b = g.board
        for i in b.revealed.indices { b.revealed[i] = true; b.revealedAt[i] = -10 }
        g.balls.removeAll()
        let r = Renderer()
        r.render(g)
        let L = g.ui.layout, cp = Tuning.cellPixels
        var lit = 0, shaded = 0
        for y in 1..<(b.size - 1) { for x in 1..<(b.size - 1) {
            let i = b.index(x, y)
            guard b.kind[i] == .block, !b.rich[i], b.hp[i] == b.maxHP[i] else { continue }
            let t = Int(b.tier[i])
            let mid = L.board.x + x * cp + cp / 2
            if b.kindAt(x, y - 1) == .empty {
                XCTAssertEqual(r.canvas.get(mid, L.board.y + y * cp) & 0x00ff_ffff, Palette.tiersLight[t] & 0x00ff_ffff); lit += 1
            }
            if b.kindAt(x, y + 1) == .empty {
                XCTAssertEqual(r.canvas.get(mid, L.board.y + y * cp + cp - 1) & 0x00ff_ffff, Palette.tiersDark[t] & 0x00ff_ffff); shaded += 1
            }
        } }
        XCTAssertGreaterThan(lit, 0); XCTAssertGreaterThan(shaded, 0)
    }

    func testPNGHasTheRightSignature() {
        let c = Canvas(width: 3, height: 2)
        let png = PNG.encode(c, scale: 2)
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
