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
    /// The colour without its glow byte, for comparisons.
    var rgbOnly: Pixel { self & 0x00ff_ffff }
}

/// Flat colours only: no highlights, no shadows, no bevels. Every colour on screen comes from
/// here. Blocks are one hue (blue) whose brightness is their durability; gold is reserved for
/// the golden pixel and coins, mint for shards.
public enum Palette {
    public static let black = rgb(0x000000)
    public static let panel0 = rgb(0x0b0c10)
    public static let panel1 = rgb(0x14161d)
    public static let panel2 = rgb(0x1e212b)
    public static let panel3 = rgb(0x2a2e3b)
    public static let border = rgb(0x343948)
    public static let muted = rgb(0x6b7285)
    public static let text2 = rgb(0xa3aabb)
    public static let text = rgb(0xeef0f5)
    public static let white = rgb(0xffffff)

    /// Explored floor: one flat step above the fog's pure black.
    public static let floor = rgb(0x0e1016)
    /// Unbreakable rock: a neutral dark grey, never brighter than the blocks around it.
    public static let wall = rgb(0x262629)

    public static let gold = rgb(0xffd23f)
    public static let goldLight = rgb(0xffe98a)
    public static let goldDim = rgb(0x9c7a10)
    public static let goldDeep = rgb(0x4a3a08)

    /// Shard pixels and the shard currency.
    public static let mint = rgb(0x4dffc3)
    public static let mintDim = rgb(0x1f8a66)
    public static let mintDeep = rgb(0x0d3d2d)

    /// Buttons and selection.
    public static let accent = rgb(0x3d7bff)
    public static let accentDim = rgb(0x1c3a7a)
    public static let accentLight = rgb(0x74a3ff)
    public static let danger = rgb(0xff4f5e)
    public static let dangerLight = rgb(0xff8a94)
    /// Ink on gold buttons: a deep warm brown that reads as black but sits with the gold.
    public static let goldInk = rgb(0x2b1d00)

    /// The durability ladder, palest (one hit left) to deepest (toughest): one blue hue, so a
    /// block gets lighter as it wears down. Index = `Economy.ladderStep`; a fresh tier-t block
    /// shows step t + 1.
    public static let ladder: [Pixel] = [0xb9d2ff, 0x74a3ff, 0x3a78f0, 0x2858c4, 0x22408a, 0x1d2c52].map { rgb($0) }

    /// The colour a fresh block of tier t shows.
    public static func tier(_ t: Int) -> Pixel { ladder[min(ladder.count - 1, t + 1)] }

    /// Half brightness, for faded particles and rings.
    public static func dimmer(_ p: Pixel) -> Pixel {
        let r = (p & 0xff) / 2, g = ((p >> 8) & 0xff) / 2, b = ((p >> 16) & 0xff) / 2
        return r | (g << 8) | (b << 16)
    }
}
