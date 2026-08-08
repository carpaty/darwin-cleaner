import SwiftUI

@main
struct DarwinCleanerApp: App {
    @StateObject private var cleaner = CleanerViewModel()
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cleaner)
                .frame(minWidth: 860, minHeight: 600)
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Scan Now") { cleaner.scan() }
                    .keyboardShortcut("r", modifiers: [.command])
                    .disabled(cleaner.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(cleaner)
                .frame(width: 460, height: 260)
        }

        MenuBarExtra("Darwin Cleaner", systemImage: "sparkles", isInserted: $showMenuBarItem) {
            MenuBarView()
                .environmentObject(cleaner)
        }
        .menuBarExtraStyle(.menu)
    }
}
