import SkylineUI
import SwiftUI
import UIKit

@main
struct SkylineLensApp: App {
    init() {
        // Ambient mode: the iPad lives on a window, so never let the screen sleep.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            LiveView()
                .preferredColorScheme(.dark)
        }
    }
}
