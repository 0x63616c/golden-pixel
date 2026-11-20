/// The whole frame, at art-pixel resolution. Everything (board, HUD, panel, text, particles,
/// lightning) is drawn here with integer coordinates only, then presented with
/// nearest-neighbour scaling at an integer factor. There is no anti-aliasing anywhere.
public final class Canvas {
    public let width: Int
    public let height: Int
    public var pixels: [Pixel]
    /// Optional clip rectangle; nothing is drawn outside it.
    public var clip: Rect?

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: Palette.black, count: width * height)
    }

    public func clear(_ c: Pixel = Palette.black) {
        for i in pixels.indices { pixels[i] = c }
    }

    @inline(__always)
    public func set(_ x: Int, _ y: Int, _ c: Pixel) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        if let r = clip, !(x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h) { return }
        pixels[y &* width &+ x] = c
    }

    @inline(__always)
    public func get(_ x: Int, _ y: Int) -> Pixel {
        guard x >= 0, y >= 0, x < width, y < height else { return Palette.black }
        return pixels[y * width + x]
    }

    public func fill(_ r: Rect, _ c: Pixel) { fill(r.x, r.y, r.w, r.h, c) }

    public func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Pixel) {
        var x0 = max(0, x), y0 = max(0, y), x1 = min(width, x + w), y1 = min(height, y + h)
        if let r = clip { x0 = max(x0, r.x); y0 = max(y0, r.y); x1 = min(x1, r.x + r.w); y1 = min(y1, r.y + r.h) }
        guard x0 < x1, y0 < y1 else { return }
        pixels.withUnsafeMutableBufferPointer { p in
            for yy in y0..<y1 {
                let row = yy * width
                for xx in x0..<x1 { p[row + xx] = c }
            }
        }
    }

    public func outline(_ r: Rect, _ c: Pixel) {
        hline(r.x, r.x + r.w - 1, r.y, c)
        hline(r.x, r.x + r.w - 1, r.y + r.h - 1, c)
        vline(r.x, r.y, r.y + r.h - 1, c)
        vline(r.x + r.w - 1, r.y, r.y + r.h - 1, c)
    }

    public func hline(_ x0: Int, _ x1: Int, _ y: Int, _ c: Pixel) {
        guard x1 >= x0 else { return }
        fill(x0, y, x1 - x0 + 1, 1, c)
    }

    public func vline(_ x: Int, _ y0: Int, _ y1: Int, _ c: Pixel) {
        guard y1 >= y0 else { return }
        fill(x, y0, 1, y1 - y0 + 1, c)
    }

    /// Bresenham: one art pixel thick, no smoothing.
    public func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Pixel) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            set(x, y, c)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// Every other pixel of a line, for hints and inactive connectors.
    public func dottedLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ c: Pixel, phase: Int = 0) {
        var x = x0, y = y0, n = phase
        let dx = abs(x1 - x0), dy = -abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx + dy
        while true {
            if n & 1 == 0 { set(x, y, c) }
            n += 1
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }

    /// Midpoint circle outline.
    public func circle(_ cx: Int, _ cy: Int, _ r: Int, _ c: Pixel) {
        guard r > 0 else { set(cx, cy, c); return }
        var x = r, y = 0, err = 1 - r
        while x >= y {
            for (px, py) in [(x, y), (y, x), (-y, x), (-x, y), (-x, -y), (-y, -x), (y, -x), (x, -y)] {
                set(cx + px, cy + py, c)
            }
            y += 1
            if err < 0 { err += 2 * y + 1 } else { x -= 1; err += 2 * (y - x) + 1 }
        }
    }

    /// A 1-pixel ring of radius r around a point that may sit between pixels: every pixel
    /// whose centre is within half a pixel of the circle. Symmetric about (cx, cy). `cover`
    /// below 1 dithers it away (Bayer), down to nothing at 0.
    public func ring(_ cx: Double, _ cy: Double, _ r: Double, _ c: Pixel, cover: Double = 1) {
        guard cover > 0 else { return }
        guard r >= 0.5 else { set(Int(cx.rounded(.down)), Int(cy.rounded(.down)), c); return }
        let x0 = Int((cx - r - 1).rounded(.down)), x1 = Int((cx + r + 1).rounded(.up))
        let y0 = Int((cy - r - 1).rounded(.down)), y1 = Int((cy + r + 1).rounded(.up))
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                let d = (dx * dx + dy * dy).squareRoot()
                if abs(d - r) < 0.5, Bayer.on(x, y, cover) { set(x, y, c) }
            }
        }
    }

    /// Draws a sprite at a whole scale (each sprite pixel becomes a scale x scale block).
    public func sprite(_ s: Sprite, _ x: Int, _ y: Int, tint: Pixel? = nil, scale: Int = 1) {
        for sy in 0..<s.height {
            for sx in 0..<s.width {
                guard let p = s.pixels[sy * s.width + sx] else { continue }
                if scale == 1 { set(x + sx, y + sy, tint ?? p) } else { fill(x + sx * scale, y + sy * scale, scale, scale, tint ?? p) }
            }
        }
    }

    /// Draws `s` with its cap top at y (descenders hang 1 row below the 7-pixel caps).
    /// Returns the drawn width.
    @discardableResult
    public func text(_ s: String, _ x: Int, _ y: Int, _ c: Pixel, scale: Int = 1) -> Int {
        var cx = x
        for ch in s {
            guard let g = PixelFont.glyph(ch) else { continue }
            for (gy, row) in g.rows.enumerated() where row != 0 {
                for gx in 0..<g.advance where row & (1 << gx) != 0 {
                    if scale == 1 { set(cx + gx, y + gy, c) } else { fill(cx + gx * scale, y + gy * scale, scale, scale, c) }
                }
            }
            cx += g.advance * scale
        }
        return max(0, cx - x - scale)
    }

    /// Darkens the whole frame by stepping every pixel down a fixed ramp (no blending, so the
    /// result stays on the palette's dark end). Used behind overlays.
    public func dim() {
        pixels.withUnsafeMutableBufferPointer { p in
            for i in 0..<p.count {
                let c = p[i]
                let r = (c & 0xff) >> 2, g = ((c >> 8) & 0xff) >> 2, b = ((c >> 16) & 0xff) >> 2
                p[i] = r | (g << 8) | (b << 16)
            }
        }
    }
}

