// Renders the README and website visuals with the app's own snipping and editor code.
// Run Tools/demo/make_demo.sh; it writes PNGs and an animated GIF to the output folder.

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import WebKit

@MainActor
enum Demo {
    static let pageSize = CGSize(width: 1280, height: 800)
    static var scale: CGFloat = 2
    static var outputFolder = URL(fileURLWithPath: ".")
    static var iconFile = URL(fileURLWithPath: "icon.png")

    static func run(page: URL) async throws {
        // Keep the demo away from the real clipboard and the user's saved pen colors.
        let settings = AppSettings.shared
        settings.autoCopyChanges = false
        settings.penStyle = InkStyle(colorHex: "#E61B1B", width: 4)
        settings.highlighterStyle = InkStyle(colorHex: "#FFE14D", width: 22)

        let screen = try await snapshot(of: page)
        let lasso = lassoPath()

        // 1. The snip: the outline appears over the frozen, dimmed screen.
        var snipFrames: [CGImage] = []
        let steps = 28
        for step in 1...steps {
            let partial = lasso.prefix(Int(Double(lasso.count) * Double(step) / Double(steps)))
            snipFrames.append(drawSnipScreen(screen, outline: Array(partial), closed: step == steps))
        }
        try write(snipFrames.last!, named: "snip.png")

        // 2. The editor with the cut-out shape.
        let outline = NSBezierPath()
        outline.move(to: lasso[0])
        for point in lasso.dropFirst() { outline.line(to: point) }
        outline.close()
        guard let snip = SnipSelectionView.crop(screen, to: outline, scale: scale) else {
            throw DemoError("Couldn't cut out the snip")
        }
        let box = outline.bounds.integral
        let model = EditorModel(image: snip, scale: scale)

        func local(_ points: [CGPoint]) -> [CGPoint] {
            // Page points (origin top-left) to snip points (origin bottom-left).
            points.map { CGPoint(x: $0.x - box.minX, y: (pageSize.height - $0.y) - box.minY) }
        }

        var editorFrames: [CGImage] = []
        let window = makeEditorWindow(model: model)
        editorFrames.append(try capture(window))

        // Highlight the summer months, then circle the hottest one and point at it.
        let highlight = local(stride(from: 0.0, through: 1.0, by: 0.05).map {
            CGPoint(x: 398 + 160 * $0, y: 522 - 3 * sin($0 * .pi))
        })
        model.tool = .highlighter
        for count in stride(from: 4, through: highlight.count, by: 4) {
            editorFrames.append(try capture(window, live: InkStroke(kind: .highlighter, style: settings.highlighterStyle, points: Array(highlight.prefix(count))), model: model))
        }
        model.addStroke(InkStroke(kind: .highlighter, style: settings.highlighterStyle, points: highlight))

        let circle = local(stride(from: 0.0, through: 1.12, by: 0.04).map {
            let angle = $0 * 2 * .pi - .pi / 2
            return CGPoint(x: 536 + 48 * cos(angle) * (1 + 0.06 * $0), y: 300 + 30 * sin(angle))
        })
        model.tool = .pen
        for count in stride(from: 4, through: circle.count, by: 4) {
            editorFrames.append(try capture(window, live: InkStroke(kind: .pen, style: settings.penStyle, points: Array(circle.prefix(count))), model: model))
        }
        model.addStroke(InkStroke(kind: .pen, style: settings.penStyle, points: circle))

        let arrow = local([CGPoint(x: 360, y: 246), CGPoint(x: 410, y: 256), CGPoint(x: 452, y: 272), CGPoint(x: 482, y: 290)])
        let arrowHead = local([CGPoint(x: 462, y: 287), CGPoint(x: 484, y: 291), CGPoint(x: 476, y: 271)])
        model.addStroke(InkStroke(kind: .pen, style: settings.penStyle, points: arrow))
        editorFrames.append(try capture(window))
        model.addStroke(InkStroke(kind: .pen, style: settings.penStyle, points: arrowHead))
        let finished = try capture(window)
        editorFrames.append(finished)
        try write(finished, named: "editor.png")

        // 3. One animated GIF: snip, pause, edit, pause.
        var frames: [(CGImage, Double)] = [(drawSnipScreen(screen, outline: [], closed: false), 0.8)]
        frames += snipFrames.map { ($0, 0.045) }
        frames.append((snipFrames.last!, 0.7))
        frames += editorFrames.map { (onBackdrop($0), 0.07) }
        frames.append((onBackdrop(finished), 2.5))
        try writeGIF(frames, named: "demo.gif", width: 960)

        // 4. The card shown when the project link is shared.
        try write(socialCard(editor: finished), named: "social-preview.png")
    }

