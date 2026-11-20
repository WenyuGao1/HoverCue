import AppKit
import Combine
import SwiftUI

@MainActor
final class CaptionPanelController: NSObject, NSWindowDelegate {
    private let panel: NonActivatingCaptionPanel
    private let hostingView: NSHostingView<CaptionOverlayView>
    private let glassView: NSGlassEffectView
    private let glassContainerView: CaptionGlassContainerView
    private let settings: OverlaySettings
    private var subscriptions: Set<AnyCancellable> = []
    private var restoringPosition = false
    private var applyingConfiguredSize = false
    private var userResizeInProgress = false
    private var persistingUserResize = false

    init(model: AppModel, settings: OverlaySettings) {
        self.settings = settings
        let captionContent = NSHostingView(rootView: CaptionOverlayView(model: model, settings: settings))
        let glassBackground = NSGlassEffectView()
        hostingView = captionContent
        glassView = glassBackground
        glassContainerView = CaptionGlassContainerView(
            glassView: glassBackground,
            captionContentView: captionContent
        )
        // The overlay window has an explicit user-controlled size. NSHostingView defaults to
        // `.standardBounds`, which feeds the changing subtitle content's minimum, intrinsic and
        // maximum sizes back into its NSWindow. Disable those content-derived constraints so new
        // caption lines can never overwrite the height selected in Settings.
        hostingView.sizingOptions = []
        let width = settings.overlayWidth
        let height = settings.overlayHeight
        let initialRect = NSRect(x: 200, y: 120, width: width, height: height)
        panel = NonActivatingCaptionPanel(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(
            width: OverlaySettings.overlayWidthRange.lowerBound,
            height: OverlaySettings.overlayHeightRange.lowerBound
        )
        panel.maxSize = NSSize(
            width: OverlaySettings.overlayWidthRange.upperBound,
            height: OverlaySettings.overlayHeightRange.upperBound
        )
        glassContainerView.frame = NSRect(origin: .zero, size: initialRect.size)
        glassContainerView.autoresizingMask = [.width, .height]
        panel.contentView = glassContainerView
        applyGlassSettings(appearance: settings.glassAppearance)
        // The borderless, nonactivating panel cannot rely on AppKit's background-drag
        // behaviour while the owning app is inactive. CaptionGlassContainerView handles
        // both movement and edge resizing explicitly so the interaction is identical
        // whether or not the main control window is visible.
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false
        glassContainerView.onManualResizeBegan = { [weak self] in
            self?.beginUserResize()
        }
        glassContainerView.onManualResizeEnded = { [weak self] in
            self?.finishUserResize()
        }

        if let origin = settings.savedOrigin() {
            restoringPosition = true
            panel.setFrameOrigin(origin)
            restoringPosition = false
        } else {
            moveToCurrentScreen()
        }

        settings.$overlayWidth
            .combineLatest(settings.$overlayHeight)
            .removeDuplicates { previous, current in
                previous.0 == current.0 && previous.1 == current.1
            }
            .sink { [weak self] width, height in
                guard let self, !self.persistingUserResize else { return }
                self.applyConfiguredSize(width: width, height: height)
            }
            .store(in: &subscriptions)
        settings.$glassAppearance
            .removeDuplicates()
            .sink { [weak self] appearance in
                self?.applyGlassSettings(appearance: appearance)
            }
            .store(in: &subscriptions)
    }

    var isVisible: Bool { panel.isVisible }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
    func toggle() { panel.isVisible ? hide() : show() }

    func moveToCurrentScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = CGPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 48
        )
        panel.setFrameOrigin(origin)
        settings.saveOrigin(origin)
    }

    func windowDidMove(_ notification: Notification) {
        guard !restoringPosition else { return }
        settings.saveOrigin(panel.frame.origin)
    }

    func windowDidResize(_ notification: Notification) {
        guard !applyingConfiguredSize else { return }
        // Only an explicit native or inactive-panel edge drag may change the window size.
        // SwiftUI content and other AppKit layout passes must still be unable to overwrite
        // the explicit size selected by the user.
        guard !userResizeInProgress, !panel.inLiveResize else { return }
        applyConfiguredSize(width: settings.overlayWidth, height: settings.overlayHeight)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: min(
                max(frameSize.width, OverlaySettings.overlayWidthRange.lowerBound),
                OverlaySettings.overlayWidthRange.upperBound
            ),
            height: min(
                max(frameSize.height, OverlaySettings.overlayHeightRange.lowerBound),
                OverlaySettings.overlayHeightRange.upperBound
            )
        )
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        beginUserResize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        finishUserResize()
    }

    private func beginUserResize() {
        userResizeInProgress = true
    }

    private func finishUserResize() {
        guard userResizeInProgress else { return }
        let size = windowWillResize(panel, to: panel.frame.size)
        userResizeInProgress = false

        // Publish both dimensions without allowing the width update to momentarily reapply
        // the previously saved height (or vice versa). The settings page and next launch then
        // use exactly the size established by the native edge/corner drag.
        persistingUserResize = true
        settings.overlayWidth = size.width
        settings.overlayHeight = size.height
        persistingUserResize = false
        settings.saveOrigin(panel.frame.origin)
    }

    private func applyConfiguredSize(width: Double, height: Double) {
        var frame = panel.frame
        guard abs(frame.width - width) > 0.5 || abs(frame.height - height) > 0.5 else { return }

        applyingConfiguredSize = true
        defer { applyingConfiguredSize = false }
        frame.origin.x += (frame.width - width) / 2
        frame.size.width = width
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: false)
    }

    private func applyGlassSettings(appearance: OverlayGlassAppearance) {
        glassView.applyCaptionGlass(
            appearance: appearance,
            cornerRadius: OverlayGlassMetrics.overlayCornerRadius
        )
        glassContainerView.applyGlassBorder(
            appearance: appearance,
            cornerRadius: OverlayGlassMetrics.overlayCornerRadius
        )
    }

