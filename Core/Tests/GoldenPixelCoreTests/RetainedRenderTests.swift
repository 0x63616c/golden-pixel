import XCTest
@testable import GoldenPixelCore

/// The renderer keeps the board canvas, the panel and the last frame between frames, and
/// repaints only what changed. What it must never do is show a stale pixel, so every frame it
/// draws here is checked, pixel for pixel and hit region for hit region, against a renderer
/// made for that one frame, which has nothing kept to get wrong.
final class RetainedRenderTests: XCTestCase {
    /// Draws the game with the kept renderer and with a brand-new one, and compares.
    func check(_ g: Game, _ r: Renderer, _ d: Display, _ what: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        r.render(g)
        let kept = r.canvas.pixels, keptHits = g.ui.hits
        let fresh = Renderer(display: d)
        fresh.render(g)
        if kept != fresh.canvas.pixels {
            let w = d.width
            let i = zip(kept, fresh.canvas.pixels).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? 0
            XCTFail("\(what()): stale pixel at \(i % w),\(i / w)", file: file, line: line)
        }
        XCTAssertEqual(keptHits.map { "\($0)" }, g.ui.hits.map { "\($0)" }, "\(what()): hit regions", file: file, line: line)
    }

    /// Runs a game through what changes the screen, checking every frame: a pan, a pinch
    /// through fractional zoom to a rest zoom, a shake, the panel, and each overlay opening
    /// and closing. `long` adds every rest zoom, a resize, the gold breaking, the next level,
    /// a restart and the menu.
    func play(_ name: String, _ g: Game, _ r: Renderer, _ d: Display, long: Bool) {
        var frame = 0
        func step(_ n: Int = 1, dt: Double = 1.0 / 60) {
            for _ in 0..<n {
                Scenes.script(name, g, frame: frame)
                g.update(dt)
                g.events.removeAll()
                check(g, r, d, "\(name) frame \(frame)")
                frame += 1
            }
        }
        func mid() -> Point { let L = g.ui.layout; return Point(L.board.x + L.board.w / 2, L.board.y + L.board.h / 2) }
        func zoom(to z: Double) {
            for _ in 0..<12 where g.ui.camera.nearestLevel(g.ui.camera.zoom) != z {
                g.handle(.pinch(center: mid(), factor: g.ui.camera.zoom < z ? 1.3 : 1 / 1.3, dx: 1, dy: -1))
                step()
            }
            g.handle(.pinchEnded)
            step(2, dt: 1.0 / 20)
            g.ui.camera.pan(31, -17); g.shake = 1; step()
        }
        step(2)
        if g.ui.screen != .game { g.perform(.play); step() }
        g.handle(.down(mid())); g.handle(.drag(from: mid(), to: Point(mid().x + 7, mid().y - 5))); step()
        g.handle(.release(mid()))
        g.ui.camera.pan(-63, 41); step()
        for z in long ? [2.0, 4.0, 3.0, 0.5, 1.0] : [2.0] { zoom(to: z) }
        g.progress.money += 4000
        g.perform(.ballRow(.fast)); step()
        g.perform(.buyBall(.basic)); step()
        g.perform(.ballRow(g.ui.selected)); step()
        g.perform(.closeSheet)
        g.progress.shards += 4
        g.perform(.openSkills); step()
        if let s = SkillNode.all.first(where: { Skills.check($0.id, ranks: g.progress.skillRanks, shards: g.progress.shards) == .ok }) {
            g.perform(.buySkill(s.id)); step()
        }
        g.perform(.closeSkills); step()
        g.perform(.pause); step()
        g.perform(.resume)
        g.handle(.longPress(Point(mid().x + 12, mid().y + 6))); step()
        g.handle(.tap(Point(g.ui.layout.panelContent.x + 14, g.ui.layout.panelContent.y + 12))); step()
        guard long else { return }

        r.resize(to: Device.se.display); check(g, r, Device.se.display, "\(name) resized")
        r.resize(to: d); step()
        // The gold breaks: the whole level is revealed in a sweep, then the next one starts.
        g.clearTimer = nil
        let gold = g.board.index(g.board.gold.x, g.board.gold.y)
        if g.board.kind[gold] == .gold {
            Scenes.exposeGold(g); step(2)
            g.board.hp[gold] = g.board.maxHP[gold] * 0.4; step()
            g.damageCell(gold, g.board.hp[gold] + 1)
        }
        step(8, dt: 1.0 / 20)
        g.clearTimer = 0.01
        step(3, dt: 1.0 / 20)
        g.restartLevel(); step(2, dt: 1.0 / 20)
        g.progress.maxLevel = max(g.progress.maxLevel, 3)
        g.pickLevel(2); g.pickLevel(2); step(2, dt: 1.0 / 20)
        g.perform(.openMenu); step()
        g.perform(.play); step(2)
    }