    /// 1280×640: the icon, name and tagline on the left, the editor on the right.
    private static func socialCard(editor: CGImage) throws -> CGImage {
        guard let icon = NSImage(contentsOf: iconFile)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw DemoError("No icon at \(iconFile.path)")
        }
        let size = CGSize(width: 1280, height: 640)
        return withScale(1) {
            bitmap(size: size) { context in
                let bounds = CGRect(origin: .zero, size: size)
                let colors = [NSColor(hex: "#1E3A8A").cgColor, NSColor(hex: "#4F46E5").cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])

                context.draw(icon, in: CGRect(x: 72, y: 380, width: 150, height: 150))

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                let title: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 76, weight: .bold), .foregroundColor: NSColor.white,
                ]
                let body: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 32, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85),
                ]
                NSAttributedString(string: "Simple Snip", attributes: title).draw(at: CGPoint(x: 72, y: 268))
                NSAttributedString(string: "Freeform screen snips\nfor macOS, with pen\nand highlighter.", attributes: body)
                    .draw(in: CGRect(x: 76, y: 70, width: 470, height: 180))
                NSGraphicsContext.restoreGraphicsState()

                let width: CGFloat = 640
                let height = width * CGFloat(editor.height) / CGFloat(editor.width)
                let rect = CGRect(x: 580, y: (size.height - height) / 2, width: width, height: height)
                let shape = CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -16), blur: 44, color: NSColor.black.withAlphaComponent(0.4).cgColor)
                context.addPath(shape)
                context.setFillColor(NSColor.white.cgColor)
                context.fillPath()
                context.restoreGState()
                context.saveGState()
                context.addPath(shape)
                context.clip()
                context.interpolationQuality = .high
                context.draw(editor, in: rect)
                context.restoreGState()
            }
        }
    }

    private static func withScale<T>(_ value: CGFloat, _ body: () -> T) -> T {
        let saved = scale
        scale = value
        defer { scale = saved }
        return body()
    }

    // MARK: The page

    private static func snapshot(of page: URL) async throws -> CGImage {
        let webView = WKWebView(frame: CGRect(origin: .zero, size: pageSize))
        let window = NSWindow(contentRect: webView.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = webView
        let loaded = LoadWaiter()
        webView.navigationDelegate = loaded
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        await loaded.wait()
        try await Task.sleep(for: .milliseconds(400))

        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(pageSize.width))
        let image = try await webView.takeSnapshot(configuration: configuration)
        var rect = CGRect(origin: .zero, size: CGSize(width: pageSize.width * scale, height: pageSize.height * scale))
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw DemoError("No page snapshot")
        }
        return resized(cgImage, to: rect.size)
    }

    /// A hand-drawn loop around the chart card, in page points (origin top-left).
    private static func lassoPath() -> [CGPoint] {
        let center = CGPoint(x: 388, y: 402)
        // A rounded-square loop, like a quick hand-drawn outline around a card.
        func squarish(_ value: Double) -> Double { value < 0 ? -pow(-value, 0.6) : pow(value, 0.6) }
        return stride(from: 0.0, through: 1.0, by: 0.01).map { t in
            let angle = t * 2 * .pi + .pi * 0.85
            // Whole-number wobbles so the outline closes without a kink.
            let wobble = 1 + 0.012 * sin(t * 2 * .pi * 3) + 0.008 * cos(t * 2 * .pi * 7)
            let x = center.x + 334 * squarish(cos(angle)) * wobble
            let y = center.y + 212 * squarish(sin(angle)) * wobble
            // Flip to bottom-left origin, as AppKit views use.
            return CGPoint(x: x, y: pageSize.height - y)
        }
    }

    private static func drawSnipScreen(_ screen: CGImage, outline: [CGPoint], closed: Bool) -> CGImage {
        bitmap(size: pageSize) { context in
            let bounds = CGRect(origin: .zero, size: pageSize)
            context.draw(screen, in: bounds)
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            context.fill(bounds)
            guard outline.count > 1 else { return }

            let path = CGMutablePath()
            path.addLines(between: outline)
            if closed { path.closeSubpath() }
            if closed {
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.draw(screen, in: bounds)
                context.restoreGState()
            }
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(path)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(3)
            context.strokePath()
            context.addPath(path)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.strokePath()
            if !closed, let tip = outline.last {
                drawCrosshair(at: tip, in: context)
            }
        }
    }

    private static func drawCrosshair(at point: CGPoint, in context: CGContext) {
        for (color, width) in [(NSColor.white, 3.0), (NSColor.black, 1.0)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.move(to: CGPoint(x: point.x - 9, y: point.y))
            context.addLine(to: CGPoint(x: point.x + 9, y: point.y))
            context.move(to: CGPoint(x: point.x, y: point.y - 9))
            context.addLine(to: CGPoint(x: point.x, y: point.y + 9))
            context.strokePath()
        }
    }

    // MARK: The editor window

    private static func makeEditorWindow(model: EditorModel) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: model.imageRect.width + 48, height: model.imageRect.height + 48 + 45),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Simple Snip"
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: EditorView(model: model) { nil })
        window.setFrameOrigin(CGPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        return window
    }

    private static func capture(_ window: NSWindow, live: InkStroke? = nil, model: EditorModel? = nil) throws -> CGImage {
        if let live, let model {
            // Show a stroke still being drawn by adding it, capturing, then undoing it.
            model.addStroke(live)
            defer { model.undo() }
            return try capture(window)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        guard let frameView = window.contentView?.superview else { throw DemoError("No window frame") }
        frameView.displayIfNeeded()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            throw DemoError("No bitmap for the window")
        }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        guard let image = rep.cgImage else { throw DemoError("No window image") }
        return image
    }

    /// The editor window with a shadow on a soft background, the size of the page.
    private static func onBackdrop(_ window: CGImage) -> CGImage {
        bitmap(size: pageSize) { context in
            let bounds = CGRect(origin: .zero, size: pageSize)
            let colors = [NSColor(hex: "#DCE6FB").cgColor, NSColor(hex: "#F3E8FA").cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])

            let size = CGSize(width: CGFloat(window.width) / scale, height: CGFloat(window.height) / scale)
            let fit = min(1, (pageSize.width - 120) / size.width, (pageSize.height - 100) / size.height)
            let drawn = CGSize(width: size.width * fit, height: size.height * fit)
            let rect = CGRect(x: (pageSize.width - drawn.width) / 2, y: (pageSize.height - drawn.height) / 2, width: drawn.width, height: drawn.height)
            let windowShape = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.28).cgColor)
            context.addPath(windowShape)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
            context.restoreGState()

            context.saveGState()
            context.addPath(windowShape)
            context.clip()
            context.draw(window, in: rect)
            context.restoreGState()
        }
    }

    // MARK: Output

    private static func bitmap(size: CGSize, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        draw(context)
        return context.makeImage()!
    }

    private static func resized(_ image: CGImage, to size: CGSize) -> CGImage {
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }

    private static func write(_ image: CGImage, named name: String) throws {
        let url = outputFolder.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw DemoError("Can't write \(name)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func writeGIF(_ frames: [(CGImage, Double)], named name: String, width: CGFloat) throws {
        let url = outputFolder.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw DemoError("Can't write \(name)")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for (image, delay) in frames {
            let height = (width * CGFloat(image.height) / CGFloat(image.width)).rounded()
            CGImageDestinationAddImage(destination, resized(image, to: CGSize(width: width, height: height)), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw DemoError("GIF failed") }
    }
}

struct DemoError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
final class LoadWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func wait() async {
        if finished { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
        continuation?.resume()
        continuation = nil
    }
}

let arguments = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
MainActor.assumeIsolated {
    Demo.outputFolder = URL(fileURLWithPath: arguments[2], isDirectory: true)
    Demo.iconFile = URL(fileURLWithPath: arguments[3])
    Task {
        do {
            try await Demo.run(page: URL(fileURLWithPath: arguments[1]))
            exit(0)
        } catch {
            FileHandle.standardError.write("demo failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}
app.run()