#if DEBUG
    var panelSizeForTesting: NSSize { panel.frame.size }
    var hostingSizingOptionsForTesting: NSHostingSizingOptions { hostingView.sizingOptions }
    var isUserResizableForTesting: Bool { panel.styleMask.contains(.resizable) }
    var hasWindowShadowForTesting: Bool { panel.hasShadow }
    var isMovableByBackgroundForTesting: Bool { panel.isMovableByWindowBackground }
    var ignoresMouseEventsForTesting: Bool { panel.ignoresMouseEvents }
    var glassStyleForTesting: NSGlassEffectView.Style { glassView.style }
    var glassCornerRadiusForTesting: CGFloat { glassView.cornerRadius }
    var glassTintOpacityForTesting: CGFloat { glassView.tintColor?.alphaComponent ?? 0 }
    var glassTintColorForTesting: NSColor? { glassView.tintColor?.usingColorSpace(.sRGB) }
    var glassOpacityForTesting: CGFloat { glassView.alphaValue }
    var captionContentOpacityForTesting: CGFloat { hostingView.alphaValue }
    var explicitGlassAppearanceForTesting: NSAppearance? { glassView.appearance }
    var glassBorderWidthForTesting: CGFloat { glassContainerView.layer?.borderWidth ?? 0 }
    var glassBorderOpacityForTesting: CGFloat {
        guard let borderColor = glassContainerView.layer?.borderColor else { return 0 }
        return NSColor(cgColor: borderColor)?.alphaComponent ?? 0
    }
    var usesLayeredNativeGlassForTesting: Bool {
        panel.contentView === glassContainerView
            && glassView.superview === glassContainerView
            && hostingView.superview === glassContainerView
    }
    var supportsInactiveEdgeResizeForTesting: Bool {
        glassContainerView.hasManualResizeHandlersForTesting
            && glassContainerView.acceptsFirstMouse(for: nil)
    }
    var supportsInactiveMovementForTesting: Bool {
        glassContainerView.capturesWholeSurfaceForTesting
            && glassContainerView.acceptsFirstMouse(for: nil)
    }
    func simulateUnexpectedResizeForTesting(height: Double) {
        var frame = panel.frame
        frame.size.height = height
        panel.setFrame(frame, display: false, animate: false)
        windowDidResize(Notification(name: NSWindow.didResizeNotification, object: panel))
    }
    func simulateUserResizeForTesting(width: Double, height: Double) {
        userResizeInProgress = true
        var frame = panel.frame
        frame.size = windowWillResize(panel, to: NSSize(width: width, height: height))
        panel.setFrame(frame, display: false, animate: false)
        windowDidEndLiveResize(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
    }
#endif
}

