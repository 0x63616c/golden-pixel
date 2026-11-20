/// The app icon, drawn with the game's own rules on a 32x32 art canvas scaled 32x to 1024 px.
///
/// One idea, readable at 40 px: the golden pixel at the dig face. Open dark fills the upper
/// left, the blue board the lower right, and the face runs diagonally through the middle. The
/// gold sits on it in a 1-px black keyline with the logo's four diagonal rays (the i-dot's
/// twinkle), and a white ball comes at it out of the dark. Blocks are 4 x 4 flat cells in
/// bands parallel to the face: worn pale where the balls hit, deep further in.
///
/// `draw(.tinted)` is the same art in greys with the gold brightest, for iOS's tinted icons
/// (the system lays its tint over the grey levels).
public enum Icon {
    public static let size = 32
    public static let scale = 32

    public enum Appearance: CaseIterable, Sendable {
        /// Full colour; also used for the dark appearance, since the icon is already dark.
        case standard
        /// Greyscale for the tinted appearance.
        case tinted
    }

    /// Board cells, 4 x 4 art px each. "." is open dark; digits are `Palette.ladder` steps.
    static let cells = [
        "......23",
        ".....234",
        "....2334",
        "...23445",
        "..234455",
        ".2334545",
        "23445555",
        "34455454",
    ]
    static let cell = 4
    /// The golden pixel: an 8 x 8 square dead centre.
    static let gold = Rect(12, 12, 8, 8)
    static let rayLength = 4
    /// The ball's top-left, in the dark left of the gold and clear of its rays.
    static let ball = Point(2, 10)

    /// The icon's parts, back to front, as the Icon Composer document (`ios/AppIcon.icon`)
    /// stacks them: each is one SVG layer there, so iOS can give each its own Liquid Glass depth.
    public enum Layer: String, CaseIterable, Sendable {
        /// The blue blocks, with the gold's keyline cut out of them (the dark shows through).
        case board
        /// The golden pixel itself.
        case gold
        /// Its four diagonal rays.
        case rays
        /// The white ball coming out of the dark.
        case ball
    }

    public static func draw(_ appearance: Appearance = .standard) -> Canvas {
        let c = Canvas(width: size, height: size)
        c.clear(Palette.black)
        for layer in Layer.allCases { paint(layer, on: c) }
        // The icon has no bloom: strip the glow bytes.
        for i in c.pixels.indices { c.pixels[i] &= 0x00ff_ffff }
        if appearance == .tinted {
            for i in c.pixels.indices { c.pixels[i] = tintedGrey(c.pixels[i]) }
        }
        return c
    }

    /// One layer alone on black (black = empty), without glow bytes.
    public static func draw(_ layer: Layer) -> Canvas {
        let c = Canvas(width: size, height: size)
        c.clear(Palette.black)
        paint(layer, on: c)
        for i in c.pixels.indices { c.pixels[i] &= 0x00ff_ffff }
        return c
    }

    static func paint(_ layer: Layer, on c: Canvas) {
        switch layer {
        case .board:
            for (y, row) in cells.enumerated() {
                for (x, ch) in row.enumerated() {
                    guard let step = ch.wholeNumberValue else { continue }
                    c.fill(x * cell, y * cell, cell, cell, Palette.ladder[step])
                }
            }
            // The gold's 1-px black keyline.
            c.fill(gold.inset(-1), Palette.black)
        case .gold:
            c.fill(gold, Palette.gold)
        case .rays:
            // From the gold's corners, over the blocks as the logo's run over its keyline:
            // light, with a dim last pixel.
            for (x0, y0, dx, dy) in [(gold.x - 1, gold.y - 1, -1, -1), (gold.maxX, gold.y - 1, 1, -1),
                                     (gold.x - 1, gold.maxY, -1, 1), (gold.maxX, gold.maxY, 1, 1)] {
                for k in 1...rayLength {
                    c.set(x0 + dx * k, y0 + dy * k, k < rayLength ? Palette.goldLight : Palette.goldDim)
                }
            }
        case .ball:
            c.sprite(Sprites.ball(.basic), ball.x, ball.y)
        }
    }

    /// A layer as a 1024 pt SVG for Icon Composer: one `rect` per flat run of art pixels on a
    /// 32-unit viewBox, so every edge lands on the art grid at any whole-multiple size. Black is
    /// empty (the document's fill is the dark).
    public static func svg(_ layer: Layer) -> String {
        let c = draw(layer)
        var done = [Bool](repeating: false, count: size * size)
        var rects: [String] = []
        for y in 0..<size {
            for x in 0..<size where !done[y * size + x] && c.get(x, y) != Palette.black {
                // Greedy: widen along the row, then grow down while the whole run matches.
                let p = c.get(x, y)
                var w = 1
                while x + w < size, !done[y * size + x + w], c.get(x + w, y) == p { w += 1 }
                var h = 1
                while y + h < size, (x..<(x + w)).allSatisfy({ !done[(y + h) * size + $0] && c.get($0, y + h) == p }) { h += 1 }
                for yy in y..<(y + h) { for xx in x..<(x + w) { done[yy * size + xx] = true } }
                let hex = "#" + [p.red, p.green, p.blue].map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined()
                rects.append("  <rect x=\"\(x)\" y=\"\(y)\" width=\"\(w)\" height=\"\(h)\" fill=\"\(hex)\"/>")
            }
        }
        let pt = size * scale
        return """
            <svg xmlns="http://www.w3.org/2000/svg" width="\(pt)" height="\(pt)" viewBox="0 0 \(size) \(size)" shape-rendering="crispEdges">
            \(rects.joined(separator: "\n"))
            </svg>

            """
    }

    /// Grey level per icon colour for the tinted appearance: the gold brightest, its rays next,
    /// the ball below them, and the blocks keeping their light-to-deep order underneath.
    static func tintedGrey(_ p: Pixel) -> Pixel {
        let level: UInt32
        switch p.rgbOnly {
        case Palette.gold.rgbOnly: level = 255
        case Palette.goldLight.rgbOnly: level = 215
        case Palette.white.rgbOnly: level = 170
        case Palette.goldDim.rgbOnly: level = 120
        case Palette.black.rgbOnly: level = 0
        default:
            // Blocks: Rec. 709 luma, a touch darker so they stay behind the gold and the ball.
            let l = (2126 * UInt32(p.red) + 7152 * UInt32(p.green) + 722 * UInt32(p.blue)) / 10000
            level = l * 4 / 5
        }
        return level | (level << 8) | (level << 16)
    }
}
