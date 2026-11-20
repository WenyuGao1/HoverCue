import AppKit
import SwiftUI

struct CaptionHistoryRow: Equatable {
    let id: String
    var source: String? = nil
    var translation: String? = nil
    var isInterim = false
}

struct CaptionHistoryScrollContent: NSViewRepresentable {
    let rows: [CaptionHistoryRow]
    let generation: Int
    @ObservedObject var settings: OverlaySettings

    func makeNSView(context: Context) -> CaptionHistoryView { CaptionHistoryView() }

    func updateNSView(_ view: CaptionHistoryView, context: Context) {
        view.update(rows: rows, generation: generation, settings: settings)
    }

    static func dismantleNSView(_ view: CaptionHistoryView, coordinator: ()) {
        view.shutdown()
    }
}

/// An explicitly bounded document gives us stable row anchors when text reflows or
/// the oldest caption expires. No scroll state or caption text is persisted here.
@MainActor
final class CaptionHistoryView: NSView {
    struct Anchor { let id: String; let offset: CGFloat }
    private let viewport = CaptionHistoryScrollView()
    private let document = CaptionHistoryDocument()
    private let scroller = CaptionHistoryScroller()
    private let latestButton = CaptionLatestButton()
    private var rowViews: [String: CaptionHistoryRowView] = [:]
    private var order: [String] = []
    private var generation: Int?
    private var pendingAnchor: Anchor?
    private var layingOut = false
    private var wheelActive = false
    private var scrollerActive = false
    private var hideTask: Task<Void, Never>?
    private var wheelEndTask: Task<Void, Never>?
    private(set) var followsLatest = true

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init() {
        super.init(frame: .zero)
        viewport.drawsBackground = false
        viewport.contentView.drawsBackground = false
        viewport.borderType = .noBorder
        viewport.hasVerticalScroller = false
        viewport.hasHorizontalScroller = false
        viewport.verticalScrollElasticity = .none
        viewport.horizontalScrollElasticity = .none
        viewport.automaticallyAdjustsContentInsets = false
        viewport.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        viewport.documentView = document
        viewport.setAccessibilityIdentifier("caption.history.scroll")
        viewport.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: viewport.contentView)
        viewport.onWheel = { [weak self] event in self?.consumeWheel(event) }
        scroller.onBegin = { [weak self] in
            self?.scrollerActive = true
            self?.wheelEndTask?.cancel()
            self?.showIndicator()
        }
        scroller.onChange = { [weak self] fraction in self?.scrollFromUser(to: fraction) }
        scroller.onEnd = { [weak self] in
            guard let self else { return }
            self.scrollerActive = false
            if self.followsLatest { self.needsLayout = true; self.layoutSubtreeIfNeeded() }
            self.scheduleIndicatorHide()
        }
        scroller.alphaValue = 0
        scroller.setAccessibilityIdentifier("caption.history.indicator")
        latestButton.target = self
        latestButton.action = #selector(returnToLatest)
        latestButton.bezelStyle = .rounded
        latestButton.controlSize = .small
        latestButton.font = .systemFont(ofSize: 12, weight: .semibold)
        latestButton.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)
        latestButton.imagePosition = .imageLeading
        latestButton.setAccessibilityIdentifier("caption.history.latest")
        addSubview(viewport)
        addSubview(scroller)
        addSubview(latestButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(rows: [CaptionHistoryRow], generation: Int, settings: OverlaySettings) {
        pendingAnchor = anchorAtTop()
        if self.generation != generation {
            self.generation = generation
            followsLatest = true
            wheelActive = false; scrollerActive = false
            wheelEndTask?.cancel(); hideTask?.cancel()
            scroller.alphaValue = 0
        }
        // Ten confirmed captions plus one transient recognition line at most.
        let bounded = Array(rows.suffix(CaptionPipelineState.defaultMaximumSegments + 1))
        let ids = Set(bounded.map(\.id))
        for id in order where !ids.contains(id) { rowViews.removeValue(forKey: id)?.removeFromSuperview() }
        order = bounded.map(\.id)
        for row in bounded {
            let view = rowViews[row.id] ?? CaptionHistoryRowView()
            if view.superview == nil { document.addSubview(view); rowViews[row.id] = view }
            view.update(row, settings: settings)
        }
        latestButton.title = settings.appLanguage.localized("Back to latest")
        latestButton.apply(appearance: settings.glassAppearance)
        scroller.setAccessibilityLabel(settings.appLanguage.localized("Recent captions"))
        scroller.tint = NSColor(settings.englishColor)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        guard !layingOut, bounds.width > 0, bounds.height > 0 else { return }
        layingOut = true
        defer { layingOut = false }
        let anchor = pendingAnchor ?? anchorAtTop()
        pendingAnchor = nil
        // A separate footer keeps the return button from covering any caption.
        let footer: CGFloat = followsLatest ? 0 : 36
        viewport.frame = NSRect(x: 0, y: 0, width: max(1, bounds.width - 18), height: max(1, bounds.height - footer))
        viewport.tile()
        let width = max(1, viewport.contentSize.width)
        let sizes = order.compactMap { id -> (String, CGFloat)? in
            rowViews[id].map { (id, $0.measuredHeight(width: width)) }
        }
        let contentHeight = sizes.reduce(0) { $0 + $1.1 }
            + CGFloat(max(0, sizes.count - 1)) * OverlayGlassMetrics.captionGroupSpacing
        // When all retained content fits, there is no hidden history to review.
        if contentHeight <= bounds.height && !followsLatest {
            followsLatest = true
            viewport.frame.size.height = bounds.height
            viewport.tile()
        }
        // Bottom alignment is independent from scrolling: a short document has
        // zero scroll range, so scrolling to its end alone cannot position text.
        var y = max(0, viewport.contentSize.height - contentHeight)
        for (id, height) in sizes {
            guard let row = rowViews[id] else { continue }
            row.frame = NSRect(x: 0, y: y, width: width, height: height)
            row.layoutLines()
            y += height + OverlayGlassMetrics.captionGroupSpacing
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(viewport.contentSize.height, contentHeight))
        if followsLatest && !wheelActive && !scrollerActive {
            setOffset(maximumOffset)
        } else if let anchor, let row = rowViews[anchor.id] {
            setOffset(row.frame.minY + anchor.offset)
        } else {
            // The viewed oldest row expired: remain at the earliest retained row.
            setOffset(0)
        }
        scroller.frame = NSRect(x: bounds.width - 14, y: 0, width: 14, height: viewport.frame.height)
        latestButton.isHidden = followsLatest
        let buttonWidth = min(bounds.width, max(100, latestButton.fittingSize.width))
        latestButton.frame = NSRect(x: bounds.width - buttonWidth, y: bounds.height - 30, width: buttonWidth, height: 28)
        updateIndicator()
    }

    override func scrollWheel(with event: NSEvent) { consumeWheel(event) }

    private func consumeWheel(_ event: NSEvent) {
        wheelActive = true
        // Apply the system's already direction-adjusted deltas synchronously.
        // Trackpads supply pixel deltas (including momentum); wheel mice supply
        // line deltas. This also works while the nonactivating panel is inactive.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 24
        setOffset(offset - event.scrollingDeltaY * scale)
        wheelDidScroll()
    }

    /// The panel routes only actual controls here; all other left drags move it.
    func interactiveControl(at point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if !latestButton.isHidden, latestButton.frame.contains(point) { return latestButton }
        if !scroller.isHidden, scroller.alphaValue > 0.05, scroller.frame.contains(point) { return scroller }
        return nil
    }

    private var maximumOffset: CGFloat { max(0, document.frame.height - viewport.contentSize.height) }
    private var offset: CGFloat { viewport.contentView.bounds.minY }

    private func setOffset(_ y: CGFloat) {
        viewport.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), maximumOffset)))
        viewport.reflectScrolledClipView(viewport.contentView)
    }

    private func anchorAtTop() -> Anchor? {
        guard let id = order.first(where: { (rowViews[$0]?.frame.maxY ?? 0) > offset + 0.5 }),
              let row = rowViews[id] else { return nil }
        return Anchor(id: id, offset: offset - row.frame.minY)
    }

    @objc private func boundsChanged() {
        if !layingOut { updateIndicator() }
    }

    private func wheelDidScroll() {
        updateFollowingAfterUserScroll()
        showIndicator()
        scheduleIndicatorHide()
        wheelEndTask?.cancel()
        wheelEndTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            guard let self else { return }
            self.wheelActive = false
            if self.followsLatest { self.needsLayout = true; self.layoutSubtreeIfNeeded() }
        }
    }

    private func updateFollowingAfterUserScroll() {
        let following = maximumOffset - offset <= 12
        if followsLatest != following {
            pendingAnchor = anchorAtTop()
            followsLatest = following
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        updateIndicator()
    }

    private func scrollFromUser(to fraction: CGFloat) {
        setOffset(maximumOffset * min(1, max(0, fraction)))
        updateFollowingAfterUserScroll()
        showIndicator()
    }

    @objc func returnToLatest() {
        wheelEndTask?.cancel()
        wheelActive = false
        followsLatest = true
        needsLayout = true
        layoutSubtreeIfNeeded()
        showIndicator()
        scheduleIndicatorHide()
    }

    private func updateIndicator() {
        scroller.isHidden = maximumOffset <= 1
        scroller.proportion = min(1, viewport.contentSize.height / max(1, document.frame.height))
        scroller.doubleValue = Double(maximumOffset > 0 ? offset / maximumOffset : 0)
        scroller.needsDisplay = true
    }

    private func showIndicator() {
        hideTask?.cancel()
        scroller.layer?.removeAllAnimations()
        if maximumOffset > 1 { scroller.alphaValue = 1 }
    }

    private func scheduleIndicatorHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard let self, !self.scrollerActive else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                self.scroller.animator().alphaValue = 0
            }, completionHandler: nil)
        }
    }

    func shutdown() {
        hideTask?.cancel(); wheelEndTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

#if DEBUG
    var topAnchorForTesting: (String, CGFloat)? { anchorAtTop().map { ($0.id, $0.offset) } }
    var offsetForTesting: CGFloat { offset }
    var maximumOffsetForTesting: CGFloat { maximumOffset }
    var indicatorVisibleForTesting: Bool { !scroller.isHidden && scroller.alphaValue > 0.05 }
    var retainedRowCountForTesting: Int { order.count }
    var footerVisibleForTesting: Bool { !latestButton.isHidden }
    var viewportFrameForTesting: NSRect { viewport.frame }
    var buttonFrameForTesting: NSRect { latestButton.frame }
    var indicatorFrameForTesting: NSRect { scroller.frame }
    var buttonAppearanceForTesting: OverlayGlassAppearance { latestButton.glassAppearance }
    func rowFrameForTesting(_ id: String) -> NSRect? { rowViews[id]?.frame }
    func scrollForTesting(to fraction: CGFloat) { scrollFromUser(to: fraction); scheduleIndicatorHide() }
#endif
}

