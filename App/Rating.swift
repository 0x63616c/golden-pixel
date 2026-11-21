import StoreKit
import UIKit

/// App Store ratings. The only StoreKit in the app: no products, no purchases, nothing read
/// back (`tools/appstore.py check` holds it to that).
@MainActor
enum Rating {
    /// Golden Pixel's Apple ID on the App Store (App Store Connect > App Information).
    static let appStoreID = "6837348992"

    /// Asks iOS to show its rating prompt, a moment after the new level has drawn. iOS decides
    /// whether anything appears: at most three times a year, never in a TestFlight build,
    /// every time in a build run from Xcode.
    static func ask() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) else { return }
            AppStore.requestReview(in: scene)
        }
    }

    /// Opens the App Store on the game's "write a review" page (the settings card's RATE button).
    static func openReviewPage() {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review") else { return }
        UIApplication.shared.open(url)
    }
}
