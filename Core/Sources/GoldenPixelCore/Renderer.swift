/// Draws a whole frame into one `Canvas` at art-pixel resolution and records the UI's hit
/// regions. Integer coordinates only: physics positions are snapped to the art grid here.
///
/// Everything is flat: one colour per surface, no highlights, shadows or bevels. Packed cells
/// of the same colour read as one seamless surface with no lines between them.
///
/// The board is drawn into its own canvas at 1 board art pixel per canvas pixel (only the part
/// the camera can see), then copied into the frame through the camera at one of its zoom
/// levels (nearest neighbour), so zoomed pixels are exact 2x2, 3x3 ... blocks, or an exact
/// every-other-pixel subsample at 0.5, on the same grid the UI uses.
///
/// The drawing is split by screen: `RenderBoard.swift` (the board and its HUD),
/// `RenderPanel.swift` (the side panel and ball sheet), `RenderPause.swift` (the pause card),
/// `RenderTree.swift` (the skill tree)
/// and `RenderMenu.swift` (menu, how to play, settings, level select).
public final class Renderer {
    public private(set) var canvas: Canvas
    var boardCanvas: Canvas
    var hits: [Hit] = []
    /// What the system covers and how round the screen is (`Display`); the layout keeps
    /// everything you read or press clear of both.
    public private(set) var insets: Insets
    public private(set) var corner: Int
    /// The layout of the frame being drawn.
    var layout: Layout
    /// While a scrolling card's body is being drawn: the part of it on screen. Hit regions are
    /// cut to it.
    var hitClip: Rect?
    /// The scrolling card body being drawn: its view and the full height of its content.
    var scrolling: (view: Rect, total: Int)?

    public init(width: Int = Tuning.canvasWidth, height: Int = Tuning.canvasHeight, insets: Insets = .zero, corner: Int = Tuning.cornerRadius) {
        canvas = Canvas(width: width, height: height)
        boardCanvas = Canvas(width: 1, height: 1)
        self.insets = insets
        self.corner = corner
        layout = Layout.make(width: width, height: height, insets: insets, corner: corner)
    }

    /// A renderer for a screen as `Display.fit` laid it out.
    public convenience init(display d: Display) {
        self.init(width: d.width, height: d.height, insets: d.insets, corner: d.corner)
    }

    public func resize(width: Int, height: Int, insets: Insets = .zero, corner: Int = Tuning.cornerRadius) {
        self.insets = insets
        self.corner = corner
        guard width != canvas.width || height != canvas.height else { return }
        canvas = Canvas(width: max(1, width), height: max(1, height))
    }

    public func resize(to d: Display) {
        resize(width: d.width, height: d.height, insets: d.insets, corner: d.corner)
    }

    public func render(_ g: Game) {
        let c = canvas
        c.clear()
        c.clip = nil
        hits = []
        hitClip = nil
        scrolling = nil
        layout = Layout.make(width: c.width, height: c.height, insets: insets, corner: corner)
        let layout = layout
        g.ui.layout = layout
        g.ui.scrollArea = nil
        g.ui.scrollMax = 0

        switch g.ui.screen {
        case .menu: drawMenu(g)
        case .howTo: drawHowTo(g)
        case .settings: drawSettings(g)
        case .levels: drawLevels(g)
        case .game:
            g.ui.camera.setSizes(boardW: g.board.pixelSize, boardH: g.board.pixelSize, viewW: layout.board.w, viewH: layout.board.h)
            drawBoard(g, layout)
            present(g, layout)
            drawLaunchPreview(g, layout)
            drawBoardHUD(g, layout)
            drawPanel(g, layout)
            drawBanners(g, layout)
            if let k = g.ui.sheet { drawBallSheet(g, k) }
            if g.ui.skillsOpen { drawTree(g) }
            if g.ui.paused { drawPause(g) }
        }
        if let t = g.ui.tooltip, t.until > g.time { drawTooltip(t) }
        g.ui.hits = hits
    }

    func hit(_ r: Rect, _ a: Action, _ info: [String] = []) {
        var r = r
        if let k = hitClip {
            // In a scrolling card: only what shows can be pressed, and a control scrolled
            // partly out of view only while a touch-sized piece of it still shows.
            let v = r.intersection(k)
            guard v.w >= min(r.w, Tuning.minTouch), v.h >= min(r.h, Tuning.minTouch) else { return }
            r = v
        }
        hits.append(Hit(rect: r, action: a, info: info))
    }

    /// The spacing step to draw a card at: the first of 0...last (0 is the roomy spacing the
    /// Duo gets, each step after it tighter) whose height fits, or the tightest.
    func fitStep(_ last: Int, into avail: Int, _ height: (Int) -> Int) -> Int {
        (0..<last).first { height($0) <= avail } ?? last
    }

    /// The button kinds. Every one is flat (one fill, at most a 1-px keyline of its own) with
    /// 1-px notched corners; pressed, the fill steps up and the content drops one pixel.
    /// - primary: blue, the main action of a sheet or card (BUY, an affordable TREE).
    /// - secondary: dark with a keyline, everything else.
    /// - gold: the one hero action on a screen (PLAY, RESUME).
    /// - danger: red, a destructive action being confirmed.
    /// - disabled: a dim keyline only, not pressable-looking.
    /// - bare: no box until pressed (a close X).
    enum ButtonStyle { case primary, secondary, danger, disabled, gold, bare }

