@preconcurrency import AVFoundation
import Foundation

struct TranslationSpeechVoiceOption: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let languageCode: String
    let qualityRawValue: Int

    var qualityLocalizationKey: String {
        switch qualityRawValue {
        case AVSpeechSynthesisVoiceQuality.premium.rawValue: "Premium"
        case AVSpeechSynthesisVoiceQuality.enhanced.rawValue: "Enhanced"
        default: "Standard"
        }
    }

    func displayName(in appLanguage: AppLanguage) -> String {
        "\(name) · \(appLanguage.localized(qualityLocalizationKey))"
    }
}

enum TranslationSpeechVoiceCatalog {
    static func highestQualityOptions(for localeIdentifier: String) -> [TranslationSpeechVoiceOption] {
        let requestedLocale = Locale(identifier: localeIdentifier)
        let requestedLanguage = requestedLocale.language.languageCode?.identifier
        let requestedRegion = requestedLocale.language.region?.identifier
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            let locale = Locale(identifier: voice.language)
            guard locale.language.languageCode?.identifier == requestedLanguage else { return false }
            if let requestedRegion,
               let voiceRegion = locale.language.region?.identifier,
               requestedRegion != voiceRegion {
                return false
            }
            return !voice.voiceTraits.contains(.isNoveltyVoice)
                && !voice.voiceTraits.contains(.isPersonalVoice)
        }
        let highestQualityByTimbre = Dictionary(grouping: candidates, by: \.name)
            .values
            .compactMap { voices in
                voices.max {
                    if $0.quality.rawValue == $1.quality.rawValue {
                        return $0.identifier > $1.identifier
                    }
                    return $0.quality.rawValue < $1.quality.rawValue
                }
            }
        return highestQualityByTimbre
            .map {
                TranslationSpeechVoiceOption(
                    id: $0.identifier,
                    name: $0.name,
                    languageCode: $0.language,
                    qualityRawValue: $0.quality.rawValue
                )
            }
            .sorted {
                if $0.name == $1.name { return $0.id < $1.id }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}

struct TranslationSpeechWorkItem: Equatable, Sendable {
    let segmentID: String
    let sequence: Int
    let text: String
    let voiceIdentifier: String
    let generation: Int
    let enqueuedAt: TimeInterval
}

struct BoundedTranslationSpeechQueue: Sendable {
    static let completeModeCapacity = 4_096

    private(set) var items: [TranslationSpeechWorkItem] = []
    let capacity: Int

    init(capacity: Int = Self.completeModeCapacity) {
        self.capacity = max(1, capacity)
    }

    @discardableResult
    mutating func enqueue(_ item: TranslationSpeechWorkItem) -> Bool {
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

    mutating func popFirst() -> TranslationSpeechWorkItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func cancelAll() {
        items.removeAll(keepingCapacity: false)
    }
}

enum TranslationSpeechEnqueueResult: Equatable, Sendable {
    case enqueued
    case voiceUnavailable
    case backlogLimitReached
}

enum TranslationSpeechRatePolicy {
    static func rate(
        forQueueDelay delay: TimeInterval,
        baseRate: Float = AVSpeechUtteranceDefaultSpeechRate,
        maximumRate: Float = AVSpeechUtteranceMaximumSpeechRate
    ) -> Float {
        let safeDelay = max(0, delay)
        let multiplier: Float
        switch safeDelay {
        case ..<2:
            multiplier = 1
        case ..<8:
            multiplier = 1 + Float((safeDelay - 2) / 6) * 0.15
        case ..<20:
            multiplier = 1.15 + Float((safeDelay - 8) / 12) * 0.15
        default:
            multiplier = 1.30
        }
        return min(maximumRate, baseRate * multiplier)
    }
}

@MainActor
final class OnDeviceTranslationSpeechService: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var queue = BoundedTranslationSpeechQueue()
    private var activeItem: TranslationSpeechWorkItem?
    private var activeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    @discardableResult
    func enqueue(
        segmentID: String,
        sequence: Int,
        text: String,
        voiceIdentifier: String,
        generation: Int
    ) -> TranslationSpeechEnqueueResult {
        guard AVSpeechSynthesisVoice(identifier: voiceIdentifier) != nil else {
            return .voiceUnavailable
        }
        let item = TranslationSpeechWorkItem(
            segmentID: segmentID,
            sequence: sequence,
            text: text,
            voiceIdentifier: voiceIdentifier,
            generation: generation,
            enqueuedAt: ProcessInfo.processInfo.systemUptime
        )
        guard activeItem?.segmentID != segmentID else { return .enqueued }
        guard queue.enqueue(item) else { return .backlogLimitReached }
        speakNextIfNeeded()
        return .enqueued
    }

    func stop() {
        queue.cancelAll()
        activeItem = nil
        activeUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speakNextIfNeeded() {
        guard activeItem == nil, let item = queue.popFirst() else { return }
        guard let voice = AVSpeechSynthesisVoice(identifier: item.voiceIdentifier) else {
            speakNextIfNeeded()
            return
        }
        let queueDelay = ProcessInfo.processInfo.systemUptime - item.enqueuedAt
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = voice
        utterance.rate = TranslationSpeechRatePolicy.rate(forQueueDelay: queueDelay)
        utterance.postUtteranceDelay = 0.05
        activeItem = item
        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        finish(utterance)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        finish(utterance)
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        guard activeUtterance === utterance else { return }
        activeItem = nil
        activeUtterance = nil
        speakNextIfNeeded()
    }
}
