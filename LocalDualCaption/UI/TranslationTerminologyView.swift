import SwiftUI

struct TranslationTerminologyView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: OverlaySettings

    private var supported: Bool {
        if #available(macOS 26.4, *) { return true }
        return false
    }
    private var parsed: ParsedTranslationTerms { settings.currentTermDraft.parsed }
    private var originalExamples: String { VocabularyExamples.terms(for: settings.sourceSelection).joined(separator: "\n") }
    private var fixedExamples: String { VocabularyExamples.fixedTranslations(source: settings.sourceSelection, target: settings.targetSelection) }
    private var sourceTitle: String { VocabularyExamples.title(for: settings.sourceSelection, in: settings.appLanguage) }
    private var pairTitle: String {
        settings.sourceSelection.terminologyDisplayName(in: settings.appLanguage) + " → " + settings.targetSelection.terminologyDisplayName(in: settings.appLanguage)
    }
    private var fixedTitle: String {
        String(format: settings.appLanguage.localized("Examples: %@ -> %@"),
               settings.sourceSelection.terminologyDisplayName(in: settings.appLanguage),
               settings.targetSelection.terminologyDisplayName(in: settings.appLanguage))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Text(verbatim: pairTitle).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
                InterfaceHelpButton(title: "About terminology", identifier: "help.terminology") {
                    Text("Rules apply to this language direction when captions next start.")
                    Text("One term per line. Matching terms stay unchanged in the translation.")
                    Text("One rule per line: original -> translation.")
                    Text("Specified translations take priority when the same term appears in both boxes.")
                    Text("Matches ignore capitalization and prefer longer phrases. Common words may have different meanings in context.")
                    Text("Up to 200 entries per box; original terms up to 120 characters, translations up to 240.")
                    Text("When captions next start, up to 200 entries are provided to on-device speech recognition as contextual hints.")
                    Text("Rules stay on this Mac. Examples are not saved as rules.")
                }
            }
            if !supported {
                InterfaceNote(text: "Translation terminology requires macOS 26.4 or later.", symbol: "info.circle")
            }
            InterfaceSettingsSection {
                editor(text: keptBinding, title: "Keep original wording", exampleTitle: sourceTitle, examples: originalExamples)
                invalidLines(parsed.invalidKeptLines)
            } header: {
                InterfaceSectionTitle(title: "Keep original wording", symbol: "text.quote")
            }
            InterfaceSettingsSection {
                editor(text: fixedBinding, title: "Specify translations", exampleTitle: fixedTitle, examples: fixedExamples)
                invalidLines(parsed.invalidFixedLines)
            } header: {
                InterfaceSectionTitle(title: "Specify translations", symbol: "character.book.closed")
            }
            if !settings.vocabulary.isEmpty {
                DisclosureGroup("Previous recognition hints") {
                    TextEditor(text: Binding(
                        get: { settings.vocabulary.joined(separator: "\n") },
                        set: { settings.vocabulary = $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                    ))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 100)
                    .disabled(model.controlsLocked)
                    Text("These entries only help recognition and do not control translation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func editor(text: Binding<String>, title: LocalizedStringKey, exampleTitle: String, examples: String) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: 130)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)) }
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(verbatim: exampleTitle).font(.system(size: 11))
                        Text(verbatim: examples).font(.system(size: 13, design: .monospaced)).lineSpacing(4)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13).padding(.vertical, 14)
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .accessibilityLabel(title)
            .accessibilityHint(Text(verbatim: exampleTitle + "\n" + examples))
            .disabled(model.controlsLocked || !supported)
    }

    @ViewBuilder private func invalidLines(_ lines: [Int]) -> some View {
        if !lines.isEmpty {
            let numbers = lines.prefix(8).map(String.init).joined(separator: ", ") + (lines.count > 8 ? "…" : "")
            Text(verbatim: String(format: settings.appLanguage.localized("Invalid or duplicate entries on lines %@ are not applied."), numbers))
                .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var keptBinding: Binding<String> {
        Binding(get: { settings.currentTermDraft.keptTerms }, set: { value in
            var draft = settings.currentTermDraft; draft.keptTerms = value
            settings.updateCurrentTermDraft(draft)
        })
    }
    private var fixedBinding: Binding<String> {
        Binding(get: { settings.currentTermDraft.fixedTranslations }, set: { value in
            var draft = settings.currentTermDraft; draft.fixedTranslations = value
            settings.updateCurrentTermDraft(draft)
        })
    }
}
