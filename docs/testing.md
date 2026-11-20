# Verification · 验证记录

The GPLv3 source candidate was verified on 20 November 2026 on Apple silicon using macOS 27.2.1 and Xcode 27.2. The documented verification command is:

```sh
./Scripts/verify_release.sh
```

| Check | Result |
| --- | --- |
| Localized resources and Info.plist | Valid |
| macOS tests | 197 passed, 0 failed, 0 skipped |
| Release static analysis and build | Passed |
| Local Release code signature | Passed strict verification |
| Signed entitlements | Exactly matched the four declared entitlement keys |
| Release binary libraries | All link paths resolve to macOS system locations |
| README previews | Rendered from built-in, synthetic caption samples in both languages |

## Manual coverage still open · 待补的手动验收

The automated run does not cover first-run privacy prompts on a separate Mac, every audio route and language pair, or downloading absent resources and then running offline. To check those paths, use public sample material, prepare the Apple language resources, confirm the selected audio route, and start and stop captions. If Apple Intelligence is available, also check contextual enhancement and its fallback behavior. Text history should start disabled, and the app should save no audio.

尚未在另一台 Mac 逐项重测首次授权、真实系统音频和麦克风设备、首次资源下载及断网运行。测试时使用公开素材，并检查启停字幕、上下文增强和回退、文字历史默认关闭等行为。
