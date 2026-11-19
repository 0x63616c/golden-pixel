import GoldenPixelCore
import MetalKit
import SwiftUI

struct PixelView: UIViewRepresentable {
    let host: GameHost
    func makeUIView(context: Context) -> PixelMetalView { PixelMetalView(host: host) }
    func updateUIView(_ view: PixelMetalView, context: Context) {}
}

/// Presents the art-pixel canvas. Every frame: the CPU draws the canvas, it is uploaded as one
/// texture, a small pass blurs its glow channel at art resolution, and the final pass draws it
/// at an integer scale with exact texel reads (no filtering) plus the soft glow on top.
final class PixelMetalView: MTKView, MTKViewDelegate {
    let host: GameHost
    private let queue: MTLCommandQueue
    private let glowPipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private let linear: MTLSamplerState
    private var baseTextures: [MTLTexture] = []
    private var glowTexture: MTLTexture?
    private var slot = 0
    private let inflight = DispatchSemaphore(value: 3)
    private var lastTime = CACurrentMediaTime()
    /// Device pixels per art pixel, and where the canvas sits in the drawable.
    private(set) var artScale = Tuning.artScale
    private var origin = SIMD2<Int32>(0, 0)

    init(host: GameHost) {
        self.host = host
        let device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        let lib = device.makeDefaultLibrary()!
        let glow = MTLRenderPipelineDescriptor()
        glow.vertexFunction = lib.makeFunction(name: "fullscreen")
        glow.fragmentFunction = lib.makeFunction(name: "glowPass")
        glow.colorAttachments[0].pixelFormat = .rgba16Float
        glowPipeline = try! device.makeRenderPipelineState(descriptor: glow)
        let present = MTLRenderPipelineDescriptor()
        present.vertexFunction = lib.makeFunction(name: "fullscreen")
        present.fragmentFunction = lib.makeFunction(name: "presentPass")
        present.colorAttachments[0].pixelFormat = .bgra8Unorm
        presentPipeline = try! device.makeRenderPipelineState(descriptor: present)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear; sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge; sd.tAddressMode = .clampToEdge
        linear = device.makeSamplerState(descriptor: sd)!
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        preferredFramesPerSecond = 120
        isMultipleTouchEnabled = true
        delegate = self
        backgroundColor = .black
    }

    required init(coder: NSCoder) { fatalError("not used") }

    /// The largest integer scale that keeps the canvas at least `Tuning.canvasHeight` (334)
    /// art pixels on its short side. On the iPhone Duo's inner display (2853 x 2007 px) that is
    /// 6, so the canvas is 475 x 334 (2850 x 2004 px, centred: 1.5 px spare per side).
    static func fit(drawable: CGSize) -> (scale: Int, width: Int, height: Int) {
        let w = Int(drawable.width), h = Int(drawable.height)
        let scale = max(1, min(w, h) / Tuning.canvasHeight)
        return (scale, max(1, w / scale), max(1, h / scale))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        let fit = Self.fit(drawable: drawableSize)
        artScale = fit.scale
        origin = SIMD2(Int32((Int(drawableSize.width) - fit.width * fit.scale) / 2), Int32((Int(drawableSize.height) - fit.height * fit.scale) / 2))
        host.renderer.resize(width: fit.width, height: fit.height)
        host.frame(dt: dt, now: now)
        host.renderer.render(host.game)

        inflight.wait()
        ensureTextures(fit.width, fit.height)
        slot = (slot + 1) % baseTextures.count
        let base = baseTextures[slot]
        let canvas = host.renderer.canvas
        canvas.pixels.withUnsafeBytes { raw in
            base.replace(region: MTLRegionMake2D(0, 0, canvas.width, canvas.height), mipmapLevel: 0,
                         withBytes: raw.baseAddress!, bytesPerRow: canvas.width * 4)
        }
        guard let cmd = queue.makeCommandBuffer(), let glow = glowTexture else { inflight.signal(); return }
        cmd.addCompletedHandler { [inflight] _ in inflight.signal() }

        let glowOn = host.game.progress.settings.glow
        let gp = MTLRenderPassDescriptor()
        gp.colorAttachments[0].texture = glow
        gp.colorAttachments[0].loadAction = .clear
        gp.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: gp) {
            enc.setRenderPipelineState(glowPipeline)
            enc.setFragmentTexture(base, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable else { cmd.commit(); return }
        pass.colorAttachments[0].loadAction = .clear
        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass) {
            enc.setRenderPipelineState(presentPipeline)
            enc.setViewport(MTLViewport(originX: Double(origin.x), originY: Double(origin.y),
                                        width: Double(fit.width * fit.scale), height: Double(fit.height * fit.scale), znear: 0, zfar: 1))
            var u = PresentUniforms(origin: origin, scale: Int32(fit.scale), glow: glowOn ? 1 : 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<PresentUniforms>.stride, index: 0)
            enc.setFragmentTexture(base, index: 0)
            enc.setFragmentTexture(glow, index: 1)
            enc.setFragmentSamplerState(linear, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        cmd.present(drawable)
        cmd.commit()
    }

    private func ensureTextures(_ w: Int, _ h: Int) {
        if let t = baseTextures.first, t.width == w, t.height == h { return }
        guard let device else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        baseTextures = (0..<3).compactMap { _ in device.makeTexture(descriptor: d) }
        let g = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        g.usage = [.renderTarget, .shaderRead]
        g.storageMode = .private
        glowTexture = device.makeTexture(descriptor: g)
    }

    // MARK: Touch → art pixels

    private func artPoint(_ t: UITouch) -> Point {
        let p = t.location(in: self)
        let s = contentScaleFactor
        let x = (Int(p.x * s) - Int(origin.x)) / max(1, artScale)
        let y = (Int(p.y * s) - Int(origin.y)) / max(1, artScale)
        return Point(x, y)
    }

    private func id(_ t: UITouch) -> Int { ObjectIdentifier(t).hashValue }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { host.touch(.began, artPoint(t), id: id(t), now: CACurrentMediaTime()) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { host.touch(.moved, artPoint(t), id: id(t), now: CACurrentMediaTime()) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { host.touch(.ended, artPoint(t), id: id(t), now: CACurrentMediaTime()) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { host.touch(.ended, artPoint(t), id: id(t), now: CACurrentMediaTime()) }
    }
}

struct PresentUniforms {
    var origin: SIMD2<Int32>
    var scale: Int32
    var glow: Int32
}
