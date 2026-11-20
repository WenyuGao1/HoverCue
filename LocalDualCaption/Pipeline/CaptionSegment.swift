import Foundation

struct CaptionSegment: Identifiable, Equatable, Sendable {
    let id: String
    let sequence: Int
    var sourceText: String
    var translatedText: String?
}

struct RecognitionEvent: Equatable, Sendable {
    let id: String
    let text: String
    let isFinal: Bool
}

enum StabilizerOutput: Equatable, Sendable {
    case interim(String)
    case stable(id: String, text: String)
}
