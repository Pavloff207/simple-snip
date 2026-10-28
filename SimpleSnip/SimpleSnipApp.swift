import SwiftUI

@main
struct SimpleSnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Simple Snip", systemImage: "scissors") {
            MenuContent()
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyCenter.shared.onPress = {
            SnipController.shared.startSnip()
        }
        AppSettings.shared.registerHotKey()
    }

    /// Clicking the Dock icon starts a snip, unless an editor window is open to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            SnipController.shared.startSnip()
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Snip", action: #selector(newSnipFromDock), keyEquivalent: "")
            .target = self
        return menu
    }

    @objc private func newSnipFromDock() {
        SnipController.shared.startSnip()
    }
}

private struct MenuContent: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button("New Snip  (\(settings.snipShortcut.displayString))") {
            SnipController.shared.startSnip()
        }

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Simple Snip") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
