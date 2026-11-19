/// One art pixel in memory order R, G, B, A (little-endian `UInt32`).
///
/// The alpha byte is never transparency: the base image is always opaque. It is the pixel's
/// *glow* (emissive strength) that the bloom post-pass reads, so the base image stays
/// pixel-perfect and the glow is layered on top.
public typealias Pixel = UInt32

@inline(__always)
public func rgb(_ hex: UInt32, glow: UInt8 = 0) -> Pixel {
    let r = (hex >> 16) & 0xff, g = (hex >> 8) & 0xff, b = hex & 0xff
    return r | (g << 8) | (b << 16) | (UInt32(glow) << 24)
}

public extension Pixel {
    @inline(__always) func glowing(_ amount: UInt8) -> Pixel { (self & 0x00ff_ffff) | (UInt32(amount) << 24) }
    var red: UInt8 { UInt8(self & 0xff) }
    var green: UInt8 { UInt8((self >> 8) & 0xff) }
    var blue: UInt8 { UInt8((self >> 16) & 0xff) }
    var glow: UInt8 { UInt8(self >> 24) }
}

/// "Vercel Neon": pure black, Vercel's greys, and a few vivid accents. Every colour on screen
/// comes from here. Gold is reserved for the golden pixel and money.
public enum Palette {
    public static let black = rgb(0x000000)
    public static let panel0 = rgb(0x0a0a0a)
    public static let panel1 = rgb(0x111111)
    public static let panel2 = rgb(0x1a1a1a)
    public static let border = rgb(0x333333)
    public static let muted = rgb(0x666666)
    public static let text2 = rgb(0xa1a1a1)
    public static let text = rgb(0xededed)
    public static let white = rgb(0xffffff)

    /// Unbreakable rock: Vercel's mid greys, lit from the top-left like everything else.
    public static let wall = rgb(0x333333)
    public static let wallLight = rgb(0x666666)
    public static let wallShade = rgb(0x1a1a1a)

    public static let gold = rgb(0xffd500)
    public static let goldLight = rgb(0xfff27a)
    public static let goldDim = rgb(0x806a00)
    public static let goldDeep = rgb(0x403500)

    public static let blue = rgb(0x0070f3)
    public static let cyan = rgb(0x50fff0)

    /// Durability ramp, cool to hot: green, acid lime, amber, hot pink, crimson.
    public static let tiers: [Pixel] = [0x00e676, 0xd4ff3a, 0xffb224, 0xff1f5a, 0xb4005a].map { rgb($0) }
    public static let tiersLight: [Pixel] = [0x7dffb8, 0xeaff9c, 0xffd88a, 0xff8aa8, 0xe0428f].map { rgb($0) }
    public static let tiersDark: [Pixel] = [0x00914a, 0x86a324, 0xa87416, 0xa3143a, 0x6e0037].map { rgb($0) }
}
