import Foundation
import Speech

actor SpeechModelManager {
    private var reservedLocale: Locale?

    func state(for identifier: String) async -> ModelState {
        guard SpeechTranscriber.isAvailable else { return .unsupported }
        let requested = Locale(identifier: identifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            return .unsupported
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .unsupported: return .unsupported
        case .supported: return .downloadable
        case .downloading: return .downloading
        case .installed: return .installed
        @unknown default: return .error
        }
    }

    func prepare(identifier: String) async throws {
        try Task.checkCancellation()
        let requested = Locale(identifier: identifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw SpeechServiceError.unsupportedLocale(identifier)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)
        guard status != .unsupported else {
            throw SpeechServiceError.unsupportedLocale(identifier)
        }
        if status != .installed, let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await request.downloadAndInstall()
            } onCancel: {
                request.progress.cancel()
            }
        }
        try Task.checkCancellation()
        if let oldLocale = reservedLocale, oldLocale.identifier != locale.identifier {
            _ = await AssetInventory.release(reservedLocale: oldLocale)
        }
        try Task.checkCancellation()
        _ = try await AssetInventory.reserve(locale: locale)
        reservedLocale = locale
    }
}

enum SpeechServiceError: LocalizedError, Sendable {
    case unsupportedLocale(String)
    case noCompatibleAudioFormat

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let locale): "The on-device speech model does not support \(locale)."
        case .noCompatibleAudioFormat: "No compatible audio format is available for on-device speech recognition."
        }
    }
}
