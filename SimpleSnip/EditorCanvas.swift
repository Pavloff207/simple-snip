import AppKit
import Combine
import SwiftUI

struct EditorCanvas: NSViewRepresentable {
    let model: EditorModel

    func makeNSView(context: Context) -> EditorCanvasView {
        EditorCanvasView(model: model)
    }

    func updateNSView(_ view: EditorCanvasView, context: Context) {
        view.needsDisplay = true
    }
}

/// Shows the screenshot with its ink and handles drawing, erasing and the crop frame.
final class EditorCanvasView: NSView {
    private let model: EditorModel
    private var changes: AnyCancellable?
    private var styleChanges: AnyCancellable?
    private var liveStroke: InkStroke?
    private var cropDrag: CropDrag?

    private let cropPadding: CGFloat = 20
    private let handleSize: CGFloat = 10

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
        // The pen and highlighter cursors follow the chosen color and size.
        styleChanges = AppSettings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    /// The part of the image on screen: the crop, or the whole image while cropping.
    private var visibleRegion: CGRect {
        model.tool == .crop ? model.imageRect : model.state.crop
    }

    /// Fits the visible region into the view, centered, never enlarged beyond 100%.
    private var imageToView: CGAffineTransform {
        let region = visibleRegion
        let padding = model.tool == .crop ? cropPadding : 0
        let available = bounds.insetBy(dx: padding, dy: padding)
        let zoom = max(0.01, min(1, available.width / region.width, available.height / region.height))
        let size = CGSize(width: region.width * zoom, height: region.height * zoom)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2)
        return CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: zoom, y: zoom)
            .translatedBy(x: -region.minX, y: -region.minY)
    }

    private func imagePoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil).applying(imageToView.inverted())
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()

        let region = visibleRegion
        context.saveGState()
        context.concatenate(imageToView)
        context.clip(to: region)
        context.draw(model.image, in: model.imageRect)
        for stroke in model.state.strokes {
            stroke.draw(in: context)
        }
        liveStroke?.draw(in: context)
        context.restoreGState()

        if model.tool == .crop {
            drawCropFrame()
        }
    }

    private func drawCropFrame() {
        let full = model.imageRect.applying(imageToView)
        let crop = model.pendingCrop.applying(imageToView)

        let shade = NSBezierPath(rect: full)
        shade.append(NSBezierPath(rect: crop))
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill()
        shade.fill()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: crop)
        border.lineWidth = 1.5
        border.stroke()

        // Rule-of-thirds guides, as most crop tools show.
        NSColor.white.withAlphaComponent(0.4).setStroke()
        for third in [1.0 / 3, 2.0 / 3] {
            let guides = NSBezierPath()
            guides.move(to: CGPoint(x: crop.minX + crop.width * third, y: crop.minY))
            guides.line(to: CGPoint(x: crop.minX + crop.width * third, y: crop.maxY))
            guides.move(to: CGPoint(x: crop.minX, y: crop.minY + crop.height * third))
            guides.line(to: CGPoint(x: crop.maxX, y: crop.minY + crop.height * third))
            guides.lineWidth = 0.5
            guides.stroke()
        }

        NSColor.white.setFill()
        for corner in [
            CGPoint(x: crop.minX, y: crop.minY), CGPoint(x: crop.maxX, y: crop.minY),
            CGPoint(x: crop.minX, y: crop.maxY), CGPoint(x: crop.maxX, y: crop.maxY),
        ] {
            NSBezierPath(rect: CGRect(
                x: corner.x - handleSize / 2, y: corner.y - handleSize / 2,
                width: handleSize, height: handleSize
            )).fill()
        }
    }

    override func resetCursorRects() {
        switch model.tool {
        case .pen, .highlighter:
            guard let kind = model.tool.inkKind else { return }
            let style = AppSettings.shared.style(for: kind)
            addCursorRect(bounds, cursor: InkCursor.make(kind: kind, style: style, zoom: imageToView.a))
        case .eraser:
            addCursorRect(bounds, cursor: InkCursor.eraser(diameter: eraserTolerance * 2 * imageToView.a))
        case .crop:
            addCursorRect(model.pendingCrop.applying(imageToView), cursor: .openHand)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = imagePoint(for: event)
        switch model.tool {
        case .pen, .highlighter:
            guard let kind = model.tool.inkKind else { return }
            liveStroke = InkStroke(kind: kind, style: AppSettings.shared.style(for: kind), points: [point])
            needsDisplay = true
        case .eraser:
            model.beginErasing()
            model.erase(at: point, tolerance: eraserTolerance)
        case .crop:
            cropDrag = CropDrag(
                edges: cropEdges(at: convert(event.locationInWindow, from: nil)),
                start: point,
                original: model.pendingCrop
            )
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(for: event)
        switch model.tool {
        case .pen, .highlighter:
            liveStroke?.points.append(point)
            needsDisplay = true
        case .eraser:
            model.erase(at: point, tolerance: eraserTolerance)
        case .crop:
            guard let cropDrag else { return }
            model.pendingCrop = cropDrag.updated(to: point, within: model.imageRect)
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch model.tool {
        case .pen, .highlighter:
            if let liveStroke {
                model.addStroke(liveStroke)
            }
            liveStroke = nil
        case .eraser:
            model.endErasing()
        case .crop:
            cropDrag = nil
            window?.invalidateCursorRects(for: self)
        }
    }

    /// About 6 screen points around the pointer, whatever the zoom.
    private var eraserTolerance: CGFloat {
        6 / max(imageToView.a, 0.01)
    }

    private func cropEdges(at viewPoint: CGPoint) -> CropDrag.Edges {
        let crop = model.pendingCrop.applying(imageToView)
        let grab = handleSize
        var edges: CropDrag.Edges = []
        let withinX = viewPoint.x > crop.minX - grab && viewPoint.x < crop.maxX + grab
        let withinY = viewPoint.y > crop.minY - grab && viewPoint.y < crop.maxY + grab
        if withinY, abs(viewPoint.x - crop.minX) < grab { edges.insert(.left) }
        if withinY, abs(viewPoint.x - crop.maxX) < grab { edges.insert(.right) }
        if withinX, abs(viewPoint.y - crop.minY) < grab { edges.insert(.bottom) }
        if withinX, abs(viewPoint.y - crop.maxY) < grab { edges.insert(.top) }
        if edges.isEmpty, crop.contains(viewPoint) { edges = .all }
        return edges
    }
}

/// One drag of the crop frame: by an edge, a corner (two edges), or the whole frame.
private struct CropDrag {
    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let bottom = Edges(rawValue: 4)
        static let top = Edges(rawValue: 8)
        static let all: Edges = [.left, .right, .bottom, .top]
    }

    let edges: Edges
    let start: CGPoint
    let original: CGRect

    private let minimumSize: CGFloat = 8

    func updated(to point: CGPoint, within bounds: CGRect) -> CGRect {
        let dx = point.x - start.x
        let dy = point.y - start.y

        if edges == .all {
            var moved = original.offsetBy(dx: dx, dy: dy)
            moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
            moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
            return moved
        }

        var minX = original.minX, maxX = original.maxX
        var minY = original.minY, maxY = original.maxY
        if edges.contains(.left) { minX = min(max(bounds.minX, original.minX + dx), maxX - minimumSize) }
        if edges.contains(.right) { maxX = max(min(bounds.maxX, original.maxX + dx), minX + minimumSize) }
        if edges.contains(.bottom) { minY = min(max(bounds.minY, original.minY + dy), maxY - minimumSize) }
        if edges.contains(.top) { maxY = max(min(bounds.maxY, original.maxY + dy), minY + minimumSize) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Pointers that show the tip of the current tool at its real size on screen.
private enum InkCursor {
    /// Big enough for the thickest highlighter at 100%, small enough for macOS to accept.
    private static let maxSize: CGFloat = 96

    static func make(kind: InkKind, style: InkStyle, zoom: CGFloat) -> NSCursor {
        let tip = min(max(style.width * zoom, 1), maxSize)
        switch kind {
        case .pen:
            // A round dot in the pen's color, like the end of a felt-tip.
            let diameter = max(tip, 4)
            return cursor(size: CGSize(width: diameter, height: diameter)) { rect in
                let dot = NSBezierPath(ovalIn: rect)
                style.color.setFill()
                dot.fill()
                outline(dot)
            }
        case .highlighter:
            // A tall chisel tip, as tall as the highlight is thick.
            let height = max(tip, 8)
            let width = max(height / 3, 4)
            return cursor(size: CGSize(width: width, height: height)) { rect in
                let chisel = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
                style.color.withAlphaComponent(0.55).setFill()
                chisel.fill()
                outline(chisel)
            }
        }
    }

    /// An empty ring that matches what the eraser touches.
    static func eraser(diameter: CGFloat) -> NSCursor {
        let size = min(max(diameter, 8), maxSize)
        return cursor(size: CGSize(width: size, height: size)) { rect in
            let ring = NSBezierPath(ovalIn: rect)
            NSColor.white.withAlphaComponent(0.35).setFill()
            ring.fill()
            outline(ring)
        }
    }

    /// Draws the tip centered on the hot spot, with room for its outline.
    private static func cursor(size: CGSize, draw: @escaping (CGRect) -> Void) -> NSCursor {
        let margin: CGFloat = 2
        let canvas = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let image = NSImage(size: canvas, flipped: false) { _ in
            draw(CGRect(origin: CGPoint(x: margin, y: margin), size: size))
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: canvas.width / 2, y: canvas.height / 2))
    }

    /// A dark ring inside a light one, so the tip shows up on any background.
    private static func outline(_ path: NSBezierPath) {
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 2
        path.stroke()
        NSColor.black.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
