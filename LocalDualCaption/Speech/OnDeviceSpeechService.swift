@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

actor OnDeviceSpeechService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultTask: Task<Void, Never>?

    func start(
        localeIdentifier: String,
        vocabulary: [String],
        onEvent: @escaping @Sendable (RecognitionEvent) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws -> AVAudioFormat {
        await stop()

        let requested = Locale(identifier: localeIdentifier)
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw SpeechServiceError.unsupportedLocale(localeIdentifier)
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .timeIndexedProgressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpeechServiceError.noCompatibleAudioFormat
        }

        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(24)
        )
        let context = SpeechContextManager.makeContext(vocabulary: vocabulary)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )
        try await analyzer.setContext(context)
        try await analyzer.prepareToAnalyze(in: format)

        self.transcriber = transcriber
        self.analyzer = analyzer
        self.continuation = continuation

        resultTask = Task {
            do {
                for try await result in transcriber.results {
                    guard !Task.isCancelled else { break }
                    let start = result.range.start
                    let identifier = "\(start.value)/\(start.timescale)"
                    onEvent(RecognitionEvent(
                        id: identifier,
                        text: String(result.text.characters),
                        isFinal: result.isFinal
                    ))
                }
            } catch is CancellationError {
                return
            } catch {
                onError(error.localizedDescription)
            }
        }

        analysisTask = Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch is CancellationError {
                return
            } catch {
                onError(error.localizedDescription)
            }
        }
        return format
    }

    func append(_ input: AnalyzerInput) {
        continuation?.yield(input)
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
        analysisTask?.cancel()
        resultTask?.cancel()
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        analysisTask = nil
        resultTask = nil
        analyzer = nil
        transcriber = nil
    }
}
