import AppKit

enum InkKind: String, Codable {
    case pen
    case highlighter

    /// Colors offered in the tool's palette, as hex RGB.
    var palette: [String] {
        switch self {
        case .pen:
            return [
                "#000000", "#FFFFFF", "#D1D3D4", "#A7A9AC", "#808285", "#58595B",
                "#B31564", "#E61B1B", "#FF5500", "#FFAA00", "#FFCE00", "#FFE600",
                "#A2E61B", "#26E600", "#008055", "#00AACC", "#004DE6", "#3D00B8",
                "#6600CC", "#600080", "#F7D7C4", "#BB9167", "#8E562E", "#613D30",
                "#FF80FF", "#FFC680", "#FFFF80", "#80FF9E", "#80D6FF", "#BCB3FF",
            ]
        case .highlighter:
            return [
                "#FFFF00", "#00FF00", "#00FFFF", "#FF00FF", "#0066FF", "#FF0000",
                "#FF8000", "#8000FF", "#00C080", "#FFB3C6", "#A0A0A0", "#000000",
            ]
        }
    }

    var widthRange: ClosedRange<Double> {
        self == .pen ? 1...24 : 4...48
    }
}

/// The color and thickness a pen or highlighter draws with. Remembered between snips.
struct InkStyle: Codable, Equatable {
    var colorHex: String
    var width: Double

    static let defaultPen = InkStyle(colorHex: "#000000", width: 3)
    static let defaultHighlighter = InkStyle(colorHex: "#FFFF00", width: 16)

    var color: NSColor { NSColor(hex: colorHex) }
}

/// One continuous line drawn with the pen or highlighter, in image points (origin bottom-left).
struct InkStroke: Identifiable, Equatable {
    let id = UUID()
    var kind: InkKind
    var style: InkStyle
    var points: [CGPoint]

    var path: CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
            return path
        }
        // Curves through the midpoints keep fast mouse strokes smooth instead of jagged.
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    func draw(in context: CGContext) {
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(style.width)
        switch kind {
        case .pen:
            context.setStrokeColor(style.color.cgColor)
        case .highlighter:
            // Multiply keeps text under the highlight readable, like a real marker.
            context.setBlendMode(.multiply)
            context.setStrokeColor(style.color.withAlphaComponent(0.55).cgColor)
        }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        path.copy(strokingWithWidth: style.width + tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
            .contains(point)
    }
}

extension NSColor {
    convenience init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits, radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
