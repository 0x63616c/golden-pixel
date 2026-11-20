import XCTest
@testable import GoldenPixelCore

/// The Duo's inner screen has heavily rounded corners: nothing you press may sit in them, and
/// everything you press is at least `Tuning.minTouch` (22 art px = 44 pt) square. The same
/// holds on every other screen (`Device.all`), where the system's insets (the Dynamic Island's
/// side, the home indicator) are out of bounds too.
final class UISafetyTests: XCTestCase {
    /// Backgrounds that fill the screen or the board: pressing them anywhere is fine.
    func isBackground(_ a: Action) -> Bool {
        switch a {
        case .board, .tree, .panel, .none, .closeSheet: return true
        default: return false
        }
    }

    func testCornerTestRejectsTheCorners() {
        let L = Layout.make(width: Tuning.canvasWidth, height: Tuning.canvasHeight)
        XCTAssertFalse(L.onScreen(2, 2))
        XCTAssertFalse(L.onScreen(L.width - 3, 3))
        XCTAssertFalse(L.onScreen(4, L.height - 4))
        XCTAssertTrue(L.onScreen(L.width / 2, 0))
        XCTAssertTrue(L.onScreen(Tuning.cornerRadius, Tuning.cornerRadius))
        XCTAssertFalse(L.safe(Rect(L.width - 30, 1, 29, 18)), "the old skills close button")
    }

    /// A renderer for every screen the layout is built for (`Device.all`), and the bare Duo
    /// canvas (no insets) the other tests draw on.
    func screens() -> [(name: String, renderer: Renderer)] {
        [("canvas", Renderer())] + Device.all.map { ($0.name, Renderer(display: $0.display)) }
    }

    func testEveryButtonIsInTheSafeAreaOutOfTheCornersAndBigEnough() {
        let screens = screens()
        for name in Scenes.names where name != "portrait" {
            let g = Scenes.make(name)
            for (screen, r) in screens {
                r.render(g)
                let L = g.ui.layout
                for h in g.ui.hits where !isBackground(h.action) {
                    if case .selectSkill = h.action {
                        // Tree nodes pan with the map; they only need to be big enough.
                    } else {
                        XCTAssertTrue(L.safe(h.rect), "\(screen) \(name): \(h.action) at \(h.rect) is outside the safe area or in a rounded corner")
                    }
                    if h.info.isEmpty {
                        XCTAssertGreaterThanOrEqual(min(h.rect.w, h.rect.h), Tuning.minTouch, "\(screen) \(name): \(h.action) at \(h.rect) is too small")
                    }
                }
            }
        }
    }

    /// Cards (the ball sheet, pause, restart, how to play, settings) and the things you can
    /// only read (coins, shards) sit wholly inside the safe area on every screen.
    func testEveryCardIsInsideTheSafeArea() {
        let screens = screens()
        for name in ["sheet", "pause", "restart", "howto", "settings", "tree", "late", "full"] {
            let g = Scenes.make(name)
            for (screen, r) in screens {
                r.render(g)
                let L = g.ui.layout
                let whole = Rect(0, 0, L.width, L.height)
                let cards = g.ui.hits.filter { $0.action == .none && $0.rect != whole }
                if name != "late" && name != "full" { XCTAssertFalse(cards.isEmpty, "\(screen) \(name): no card") }
                for h in cards {
                    XCTAssertTrue(L.safe(h.rect), "\(screen) \(name): \(h.rect) is outside the safe area \(L.safeArea)")
                }
            }
        }
    }

    /// With every ball type unlocked, each one still has its own touch-sized row in the panel
    /// on every screen, none overlapping.
    func testEveryBallHasARowOnEveryScreen() {
        let g = Scenes.make("full")
        XCTAssertEqual(g.mods.unlocked.count, BallKind.allCases.count)
        for (screen, r) in screens() {
            r.render(g)
            let L = g.ui.layout
            var rows: [Rect] = []
            for k in BallKind.allCases {
                guard let h = g.ui.hits.last(where: { $0.action == .ballRow(k) }) else { XCTFail("\(screen): no row for \(k)"); continue }
                let A = L.panelContent
                XCTAssertTrue(h.rect.x >= A.x && h.rect.y >= A.y && h.rect.maxX <= A.maxX && h.rect.maxY <= A.maxY,
                              "\(screen): \(k) row \(h.rect) leaves the panel's safe part \(A)")
                XCTAssertGreaterThanOrEqual(min(h.rect.w, h.rect.h), Tuning.minTouch, "\(screen): \(k)")
                for o in rows { XCTAssertEqual(o.intersection(h.rect).w * o.intersection(h.rect).h, 0, "\(screen): \(k) overlaps another row") }
                rows.append(h.rect)
            }
        }
    }