    func testEverySceneMatchesAFreshRendererOnTheDuo() {
        let d = Device.duo.display
        // One renderer for every scene, so what one game left behind meets the next.
        let r = Renderer(display: d)
        for name in Scenes.names { play(name, Scenes.make(name), r, d, long: name == "mid" || name == "late") }
    }

    func testOtherScreensMatchAFreshRenderer() {
        let portrait = Display.fit(pixelWidth: Device.duo.pixelHeight, pixelHeight: Device.duo.pixelWidth, pointScale: 3, safe: (0, 0, 0, 34))
        for (title, d) in Device.all.dropFirst().map({ ($0.name, $0.display) }) + [("duo portrait", portrait)] {
            play("\(title) goldhunt", Scenes.make("goldhunt"), Renderer(display: d), d, long: false)
        }
    }

    /// A save restored into a new game is drawn right by a renderer that was showing another.
    func testARestoredSaveMatchesAFreshRenderer() {
        let d = Device.duo.display
        let r = Renderer(display: d)
        let g = Scenes.make("late")
        for i in 0..<3 { g.update(1.0 / 60); check(g, r, d, "before \(i)") }
        let restored = Game(seed: 9)
        restored.load(g.saveFile())
        restored.ui.screen = .game
        for i in 0..<4 { restored.update(1.0 / 60); check(restored, r, d, "restored \(i)") }
        for i in 0..<2 { g.update(1.0 / 60); check(g, r, d, "back \(i)") }
    }

    /// A cell written straight into the board's arrays, as the simulation, the fog, a restored
    /// save and tests all do, shows on the next frame with no one telling the renderer.
    func testCellsChangedBehindTheRenderersBackAreRedrawn() {
        let d = Device.duo.display
        let r = Renderer(display: d)
        let g = Scenes.make("mid")
        check(g, r, d, "before")
        let b = g.board
        let i = b.index(b.spawn.x + 1, b.spawn.y)
        b.kind[i] = .shard; b.hp[i] = 3; b.maxHP[i] = 3
        check(g, r, d, "a shard appears")
        b.kind[i] = .block; b.rich[i] = true
        check(g, r, d, "a rich block")
        b.hp[i] = 1
        check(g, r, d, "damaged")
        b.hitAt[i] = g.time
        check(g, r, d, "hit")
        for j in b.revealed.indices { b.revealed[j] = false }
        check(g, r, d, "the fog comes back")
        for j in b.revealed.indices { b.revealed[j] = true; b.revealedAt[j] = g.time - 0.1 }
        check(g, r, d, "and lifts, dithering")
        g.board = LevelGen.make(level: 5, at: g.time)
        g.centreCamera()
        check(g, r, d, "another board")
    }

    /// Looks that change with the clock alone: a hit flashes its cell white for one frame and
    /// then the cell is itself again, with nothing written to the board in between.
    func testAHitFlashesForOneFrameAndGoes() {
        let d = Device.duo.display
        let r = Renderer(display: d)
        let g = Scenes.make("mid")
        g.balls.removeAll(); g.particles.removeAll()
        r.render(g)
        let b = g.board, cp = Tuning.cellPixels
        let o = g.ui.camera.origin, L = g.ui.layout
        func middle(_ i: Int) -> Point { Point(L.board.x + Int(o.x) + (i % b.size) * cp + 4, L.board.y + Int(o.y) + (i / b.size) * cp + 4) }
        guard let i = b.kind.indices.first(where: { b.kind[$0] == .block && !b.rich[$0] && Fog.coverage(b, $0, at: g.time) >= 1
            && L.board.inset(cp).contains(middle($0)) }) else { return XCTFail("no block in view") }
        let at = middle(i)
        let colour = r.canvas.get(at.x, at.y)
        XCTAssertNotEqual(colour.rgbOnly, Palette.white.rgbOnly)
        b.hitAt[i] = g.time
        check(g, r, d, "hit")
        XCTAssertEqual(r.canvas.get(at.x, at.y), Palette.white.glowing(200), "the hit cell flashes")
        g.update(1.0 / 30)
        check(g, r, d, "after")
        XCTAssertEqual(r.canvas.get(at.x, at.y), colour, "and is itself again a frame later")
    }