@MainActor
private final class CaptionHistoryScrollView: NSScrollView {
    var onWheel: ((NSEvent) -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func scrollWheel(with event: NSEvent) {
        onWheel?(event)
    }
}

private final class CaptionHistoryDocument: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
}

private final class CaptionHistoryRowView: NSView {
    private let source = NSTextField(wrappingLabelWithString: "")
    private let translation = NSTextField(wrappingLabelWithString: "")
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for field in [source, translation] {
            field.isSelectable = false
            field.lineBreakMode = .byWordWrapping
            field.maximumNumberOfLines = 0
            addSubview(field)
        }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ row: CaptionHistoryRow, settings: OverlaySettings) {
        let sourceColor = NSColor(settings.englishColor)
        configure(source, text: row.source, font: .systemFont(ofSize: settings.englishFontSize, weight: row.isInterim ? .regular : .medium),
                  color: row.isInterim ? sourceColor.withAlphaComponent(sourceColor.alphaComponent * 0.72) : sourceColor)
        configure(translation, text: row.translation, font: .systemFont(ofSize: settings.chineseFontSize, weight: .semibold), color: NSColor(settings.chineseColor))
    }

    private func configure(_ field: NSTextField, text: String?, font: NSFont, color: NSColor) {
        field.isHidden = text?.isEmpty != false
        field.attributedStringValue = NSAttributedString(string: text ?? "", attributes: [.font: font, .foregroundColor: color])
    }

    private func height(_ field: NSTextField, width: CGFloat) -> CGFloat {
        guard !field.isHidden else { return 0 }
        return ceil(field.attributedStringValue.boundingRect(with: NSSize(width: max(1, width - 4), height: 1_000_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 3
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        height(source, width: width) + height(translation, width: width)
            + (!source.isHidden && !translation.isHidden ? OverlayGlassMetrics.captionPairSpacing : 0)
    }

    func layoutLines() {
        let firstHeight = height(source, width: bounds.width)
        source.frame = NSRect(x: 0, y: 0, width: bounds.width, height: firstHeight)
        let gap = !source.isHidden && !translation.isHidden ? OverlayGlassMetrics.captionPairSpacing : 0
        translation.frame = NSRect(x: 0, y: firstHeight + gap, width: bounds.width, height: height(translation, width: bounds.width))
    }
}

/// A small overlay control, independent of the system's always-show-scrollers
/// preference. Its permanently reserved lane never covers caption glyphs.
@MainActor
private final class CaptionHistoryScroller: NSControl {
    var proportion: CGFloat = 1
    var tint = NSColor.labelColor
    var onBegin: (() -> Void)?
    var onChange: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var grabOffset: CGFloat = 0
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.scrollBar)
        setAccessibilityOrientation(.vertical)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var thumb: NSRect {
        let height = min(bounds.height, max(24, bounds.height * proportion))
        return NSRect(x: (bounds.width - 4) / 2, y: (bounds.height - height) * CGFloat(doubleValue), width: 4, height: height)
    }
    override func draw(_ dirtyRect: NSRect) {
        tint.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2).fill()
    }
    override func mouseDown(with event: NSEvent) {
        onBegin?()
        let y = convert(event.locationInWindow, from: nil).y
        grabOffset = thumb.minY <= y && y <= thumb.maxY ? y - thumb.minY : thumb.height / 2
        move(to: y)
    }
    override func mouseDragged(with event: NSEvent) { move(to: convert(event.locationInWindow, from: nil).y) }
    override func mouseUp(with event: NSEvent) { onEnd?() }
    private func move(to y: CGFloat) { onChange?(min(1, max(0, (y - grabOffset) / max(1, bounds.height - thumb.height)))) }
    override func accessibilityValue() -> Any? { NSNumber(value: doubleValue) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 1) }
    override func setAccessibilityValue(_ value: Any?) {
        guard let number = value as? NSNumber else { return }
        onBegin?(); onChange?(min(1, max(0, CGFloat(number.doubleValue)))); onEnd?()
    }
    override func accessibilityPerformIncrement() -> Bool { onBegin?(); onChange?(min(1, CGFloat(doubleValue) + 0.1)); onEnd?(); return true }
    override func accessibilityPerformDecrement() -> Bool { onBegin?(); onChange?(max(0, CGFloat(doubleValue) - 0.1)); onEnd?(); return true }
}
