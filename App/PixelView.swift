import GoldenPixelCore
import MetalKit
import SwiftUI

struct PixelView: UIViewRepresentable {
    let host: GameHost
    func makeUIView(context: Context) -> PixelMetalView { PixelMetalView(host: host) }
    func updateUIView(_ view: PixelMetalView, context: Context) {}
}

/// Presents the art-pixel canvas. Every frame the CPU draws the canvas. When it differs from
/// the last one, it is uploaded as one texture, a small pass blurs its glow channel at art
/// resolution (only with the glow setting on), and the final pass draws it at an integer scale
/// with exact texel reads (no filtering) plus the soft glow on top. A frame that came out the
/// same as the last is not uploaded or presented: the screen already shows it.
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
    /// How the canvas sits on the screen (`display()`), kept between frames: reading the
    /// window's safe area every frame is not free. Dropped when the view lays out or its
    /// safe area changes, and re-read once a second in any case.
    private var fit: Display?
    private var fitSize = CGSize.zero
    private var fitAge = 0
    /// The next frame goes to the screen even if the canvas has not changed: the first one,
    /// and after anything that changes where or how it is shown.
    private var mustPresent = true
    private var wasPaused = false
    /// The glow setting the screen last showed.
    private var shownGlow = false

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

    /// How the canvas sits in the drawable (`Display.fit` in the core): one art pixel is 2
    /// points on every screen, so the Duo's inner display (2853 x 2007 px at @3x) gets a
    /// 475 x 334 canvas at scale 6 and an iPhone 18 Pro (2622 x 1206 px) gets 437 x 201 at the
    /// same scale. The safe area goes with it, so the layout keeps clear of the Dynamic Island
    /// and the home indicator.
    func display() -> Display {
        let i = window?.safeAreaInsets ?? safeAreaInsets
        return Display.fit(pixelWidth: Int(drawableSize.width), pixelHeight: Int(drawableSize.height),
                           pointScale: Double(contentScaleFactor),
                           safe: (Double(i.left), Double(i.top), Double(i.right), Double(i.bottom)))
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { fit = nil; mustPresent = true }

    override func layoutSubviews() { super.layoutSubviews(); fit = nil }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); fit = nil }
    override func didMoveToWindow() { super.didMoveToWindow(); fit = nil; mustPresent = true }

    private func currentFit() -> Display {
        fitAge += 1
        if let f = fit, fitAge < 120, fitSize == drawableSize { return f }
        let f = display()
        if f != fit { mustPresent = true }
        fit = f; fitSize = drawableSize; fitAge = 0
        noteScreen(f)
        return f
    }

    /// Staged scenes only: notes the safe area (in points), the screen's pixels per point and
    /// the art scale next to the save file, so the screenshot tools (`ios/ios.sh compare`) can
    /// draw what the island and the home indicator cover on each phone and grid-check it.
    private func noteScreen(_ d: Display) {
        guard host.scene != nil else { return }
        let i = window?.safeAreaInsets ?? safeAreaInsets
        let json = "{\"top\": \(i.top), \"left\": \(i.left), \"bottom\": \(i.bottom), \"right\": \(i.right), "
            + "\"scale\": \(contentScaleFactor), \"art\": \(d.scale)}\n"
        guard json != screenNote else { return }
        screenNote = json
        try? json.write(to: SaveStore.url.deletingLastPathComponent().appendingPathComponent("safe-area.json"),
                        atomically: true, encoding: .utf8)
    }
    private var screenNote = ""

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now
        let fit = currentFit()
        artScale = fit.scale
        origin = SIMD2(Int32(fit.originX), Int32(fit.originY))
        host.renderer.resize(to: fit)
        host.frame(dt: dt, now: now)
        // Not the active app: the game stands still, so there is nothing new to draw.
        if host.paused != wasPaused { wasPaused = host.paused; mustPresent = true }
        if host.paused && !mustPresent { return }
        host.renderer.render(host.game)
        let glowOn = host.game.progress.settings.glow
        guard host.renderer.changed || mustPresent || glowOn != shownGlow else { return }

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

        // The glow pass only runs with the setting on: the final pass does not read it otherwise.
        if glowOn {
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
        mustPresent = false
        shownGlow = glowOn
    }

    private func ensureTextures(_ w: Int, _ h: Int) {
        if let t = baseTextures.first, t.width == w, t.height == h { return }
        guard let device else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        // Rewritten from the CPU every frame: keeping it in the GPU's own compressed layout
        // costs more on each upload than it saves on the one read.
        d.allowGPUOptimizedContents = false
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