    /// Fill, keyline and ink for a button style.
    func buttonColours(_ style: ButtonStyle, pressed: Bool) -> (fill: Pixel?, edge: Pixel?, ink: Pixel) {
        switch style {
        case .primary: return (pressed ? Palette.accentLight : Palette.accent, nil, Palette.white)
        case .secondary: return (pressed ? Palette.panel3 : Palette.panel2, pressed ? Palette.muted : Palette.border, pressed ? Palette.white : Palette.text)
        case .danger: return (pressed ? Palette.dangerLight : Palette.danger, nil, Palette.black)
        case .disabled: return (Palette.panel1, Palette.panel3, Palette.muted)
        case .gold: return (pressed ? Palette.goldLight : Palette.gold, nil, Palette.goldInk)
        case .bare: return (pressed ? Palette.panel3 : nil, nil, pressed ? Palette.white : Palette.text2)
        }
    }

    /// A flat box with stepped (notched) corners: `notch` 1 drops each corner pixel, 2 drops a
    /// 2-1 step. An optional keyline runs 1 px inside the edge and follows the notch.
    func box(_ r: Rect, _ fill: Pixel, edge: Pixel? = nil, notch: Int = 1) {
        let c = canvas
        func notched(_ r: Rect, _ col: Pixel, _ n: Int) {
            guard r.w > 0, r.h > 0 else { return }
            for y in 0..<r.h {
                let d = min(y, r.h - 1 - y)
                let cut = d < n ? n - d : 0
                c.fill(r.x + cut, r.y + y, r.w - 2 * cut, 1, col)
            }
        }
        if let e = edge {
            notched(r, e, notch)
            notched(r.inset(1), fill, notch - 1)
        } else {
            notched(r, fill, notch)
        }
    }

    /// A flat button: a notched box, then its icon and label centred as one group (icon, 5 px,
    /// label), each on the cap line. Records its hit region.
    func button(_ g: Game, _ r: Rect, _ label: String, _ a: Action, style: ButtonStyle = .secondary,
                icon: Sprite? = nil, tintIcon: Bool = false, scale: Int = 1, info: [String] = []) {
        let c = canvas
        let pressed = style != .disabled && g.isPressed(a)
        let (fill, edge, ink) = buttonColours(style, pressed: pressed)
        if let f = fill { box(r, f, edge: edge) }
        let tw = PixelFont.measure(label, scale: scale)
        let iw = icon.map { $0.width * scale + (label.isEmpty ? 0 : 5 * scale) } ?? 0
        let x = r.x + (r.w - tw - iw + 1) / 2
        let dy = pressed ? 1 : 0
        if let s = icon {
            let tint: Pixel? = style == .disabled ? Palette.muted : (tintIcon ? ink : nil)
            c.sprite(s, x, r.y + (r.h - s.height * scale + 1) / 2 + dy, tint: tint, scale: scale)
        }
        c.text(label, x + iw, r.y + (r.h - PixelFont.capHeight * scale + 1) / 2 + dy, ink, scale: scale)
        hit(r, a, info)
    }

    /// Splits text into lines no wider than `width` art pixels.
    func wrap(_ s: String, width: Int) -> [String] {
        var lines: [String] = [], line = ""
        for word in s.split(separator: " ") {
            let next = line.isEmpty ? String(word) : line + " " + word
            if PixelFont.measure(next) <= width || line.isEmpty { line = next } else { lines.append(line); line = String(word) }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    func centred(_ s: String, _ cx: Int, _ y: Int, _ col: Pixel, scale: Int = 1) {
        canvas.text(s, cx - PixelFont.measure(s, scale: scale) / 2, y, col, scale: scale)
    }

    func format1(_ v: Double) -> String {
        let t = Int((v * 10).rounded())
        return "\(t / 10).\(t % 10)"
    }

    // MARK: - Banners, tooltip

    func drawBanners(_ g: Game, _ L: Layout) {
        let c = canvas
        let B = L.boardContent
        var y = L.board.y + L.board.h / 2 - 20
        for b in g.banners.prefix(3) {
            let scale = b.big ? 3 : 1
            let h = PixelFont.capHeight * scale
            // Banners blink in and out rather than fading.
            if b.life < 0.3 && Int(b.life * 20) % 2 == 0 { y += h + 8; continue }
            let w = PixelFont.measure(b.text, scale: scale)
            let x = B.x + (B.w - w) / 2
            c.fill(x - 4, y - 4, w + 8, h + 8, Palette.black)
            c.text(b.text, x, y, b.color.glowing(b.big ? 255 : 120), scale: scale)
            y += h + 10
        }
    }

    func drawTooltip(_ t: Tooltip) {
        let w = (t.lines.map { PixelFont.measure($0) }.max() ?? 0) + 10
        let h = t.lines.count * PixelFont.lineHeight + 7
        var x = t.at.x - w / 2, y = t.at.y - h - 10
        if y < layout.safeArea.y + 4 { y = t.at.y + 12 }
        let K = layout.clear
        x = max(K.x, min(K.maxX - w, x))
        y = max(K.y + 4, min(K.maxY - h - 4, y))
        let r = Rect(x, y, w, h)
        let c = canvas
        c.fill(r, Palette.panel3)
        for (j, line) in t.lines.enumerated() { c.text(line, x + 5, y + 5 + j * PixelFont.lineHeight, j == 0 ? Palette.white : Palette.text2) }
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
