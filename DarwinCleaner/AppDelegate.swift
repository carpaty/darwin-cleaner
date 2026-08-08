import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange(_:)),
            name: UserDefaults.didChangeNotification,
            object: UserDefaults.standard
        )
        updateStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        AppController.shared.showMainWindow()
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard isMenuBarItemEnabled,
              let closingWindow = notification.object as? NSWindow else { return }
        let hasAnotherVisibleWindow = NSApp.windows.contains {
            $0 !== closingWindow && $0.isVisible && $0.canBecomeMain
        }
        if !hasAnotherVisibleWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc nonisolated private func defaultsDidChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.updateStatusItem()
        }
    }

    private var isMenuBarItemEnabled: Bool {
        UserDefaults.standard.object(forKey: "showMenuBarItem") == nil
            || UserDefaults.standard.bool(forKey: "showMenuBarItem")
    }

    private func updateStatusItem() {
        if isMenuBarItemEnabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Darwin Cleaner")
                button.image?.isTemplate = true
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.toolTip = "Open Darwin Cleaner"
            }
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            NSApp.setActivationPolicy(.regular)
        }
    }
}
