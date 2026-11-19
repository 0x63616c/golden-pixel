/// A tiny PNG writer (stored deflate, no compression) so previews, icons and tests can save
/// frames on any machine without image libraries.
public enum PNG {
    /// RGB or RGBA 8-bit rows.
    public static func encode(width: Int, height: Int, rgba: [UInt8], alpha: Bool) -> [UInt8] {
        let ch = alpha ? 4 : 3
        var raw: [UInt8] = []
        raw.reserveCapacity((width * ch + 1) * height)
        for y in 0..<height {
            raw.append(0)
            let row = y * width * ch
            raw.append(contentsOf: rgba[row..<(row + width * ch)])
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        var ihdr: [UInt8] = []
        ihdr += be32(UInt32(width)); ihdr += be32(UInt32(height))
        ihdr += [8, alpha ? 6 : 2, 0, 0, 0]
        chunk(&out, "IHDR", ihdr)
        chunk(&out, "IDAT", zlibStored(raw))
        chunk(&out, "IEND", [])
        return out
    }

    /// The canvas as an RGB PNG, each art pixel scaled up `scale` times (nearest neighbour).
    /// With `bloom`, the glow channel is blurred and added on top, like the app's post-pass.
    public static func encode(_ c: Canvas, scale: Int = 1, bloom: Bool = false) -> [UInt8] {
        let w = c.width * scale, h = c.height * scale
        var glow: [Float] = []
        if bloom { glow = Bloom.glowMap(c) }
        var data = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            for x in 0..<w {
                let ax = x / scale, ay = y / scale
                let p = c.pixels[ay * c.width + ax]
                var r = Float(p.red), g = Float(p.green), b = Float(p.blue)
                if bloom {
                    let gi = (ay * c.width + ax) * 3
                    r += glow[gi]; g += glow[gi + 1]; b += glow[gi + 2]
                }
                let o = (y * w + x) * 3
                data[o] = UInt8(min(255, r)); data[o + 1] = UInt8(min(255, g)); data[o + 2] = UInt8(min(255, b))
            }
        }
        return encode(width: w, height: h, rgba: data, alpha: false)
    }

    static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)] }

    static func chunk(_ out: inout [UInt8], _ type: String, _ data: [UInt8]) {
        out += be32(UInt32(data.count))
        let t = Array(type.utf8)
        out += t
        out += data
        out += be32(crc(t + data))
    }

    static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc(_ d: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffff_ffff
    }

    static func zlibStored(_ d: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65535, d.count - i)
            let last: UInt8 = i + n >= d.count ? 1 : 0
            out.append(last)
            out += [UInt8(n & 0xff), UInt8(n >> 8), UInt8(~n & 0xff), UInt8((~n >> 8) & 0xff)]
            out += d[i..<(i + n)]
            i += n
        } while i < d.count
        var a: UInt32 = 1, b: UInt32 = 0
        for x in d { a = (a + UInt32(x)) % 65521; b = (b + a) % 65521 }
        out += be32((b << 16) | a)
        return out
    }
}

/// The CPU twin of the app's bloom shader, for previews: glow channel times colour, blurred.
public enum Bloom {
    public static func glowMap(_ c: Canvas, radius: Int = 3, strength: Float = 0.9) -> [Float] {
        let w = c.width, h = c.height
        var src = [Float](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            let p = c.pixels[i]
            let k = Float(p.glow) / 255
            src[i * 3] = Float(p.red) * k; src[i * 3 + 1] = Float(p.green) * k; src[i * 3 + 2] = Float(p.blue) * k
        }
        func blur(_ a: [Float], horizontal: Bool) -> [Float] {
            var o = [Float](repeating: 0, count: a.count)
            let n = Float(2 * radius + 1)
            for y in 0..<h {
                for x in 0..<w {
                    var r: Float = 0, g: Float = 0, b: Float = 0
                    for d in -radius...radius {
                        let xx = horizontal ? min(w - 1, max(0, x + d)) : x
                        let yy = horizontal ? y : min(h - 1, max(0, y + d))
                        let j = (yy * w + xx) * 3
                        r += a[j]; g += a[j + 1]; b += a[j + 2]
                    }
                    let j = (y * w + x) * 3
                    o[j] = r / n * strength; o[j + 1] = g / n * strength; o[j + 2] = b / n * strength
                }
            }
            return o
        }
        var m = blur(blur(src, horizontal: true), horizontal: false)
        m = blur(blur(m, horizontal: true), horizontal: false)
        for i in 0..<m.count { m[i] *= 1.6 }
        return m
    }
}
