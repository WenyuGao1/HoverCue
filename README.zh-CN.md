<p align="center">
  <img src="LocalDualCaption/Assets.xcassets/AppIcon.appiconset/AppIcon-128@2x.png" width="78" alt="HoverCue icon">
</p>

<h1 align="center">HoverCue</h1>

<p align="center"><strong>Mac 上的实时双语悬浮字幕</strong></p>

<p align="center">开会、听课或看视频时，在屏幕上同时看原文和译文。语音识别和翻译在 Mac 上完成。</p>

<p align="center">
  <strong><a href="https://github.com/WenyuGao1/HoverCue/releases/download/v1.0.2/HoverCue-v1.0.2-macOS-arm64.dmg">下载 Mac 安装包</a></strong>
  · <a href="https://github.com/WenyuGao1/HoverCue/releases/latest">发布说明</a>
  · <a href="README.md">English</a>
</p>

**安装前请看。** HoverCue 需要搭载 Apple 芯片、运行 macOS 26 或更新版本的 Mac。安装包采用本地签名，未经 Apple 公证，首次打开可能被 macOS 拦截。[首次打开和授权方法](#下载和使用)

![HoverCue v1.0.2 在 macOS 上运行的主窗口，显示音源、语言设置和应用内置的双语字幕预览](docs/images/zh-CN/main-v1.0.2.png)

## 功能与界面

可以选麦克风、指定的 Mac 应用或全部系统音频。设置原文和译文语言后即可开启字幕。支持英语、简体及繁体中文、德语、西班牙语、法语、意大利语、日语、韩语和葡萄牙语。具体可用的语言组合取决于 macOS 版本及语言资源。

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>悬浮字幕外观</strong><br>
      <a href="docs/images/zh-CN/appearance-v1.0.2.png"><img src="docs/images/zh-CN/appearance-v1.0.2.png" width="460" alt="HoverCue 字幕外观设置与双语预览"></a><br>
      调节字体大小、颜色和玻璃外观，也可以在悬浮窗里回看最近的双语字幕。
    </td>
    <td width="50%" valign="top">
      <strong>两种翻译模式</strong><br>
      <a href="docs/images/zh-CN/translation.png"><img src="docs/images/zh-CN/translation.png" width="460" alt="HoverCue 设置显示低延迟和上下文增强翻译模式"></a><br>
      低延迟模式适合跟上讲话。在支持 Apple 智能的 Mac 上，上下文增强可以参考前面几句。
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>自定义术语</strong><br>
      <a href="docs/images/zh-CN/terminology.png"><img src="docs/images/zh-CN/terminology.png" width="460" alt="HoverCue 术语页展示保留原词与指定译法"></a><br>
      保留人名、缩写和专业词，也可以按语言方向指定固定译法。
    </td>
    <td width="50%" valign="top">
      <strong>译文朗读</strong><br>
      <a href="docs/images/zh-CN/voice.png"><img src="docs/images/zh-CN/voice.png" width="460" alt="HoverCue 朗读与声音设置"></a><br>
      为译文语言选择已安装的 macOS 系统音色，自动朗读完成的译文。
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>可选的本地历史</strong><br>
      <a href="docs/images/zh-CN/history.png"><img src="docs/images/zh-CN/history.png" width="460" alt="HoverCue 翻译历史显示保存关闭、没有已保存记录的初次使用状态"></a><br>
      征得参与者同意后可保存、回看和导出双语文字，兼容的 Mac 还能在本地生成双语总结。
    </td>
    <td width="50%" valign="top">
      <strong>全程在本机处理</strong><br>
      <a href="docs/images/zh-CN/privacy.png"><img src="docs/images/zh-CN/privacy.png" width="268" alt="HoverCue 隐私说明展示音频和可选文字历史的处理方式"></a><br>
      语音识别和翻译都在 Mac 上进行，音频不保存、不上传。文字历史每次启动默认关闭。
    </td>
  </tr>
</table>

*实拍自 macOS。主窗口和字幕外观页显示 v1.0.2 的山湖底图。字幕来自内置预览，历史页显示初次使用时的空白状态。*

## 下载和使用

1. **安装并打开 HoverCue。** 下载 DMG，把 HoverCue 拖进「应用程序」，再从那里尝试打开。[官方下载](https://github.com/WenyuGao1/HoverCue/releases/latest)
2. **如果 macOS 拦截首次打开。** 确认安装包来自上面的官方发布页。先尝试打开一次，再到 **系统设置 → 隐私与安全性**，往下滚动，点「仍要打开」并确认。[Apple 官方操作说明](https://support.apple.com/zh-cn/102445)
3. **按音源授予权限。** 在 HoverCue 的「实时字幕」里选好音源和语言，然后打开应用内的 **设置 → 权限与离线模型**，点所需权限旁边的「允许」，按系统提示操作。

   - **语音识别**适用于所有音源。之前点过拒绝的话，到 **系统设置 → 隐私与安全性 → 语音识别**为 HoverCue 开启。
   - **屏幕与系统音频录制**适用于「全部系统音频」或某个应用的声音。到 **系统设置 → 隐私与安全性 → 屏幕与系统音频录制**为 HoverCue 开启。这个权限名称里有「屏幕」，HoverCue 只接收声音，不采集屏幕画面。如果 macOS 提示重新打开，退出 HoverCue 后再打开。
   - **麦克风**只在用麦克风作为音源时需要。可以在 HoverCue 的设置里主动授权，也可以选好麦克风后点「开始字幕」，按系统弹窗授权。之前点过拒绝的话，到 **系统设置 → 隐私与安全性 → 麦克风**为 HoverCue 开启。

4. **准备语言资源，再开始字幕。** 如果所选语言的语音或翻译模型还没安装，到应用内的 **设置 → 权限与离线模型**点「下载所需模型」。macOS 首次下载这些语言资源时可能需要联网。看到「已准备好离线字幕」后，回到「实时字幕」，点「开始字幕」。音频处理和翻译都在 Mac 上完成。

按 **⌥⌘C** 开始或停止字幕，按 **⌥⌘O** 显示或隐藏悬浮窗。选择浏览器作为音源时，该浏览器所有标签页播放的声音都可能进入字幕。

低延迟翻译和术语控制需要 **macOS 26.4 或更新版本**。上下文增强还需要 Apple 智能和受支持的语言组合。上下文增强不可用时，应用会回到系统翻译。

> HoverCue 官方版在本仓库免费提供。第三方发布者不得冒充官方发布，也不得暗示其版本获得 HoverCue 项目的认可或背书。

## 从源码构建

工程只使用 Apple 框架，无外部依赖包。已验证的构建工具链为 **Xcode 27.2**。

```sh
git clone https://github.com/WenyuGao1/HoverCue.git
cd HoverCue
open LocalDualCaption.xcodeproj
```

在 Xcode 选择 **LocalDualCaption** 和 **My Mac**，然后选择 **Product → Run**。也可以从终端构建并打开应用。

```sh
xcodebuild -project LocalDualCaption.xcodeproj -scheme LocalDualCaption \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath DerivedData build
open DerivedData/Build/Products/Debug/HoverCue.app
```

本地构建使用开发签名。如果 Mac 上已装有另一份 HoverCue，请确认打开的是刚构建的版本。

```sh
./Scripts/verify_release.sh
```

验证脚本检查本地化资源，运行 macOS 单元测试，分析并构建 Release 版本，再核验签名和权限。系统翻译集成测试可能需要提前安装 Apple 提供的语言资源。

[技术架构](docs/architecture.md) · [隐私说明](docs/privacy.md) · [验证记录](docs/testing.md) · [依赖与素材说明](THIRD_PARTY_NOTICES.md)

## 反馈

报告问题时请注明 macOS 与 HoverCue 版本、语言组合和音源类型，并用演示素材给出复现步骤。请把真实音频、字幕、译文、导出记录和会议截图留在本机。 [GitHub Issues](https://github.com/WenyuGao1/HoverCue/issues)

## 许可证

版权 © 2026 Wenyu Gao。HoverCue 源码和原创项目素材采用 [GNU 通用公共许可证第三版](LICENSE)，标识为 `GPL-3.0-only`。允许学习、修改、商用和分发。分发受此许可证约束的修改版时，须按许可证要求向接收者提供对应源码。

旧版 `v1.0.0` 沿用当时发布的 MIT 许可。Apple 系统框架及系统模型由 Apple 单独提供，适用各自条款。 [依赖与素材说明](THIRD_PARTY_NOTICES.md)
