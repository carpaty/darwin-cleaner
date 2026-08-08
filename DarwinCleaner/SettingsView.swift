import SwiftUI

struct SettingsView: View {
    @AppStorage("showMenuBarItem") private var showMenuBarItem = true
    @AppStorage("launchAtLoginRequested") private var launchAtLoginRequested = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show icon in the menu bar", isOn: $showMenuBarItem)
                Toggle("Launch at login", isOn: $launchAtLoginRequested)
                    .disabled(true)
                Text("Launch at login will be enabled after the app is signed and distributed with a stable bundle identifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Privacy") {
                Text("Darwin Cleaner scans only known folders in your home directory. It does not upload file names or analytics.")
                    .foregroundStyle(.secondary)
            }
            Section("Safety") {
                Text("Backups, installers, archives, app leftovers, and command-based cleaners are never selected automatically.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
