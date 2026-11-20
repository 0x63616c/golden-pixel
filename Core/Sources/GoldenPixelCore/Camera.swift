/// The board camera. `zoom` is canvas pixels per board art pixel. At rest it is one of
/// `levels`: whole numbers (zoom 2 = every board art pixel drawn as a 2x2 block of canvas
/// pixels = 12x12 device pixels on the Duo) or 0.5, an exact subsample (every other board
/// pixel), so the board always stays on the UI's art grid. A pinch may pass through any zoom;
/// on release the camera eases into the nearest level and snaps its position so the board's
/// origin lands on a whole canvas pixel. The UI never zooms.
public struct Camera: Equatable, Sendable {
    /// The board's zoom levels. The skill tree uses its own (`Camera.treeLevels`).
    public static let boardLevels: [Double] = [0.5, 1, 2, 3, 4]
    public static let treeLevels: [Double] = [0.5, 1, 2]
    /// Where a double-tap takes you from zoom 1 or less.
    public static let closeUp = 2.0
    /// How fast the settle eases (per second, exponential).
    public static let settleRate = 18.0

    /// Board size and view size, in board art pixels and canvas pixels.
    public var boardW: Int
    public var boardH: Int
    public var viewW: Int
    public var viewH: Int
    /// The zooms the camera may rest at, ascending.
    public let levels: [Double]
    /// How far past the board's edge the view may go, as a fraction of half the view: 0 keeps
    /// the view inside the board, 1 lets any board point reach the centre of the view (so a
    /// spawn near the edge still starts in the middle of the screen).
    public var overscroll: Double
    public var minZoom: Double { levels.first! }
    public var maxZoom: Double { levels.last! }
    public private(set) var zoom: Double = 1
    /// The board art-pixel position at the centre of the view.
    public private(set) var cx: Double
    public private(set) var cy: Double
    /// Set while easing toward a whole zoom after a pinch or a double-tap.
    public private(set) var target: (zoom: Double, cx: Double, cy: Double)?

    public init(boardW: Int, boardH: Int, viewW: Int, viewH: Int, levels: [Double] = Camera.boardLevels, overscroll: Double = 0) {
        self.boardW = boardW; self.boardH = boardH; self.viewW = viewW; self.viewH = viewH
        self.levels = levels
        self.overscroll = overscroll
        cx = Double(boardW) / 2; cy = Double(boardH) / 2
        clamp(); snapToGrid()
    }

    public static func == (a: Camera, b: Camera) -> Bool {
        a.zoom == b.zoom && a.cx == b.cx && a.cy == b.cy && a.boardW == b.boardW && a.viewW == b.viewW
            && (a.target == nil) == (b.target == nil)
    }

    public var isAtRest: Bool { target == nil && levels.contains(zoom) }

    /// The resting zoom nearest to z (in log space, so 1.4 rounds to 1 and 1.5 to 2).
    public func nearestLevel(_ z: Double) -> Double {
        levels.min { abs(log($0) - log(z)) < abs(log($1) - log(z)) }!
    }

    /// Centres the view on board art pixel (x, y) straight away, keeping the zoom.
    public mutating func look(at x: Double, _ y: Double) {
        target = nil
        cx = x; cy = y
        clamp(); snapToGrid()
    }

    /// Canvas offset (from the view's top-left) of board art pixel (0, 0).
    public var origin: (x: Double, y: Double) {
        (Double(viewW) / 2 - cx * zoom, Double(viewH) / 2 - cy * zoom)
    }

    /// View-local canvas point → board art pixel (fractional).
    public func toBoard(_ vx: Double, _ vy: Double) -> (x: Double, y: Double) {
        let o = origin
        return ((vx - o.x) / zoom, (vy - o.y) / zoom)
    }

    /// Board art pixel → view-local canvas point.
    public func toView(_ bx: Double, _ by: Double) -> (x: Double, y: Double) {
        let o = origin
        return (o.x + bx * zoom, o.y + by * zoom)
    }

    /// Keeps the view inside the board; a board smaller than the view stays centred.
    mutating func clamp() {
        zoom = min(maxZoom, max(minZoom, zoom))
        (cx, cy) = Camera.clamped(cx, cy, zoom: zoom, self)
    }

