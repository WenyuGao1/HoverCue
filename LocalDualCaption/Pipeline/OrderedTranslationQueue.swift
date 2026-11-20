import Foundation

struct TranslationWorkItem: Equatable, Sendable {
    let segmentID: String
    let sequence: Int
    let text: String
    let generation: Int
    var context: TranslationContextSnapshot? = nil
}

struct OrderedTranslationQueue: Sendable {
    private(set) var items: [TranslationWorkItem] = []
    let capacity: Int

    init(capacity: Int = 4) {
        self.capacity = max(1, capacity)
    }

    @discardableResult
    mutating func enqueue(_ item: TranslationWorkItem) -> Bool {
        if let duplicateIndex = items.firstIndex(where: { $0.segmentID == item.segmentID }) {
            items[duplicateIndex] = item
            items.sort { $0.sequence < $1.sequence }
            return true
        }
        guard items.count < capacity else { return false }
        items.append(item)
        items.sort { $0.sequence < $1.sequence }
        return true
    }

    mutating func popFirst() -> TranslationWorkItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func cancelAll() {
        items.removeAll(keepingCapacity: false)
    }
}
