import Foundation

struct CaptionPipelineState: Sendable {
    static let defaultMaximumSegments = 10

    private(set) var segments: [CaptionSegment] = []
    private(set) var interimSourceText = ""
    private(set) var generation = 0
    private var nextSequence = 0
    private var stabilizer = SegmentStabilizer()
    let maximumSegments: Int

    init(maximumSegments: Int = Self.defaultMaximumSegments) {
        self.maximumSegments = max(1, maximumSegments)
    }

    mutating func start() {
        generation += 1
        interimSourceText = ""
        segments.removeAll(keepingCapacity: false)
        stabilizer.reset()
        nextSequence = 0
    }

    @discardableResult
    mutating func stop() -> Int {
        generation += 1
        interimSourceText = ""
        segments.removeAll(keepingCapacity: false)
        stabilizer.reset()
        nextSequence = 0
        return generation
    }

    mutating func ingest(_ event: RecognitionEvent) -> TranslationWorkItem? {
        guard let output = stabilizer.ingest(event) else { return nil }
        switch output {
        case .interim(let text):
            interimSourceText = text
            return nil
        case .stable(let id, let text):
            interimSourceText = ""
            let sequence = nextSequence
            nextSequence += 1
            segments.append(CaptionSegment(
                id: id,
                sequence: sequence,
                sourceText: text,
                translatedText: nil
            ))
            if segments.count > maximumSegments {
                segments.removeFirst(segments.count - maximumSegments)
            }
            return TranslationWorkItem(segmentID: id, sequence: sequence, text: text, generation: generation)
        }
    }

    @discardableResult
    mutating func applyTranslation(_ text: String, to segmentID: String, generation expectedGeneration: Int) -> Bool {
        guard expectedGeneration == generation,
              let index = segments.firstIndex(where: { $0.id == segmentID }) else { return false }
        segments[index].translatedText = text
        return true
    }
}
