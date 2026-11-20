import Foundation

struct SegmentStabilizer: Sendable {
    private(set) var stableIDs: Set<String> = []
    private var stableIDOrder: [String] = []
    private var lastInterim: (id: String, text: String)?
    let rememberedIDLimit: Int

    init(rememberedIDLimit: Int = 64) {
        self.rememberedIDLimit = max(8, rememberedIDLimit)
    }

    mutating func ingest(_ event: RecognitionEvent) -> StabilizerOutput? {
        let text = event.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if event.isFinal {
            guard stableIDs.insert(event.id).inserted else { return nil }
            stableIDOrder.append(event.id)
            while stableIDOrder.count > rememberedIDLimit {
                stableIDs.remove(stableIDOrder.removeFirst())
            }
            if lastInterim?.id == event.id { lastInterim = nil }
            return .stable(id: event.id, text: text)
        }

        guard lastInterim?.id != event.id || lastInterim?.text != text else { return nil }
        lastInterim = (event.id, text)
        return .interim(text)
    }

    mutating func reset() {
        stableIDs.removeAll(keepingCapacity: false)
        stableIDOrder.removeAll(keepingCapacity: false)
        lastInterim = nil
    }
}
