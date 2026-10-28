import AppKit
import OSLog
import ScreenCaptureKit

private let log = Logger(subsystem: "com.pavloff.SimpleSnip", category: "Snip")

/// A still image of one display, taken just before the snip overlay appears.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
}

/// Runs one snip: freezes every display, lets the user draw a freeform shape, then copies the result.
@MainActor
final class SnipController {
    static let shared = SnipController()

    private var overlays: [SnipOverlayWindow] = []
    private var isSnipping = false

    func startSnip() {
        guard !isSnipping else { return }

        // Ask ScreenCaptureKit directly rather than CGPreflightScreenCaptureAccess(), whose answer
        // stays "denied" until relaunch even after the user grants permission.
        isSnipping = true
        Task {
            do {
                let frozenScreens = try await Self.captureAllScreens()
                guard !frozenScreens.isEmpty else {
                    isSnipping = false
                    return
                }
                showOverlays(for: frozenScreens)
            } catch {
                isSnipping = false
                log.error("Screen capture failed: \(error.localizedDescription, privacy: .public)")
                CGRequestScreenCaptureAccess()
                showPermissionAlert()
            }
        }
    }

    private func showOverlays(for frozenScreens: [FrozenScreen]) {
        overlays = frozenScreens.map { frozen in
            SnipOverlayWindow(frozen: frozen) { [weak self] image in
                self?.finish(with: image, scale: frozen.screen.backingScaleFactor)
            }
        }
        NSApp.activate()
        for overlay in overlays {
            overlay.orderFrontRegardless()
        }
        // Start with keyboard focus on the screen under the pointer so Esc works right away.
        let mouse = NSEvent.mouseLocation
        let focused = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        focused?.makeKey()
    }

    private func finish(with image: CGImage?, scale: CGFloat) {
        for overlay in overlays {
            overlay.orderOut(nil)
        }
        overlays.removeAll()
        isSnipping = false

        if let image {
            Clipboard.copy(image)
            EditorWindowController.open(image: image, scale: scale)
        } else if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            // Cancelled: hand focus back to the app the user was working in.
            NSApp.hide(nil)
        }
    }

    private static func captureAllScreens() async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [FrozenScreen] = []

        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { continue }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
            configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
            configuration.showsCursor = false
            configuration.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            result.append(FrozenScreen(screen: screen, image: image))
        }
        return result
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Simple Snip needs permission to capture the screen"
        alert.informativeText = """
            Open System Settings → Privacy & Security → Screen & System Audio Recording, \
            turn on Simple Snip, then try again. You may need to quit and reopen Simple Snip.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum Clipboard {
    static func copy(_ image: CGImage) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }
}
