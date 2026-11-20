# Repository Rules

- Keep all audio, recognition, and translation on device. Never add network services or `com.apple.security.network.client`.
- Never save or export audio, or log or upload live content. Text history may be saved locally and exported only after the user explicitly enables history and confirms that all involved participants know and agree. History must default to off at every app launch; disabling must stop new recording immediately. Keep history storage and queues bounded.
- Request microphone permission only after the user explicitly selects the system-default microphone source or asks to grant that permission. Do not request camera, Accessibility, Input Monitoring, location, contacts, or calendar permissions.
- Use Apple system frameworks only; do not add packages, third-party SDKs, embedded model runtimes, or large bundled models.
- Register only ScreenCaptureKit `.audio` output for system-audio capture. Capture the user-selected system-default microphone with Apple audio-input APIs; do not register ScreenCaptureKit microphone output. Do not add screen output, screenshots, or video-frame processing.
- Keep all streaming structures bounded. Preserve generation checks so stopped or stale tasks cannot update captions.
- Verify API signatures against the installed SDK before changing Speech or Translation integration.
- Run the macOS unit tests and a Release build after meaningful changes. Recheck the signed entitlements before delivery.
