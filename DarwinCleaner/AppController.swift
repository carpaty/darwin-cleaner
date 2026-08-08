import AppKit
import SwiftUI

@MainActor
final class AppController {
    static let shared = AppController()
    static let mainWindowID = "main"

    private var openWindowAction: OpenWindowAction?

    private init() {}

    func install(openWindowAction: OpenWindowAction) {
        self.openWindowAction = openWindowAction
    }

    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openWindowAction?(id: Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        }
    }
}