    /// Under the system's insets the panel is only its background: no text or tile runs out
    /// from the safe area, and nothing spills out of a ball row into the gaps around it.
    func testNothingInThePanelLeavesItsRowOrTheSafeArea() {
        for name in ["start", "mid", "late", "full"] {
            let g = Scenes.make(name)
            g.banners.removeAll()
            for (screen, r) in screens() {
                r.render(g)
                let L = g.ui.layout, P = L.panel, A = L.panelContent
                let rows = g.ui.hits.compactMap { h -> Rect? in if case .ballRow = h.action { return h.rect } else { return nil } }
                let top = rows.map(\.y).min() ?? P.maxY
                for y in P.y..<P.maxY { for x in P.x..<P.maxX {
                    let inSafe = x >= A.x && x < A.maxX && y >= A.y && y < A.maxY
                    // Below the header, everything outside a row is background.
                    let checked = !inSafe || (y >= top && !rows.contains { $0.contains(Point(x, y)) })
                    if checked { XCTAssertEqual(r.canvas.get(x, y), Palette.panel0, "\(screen) \(name): \(x),\(y)") }
                } }
            }
        }
    }

    /// A card too tall for the screen scrolls: a drag anywhere on its body moves it, it stops
    /// at both ends, the header stays put, and only controls that show can be pressed.
    func testATallCardScrolls() {
        let r = Renderer(display: Device.pro.display)
        let g = Scenes.make("menu")
        g.perform(.howTo)
        r.render(g)
        guard let area = g.ui.scrollArea else { return XCTFail("how to play fits the phone without scrolling?") }
        XCTAssertGreaterThan(g.ui.scrollMax, 0)
        XCTAssertEqual(g.ui.scroll, 0)
        XCTAssertTrue(g.ui.layout.safe(area))
        let back = g.ui.hits.last { $0.action == .backToMenu }!.rect
        let before = r.canvas.pixels
        let p = Point(area.x + area.w / 2, area.y + area.h / 2)
        g.handle(.down(p))
        g.handle(.drag(from: p, to: Point(p.x, p.y - 40)))
        g.handle(.release(Point(p.x, p.y - 40)))
        XCTAssertEqual(g.ui.scroll, 40)
        r.render(g)
        XCTAssertNotEqual(r.canvas.pixels, before, "the content moved")
        XCTAssertEqual(g.ui.hits.last { $0.action == .backToMenu }!.rect, back, "the header stays put")
        // Past the end: it stops with the last line showing.
        g.handle(.down(p))
        g.handle(.drag(from: p, to: Point(p.x, p.y - 4000)))
        g.handle(.release(Point(p.x, p.y - 4000)))
        r.render(g)
        XCTAssertEqual(g.ui.scroll, g.ui.scrollMax)
        g.handle(.down(p))
        g.handle(.drag(from: p, to: Point(p.x, p.y + 4000)))
        g.handle(.release(Point(p.x, p.y + 4000)))
        XCTAssertEqual(g.ui.scroll, 0)
        // Leaving and coming back starts at the top again.
        g.ui.scroll = 25
        g.perform(.backToMenu)
        g.perform(.howTo)
        XCTAssertEqual(g.ui.scroll, 0)
    }

    /// On the shortest screen the settings card scrolls too. Rows stay pressable, a drag that
    /// starts on a row scrolls instead of toggling it, and every control can be reached.
    func testScrollingSettingsKeepsEveryControlReachable() {
        let r = Renderer(display: Device.mini.display)
        let g = Scenes.make("menu")
        g.perform(.settings)
        r.render(g)
        guard let area = g.ui.scrollArea else { return XCTFail("settings fits the smallest phone without scrolling?") }
        let sound = g.progress.settings.sound
        let row = g.ui.hits.last { $0.action == .setting(0) }!.rect
        let p = Point(row.x + row.w / 2, row.y + row.h / 2)
        g.handle(.down(p))
        g.handle(.drag(from: p, to: Point(p.x, p.y - 4000)))
        g.handle(.release(Point(p.x, p.y - 4000)))
        XCTAssertEqual(g.progress.settings.sound, sound, "a drag is not a tap")
        XCTAssertEqual(g.ui.scroll, g.ui.scrollMax)
        r.render(g)
        // Scrolled to the end, the last control shows whole.
        let reset = g.ui.hits.last { $0.action == .resetProgress }
        XCTAssertNotNil(reset, "RESET PROGRESS can be reached")
        for h in g.ui.hits where !isBackground(h.action) && h.action != .backToMenu {
            let v = h.rect.intersection(area)
            XCTAssertEqual(v, h.rect, "\(h.action) is pressable only where it shows")
            XCTAssertGreaterThanOrEqual(min(h.rect.w, h.rect.h), Tuning.minTouch, "\(h.action)")
        }
        // A tap still toggles.
        g.ui.scroll = 0
        r.render(g)
        let top = g.ui.hits.last { $0.action == .setting(0) }!.rect
        g.handle(.down(Point(top.x + 10, top.y + 10)))
        g.handle(.tap(Point(top.x + 10, top.y + 10), time: 1))
        XCTAssertNotEqual(g.progress.settings.sound, sound)
    }

