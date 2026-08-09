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

    @objc private func showMainWindow(_ sender: Any?) {
        AppController.shared.showMainWindow()
    }

    @objc private func showSettings(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: self) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: self)
        }
    }

    @objc private func showAbout(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(sender)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard isMenuBarItemEnabled else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard self?.isMenuBarItemEnabled == true else { return }
            let hasVisibleWindow = NSApp.windows.contains {
                $0.isVisible && $0.canBecomeMain
            }
            if !hasVisibleWindow {
                NSApp.setActivationPolicy(.accessory)
            }
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
                let image = NSApp.applicationIconImage.copy() as? NSImage
                image?.size = NSSize(width: 18, height: 18)
                image?.isTemplate = false
                image?.accessibilityDescription = "Darwin Cleaner"
                button.image = image
                button.toolTip = "Open Darwin Cleaner"
            }
            item.menu = makeStatusMenu()
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            NSApp.setActivationPolicy(.regular)
        }
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem(title: "Open Darwin Cleaner", action: #selector(showMainWindow(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Settings…", action: #selector(showSettings(_:))))
        menu.addItem(menuItem(title: "About Darwin Cleaner", action: #selector(showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "Quit Darwin Cleaner", action: #selector(quit(_:)), keyEquivalent: "q"))
        return menu
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }
}
