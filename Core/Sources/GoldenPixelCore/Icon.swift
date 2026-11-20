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

    public static func draw(_ appearance: Appearance = .standard) -> Canvas {
        let c = Canvas(width: size, height: size)
        c.clear(Palette.black)
        for (y, row) in cells.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let step = ch.wholeNumberValue else { continue }
                c.fill(x * cell, y * cell, cell, cell, Palette.ladder[step])
            }
        }
        // Keyline, gold, then the rays from its corners (over the keyline and the blocks, as
        // the logo's run over its keyline): light, with a dim last pixel.
        c.fill(gold.inset(-1), Palette.black)
        c.fill(gold, Palette.gold)
        for (x0, y0, dx, dy) in [(gold.x - 1, gold.y - 1, -1, -1), (gold.maxX, gold.y - 1, 1, -1),
                                 (gold.x - 1, gold.maxY, -1, 1), (gold.maxX, gold.maxY, 1, 1)] {
            for k in 1...rayLength {
                c.set(x0 + dx * k, y0 + dy * k, k < rayLength ? Palette.goldLight : Palette.goldDim)
            }
        }
        c.sprite(Sprites.ball(.basic), ball.x, ball.y)
        // The icon has no bloom: strip the glow bytes.
        for i in c.pixels.indices { c.pixels[i] &= 0x00ff_ffff }
        if appearance == .tinted {
            for i in c.pixels.indices { c.pixels[i] = tintedGrey(c.pixels[i]) }
        }
        return c
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
