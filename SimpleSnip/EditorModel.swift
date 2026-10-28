import AppKit
import UniformTypeIdentifiers

enum EditorTool {
    case pen
    case highlighter
    case eraser
    case crop

    var inkKind: InkKind? {
        switch self {
        case .pen: return .pen
        case .highlighter: return .highlighter
        default: return nil
        }
    }
}

/// Everything an undo step restores: the ink and the crop.
struct EditorState: Equatable {
    var strokes: [InkStroke] = []
    var crop: CGRect
}

/// One screenshot being edited: the snip, its ink, crop, undo history and saving.
@MainActor
final class EditorModel: ObservableObject {
    let image: CGImage
    let scale: CGFloat
    let imageRect: CGRect
    let createdAt = Date()

    @Published private(set) var state: EditorState
    @Published var tool: EditorTool = .pen {
        didSet {
            if tool == .crop {
                pendingCrop = state.crop
            } else if oldValue != .crop {
                lastInkTool = tool
            }
        }
    }
    /// The crop rectangle being adjusted while the crop tool is active.
    @Published var pendingCrop: CGRect = .zero
    @Published private(set) var hasUnsavedChanges = false

    private var undoStack: [EditorState] = []
    private var redoStack: [EditorState] = []
    private var lastInkTool: EditorTool = .pen

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        imageRect = CGRect(x: 0, y: 0, width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        state = EditorState(crop: imageRect)
    }

    // MARK: Editing

    func addStroke(_ stroke: InkStroke) {
        var next = state
        next.strokes.append(stroke)
        commit(next)
    }

    /// Eraser drags remove strokes live; the whole drag becomes one undo step.
    private var stateBeforeErasing: EditorState?

    func beginErasing() {
        stateBeforeErasing = state
    }

    func erase(at point: CGPoint, tolerance: CGFloat) {
        let remaining = state.strokes.filter { !$0.contains(point, tolerance: tolerance) }
        if remaining.count != state.strokes.count {
            state.strokes = remaining
        }
    }

    func endErasing() {
        guard let before = stateBeforeErasing else { return }
        stateBeforeErasing = nil
        if before != state {
            undoStack.append(before)
            redoStack.removeAll()
            didEdit()
        }
    }

    func eraseAllInk() {
        guard !state.strokes.isEmpty else { return }
        var next = state
        next.strokes.removeAll()
        commit(next)
    }

    func applyCrop() {
        let crop = pendingCrop.intersection(imageRect)
        tool = lastInkTool
        guard crop.width >= 1, crop.height >= 1, crop != state.crop else { return }
        var next = state
        next.crop = crop
        commit(next)
    }

    func cancelCrop() {
        tool = lastInkTool
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(state)
        state = previous
        didEdit()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(state)
        state = next
        didEdit()
    }

    private func commit(_ next: EditorState) {
        undoStack.append(state)
        redoStack.removeAll()
        state = next
        didEdit()
    }

    private func didEdit() {
        hasUnsavedChanges = true
        if AppSettings.shared.autoCopyChanges {
            copyToClipboard()
        }
    }

    // MARK: Output

    /// The finished screenshot: the snip with its ink, cut to the crop, at full Retina resolution.
    func render() -> CGImage? {
        let crop = state.crop
        let width = Int((crop.width * scale).rounded())
        let height = Int((crop.height * scale).rounded())
        let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -crop.minX, y: -crop.minY)
        context.draw(image, in: imageRect)
        for stroke in state.strokes {
            stroke.draw(in: context)
        }
        return context.makeImage()
    }

    func copyToClipboard() {
        if let rendered = render() {
            Clipboard.copy(rendered)
        }
    }

    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        return "Screenshot \(formatter.string(from: createdAt))"
    }

    /// Shows the save panel. `completion` gets true once the file is written.
    func save(from window: NSWindow?, completion: ((Bool) -> Void)? = nil) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [.png, .jpeg]
        panel.showsContentTypes = true
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else {
                completion?(false)
                return
            }
            let saved = self.write(to: url)
            if saved {
                self.hasUnsavedChanges = false
            }
            completion?(saved)
        }

        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    func discardChanges() {
        hasUnsavedChanges = false
    }

    private func write(to url: URL) -> Bool {
        guard let rendered = render() else { return false }
        let isJPEG = UTType(filenameExtension: url.pathExtension)?.conforms(to: .jpeg) == true
        let output = isJPEG ? Self.flattenedOnWhite(rendered) ?? rendered : rendered

        let bitmap = NSBitmapImageRep(cgImage: output)
        let data = isJPEG
            ? bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            : bitmap.representation(using: .png, properties: [:])
        guard let data else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// JPEG has no transparency, so the area outside a freeform shape becomes white.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(.white)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