    /// Nothing scrolls on the Duo: every card fits its screen.
    func testNothingScrollsOnTheDuo() {
        for r in [Renderer(), Renderer(display: Device.duo.display)] {
            for name in ["howto", "settings"] {
                let g = Scenes.make(name)
                r.render(g)
                XCTAssertNil(g.ui.scrollArea, name)
                XCTAssertEqual(g.ui.scrollMax, 0, name)
            }
        }
    }

    /// The menu keeps its three buttons, and the whole logo, on every screen.
    func testTheMenuFitsEveryScreen() {
        let g = Scenes.make("menu")
        for (screen, r) in screens() {
            r.render(g)
            let L = g.ui.layout
            let buttons = g.ui.hits.filter { $0.action != .none }
            XCTAssertEqual(buttons.count, 3, screen)
            // The logo is the only thing in pure white above the hero button: its top row
            // must be on screen, below the top of the safe area.
            let hero = g.ui.hits.last { $0.action == .play }!.rect
            XCTAssertGreaterThanOrEqual(hero.y - L.safeArea.y, r.logoSize(lineGap: 4).h + 6, "\(screen): no room for the logo above PLAY")
        }
    }

    /// The panel's own corners are empty: just its background colour.
    func testNothingIsDrawnInThePanelsCorners() {
        for name in ["start", "mid", "late"] {
            let g = Scenes.make(name)
            g.banners.removeAll()
            let r = Renderer()
            r.render(g)
            let L = g.ui.layout
            for y in 0..<L.height { for x in L.panel.x..<L.width where !L.onScreen(x, y) || !L.onScreen(x + 1, y + 1) {
                XCTAssertEqual(r.canvas.get(x, y), Palette.panel0, "\(name) \(x),\(y)")
            } }
        }
    }
    /// The build label shows on the menu and the settings card, in muted type, clear of the
    /// rounded corners and of every button.
    func testBuildLabelIsDrawnClearOfCornersAndButtons() {
        for name in ["menu", "settings"] {
            let a = Scenes.make(name), b = Scenes.make(name)
            XCTAssertFalse(a.buildLabel.isEmpty, "\(name): staged scenes carry a sample label")
            // Same length, different glyphs: the layout is identical, so only the label differs.
            b.buildLabel = "9.9.9 (999999999999) zzzzzzz"
            XCTAssertEqual(PixelFont.measure(a.buildLabel), PixelFont.measure(b.buildLabel))
            let ra = Renderer(), rb = Renderer()
            ra.render(a); rb.render(b)
            let L = a.ui.layout
            var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min, muted = 0
            for y in 0..<L.height { for x in 0..<L.width where ra.canvas.get(x, y) != rb.canvas.get(x, y) {
                x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
                if ra.canvas.get(x, y).rgbOnly == Palette.muted.rgbOnly { muted += 1 }
            } }
            XCTAssertGreaterThan(muted, 20, "\(name): the label is drawn in muted ink")
            guard x0 <= x1 else { continue }
            let tag = Rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
            XCTAssertLessThanOrEqual(tag.h, PixelFont.capHeight + 2, "\(name): one small line")
            let r = Tuning.cornerRadius
            XCTAssertTrue(L.safe(tag), "\(name): label at \(tag) is in a rounded corner")
            XCTAssertTrue(tag.x >= r && tag.maxX <= L.width - r || tag.y >= r && tag.maxY <= L.height - r,
                          "\(name): label at \(tag) is within the corner radius")
            for h in a.ui.hits where !isBackground(h.action) {
                let overlap = tag.x < h.rect.maxX && h.rect.x < tag.maxX && tag.y < h.rect.maxY && h.rect.y < tag.maxY
                XCTAssertFalse(overlap, "\(name): label at \(tag) overlaps \(h.action) at \(h.rect)")
            }
        }
    }
}
