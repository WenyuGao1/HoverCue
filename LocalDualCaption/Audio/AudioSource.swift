import Foundation

struct AudioSource: Identifiable, Hashable, Sendable {
    private static let microphoneDevicePrefix = "microphone-device:"

    static let systemDefaultMicrophone = AudioSource(
        id: "microphone-default",
        title: "System Default Microphone",
        bundleIdentifier: nil,
        processID: nil,
        microphoneDeviceUID: nil
    )
    static let allSystemAudio = AudioSource(
        id: "all",
        title: "All System Audio",
        bundleIdentifier: nil,
        processID: nil,
        microphoneDeviceUID: nil
    )

    let id: String
    let title: String
    let bundleIdentifier: String?
    let processID: pid_t?
    let microphoneDeviceUID: String?
    let isAvailable: Bool
    let isAuxiliary: Bool

    init(
        id: String,
        title: String,
        bundleIdentifier: String?,
        processID: pid_t?,
        microphoneDeviceUID: String? = nil,
        isAvailable: Bool = true,
        isAuxiliary: Bool = false
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.processID = processID
        self.microphoneDeviceUID = microphoneDeviceUID
        self.isAvailable = isAvailable
        self.isAuxiliary = isAuxiliary
    }

    static func microphone(title: String, deviceUID: String) -> AudioSource {
        AudioSource(
            id: microphoneDevicePrefix + deviceUID,
            title: title,
            bundleIdentifier: nil,
            processID: nil,
            microphoneDeviceUID: deviceUID
        )
    }

    static func unavailableMicrophone(forSourceID sourceID: String) -> AudioSource? {
        guard sourceID.hasPrefix(microphoneDevicePrefix) else { return nil }
        let deviceUID = String(sourceID.dropFirst(microphoneDevicePrefix.count))
        guard !deviceUID.isEmpty else { return nil }
        return AudioSource(
            id: sourceID,
            title: "Selected Microphone",
            bundleIdentifier: nil,
            processID: nil,
            microphoneDeviceUID: deviceUID,
            isAvailable: false
        )
    }

    var isSystemDefaultMicrophone: Bool {
        id == Self.systemDefaultMicrophone.id
    }

    /// Older selections use bundle-id + PID. Recover identity after a process exits.
    static func applicationBundleIdentifier(forSourceID id: String) -> String? {
        guard !id.hasPrefix(microphoneDevicePrefix),
              let separator = id.lastIndex(of: "-"),
              Int32(id[id.index(after: separator)...]) != nil else { return nil }
        let bundleID = String(id[..<separator])
        return bundleID.isEmpty ? nil : bundleID
    }

    func unavailable() -> AudioSource {
        AudioSource(id: id, title: title, bundleIdentifier: bundleIdentifier,
                    processID: processID, microphoneDeviceUID: microphoneDeviceUID,
                    isAvailable: false, isAuxiliary: isAuxiliary)
    }

    var isMicrophone: Bool {
        isSystemDefaultMicrophone || microphoneDeviceUID != nil
    }
}
