// gp-render: renders game scenes to PNG without a device.
//   swift run gp-render <scene> <out-dir> [--scale N] [--size WxH] [--frames N] [--bloom]
// Scenes: title, start, early, mid, late, skills, upgrades, gold, portrait, zoom, all; or icon
// (the flat 1024 px PNGs), or icon-layers (one SVG per Icon.Layer, for ios/AppIcon.icon/Assets).
// Default: the Duo canvas (475x334) at scale 6 = the device's own pixels, bloom off, so the
// output is pixel-exact (every 6x6 block one colour; tools/gridcheck.py verifies).
import Foundation
import GoldenPixelCore

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
let bloom = args.contains("--bloom")
args.removeAll { $0 == "--bloom" }
let scale = Int(option("--scale") ?? "\(Tuning.artScale)") ?? Tuning.artScale
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
let scenes = scene == "all" ? Scenes.names : [scene]
for name in scenes {
    let w = name == "portrait" ? size[1] : size[0], h = name == "portrait" ? size[0] : size[1]
    let renderer = Renderer(width: w, height: h)
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
