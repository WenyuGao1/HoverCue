import AppKit

enum CaptionButtonState: CaseIterable { case normal, hovered, pressed }

struct CaptionButtonPalette {
    let background: NSColor
    let foreground: NSColor
    let border: NSColor

    static func colors(appearance: OverlayGlassAppearance, state: CaptionButtonState) -> Self {
        let fill: UInt32
        let ink: UInt32
        let edge: UInt32
        switch appearance {
        case .light:
            fill = switch state { case .normal: 0xF5F5F7; case .hovered: 0xE9E9ED; case .pressed: 0xDADAE0 }
            ink = 0x1D1D1F; edge = 0xA8A8AD
        case .dark:
            fill = switch state { case .normal: 0x303034; case .hovered: 0x3C3C42; case .pressed: 0x484850 }
            ink = 0xFFFFFF; edge = 0x8E8E93
        case .highTransparency:
            fill = switch state { case .normal: 0x242428; case .hovered: 0x303036; case .pressed: 0x3C3C44 }
            ink = 0xFFFFFF; edge = 0xB8B8BE
        }
        return Self(background: color(fill), foreground: color(ink), border: color(edge))
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

/// Retain native button actions and accessibility, with an opaque local surface
/// whose contrast stays stable over every glass mode and desktop background.
@MainActor
final class CaptionLatestButton: NSButton {
    private(set) var glassAppearance: OverlayGlassAppearance = .light
    private var hovering = false
    private var hoverArea: NSTrackingArea?
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func apply(appearance: OverlayGlassAppearance) {
        glassAppearance = appearance
        self.appearance = NSAppearance(named: appearance == .light ? .aqua : .darkAqua)
        alphaValue = 1
        needsDisplay = true
    }

    var currentPalette: CaptionButtonPalette {
        .colors(appearance: glassAppearance, state: isHighlighted ? .pressed : (hovering ? .hovered : .normal))
    }

    override var fittingSize: NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 12, weight: .semibold)]
        return NSSize(width: ceil((title as NSString).size(withAttributes: attributes).width) + 44, height: 28)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let palette = currentPalette
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        palette.background.setFill(); shape.fill()
        palette.border.setStroke(); shape.lineWidth = 1; shape.stroke()
        let textFont = font ?? .systemFont(ofSize: 12, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: palette.foreground]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let x = max(10, (bounds.width - textSize.width - 20) / 2)
        // Draw a crisp vector down-to-line arrow with the exact text color.
        let arrow = NSBezierPath()
        let y = (bounds.height - 14) / 2
        arrow.move(to: NSPoint(x: x + 6, y: y + 1)); arrow.line(to: NSPoint(x: x + 6, y: y + 10))
        arrow.move(to: NSPoint(x: x + 2, y: y + 6)); arrow.line(to: NSPoint(x: x + 6, y: y + 10)); arrow.line(to: NSPoint(x: x + 10, y: y + 6))
        arrow.move(to: NSPoint(x: x + 1, y: y + 13)); arrow.line(to: NSPoint(x: x + 11, y: y + 13))
        arrow.lineWidth = 1.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        palette.foreground.setStroke(); arrow.stroke()
        (title as NSString).draw(at: NSPoint(x: x + 20, y: (bounds.height - textSize.height) / 2), withAttributes: attributes)
    }
}
