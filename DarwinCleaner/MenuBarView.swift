import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var cleaner: CleanerViewModel

    var body: some View {
        Button(cleaner.isBusy ? "Working…" : "Scan Now") {
            cleaner.scan()
        }
        .disabled(cleaner.isBusy)

        if !cleaner.items.isEmpty {
            Text("Found: \(cleaner.items.reduce(0) { $0 + $1.size }.formattedBytes)")
            Button("Open Darwin Cleaner") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            }
        }

        Divider()
        SettingsLink { Text("Settings…") }
        Button("Quit") { NSApp.terminate(nil) }
    }
}
