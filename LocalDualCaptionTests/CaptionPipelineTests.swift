@preconcurrency import AVFoundation
import XCTest
@testable import LocalDualCaption

final class CaptionPipelineTests: XCTestCase {
    func testSystemAudioSamplesAreCopiedIntoFreshPCMBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        source.frameLength = 4
        let sourceSamples = try XCTUnwrap(source.floatChannelData?[0])
        sourceSamples[0] = 0.25
        sourceSamples[1] = -0.5
        sourceSamples[2] = 0.75
        sourceSamples[3] = -1.0

        let destination = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        XCTAssertEqual(destination.frameLength, 0)
        XCTAssertEqual(
            UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)[0].mDataByteSize,
            0
        )

        let copied = AudioBufferConverter.copyAudioData(
            from: UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList),
            to: destination,
            frameCount: source.frameLength
        )

        XCTAssertTrue(copied)
        XCTAssertEqual(destination.frameLength, source.frameLength)
        let destinationSamples = try XCTUnwrap(destination.floatChannelData?[0])
        XCTAssertEqual(destinationSamples[0], 0.25)
        XCTAssertEqual(destinationSamples[1], -0.5)
        XCTAssertEqual(destinationSamples[2], 0.75)
        XCTAssertEqual(destinationSamples[3], -1.0)
    }

    func testLiveAudioUsesContiguousAnalyzerTimelineAfterConversion() throws {
        // AnalyzerInput requires signed 16-bit samples on macOS 27. Production
        // uses SpeechAnalyzer's negotiated format; keep this fixture compatible.
        let format = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
        buffer.frameLength = 320
        let samples = try XCTUnwrap(buffer.int16ChannelData?[0])
        samples.initialize(repeating: 0, count: Int(buffer.frameLength))

        let first = AudioBufferConverter.makeContiguousAnalyzerInput(buffer)
        let second = AudioBufferConverter.makeContiguousAnalyzerInput(buffer)

        XCTAssertNil(first.bufferStartTime)
        XCTAssertNil(second.bufferStartTime)
    }

    func testInterimSourceTextDoesNotSubmitTranslation() {
        var pipeline = CaptionPipelineState()
        pipeline.start()
        let work = pipeline.ingest(.init(id: "one", text: "hello", isFinal: false))
        XCTAssertNil(work)
        XCTAssertEqual(pipeline.interimSourceText, "hello")
        XCTAssertTrue(pipeline.segments.isEmpty)
    }

    func testStableSourceTextSubmitsOnlyOnce() {
        var pipeline = CaptionPipelineState()
        pipeline.start()
        let event = RecognitionEvent(id: "one", text: "Hello world.", isFinal: true)
        XCTAssertNotNil(pipeline.ingest(event))
        XCTAssertNil(pipeline.ingest(event))
        XCTAssertEqual(pipeline.segments.count, 1)
    }

    func testSameContentWithDifferentSegmentIDsIsPreserved() {
        var pipeline = CaptionPipelineState()
        pipeline.start()
        XCTAssertNotNil(pipeline.ingest(.init(id: "one", text: "Yes.", isFinal: true)))
        XCTAssertNotNil(pipeline.ingest(.init(id: "two", text: "Yes.", isFinal: true)))
        XCTAssertEqual(pipeline.segments.map(\.sourceText), ["Yes.", "Yes."])
    }

    func testDuplicateInterimRecognitionIsNotRepeated() {
        var stabilizer = SegmentStabilizer()
        let event = RecognitionEvent(id: "one", text: "renewable", isFinal: false)
        XCTAssertEqual(stabilizer.ingest(event), .interim("renewable"))
        XCTAssertNil(stabilizer.ingest(event))
    }

    func testTranslationsCannotReorderSourceSegments() {
        var pipeline = CaptionPipelineState(maximumSegments: 3)
        pipeline.start()
        let first = pipeline.ingest(.init(id: "one", text: "First", isFinal: true))!
        let second = pipeline.ingest(.init(id: "two", text: "Second", isFinal: true))!
        XCTAssertTrue(pipeline.applyTranslation("第二", to: second.segmentID, generation: second.generation))
        XCTAssertTrue(pipeline.applyTranslation("第一", to: first.segmentID, generation: first.generation))
        XCTAssertEqual(pipeline.segments.map(\.id), ["one", "two"])
        XCTAssertEqual(pipeline.segments.map(\.translatedText), ["第一", "第二"])
    }

    func testExpiredTranslationCannotOverwriteNewSession() {
        var pipeline = CaptionPipelineState()
        pipeline.start()
        let oldWork = pipeline.ingest(.init(id: "old", text: "Old", isFinal: true))!
        pipeline.start()
        _ = pipeline.ingest(.init(id: "new", text: "New", isFinal: true))
        XCTAssertFalse(pipeline.applyTranslation("旧", to: oldWork.segmentID, generation: oldWork.generation))
        XCTAssertNil(pipeline.segments.first?.translatedText)
    }

    func testStopAdvancesGenerationAndCancelsQueue() {
        var pipeline = CaptionPipelineState()
        var queue = OrderedTranslationQueue()
        pipeline.start()
        let work = pipeline.ingest(.init(id: "one", text: "Text", isFinal: true))!
        queue.enqueue(work)
        XCTAssertEqual(pipeline.segments.count, 1)
        let oldGeneration = pipeline.generation
        let stoppedGeneration = pipeline.stop()
        queue.cancelAll()
        XCTAssertGreaterThan(stoppedGeneration, oldGeneration)
        XCTAssertTrue(queue.items.isEmpty)
        XCTAssertTrue(pipeline.interimSourceText.isEmpty)
        XCTAssertTrue(pipeline.segments.isEmpty)
    }

    func testRepeatedStartStopCyclesRejectEveryStaleTranslationAndClearState() throws {
        var pipeline = CaptionPipelineState()
        var queue = OrderedTranslationQueue(capacity: 8)
        var staleWork: TranslationWorkItem?

        for cycle in 0..<500 {
            pipeline.start()
            let currentWork = try XCTUnwrap(
                pipeline.ingest(.init(id: "shared", text: "Cycle \(cycle)", isFinal: true))
            )

            if let staleWork {
                XCTAssertFalse(
                    pipeline.applyTranslation(
                        "stale",
                        to: staleWork.segmentID,
                        generation: staleWork.generation
                    )
                )
                XCTAssertNil(pipeline.segments.first?.translatedText)
            }

            queue.enqueue(currentWork)
            _ = pipeline.ingest(.init(id: "interim-\(cycle)", text: "partial", isFinal: false))
            _ = pipeline.stop()
            queue.cancelAll()

            XCTAssertTrue(queue.items.isEmpty)
            XCTAssertTrue(pipeline.interimSourceText.isEmpty)
            XCTAssertTrue(pipeline.segments.isEmpty)
            staleWork = currentWork
        }

        XCTAssertEqual(pipeline.generation, 1_000)
    }

    func testCaptionQueueKeepsTenLatestSegmentsByDefault() {
        var pipeline = CaptionPipelineState()
        pipeline.start()
        for index in 0..<50 {
            _ = pipeline.ingest(.init(id: "\(index)", text: "Text \(index)", isFinal: true))
        }
        XCTAssertEqual(pipeline.maximumSegments, 10)
        XCTAssertEqual(pipeline.segments.count, 10)
        XCTAssertEqual(pipeline.segments.map(\.id), (40..<50).map(String.init))
    }

    func testInterimCaptionDoesNotEvictTenConfirmedCaptions() {
        var pipeline = CaptionPipelineState()
        pipeline.start()
        for index in 0..<10 {
            _ = pipeline.ingest(.init(id: "\(index)", text: "Text \(index)", isFinal: true))
        }
        _ = pipeline.ingest(.init(id: "current", text: "Still recognizing", isFinal: false))
        XCTAssertEqual(pipeline.segments.count, 10)
        XCTAssertEqual(pipeline.segments.first?.id, "0")
        XCTAssertEqual(pipeline.interimSourceText, "Still recognizing")
    }

    func testTranslationQueueRejectsOverflowWithoutDiscardingAcceptedWork() {
        var queue = OrderedTranslationQueue(capacity: 3)
        XCTAssertTrue(queue.enqueue(.init(segmentID: "4", sequence: 4, text: "x", generation: 1)))
        XCTAssertTrue(queue.enqueue(.init(segmentID: "2", sequence: 2, text: "x", generation: 1)))
        XCTAssertTrue(queue.enqueue(.init(segmentID: "3", sequence: 3, text: "x", generation: 1)))
        XCTAssertFalse(queue.enqueue(.init(segmentID: "1", sequence: 1, text: "x", generation: 1)))
        XCTAssertEqual(queue.items.count, 3)
        XCTAssertEqual(queue.items.map(\.sequence), [2, 3, 4])
    }

    func testTranslationQueueRemainsBoundedDuringLargeBurstAndFullyCancels() {
        var queue = OrderedTranslationQueue(capacity: 8)

        for sequence in 0..<10_000 {
            let accepted = queue.enqueue(.init(
                segmentID: "segment-\(sequence)",
                sequence: sequence,
                text: "Text \(sequence)",
                generation: 1
            ))
            XCTAssertEqual(accepted, sequence < 8)
            XCTAssertLessThanOrEqual(queue.items.count, queue.capacity)
        }

        XCTAssertEqual(queue.items.map(\.sequence), Array(0..<8))
        XCTAssertEqual((0..<8).compactMap { _ in queue.popFirst()?.sequence }, Array(0..<8))
        XCTAssertNil(queue.popFirst())

        queue.enqueue(.init(segmentID: "final", sequence: 10_000, text: "Final", generation: 1))
        queue.cancelAll()
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testCompleteTranslationSpeechQueueNeverDiscardsAcceptedSegments() {
        var queue = BoundedTranslationSpeechQueue(capacity: 2)
        for sequence in 0..<2 {
            XCTAssertTrue(queue.enqueue(.init(
                segmentID: "segment-\(sequence)",
                sequence: sequence,
                text: "Translation \(sequence)",
                voiceIdentifier: "voice",
                generation: 1,
                enqueuedAt: Double(sequence)
            )))
        }
        XCTAssertFalse(queue.enqueue(.init(
            segmentID: "segment-2",
            sequence: 2,
            text: "Translation 2",
            voiceIdentifier: "voice",
            generation: 1,
            enqueuedAt: 2
        )))

        XCTAssertEqual(queue.items.map(\.sequence), [0, 1])
        XCTAssertEqual(queue.popFirst()?.sequence, 0)
        XCTAssertEqual(queue.popFirst()?.sequence, 1)
        XCTAssertNil(queue.popFirst())
    }

    func testTranslationSpeechQueueDeduplicatesAndCancels() {
        var queue = BoundedTranslationSpeechQueue(capacity: 3)
        queue.enqueue(.init(
            segmentID: "same",
            sequence: 1,
            text: "First",
            voiceIdentifier: "voice",
            generation: 1,
            enqueuedAt: 1
        ))
        queue.enqueue(.init(
            segmentID: "same",
            sequence: 1,
            text: "Updated",
            voiceIdentifier: "voice",
            generation: 1,
            enqueuedAt: 2
        ))

        XCTAssertEqual(queue.items.map(\.text), ["Updated"])
        queue.cancelAll()
        XCTAssertTrue(queue.items.isEmpty)
    }

    func testTranslationSpeechRateIncreasesSmoothlyWithQueueDelayAndIsCapped() {
        let base: Float = 0.5
        let maximum: Float = 0.8
        let rates = [0.0, 2.0, 5.0, 8.0, 14.0, 20.0, 200.0].map {
            TranslationSpeechRatePolicy.rate(
                forQueueDelay: $0,
                baseRate: base,
                maximumRate: maximum
            )
        }

        XCTAssertEqual(rates[0], base, accuracy: 0.0001)
        XCTAssertEqual(rates[1], base, accuracy: 0.0001)
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertEqual(rates[rates.count - 1], base * 1.30, accuracy: 0.0001)
        XCTAssertTrue(rates.allSatisfy { $0 <= maximum })
    }

    func testTranslationSpeechRateNeverExceedsSystemMaximum() {
        XCTAssertEqual(
            TranslationSpeechRatePolicy.rate(
                forQueueDelay: 100,
                baseRate: 0.9,
                maximumRate: 1.0
            ),
            1.0,
            accuracy: 0.0001
        )
    }

    func testTranslationVoiceCatalogUsesHighestInstalledQualityForEveryTimbre() {
        let options = TranslationSpeechVoiceCatalog.highestQualityOptions(for: "zh-CN")

        XCTAssertFalse(options.isEmpty)
        XCTAssertTrue(options.allSatisfy { $0.languageCode == "zh-CN" })
        XCTAssertEqual(Set(options.map(\.id)).count, options.count)
        XCTAssertEqual(Set(options.map(\.name)).count, options.count)
        let installedChineseVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "zh-CN"
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        for option in options {
            XCTAssertEqual(
                option.qualityRawValue,
                installedChineseVoices
                    .filter { $0.name == option.name }
                    .map(\.quality.rawValue)
                    .max()
            )
        }
    }

    func testErrorStateIsSafeAndReadable() {
        let status = CaptionStatus.error("Model unavailable")
        XCTAssertEqual(status.label, "Error: Model unavailable")
    }

    func testTraditionalChineseTargetIsNormalizedWhileNonChineseContentIsPreserved() throws {
        let input = "軟體 OpenAI GPT-5 2026：風力發電，檔案 A/B。"
        let output = try CaptionTextNormalizer.normalizeTranslation(
            input,
            expectedTarget: .init(language: .chinese, chineseScript: .simplified),
            actualTargetLanguage: Locale.Language(identifier: "zh-Hant")
        )

        XCTAssertEqual(output, "软体 OpenAI GPT-5 2026：风力发电，档案 A/B。")
    }

    func testSimplifiedChineseTargetCanBeNormalizedToTraditional() throws {
        let input = "软件 OpenAI GPT-5 2026：风力发电，文件 A/B。"
        let output = try CaptionTextNormalizer.normalizeTranslation(
            input,
            expectedTarget: .init(language: .chinese, chineseScript: .traditional),
            actualTargetLanguage: Locale.Language(identifier: "zh-Hans")
        )

        XCTAssertEqual(output, "軟件 OpenAI GPT-5 2026：風力發電，文件 A/B。")
    }

    func testNonChineseTargetIsReturnedUnchanged() throws {
        let output = try CaptionTextNormalizer.normalizeTranslation(
            "Énergie OpenAI 2026.",
            expectedTarget: .init(language: .french, chineseScript: .simplified),
            actualTargetLanguage: Locale.Language(identifier: "fr-FR")
        )

        XCTAssertEqual(output, "Énergie OpenAI 2026.")
    }

    func testUnexpectedTranslationTargetLanguageIsRejected() {
        XCTAssertThrowsError(
            try CaptionTextNormalizer.normalizeTranslation(
                "Unexpected output",
                expectedTarget: .init(language: .chinese, chineseScript: .simplified),
                actualTargetLanguage: Locale.Language(identifier: "en")
            )
        )
    }
}
