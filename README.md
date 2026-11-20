<p align="center">
  <img src="LocalDualCaption/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png" width="78" alt="HoverCue icon">
</p>

<h1 align="center">HoverCue</h1>

<p align="center"><strong>Live bilingual captions for Mac</strong></p>

<p align="center">Follow meetings, courses and videos with the original speech and its translation in a floating caption window. Speech recognition and translation run on your Mac.</p>

<p align="center">
  <strong><a href="https://github.com/WenyuGao1/HoverCue/releases/download/v1.0.1/HoverCue-v1.0.1-macOS-arm64.dmg">Download for Mac</a></strong>
  · <a href="https://github.com/WenyuGao1/HoverCue/releases/latest">Release notes</a>
  · <a href="README.zh-CN.md">简体中文</a>
</p>

![HoverCue's audio and language controls beside floating English and Chinese captions with sample text](docs/images/hovercue-en.jpg)

## See HoverCue in action

Choose the microphone, one Mac app, or all system audio. Set the spoken and translated languages, then start captions. HoverCue offers English, Chinese (Simplified and Traditional), German, Spanish, French, Italian, Japanese, Korean and Portuguese. Exact language combinations depend on macOS and the language resources installed.

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>Floating caption controls</strong><br>
      <a href="docs/images/en/appearance.jpg"><img src="docs/images/en/appearance.jpg" width="460" alt="HoverCue caption appearance controls with a bilingual preview"></a><br>
      Adjust text size, colors and glass appearance. Revisit recent caption pairs in the floating window.
    </td>
    <td width="50%" valign="top">
      <strong>Two translation modes</strong><br>
      <a href="docs/images/en/translation.jpg"><img src="docs/images/en/translation.jpg" width="460" alt="HoverCue settings showing low-latency and contextual translation modes"></a><br>
      Use low latency to keep up with speech or let contextual enhancement consider recent sentences on supported Macs.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>Custom terminology</strong><br>
      <a href="docs/images/en/terminology.jpg"><img src="docs/images/en/terminology.jpg" width="460" alt="HoverCue terminology rules with example original terms and a fixed translation"></a><br>
      Keep names, acronyms and technical terms as written, or supply a preferred translation for each language pair.
    </td>
    <td width="50%" valign="top">
      <strong>Spoken translations</strong><br>
      <a href="docs/images/en/voice.jpg"><img src="docs/images/en/voice.jpg" width="460" alt="HoverCue voice settings with options for spoken translations"></a><br>
      Read completed translations aloud. Choose an installed macOS voice for the target language.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>Optional local history</strong><br>
      <a href="docs/images/en/history.jpg"><img src="docs/images/en/history.jpg" width="460" alt="HoverCue history showing a sample battery test record and bilingual summary"></a><br>
      Save and export bilingual text after everyone agrees. Supported Macs can generate summaries on device.
    </td>
    <td width="50%" valign="top">
      <strong>On-device processing</strong><br>
      <a href="docs/images/en/privacy.jpg"><img src="docs/images/en/privacy.jpg" width="460" alt="HoverCue privacy information showing how audio and optional text history are handled"></a><br>
      Speech recognition and translation run on your Mac. Audio is never saved or uploaded.
    </td>
  </tr>
</table>

*Screenshots use sample captions and a synthetic translation history.*

## Download and use

1. Download the [Mac installer](https://github.com/WenyuGao1/HoverCue/releases/latest) on an **Apple silicon Mac running macOS 26 or later**.
2. Open the DMG, drag HoverCue to **Applications**, then open the app. The [release page](https://github.com/WenyuGao1/HoverCue/releases/latest) explains how to open this locally signed build if macOS prompts you.
3. Choose an audio source and language pair. Grant the required macOS permissions and prepare missing language resources. macOS may need internet access for the initial download.

Press **⌥⌘C** to start or stop captions and **⌥⌘O** to show or hide the floating window. System audio permission is under **System Settings → Privacy & Security → Screen & System Audio Recording**. App audio selection includes all audio from the selected app, including other tabs in a browser. HoverCue requests microphone permission when you explicitly select a microphone source or request access.

Low-latency translation and terminology controls require **macOS 26.4 or later**. Contextual enhancement also requires Apple Intelligence and a supported language pair. HoverCue falls back to system translation when contextual enhancement is unavailable.

> Official HoverCue releases are available free of charge from this repository. Third-party distributors must not present their releases as official or imply approval or endorsement by the HoverCue project.

## Build from source

The project uses Apple frameworks and has no external packages. The verified build toolchain is **Xcode 27.2**.

```sh
git clone https://github.com/WenyuGao1/HoverCue.git
cd HoverCue
open LocalDualCaption.xcodeproj
```

Select **LocalDualCaption** and **My Mac** in Xcode, then choose **Product → Run**. A local command-line build uses the same scheme.

```sh
xcodebuild -project LocalDualCaption.xcodeproj -scheme LocalDualCaption \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/HoverCue.app
```

This uses local development signing. If another copy of HoverCue is installed, make sure you open the build you just compiled.

```sh
./Scripts/verify_release.sh
```

The verification script checks localized resources, runs the macOS tests, analyzes and builds the Release configuration, and verifies its signature and entitlements. The system translation integration test may need Apple language resources installed.

[Architecture](docs/architecture.md) · [Privacy](docs/privacy.md) · [Verification](docs/testing.md) · [Dependency and asset notes](THIRD_PARTY_NOTICES.md)

## Feedback

Report issues with your macOS and HoverCue versions, language pair, audio source type and steps that use sample material. Keep real audio, captions, translations, exported histories and meeting screenshots private. [GitHub Issues](https://github.com/WenyuGao1/HoverCue/issues)

## License

Copyright © 2026 Wenyu Gao. The HoverCue source and original project assets are licensed under the [GNU General Public License, version 3 only](LICENSE), SPDX `GPL-3.0-only`. You may study, modify and use the software commercially. Distributors of a GPL-covered modified version must make the corresponding source available to recipients as required by the license.

The earlier `v1.0.0` release retains the MIT terms under which it was published. Apple frameworks and OS-provided models are supplied separately under their applicable terms. [Dependency and asset notes](THIRD_PARTY_NOTICES.md)