/// Keeps the native Liquid Glass substrate independent from the caption content so the
/// background material never fades the text or makes it less readable.
final class CaptionGlassContainerView: NSView {
    private struct DragSession {
        let initialFrame: NSRect
        let initialMouseLocation: NSPoint
        let edges: CaptionResizeEdges

        var isResize: Bool { !edges.isEmpty }
    }

    private let glassView: NSGlassEffectView
    private let captionContentView: NSView
    private var dragSession: DragSession?
    var onManualResizeBegan: (() -> Void)?
    var onManualResizeEnded: (() -> Void)?

    init(glassView: NSGlassEffectView, captionContentView: NSView) {
        self.glassView = glassView
        self.captionContentView = captionContentView
        super.init(frame: .zero)

        glassView.contentView = NSView()
        glassView.frame = bounds
        glassView.autoresizingMask = [.width, .height]
        captionContentView.frame = bounds
        captionContentView.autoresizingMask = [.width, .height]

        addSubview(glassView)
        addSubview(captionContentView, positioned: .above, relativeTo: glassView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        // Keep background dragging on inactive panels, while allowing the history
        // scroller and return-to-latest button to receive their own mouse gestures.
        if CaptionWindowResizer.edges(at: point, in: bounds).isEmpty,
           let history = captionHistoryView,
           let control = history.interactiveControl(at: history.convert(point, from: self)) {
            return control
        }
        return self
    }

    override func scrollWheel(with event: NSEvent) {
        if let history = captionHistoryView {
            history.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    private var captionHistoryView: CaptionHistoryView? {
        func find(in view: NSView) -> CaptionHistoryView? {
            if let history = view as? CaptionHistoryView { return history }
            for child in view.subviews {
                if let result = find(in: child) { return result }
            }
            return nil
        }
        return find(in: captionContentView)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let edges = CaptionWindowResizer.edges(at: point, in: bounds)
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        finishCurrentDragIfNeeded()
        let session = DragSession(
            initialFrame: window.frame,
            initialMouseLocation: NSEvent.mouseLocation,
            edges: edges
        )
        dragSession = session
        if session.isResize {
            CaptionWindowResizer.cursor(for: edges)?.set()
            onManualResizeBegan?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let session = dragSession, let window else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let delta = NSPoint(
            x: currentMouseLocation.x - session.initialMouseLocation.x,
            y: currentMouseLocation.y - session.initialMouseLocation.y
        )
        let frame = session.isResize
            ? CaptionWindowResizer.resizedFrame(
                initialFrame: session.initialFrame,
                mouseDelta: delta,
                edges: session.edges
            )
            : CaptionWindowResizer.movedFrame(
                initialFrame: session.initialFrame,
                mouseDelta: delta
            )
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragSession != nil else {
            super.mouseUp(with: event)
            return
        }
        finishCurrentDragIfNeeded()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for region in CaptionWindowResizer.cursorRegions(in: bounds) {
            addCursorRect(region.rect, cursor: region.cursor)
        }
    }

    func applyGlassBorder(
        appearance: OverlayGlassAppearance,
        cornerRadius: CGFloat
    ) {
        applyCaptionGlassBorder(
            appearance: appearance,
            cornerRadius: cornerRadius
        )
    }

    private func finishCurrentDragIfNeeded() {
        guard let session = dragSession else { return }
        dragSession = nil
        if session.isResize {
            onManualResizeEnded?()
        }
    }

#if DEBUG
    var hasManualResizeHandlersForTesting: Bool {
        onManualResizeBegan != nil && onManualResizeEnded != nil
    }
    var capturesWholeSurfaceForTesting: Bool {
        hitTest(NSPoint(x: bounds.midX, y: bounds.midY)) === self
    }
#endif
}

struct CaptionResizeEdges: OptionSet, Equatable {
    let rawValue: Int

    static let left = CaptionResizeEdges(rawValue: 1 << 0)
    static let right = CaptionResizeEdges(rawValue: 1 << 1)
    static let bottom = CaptionResizeEdges(rawValue: 1 << 2)
    static let top = CaptionResizeEdges(rawValue: 1 << 3)
}

@MainActor
enum CaptionWindowResizer {
    static let hitThickness: CGFloat = 12

    struct CursorRegion {
        let rect: NSRect
        let cursor: NSCursor
    }

    static func edges(at point: NSPoint, in bounds: NSRect) -> CaptionResizeEdges {
        guard bounds.contains(point) else { return [] }
        var edges: CaptionResizeEdges = []
        if point.x <= bounds.minX + hitThickness { edges.insert(.left) }
        if point.x >= bounds.maxX - hitThickness { edges.insert(.right) }
        if point.y <= bounds.minY + hitThickness { edges.insert(.bottom) }
        if point.y >= bounds.maxY - hitThickness { edges.insert(.top) }
        return edges
    }

    static func resizedFrame(
        initialFrame: NSRect,
        mouseDelta: NSPoint,
        edges: CaptionResizeEdges
    ) -> NSRect {
        var frame = initialFrame

        if edges.contains(.left) {
            let width = clamp(
                initialFrame.width - mouseDelta.x,
                to: OverlaySettings.overlayWidthRange
            )
            frame.origin.x = initialFrame.maxX - width
            frame.size.width = width
        } else if edges.contains(.right) {
            frame.size.width = clamp(
                initialFrame.width + mouseDelta.x,
                to: OverlaySettings.overlayWidthRange
            )
        }

        if edges.contains(.bottom) {
            let height = clamp(
                initialFrame.height - mouseDelta.y,
                to: OverlaySettings.overlayHeightRange
            )
            frame.origin.y = initialFrame.maxY - height
            frame.size.height = height
        } else if edges.contains(.top) {
            frame.size.height = clamp(
                initialFrame.height + mouseDelta.y,
                to: OverlaySettings.overlayHeightRange
            )
        }

        return frame
    }

    static func movedFrame(initialFrame: NSRect, mouseDelta: NSPoint) -> NSRect {
        NSRect(
            x: initialFrame.origin.x + mouseDelta.x,
            y: initialFrame.origin.y + mouseDelta.y,
            width: initialFrame.width,
            height: initialFrame.height
        )
    }

    static func cursor(for edges: CaptionResizeEdges) -> NSCursor? {
        guard let position = cursorPosition(for: edges) else { return nil }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    static func cursorRegions(in bounds: NSRect) -> [CursorRegion] {
        let thickness = min(hitThickness, bounds.width / 2, bounds.height / 2)
        let middleWidth = max(0, bounds.width - 2 * thickness)
        let middleHeight = max(0, bounds.height - 2 * thickness)

        return [
            region(
                NSRect(x: bounds.minX, y: bounds.minY, width: thickness, height: thickness),
                position: .bottomLeft
            ),
            region(
                NSRect(x: bounds.maxX - thickness, y: bounds.minY, width: thickness, height: thickness),
                position: .bottomRight
            ),
            region(
                NSRect(x: bounds.minX, y: bounds.maxY - thickness, width: thickness, height: thickness),
                position: .topLeft
            ),
            region(
                NSRect(x: bounds.maxX - thickness, y: bounds.maxY - thickness, width: thickness, height: thickness),
                position: .topRight
            ),
            region(
                NSRect(x: bounds.minX, y: bounds.minY + thickness, width: thickness, height: middleHeight),
                position: .left
            ),
            region(
                NSRect(x: bounds.maxX - thickness, y: bounds.minY + thickness, width: thickness, height: middleHeight),
                position: .right
            ),
            region(
                NSRect(x: bounds.minX + thickness, y: bounds.minY, width: middleWidth, height: thickness),
                position: .bottom
            ),
            region(
                NSRect(x: bounds.minX + thickness, y: bounds.maxY - thickness, width: middleWidth, height: thickness),
                position: .top
            )
        ]
    }

    private static func cursorPosition(
        for edges: CaptionResizeEdges
    ) -> NSCursor.FrameResizePosition? {
        switch edges {
        case [.left, .bottom]: .bottomLeft
        case [.right, .bottom]: .bottomRight
        case [.left, .top]: .topLeft
        case [.right, .top]: .topRight
        case [.left]: .left
        case [.right]: .right
        case [.bottom]: .bottom
        case [.top]: .top
        default: nil
        }
    }

    private static func region(
        _ rect: NSRect,
        position: NSCursor.FrameResizePosition
    ) -> CursorRegion {
        CursorRegion(
            rect: rect,
            cursor: NSCursor.frameResize(position: position, directions: .all)
        )
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<Double>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

final class NonActivatingCaptionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
