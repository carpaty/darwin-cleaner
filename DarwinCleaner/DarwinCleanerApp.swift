import SwiftUI

@main
struct DarwinCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var cleaner = CleanerViewModel()

    var body: some Scene {
        WindowGroup("Darwin Cleaner", id: AppController.mainWindowID) {
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

    }
}
