// gp-render: renders game scenes to PNG without a device.
//   swift run gp-render <scene> <out-dir> [--device NAME] [--scale N] [--size WxH] [--frames N] [--bloom]
// Scenes: see Scenes.names (menu, start, mid, late, tree, sheet, ...), all; or icon
// (the flat 1024 px PNGs), icon-layers (one SVG per Icon.Layer, for ios/AppIcon.icon/Assets),
// or levels (every campaign level's map on one sheet).
// Default: the Duo canvas (475x334) at scale 6 = the device's own pixels, bloom off, so the
// output is pixel-exact (every 6x6 block one colour; tools/gridcheck.py verifies).
// --device duo|iphone|max|se|mini renders that screen's canvas with its safe area, at its own
// scale (see Device in the core): what the app draws there, without a simulator.
import Foundation
import GoldenPixelCore

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let bloom = args.contains("--bloom")
args.removeAll { $0 == "--bloom" }
var display: Display?
if let name = option("--device") {
    guard let d = Device.named(name) else {
        print("unknown device \(name): one of \(Device.all.map(\.name).joined(separator: ", "))")
        exit(1)
    }
    display = d.display
}
let scale = Int(option("--scale") ?? "") ?? display?.scale ?? Tuning.artScale
let size = (option("--size") ?? "\(Tuning.canvasWidth)x\(Tuning.canvasHeight)").split(separator: "x").compactMap { Int($0) }
let frames = Int(option("--frames") ?? "0") ?? 0
let scene = args.first ?? "all"
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "build/render")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

if scene == "icon" {
    try Data(PNG.encode(Icon.draw(), scale: Icon.scale, bloom: false)).write(to: out.appendingPathComponent("icon.png"))
    try Data(PNG.encode(Icon.draw(.tinted), scale: Icon.scale, bloom: false)).write(to: out.appendingPathComponent("icon-tinted.png"))
    print("rendered icon")
    exit(0)
}
if scene == "icon-layers" {
    for layer in Icon.Layer.allCases {
        try Icon.svg(layer).write(to: out.appendingPathComponent("\(layer.rawValue).svg"), atomically: true, encoding: .utf8)
    }
    print("rendered icon layers: \(Icon.Layer.allCases.map(\.rawValue).joined(separator: ", "))")
    exit(0)
}
if scene == "levels" {
    // One sheet of every campaign level's map, one art pixel per cell, for level design: the
    // rock that shapes it (gray where it faces the dig, dark where it is solid), every block
    // in its durability shade, the spawn pocket (white dot), the shards (mint) and the gold.
    let count = LevelSpec.campaign.count, cols = 4, tile = 2 * 50 + 5 + 8, head = 14
    let rows = (count + cols - 1) / cols
    let sheet = Canvas(width: cols * tile + 8, height: rows * (tile + head) + 8)
    sheet.fill(0, 0, sheet.width, sheet.height, Palette.black)
    for level in 1...count {
        let b = LevelGen.make(level: level)
        let ox = 8 + ((level - 1) % cols) * tile, oy = 8 + ((level - 1) / cols) * (tile + head)
        _ = sheet.text("\(level) \(b.name)", ox, oy, Palette.text)
        for y in 0..<b.size { for x in 0..<b.size {
            let i = b.index(x, y)
            let c: Pixel
            switch b.kind[i] {
            case .wall:
                var faces = false
                for dy in -1...1 { for dx in -1...1 where b.kindAt(x + dx, y + dy) != .wall { faces = true } }
                c = faces ? Palette.muted : Palette.panel1
            case .block: c = Palette.tier(Int(b.tier[i]))
            case .shard: c = Palette.mint
            case .gold: c = Palette.gold
            case .empty: c = x == b.spawn.x && y == b.spawn.y ? Palette.white : Palette.black
            }
            sheet.set(ox + x, oy + head + y, c)
        } }
    }
    try Data(PNG.encode(sheet, scale: scale, bloom: false)).write(to: out.appendingPathComponent("levels.png"))
    print("rendered levels")
    exit(0)
}
let scenes = scene == "all" ? Scenes.names : [scene]
for name in scenes {
    let w = name == "portrait" ? size[1] : size[0], h = name == "portrait" ? size[0] : size[1]
    let renderer = display.map { Renderer(display: $0) } ?? Renderer(width: w, height: h)
    let game = Scenes.make(name)
    if frames > 0 {
        let dir = out.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in 0..<frames {
            for _ in 0..<2 { game.update(1.0 / 60) }
            Scenes.script(name, game, frame: f)
            renderer.render(game)
            let png = PNG.encode(renderer.canvas, scale: scale, bloom: bloom)
            try Data(png).write(to: dir.appendingPathComponent(String(format: "%04d.png", f)))
        }
    } else {
        renderer.render(game)
        try Data(PNG.encode(renderer.canvas, scale: scale, bloom: bloom)).write(to: out.appendingPathComponent("\(name).png"))
    }
    print("rendered \(name)")
}