public struct Rect: Equatable, Sendable {
    public var x: Int, y: Int, w: Int, h: Int
    public init(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    public func contains(_ p: Point) -> Bool { p.x >= x && p.y >= y && p.x < x + w && p.y < y + h }
    public var maxX: Int { x + w }
    public var maxY: Int { y + h }
    public func inset(_ d: Int) -> Rect { Rect(x + d, y + d, w - 2 * d, h - 2 * d) }
    /// The part of this rectangle inside `o` (zero-sized when they don't meet).
    public func intersection(_ o: Rect) -> Rect {
        let x0 = max(x, o.x), y0 = max(y, o.y)
        return Rect(x0, y0, max(0, min(maxX, o.maxX) - x0), max(0, min(maxY, o.maxY) - y0))
    }
}

public struct Point: Equatable, Sendable {
    public var x: Int, y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

/// 4x4 ordered-dither thresholds (0...15). Fades, reveals and glows step through these, so
/// every transition is a pixel pattern rather than a gradient.
public enum Bayer {
    static let m: [Int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    @inline(__always) public static func at(_ x: Int, _ y: Int) -> Int { m[(y & 3) * 4 + (x & 3)] }
    /// True when this pixel is "on" at coverage `t` in 0...1.
    @inline(__always) public static func on(_ x: Int, _ y: Int, _ t: Double) -> Bool { Double(at(x, y)) < t * 16 }
}