    static func clamped(_ x: Double, _ y: Double, zoom: Double, _ c: Camera) -> (Double, Double) {
        func axis(_ v: Double, _ board: Int, _ view: Int) -> Double {
            let half = Double(view) / 2 / zoom
            if half * 2 >= Double(board) { return Double(board) / 2 }
            let reach = half * (1 - c.overscroll)
            return min(Double(board) - reach, max(reach, v))
        }
        return (axis(x, c.boardW, c.viewW), axis(y, c.boardH, c.viewH))
    }

    /// Zoom by `factor` about the view point (vx, vy), keeping the board point under it fixed.
    public mutating func pinch(factor: Double, at vx: Double, _ vy: Double) {
        target = nil
        let anchor = toBoard(vx, vy)
        zoom = min(maxZoom * 1.15, max(minZoom / 1.15, zoom * factor))
        // Solve for the centre that keeps `anchor` under (vx, vy).
        cx = anchor.x - (vx - Double(viewW) / 2) / zoom
        cy = anchor.y - (vy - Double(viewH) / 2) / zoom
        let z = zoom
        zoom = min(maxZoom, max(minZoom, z))
        (cx, cy) = Camera.clamped(cx, cy, zoom: zoom, self)
        zoom = z
    }

    /// Pan by a drag of (dx, dy) canvas pixels: the board follows the finger.
    public mutating func pan(_ dx: Double, _ dy: Double) {
        if let t = target { zoom = t.zoom; cx = t.cx; cy = t.cy; target = nil }
        cx -= dx / zoom; cy -= dy / zoom
        clamp()
        snapToGrid()
    }

    /// Fingers lifted: ease into the nearest zoom level, anchored on the view centre.
    public mutating func settle() {
        aim(zoom: nearestLevel(zoom), cx: cx, cy: cy)
    }

    /// Double-tap: from close up, back out to zoom 1 around the same spot; otherwise go
    /// close-up on the tapped view point.
    public mutating func toggle(at vx: Double, _ vy: Double) {
        if (target?.zoom ?? zoom) > 1.01 {
            aim(zoom: 1, cx: cx, cy: cy)
        } else {
            let p = toBoard(vx, vy)
            aim(zoom: Camera.closeUp, cx: p.x, cy: p.y)
        }
    }

    mutating func aim(zoom z: Double, cx x: Double, cy y: Double) {
        var (tx, ty) = Camera.clamped(x, y, zoom: z, self)
        (tx, ty) = Camera.gridCentre(tx, ty, zoom: z, viewW: viewW, viewH: viewH)
        (tx, ty) = Camera.clamped(tx, ty, zoom: z, self)
        (tx, ty) = Camera.gridCentre(tx, ty, zoom: z, viewW: viewW, viewH: viewH)
        target = (z, tx, ty)
    }

    /// The nearest centre for which the board origin is a whole canvas pixel at zoom z.
    static func gridCentre(_ x: Double, _ y: Double, zoom z: Double, viewW: Int, viewH: Int) -> (Double, Double) {
        func axis(_ v: Double, _ view: Int) -> Double {
            let o = (Double(view) / 2 - v * z).rounded()
            return (Double(view) / 2 - o) / z
        }
        return (axis(x, viewW), axis(y, viewH))
    }

    mutating func snapToGrid() {
        guard levels.contains(zoom) else { return }
        (cx, cy) = Camera.gridCentre(cx, cy, zoom: zoom, viewW: viewW, viewH: viewH)
    }

    /// Advances the settle animation; lands exactly on the target.
    public mutating func update(_ dt: Double) {
        guard let t = target else { return }
        let k = 1 - exp(-Camera.settleRate * dt)
        // Ease zoom in log space so zooming in and out feel the same.
        zoom = exp(log(zoom) + (log(t.zoom) - log(zoom)) * k)
        cx += (t.cx - cx) * k; cy += (t.cy - cy) * k
        if abs(zoom - t.zoom) < 0.004 && abs(cx - t.cx) * zoom < 0.25 && abs(cy - t.cy) * zoom < 0.25 {
            zoom = t.zoom; cx = t.cx; cy = t.cy; target = nil
        }
    }

    /// Resize (layout change); keeps zoom and centre.
    public mutating func setSizes(boardW bw: Int, boardH bh: Int, viewW vw: Int, viewH vh: Int) {
        guard bw != boardW || bh != boardH || vw != viewW || vh != viewH else { return }
        boardW = bw; boardH = bh; viewW = vw; viewH = vh
        clamp(); snapToGrid()
    }
}

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
