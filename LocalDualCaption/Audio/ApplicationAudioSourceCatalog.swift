import Foundation

enum ApplicationAudioSourceCatalog {
    /// Unknown/background processes remain selectable in the compatibility submenu.
    static func isAuxiliary(isRegularApplication: Bool, bundleURL: URL?,
                            runningBundleID: String?, captureBundleID: String) -> Bool {
        guard isRegularApplication, let bundleURL,
              bundleURL.pathExtension.lowercased() == "app",
              !captureBundleID.isEmpty, runningBundleID == captureBundleID else { return true }
        let path = bundleURL.path
        return ["/Contents/XPCServices/", "/Contents/PlugIns/", "/Contents/Frameworks/",
                "/Contents/Library/LoginItems/"].contains { path.contains($0) }
    }

    static func preservingSelection(_ selectedID: String, previous: [AudioSource],
                                    refreshed: [AudioSource]) -> (sources: [AudioSource], selectedID: String) {
        if refreshed.contains(where: { $0.id == selectedID }) { return (refreshed, selectedID) }
        let previousSource = previous.first { $0.id == selectedID }
        let bundleID = previousSource?.bundleIdentifier
            ?? AudioSource.applicationBundleIdentifier(forSourceID: selectedID)
        if let bundleID {
            let replacements = refreshed.filter { $0.bundleIdentifier == bundleID && $0.isAvailable }
            // Never guess between multiple processes sharing an identity.
            if replacements.count == 1 { return (refreshed, replacements[0].id) }
        }
        let missing = previousSource?.unavailable()
            ?? AudioSource.unavailableMicrophone(forSourceID: selectedID)
            ?? AudioSource(id: selectedID, title: bundleID ?? "Selected Application",
                           bundleIdentifier: bundleID, processID: nil, isAvailable: false)
        return ([missing] + refreshed, selectedID)
    }
}
