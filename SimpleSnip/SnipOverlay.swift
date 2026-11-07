import AppKit

/// A full-screen borderless window that shows the frozen screen and takes the snip outline.
final class SnipOverlayWindow: NSWindow {
    init(frozen: FrozenScreen, mode: SnipMode, onFinish: @escaping (CGImage?) -> Void) {
        super.init(
            contentRect: frozen.screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = SnipSelectionView(
            frozenImage: frozen.image,
            scale: frozen.screen.backingScaleFactor,
            mode: mode,
            onFinish: onFinish
        )
        setFrame(frozen.screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}

/// Takes a freeform outline or a dragged rectangle, depending on the snip mode.
final class SnipSelectionView: NSView {
    private let frozenImage: CGImage
    private let scale: CGFloat
    private let mode: SnipMode
    private let onFinish: (CGImage?) -> Void
    private var path: NSBezierPath?
    private var dragStart: CGPoint = .zero

    init(frozenImage: CGImage, scale: CGFloat, mode: SnipMode, onFinish: @escaping (CGImage?) -> Void) {
        self.frozenImage = frozenImage
        self.scale = scale
        self.mode = mode
        self.onFinish = onFinish
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.draw(frozenImage, in: bounds)
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill(using: .sourceOver)

        guard let path else { return }

        // Show the area being snipped at full brightness.
        context.saveGState()
        path.addClip()
        context.draw(frozenImage, in: bounds)
        context.restoreGState()

        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        NSColor.black.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 3
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        switch mode {
        case .freeform:
            let newPath = NSBezierPath()
            newPath.move(to: dragStart)
            path = newPath
        case .rectangle:
            path = NSBezierPath(rect: CGRect(origin: dragStart, size: .zero))
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch mode {
        case .freeform:
            path?.line(to: point)
        case .rectangle:
            let rect = CGRect(
                x: min(dragStart.x, point.x), y: min(dragStart.y, point.y),
                width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y)
            )
            // Whole points keep the snip's edges crisp.
            path = NSBezierPath(rect: rect.integral)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let path else { return }
        path.close()

        // A click or a tiny scribble isn't a snip; let the user try again.
        guard path.bounds.width >= 4, path.bounds.height >= 4 else {
            self.path = nil
            needsDisplay = true
            return
        }
        onFinish(Self.crop(frozenImage, to: path, scale: scale))
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 /* Esc */ {
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    /// Cuts the shape out of the frozen screen. Pixels outside the shape are transparent.
    static func crop(_ image: CGImage, to path: NSBezierPath, scale: CGFloat) -> CGImage? {
        var toPixels = CGAffineTransform(scaleX: scale, y: scale)
        guard let pixelPath = path.cgPath.copy(using: &toPixels) else { return nil }

        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let box = pixelPath.boundingBoxOfPath.integral.intersection(imageRect)
        guard box.width >= 1, box.height >= 1 else { return nil }

        let colorSpace = image.colorSpace.flatMap { $0.supportsOutput ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(box.width),
            height: Int(box.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: -box.minX, y: -box.minY)
        context.addPath(pixelPath)
        context.clip()
        context.draw(image, in: imageRect)
        return context.makeImage()
    }
}
