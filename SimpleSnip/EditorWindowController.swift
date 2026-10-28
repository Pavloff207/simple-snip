import AppKit
import SwiftUI

/// One editor window per snip.
@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openEditors: Set<EditorWindowController> = []

    private let model: EditorModel

    static func open(image: CGImage, scale: CGFloat) {
        let controller = EditorWindowController(model: EditorModel(image: image, scale: scale))
        openEditors.insert(controller)
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(model: EditorModel) {
        self.model = model

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Simple Snip"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let hosting = NSHostingController(rootView: EditorView(model: model) { [weak window] in window })
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.delegate = self
        window.setContentSize(Self.initialContentSize(for: model.imageRect.size, on: NSScreen.main))
        window.contentMinSize = CGSize(width: 420, height: 240)
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Big enough to show the snip at 100% plus the toolbar, but never larger than most of the screen.
    private static func initialContentSize(for imageSize: CGSize, on screen: NSScreen?) -> CGSize {
        let toolbarHeight: CGFloat = 45
        let margin: CGFloat = 24
        let available = screen?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        return CGSize(
            width: min(max(imageSize.width + margin * 2, 420), available.width * 0.85),
            height: min(max(imageSize.height + margin * 2 + toolbarHeight, 240), available.height * 0.85)
        )
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.hasUnsavedChanges, AppSettings.shared.askToSaveEdits else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this screenshot?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                self.model.save(from: sender) { saved in
                    if saved { sender.close() }
                }
            case .alertSecondButtonReturn:
                self.model.discardChanges()
                sender.close()
            default:
                break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        Self.openEditors.remove(self)
    }
}
