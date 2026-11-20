@preconcurrency import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import Speech

final class AudioBufferConverter {
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    func convert(_ sampleBuffer: CMSampleBuffer) -> AnalyzerInput? {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let input = copyPCMBuffer(from: sampleBuffer) else { return nil }

        return convert(input)
    }

    func convert(_ input: AVAudioPCMBuffer) -> AnalyzerInput? {
        let output: AVAudioPCMBuffer
        if input.format == targetFormat {
            output = input
        } else {
            guard let converted = convertFormat(input) else { return nil }
            output = converted
        }
        return Self.makeContiguousAnalyzerInput(output)
    }

    static func copyPCMBuffer(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard input.frameLength > 0,
              let output = AVAudioPCMBuffer(
                  pcmFormat: input.format,
                  frameCapacity: input.frameLength
              ) else { return nil }
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
        guard copyAudioData(from: sourceBuffers, to: output, frameCount: input.frameLength) else {
            return nil
        }
        return output
    }

    static func makeContiguousAnalyzerInput(_ buffer: AVAudioPCMBuffer) -> AnalyzerInput {
        // ScreenCaptureKit timestamps describe the pre-conversion buffers. Audio conversion
        // can shift samples between output buffers, so reusing those timestamps can make two
        // converted buffers overlap. A nil start time tells SpeechAnalyzer to append this live
        // buffer immediately after the previous one, preserving a valid contiguous timeline.
        AnalyzerInput(buffer: buffer, bufferStartTime: nil)
    }

    private func copyPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: basicDescription) else { return nil }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr, requiredSize > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: requiredSize, alignment: 16)
        defer { raw.deallocate() }
        let sourceList = raw.assumingMemoryBound(to: AudioBufferList.self)
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: sourceList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard status == noErr else { return nil }

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourceList)
        guard Self.copyAudioData(from: sourceBuffers, to: output, frameCount: frameCount) else { return nil }
        return output
    }

    static func copyAudioData(
        from sourceBuffers: UnsafeMutableAudioBufferListPointer,
        to output: AVAudioPCMBuffer,
        frameCount: AVAudioFrameCount
    ) -> Bool {
        guard frameCount > 0, frameCount <= output.frameCapacity else { return false }

        // A newly allocated AVAudioPCMBuffer has frameLength == 0, so every destination
        // AudioBuffer initially reports mDataByteSize == 0. Set the valid frame length before
        // reading the destination AudioBufferList; otherwise the copy silently moves zero bytes
        // and SpeechAnalyzer receives silence even while system audio is playing.
        output.frameLength = frameCount
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else {
            output.frameLength = 0
            return false
        }

        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData,
                  sourceBuffers[index].mDataByteSize == destinationBuffers[index].mDataByteSize else {
                output.frameLength = 0
                return false
            }
            destinationData.copyMemory(
                from: sourceData,
                byteCount: Int(sourceBuffers[index].mDataByteSize)
            )
        }
        return true
    }

    private func convertFormat(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if converter == nil || converterSourceFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: targetFormat)
            converterSourceFormat = input.format
        }
        guard let converter else { return nil }
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return nil }

        let inputState = ConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if inputState.supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputState.supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil else { return nil }
        return output.frameLength > 0 ? output : nil
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var supplied = false
}
