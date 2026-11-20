import CoreAudio
import Foundation

enum MicrophoneDeviceCatalog {
    static func availableSources() throws -> [AudioSource] {
        try deviceIDs()
            .compactMap { deviceID -> AudioSource? in
                guard (try? hasInput(deviceID)) == true,
                      let name = try? stringProperty(
                        objectID: deviceID,
                        selector: kAudioObjectPropertyName
                      ),
                      let uid = try? stringProperty(
                        objectID: deviceID,
                        selector: kAudioDevicePropertyDeviceUID
                      ) else {
                    return nil
                }
                return .microphone(title: name, deviceUID: uid)
            }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    static func deviceID(for source: AudioSource) throws -> AudioDeviceID {
        if source.isSystemDefaultMicrophone {
            let deviceID: AudioDeviceID = try scalarProperty(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDefaultInputDevice
            )
            guard deviceID != kAudioObjectUnknown, try hasInput(deviceID) else {
                throw MicrophoneCaptureError.noInputDevice
            }
            return deviceID
        }

        guard source.isAvailable, let expectedUID = source.microphoneDeviceUID else {
            throw MicrophoneCaptureError.selectedDeviceUnavailable
        }
        for deviceID in try deviceIDs() where (try? hasInput(deviceID)) == true {
            if let uid = try? stringProperty(
                objectID: deviceID,
                selector: kAudioDevicePropertyDeviceUID
            ), uid == expectedUID {
                return deviceID
            }
        }
        throw MicrophoneCaptureError.selectedDeviceUnavailable
    }

    private static func deviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize
            )
        )
        guard dataSize > 0 else { return [] }

        var devices = [AudioDeviceID](
            repeating: kAudioObjectUnknown,
            count: Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        )
        try devices.withUnsafeMutableBytes { buffer in
            try check(
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    0,
                    nil,
                    &dataSize,
                    buffer.baseAddress!
                )
            )
        }
        return devices
    }

    private static func hasInput(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(
            AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        )
        return dataSize >= UInt32(MemoryLayout<AudioStreamID>.stride)
    }

    private static func scalarProperty<T>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> T {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<T>.size)
        return try withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer in
            try check(
                AudioObjectGetPropertyData(
                    objectID,
                    &address,
                    0,
                    nil,
                    &dataSize,
                    buffer.baseAddress!
                )
            )
            return buffer[0]
        }
    }

    private static func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        try check(
            AudioObjectGetPropertyData(
                objectID,
                &address,
                0,
                nil,
                &dataSize,
                &value
            )
        )
        guard let value else { throw MicrophoneDeviceCatalogError.invalidProperty }
        return value.takeUnretainedValue() as String
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw MicrophoneDeviceCatalogError.coreAudio(status)
        }
    }
}

enum MicrophoneDeviceCatalogError: LocalizedError, Sendable {
    case coreAudio(OSStatus)
    case invalidProperty

    var errorDescription: String? {
        "Unable to read available microphones."
    }
}
