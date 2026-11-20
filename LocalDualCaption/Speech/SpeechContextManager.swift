import Speech

enum SpeechContextManager {
    static func makeContext(vocabulary: [String]) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(vocabulary.prefix(200))
        return context
    }
}
