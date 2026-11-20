import Foundation

enum PermissionState: String, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

enum ModelState: String, Sendable {
    case checking
    case unsupported
    case downloadable
    case downloading
    case installed
    case error
}

enum CaptionStatus: Equatable, Sendable {
    case preparing
    case listening
    case recognizing
    case translating
    case stopped
    case error(String)

    var label: String { label(language: .english) }

    func label(language: AppLanguage) -> String {
        switch self {
        case .preparing: language.localized("Preparing")
        case .listening: language.localized("Listening")
        case .recognizing: language.localized("Recognizing")
        case .translating: language.localized("Translating")
        case .stopped: language.localized("Stopped")
        case .error(let message): "\(language.localized("Error")): \(language.localizedMessage(message))"
        }
    }
}
