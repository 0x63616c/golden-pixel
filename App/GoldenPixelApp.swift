import SwiftUI

/// The app shell. SwiftUI owns the window and lifecycle; the whole game, HUD and panel are one
/// pixel-perfect frame drawn by `GoldenPixelCore` and presented by `PixelView` through Metal.
@main
struct GoldenPixelApp: App {
    @Environment(\.scenePhase) private var phase
    @State private var host = GameHost()

    var body: some Scene {
        WindowGroup {
            PixelView(host: host)
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
                .background(Color.black)
                .onChange(of: phase) { _, p in
                    if p != .active { host.save() }
                    host.paused = p != .active
                }
        }
    }
}
