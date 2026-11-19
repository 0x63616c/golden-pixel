import XCTest
@testable import GoldenPixelCore

/// The grid check: every frame is one art-pixel canvas shown at one whole scale, so after
/// upscaling, every N x N block is a single solid colour. The same check runs on real
/// simulator screenshots in CI (tools/gridcheck.py).
final class GridTests: XCTestCase {
    /// Nearest-neighbour upscale, as the Metal present pass does it.
    func upscale(_ c: Canvas, _ n: Int) -> [Pixel] {
        var out = [Pixel](repeating: 0, count: c.width * n * c.height * n)
        for y in 0..<(c.height * n) { for x in 0..<(c.width * n) { out[y * c.width * n + x] = c.pixels[(y / n) * c.width + x / n] } }
        return out
    }

    func assertBlocksSolid(_ px: [Pixel], width: Int, height: Int, n: Int, x0: Int = 0, y0: Int = 0, _ name: String) {
        var bad = 0
        var by = y0
        while by + n <= height {
            var bx = x0
            while bx + n <= width {
                let v = px[by * width + bx] & 0x00ff_ffff
                outer: for y in by..<(by + n) { for x in bx..<(bx + n) where px[y * width + x] & 0x00ff_ffff != v { bad += 1; break outer } }
                bx += n
            }
            by += n
        }
        XCTAssertEqual(bad, 0, "\(name): \(bad) blocks of \(n)x\(n) are not one colour")
    }

    func testEveryStagedSceneIsOnTheGrid() {
        let n = Tuning.artScale
        for name in Scenes.names {
            let g = Scenes.make(name)
            let r = Renderer(width: name == "portrait" ? Tuning.canvasHeight : Tuning.canvasWidth,
                             height: name == "portrait" ? Tuning.canvasWidth : Tuning.canvasHeight)
            for frame in 0..<3 {
                r.render(g)
                let c = r.canvas
                assertBlocksSolid(upscale(c, n), width: c.width * n, height: c.height * n, n: n, "\(name) frame \(frame)")
                g.update(1.0 / 60)
            }
        }
    }

    /// Zoomed in at rest, every board art pixel is an exact zoom x zoom block of canvas pixels
    /// aligned to the board's origin, so nothing on the board is at a sub-grid offset.
    func testZoomedBoardIsWholeBlocks() {
        let g = Scenes.make("zoom")
        XCTAssertTrue(g.ui.camera.isAtRest)
        let z = Int(g.ui.camera.zoom)
        XCTAssertGreaterThan(z, 1)
        let r = Renderer()
        g.shake = 0
        // Board-only check: drop the fixed UI that floats over the board (combo, banners).
        g.combo = 0; g.banners.removeAll()
        r.render(g)
        let L = g.ui.layout, o = g.ui.camera.origin
        let ox = ((Int(o.x) % z) + z) % z, oy = ((Int(o.y) % z) + z) % z
        // Crop the board view and check zoom x zoom blocks from the board's phase.
        var crop = [Pixel](repeating: 0, count: L.board.w * L.board.h)
        for y in 0..<L.board.h { for x in 0..<L.board.w { crop[y * L.board.w + x] = r.canvas.get(L.board.x + x, L.board.y + y) } }
        // The HUD zoom badge sits on top of the board; blank it out.
        for y in 0..<14 { for x in (L.board.w - 30)..<L.board.w { crop[y * L.board.w + x] = 0 } }
        assertBlocksSolid(crop, width: L.board.w, height: L.board.h, n: z, x0: ox, y0: oy, "zoom \(z)")
    }

    /// Balls, sparks and text land on whole art pixels: the canvas has no colours outside the
    /// palette's own entries blended (no anti-aliasing), checked by counting distinct colours.
    func testNoAntiAliasing() {
        let g = Scenes.make("mid")
        let r = Renderer()
        r.render(g)
        let colours = Set(r.canvas.pixels.map { $0 & 0x00ff_ffff })
        XCTAssertLessThan(colours.count, 96, "a smoothed frame would have hundreds of in-between colours")
    }
}