    /// `changed` may only say no when the frame really is the last one again, and it does say
    /// no for nearly every frame that is (the open tree, the pause card), which is what lets
    /// the shell leave those frames off the GPU.
    func testUnchangedFramesAreReportedAndOnlyThose() {
        for (name, stands) in [("tree", true), ("pause", true), ("mid", false), ("menu", false)] {
            let g = Scenes.make(name)
            let r = Renderer(display: Device.duo.display)
            r.render(g)
            var last = r.canvas.pixels, reported = 0, repeated = 0
            for frame in 0..<120 {
                g.update(1.0 / 120)
                r.render(g)
                if r.canvas.pixels == last { repeated += 1 }
                if !r.changed {
                    reported += 1
                    XCTAssertEqual(r.canvas.pixels, last, "\(name) frame \(frame) was reported unchanged")
                }
                last = r.canvas.pixels
            }
            if stands { XCTAssertGreaterThan(repeated, 60, "\(name) mostly stands still") }
            XCTAssertGreaterThanOrEqual(reported * 10, repeated * 9, "\(name): repeated frames reported unchanged")
        }
    }

    /// The frame is not cleared on the game screen, because the board and the panel write all
    /// of it: true of the layout on every screen, both ways up.
    func testTheBoardAndThePanelFillTheFrame() {
        for dev in Device.all {
            let d = dev.display
            XCTAssertTrue(Layout.make(width: d.width, height: d.height, insets: d.insets, corner: d.corner).fills, dev.name)
            XCTAssertTrue(Layout.make(width: d.height, height: d.width, insets: d.insets, corner: d.corner).fills, "\(dev.name) portrait")
        }
        var odd = Layout.make(width: 300, height: 200)
        odd.panel.w -= 1
        XCTAssertFalse(odd.fills)
    }

    func testBoardCountsWritesToItsCellsAndItsFog() {
        let b = LevelGen.make(level: 1)
        var v = b.fogVersion
        b.kind[0] = .empty
        XCTAssertNotEqual(b.fogVersion, v); v = b.fogVersion
        b.revealed[3] = true
        XCTAssertNotEqual(b.fogVersion, v); v = b.fogVersion
        Fog.reveal(b, b.spawn.x + 6, b.spawn.y, radius: 2, at: 0)
        XCTAssertNotEqual(b.fogVersion, v); v = b.fogVersion
        b.hp[0] = 2; b.hitAt[0] = 1
        XCTAssertEqual(b.fogVersion, v, "only cells and fog count")
    }

    /// The canvas journal: what is drawn while recording comes back off exactly.
    func testCanvasRewindRestoresWhatWasDrawnOver() {
        let c = Canvas(width: 24, height: 16)
        c.fill(2, 2, 9, 9, Palette.gold)
        c.set(20, 3, Palette.mint)
        let before = c.pixels
        c.recording = true
        c.fill(0, 0, 12, 6, Palette.white)
        c.fill(4, 4, 30, 30, Palette.accent)
        c.ring(10, 8, 5, Palette.danger)
        c.line(0, 15, 23, 0, Palette.mint)
        c.set(20, 3, Palette.black); c.set(20, 3, Palette.white)
        c.sprite(Sprites.ball(.basic), 18, 10)
        c.recording = false
        XCTAssertNotEqual(c.pixels, before)
        c.rewind()
        XCTAssertEqual(c.pixels, before)
        c.set(1, 1, Palette.white)
        c.rewind()
        XCTAssertEqual(c.get(1, 1), Palette.white, "drawing outside a recording stays")
    }
}
