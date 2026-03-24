import SwiftUI
import UIKit

@main
struct VinoPhoneApp: App {
    init() {
        UIApplication.shared.isIdleTimerDisabled = true
    }

    var body: some Scene {
        WindowGroup {
            VinoPhoneShellView()
                .preferredColorScheme(.dark)
        }
    }
}
