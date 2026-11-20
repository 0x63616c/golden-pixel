/// How the art canvas sits on a screen: one art pixel is the same physical size on every
/// phone (`Tuning.pointsPerArtPixel` points, 6 device pixels at @3x), so a smaller phone gets
/// a smaller canvas, never smaller pixels. The layout then fits itself to that canvas and to
/// the part of it the system leaves clear (`Layout`).

/// Distances in from the canvas edges, in art pixels: what the system covers (the Dynamic
/// Island's side of the screen, the home indicator).
public struct Insets: Equatable, Sendable {
    public var left: Int, top: Int, right: Int, bottom: Int
    public init(left: Int = 0, top: Int = 0, right: Int = 0, bottom: Int = 0) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
    public static let zero = Insets()
}

public struct Display: Equatable, Sendable {
    /// Device pixels per art pixel.
    public var scale: Int
    /// The canvas, in art pixels.
    public var width: Int
    public var height: Int
    /// Where the canvas starts in the drawable, in device pixels (it is centred, so at most
    /// `scale - 1` pixels are left over per axis).
    public var originX: Int
    public var originY: Int
    /// The safe area, as insets from the canvas edges in art pixels (rounded up).
    public var insets: Insets
    /// The screen's corner radius in art pixels: 0 on a square screen.
    public var corner: Int

    /// The canvas for a drawable of `pixelWidth` x `pixelHeight` device pixels at `pointScale`
    /// pixels per point, with the system's safe-area insets in points.
    ///
    /// The scale is `Tuning.pointsPerArtPixel` points per art pixel (6 at @3x, 4 at @2x). Only
    /// if that leaves less than `Tuning.minSafeLong` x `Tuning.minSafeShort` clear art pixels
    /// does it step down, a whole scale at a time.
    public static func fit(pixelWidth: Int, pixelHeight: Int, pointScale: Double,
                           safe: (left: Double, top: Double, right: Double, bottom: Double) = (0, 0, 0, 0)) -> Display {
        var s = max(1, Int((Double(Tuning.pointsPerArtPixel) * pointScale).rounded()))
        while true {
            let d = Display(pixelWidth: pixelWidth, pixelHeight: pixelHeight, pointScale: pointScale, safe: safe, scale: s)
            let w = d.width - d.insets.left - d.insets.right, h = d.height - d.insets.top - d.insets.bottom
            if s == 1 || (min(w, h) >= Tuning.minSafeShort && max(w, h) >= Tuning.minSafeLong) { return d }
            s -= 1
        }
    }

    init(pixelWidth: Int, pixelHeight: Int, pointScale: Double, safe: (left: Double, top: Double, right: Double, bottom: Double), scale s: Int) {
        scale = s
        width = max(1, pixelWidth / s); height = max(1, pixelHeight / s)
        originX = (pixelWidth - width * s) / 2; originY = (pixelHeight - height * s) / 2
        // A safe-area edge in device pixels, measured from the canvas edge, in whole art pixels.
        func inset(_ points: Double, _ origin: Int) -> Int {
            let px = Int((points * pointScale).rounded(.up)) - origin
            return px <= 0 ? 0 : (px + s - 1) / s
        }
        insets = Insets(left: inset(safe.left, originX), top: inset(safe.top, originY),
                        right: inset(safe.right, pixelWidth - originX - width * s), bottom: inset(safe.bottom, pixelHeight - originY - height * s))
        // There is no public corner radius. A screen with no safe-area insets at all is a
        // square one (a home-button phone); every other iPhone screen is rounded.
        let square = safe.left <= 0 && safe.top <= 0 && safe.right <= 0 && safe.bottom <= 0
        corner = square ? 0 : Tuning.cornerRadius
    }
}

/// The screens the layout is checked on (`UISafetyTests`, `gp-render --device`,
/// `ios/ios.sh compare`). Sizes are landscape device pixels; safe areas are landscape points.
public struct Device: Sendable {
    public let name: String
    public let title: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let pointScale: Double
    public let safe: (left: Double, top: Double, right: Double, bottom: Double)

    public var display: Display {
        Display.fit(pixelWidth: pixelWidth, pixelHeight: pixelHeight, pointScale: pointScale, safe: safe)
    }

    /// The target: the Duo's inner screen. Safe area as its simulator reports it.
    public static let duo = Device(name: "duo", title: "iPhone Duo (inner)", pixelWidth: 2853, pixelHeight: 2007, pointScale: 3, safe: (0, 0, 0, 34))
    /// Safe areas as the iOS 27.2 simulators report them (`just compare` writes them out).
    public static let pro = Device(name: "iphone", title: "iPhone 18 Pro", pixelWidth: 2622, pixelHeight: 1206, pointScale: 3, safe: (62, 0, 62, 20))
    public static let proMax = Device(name: "max", title: "iPhone 18 Pro Max", pixelWidth: 2868, pixelHeight: 1320, pointScale: 3, safe: (62, 0, 62, 20))
    /// The two smallest screens iOS 26 runs on, also as their simulators report them: the
    /// narrowest canvas and the shortest one. The mini draws 2.88 pixels per point (iOS
    /// resamples its frame onto the panel), so it rounds to scale 6 like the @3x phones.
    public static let se = Device(name: "se", title: "iPhone SE", pixelWidth: 1334, pixelHeight: 750, pointScale: 2, safe: (0, 0, 0, 0))
    public static let mini = Device(name: "mini", title: "iPhone 13 mini", pixelWidth: 2340, pixelHeight: 1080, pointScale: 2.88, safe: (50, 0, 50, 20))

    public static let all: [Device] = [duo, pro, proMax, se, mini]
    public static func named(_ name: String) -> Device? { all.first { $0.name == name } }
}
