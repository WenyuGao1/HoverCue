import SwiftUI

struct CaptionOverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings
    var body: some View {
        CaptionHistoryScrollContent(rows: displayedRows, generation: model.captionSessionGeneration, settings: settings)
            .padding(.horizontal, OverlayGlassMetrics.captionHorizontalPadding)
            .padding(.vertical, OverlayGlassMetrics.captionVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .padding(OverlayGlassMetrics.captionOuterPadding)
            .environment(\.locale, settings.appLanguage.locale)
    }

    private var displayedRows: [CaptionHistoryRow] {
        var rows: [CaptionHistoryRow] = model.segments.suffix(CaptionPipelineState.defaultMaximumSegments).compactMap { segment in
            let source = settings.captionDisplayMode.showsTranscription ? segment.sourceText : nil
            let translation = settings.captionDisplayMode.showsTranslation ? segment.translatedText : nil
            guard source?.isEmpty == false || translation?.isEmpty == false else { return nil }
            return CaptionHistoryRow(id: "stable:" + segment.id, source: source, translation: translation)
        }
        if settings.captionDisplayMode.showsTranscription && !model.interimSourceText.isEmpty {
            rows.append(CaptionHistoryRow(id: "interim", source: model.interimSourceText, isInterim: true))
        }
        if rows.isEmpty {
            rows.append(CaptionHistoryRow(id: "waiting", source: settings.appLanguage.localized("Waiting for source-language audio…"), isInterim: true))
        }
        return rows
    }

}

/// Draws only the clean vector glyphs. Keeping the caption free of shadow, blur, and
/// offscreen rasterization avoids contour artifacts on the nearly transparent glass.
struct CaptionText: View {
    let text: Text
    let font: Font
    let foregroundColor: Color

    var body: some View {
        text
            .font(font)
            .foregroundStyle(foregroundColor)
        .fixedSize(horizontal: false, vertical: true)
    }
}
