import AppKit
import SwiftUI

struct OverlayGlassBackground: NSViewRepresentable {
    let appearance: OverlayGlassAppearance
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.contentView = NSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSGlassEffectView) {
        view.applyCaptionGlass(
            appearance: appearance,
            cornerRadius: cornerRadius
        )
    }
}

/// Renders the preview image and the native glass inside one AppKit subtree.
///
/// `NSGlassEffectView` samples the content behind it. Keeping the landscape and glass
/// together makes the preview behave like the real floating panel instead of sampling
/// the otherwise plain background of the Settings window.
struct OverlayGlassPreviewSurface: NSViewRepresentable {
    let appearance: OverlayGlassAppearance
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> OverlayGlassPreviewView {
        OverlayGlassPreviewView(
            appearance: appearance,
            cornerRadius: cornerRadius
        )
    }

    func updateNSView(_ view: OverlayGlassPreviewView, context: Context) {
        view.apply(
            appearance: appearance,
            cornerRadius: cornerRadius
        )
    }
}

final class OverlayGlassPreviewView: NSView {
    private let landscapeView = NSImageView()
    private let glassView = NSGlassEffectView()

    init(
        appearance: OverlayGlassAppearance,
        cornerRadius: CGFloat
    ) {
        super.init(frame: .zero)

        wantsLayer = true
        landscapeView.image = Self.loadLandscapeImage()
        landscapeView.imageScaling = .scaleAxesIndependently
        landscapeView.imageAlignment = .alignCenter

        glassView.contentView = NSView()
        glassView.frame = bounds
        glassView.autoresizingMask = [.width, .height]

        addSubview(landscapeView)
        addSubview(glassView, positioned: .above, relativeTo: landscapeView)
        apply(appearance: appearance, cornerRadius: cornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    private static func loadLandscapeImage() -> NSImage? {
        let bundle = Bundle(for: OverlayGlassPreviewView.self)
        if let url = bundle.url(
            forResource: "OverlayPreviewLandscape",
            withExtension: "png"
        ), let image = NSImage(contentsOf: url) {
            return image
        }
        return bundle.image(
            forResource: NSImage.Name("OverlayPreviewLandscape")
        )
    }

    override func layout() {
        super.layout()
        guard let imageSize = landscapeView.image?.size,
              imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            landscapeView.frame = bounds
            return
        }

        let scale = max(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let scaledSize = NSSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        landscapeView.frame = NSRect(
            x: bounds.midX - scaledSize.width / 2,
            y: bounds.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    func apply(
        appearance: OverlayGlassAppearance,
        cornerRadius: CGFloat
    ) {
        glassView.applyCaptionGlass(
            appearance: appearance,
            cornerRadius: cornerRadius
        )
        applyCaptionGlassBorder(
            appearance: appearance,
            cornerRadius: cornerRadius
        )
    }

#if DEBUG
    var hasLandscapeImageForTesting: Bool {
        landscapeView.image != nil
    }
    var glassAppearanceForTesting: NSAppearance? {
        glassView.appearance
    }
    var glassOpacityForTesting: CGFloat {
        glassView.alphaValue
    }
    var glassTintColorForTesting: NSColor? {
        glassView.tintColor?.usingColorSpace(.sRGB)
    }
    var glassTintOpacityForTesting: CGFloat {
        glassView.tintColor?.alphaComponent ?? 0
    }
    var glassBorderWidthForTesting: CGFloat {
        layer?.borderWidth ?? 0
    }
#endif
}

extension NSGlassEffectView {
    func applyCaptionGlass(
        appearance: OverlayGlassAppearance,
        cornerRadius: CGFloat
    ) {
        style = .clear
        self.cornerRadius = cornerRadius
        // Resolve the native material explicitly so the Light/Dark control remains stable
        // regardless of the desktop appearance.
        self.appearance = NSAppearance(
            named: appearance == .dark ? .darkAqua : .aqua
        )
        // The native Light and Dark glass modes need a small mode-specific tint to stay
        // visually distinct over the same content. This is part of the glass material,
        // not a separate opacity overlay; the removed user opacity setting remains at 0%.
        switch appearance {
        case .light:
            tintColor = NSColor.white.withAlphaComponent(
                OverlayGlassMetrics.lightGlassTintOpacity
            )
        case .dark:
            tintColor = NSColor.black.withAlphaComponent(
                OverlayGlassMetrics.darkGlassTintOpacity
            )
        case .highTransparency:
            tintColor = nil
        }
        alphaValue = appearance == .highTransparency
            ? OverlayGlassMetrics.highTransparencyGlassOpacity
            : 1
    }
}

extension NSView {
    func applyCaptionGlassBorder(
        appearance: OverlayGlassAppearance,
        cornerRadius: CGFloat
    ) {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = appearance == .highTransparency
            ? OverlayGlassMetrics.highTransparencyBorderWidth
            : 0
        layer?.borderColor = appearance == .highTransparency
            ? NSColor.white.withAlphaComponent(
                OverlayGlassMetrics.highTransparencyBorderOpacity
            ).cgColor
            : nil
    }
}
