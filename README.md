# BoomPet

一个原生、轻量的 macOS 桌面宠物与全屏提醒应用。

BoomPet 会把宠物保持在鼠标所在的显示器与桌面空间中。你可以创建自定义周期提醒；到达设定时间时，宠物会用全屏漫画式 **BOOM** 动画提醒你休息、喝水或处理下一件事。

> The interface supports Chinese, English, and following the macOS system language.

## 功能亮点

- 原生 Swift、SwiftUI 与 AppKit 实现，无 Electron 运行时
- 支持 Intel 与 Apple Silicon
- 支持多显示器、多个 Space 及全屏应用
- 宠物可拖拽、记忆位置，并在鼠标所在屏幕连续自主巡游
- 拖到屏幕边缘后，宠物会收起并显示固定爪印图标
- 悬停、点击、拖拽、发呆和游走时会出现淘气的思考气泡
- 内置宠物采用身体、头、耳、眼、嘴、前爪和尾巴分层动画
- 新版骨骼动作包将四只脚、头部、双耳、眼睛、嘴、身体和尾巴完全分离
- `pet-rig.json` 可配置父子层级、锚点、关键帧、朝向、动作速度和巡游路线
- 支持导入用户动作包；内置动作包就是一套可复制修改的完整示例
- 静止约 2 FPS、移动窗口约 20 FPS、肢体动画最高 15 FPS，不可见时暂停刷新
- 宠物尺寸可在设置中按 `80–260 px` 调整
- 互动台词可按六种场景分别配置中文与英文，每行一句
- 内置本地心情与行为引擎，无需联网或 API Key
- 自定义周期任务，任务列表首次启动时为空
- 提醒严格对齐整分钟的 `00` 秒，连续运行不会逐次漂移
- 每个任务可启用、停用、删除或立即预览 BOOM
- 双击任务标题即可修改提醒内容
- 漫画式全屏 BOOM、冲击波、粒子、星芒及提醒文字
- BOOM 支持自动关闭时间和轻量/标准/闪亮三档，开场结束后停止持续重绘
- 支持导入 PNG、JPG、GIF 与 WebP 宠物图片
- 导入时自动去除边缘纯色背景并裁切透明空白
- 支持跟随系统、中文和 English
- 鼠标所在屏幕选区截图与离线 macOS Vision OCR
- OCR 结果编辑、复制、自动互译；历史默认保存 200 条
- OCR 历史上限可在 `20–2000` 条之间设置
- 支持百度翻译、OpenAI Compatible、DeepL 和 LibreTranslate
- 可选剪贴板文本历史和基础选区贴图
- 翻译 API Key 保存于 macOS Keychain
- 提醒、宠物、OCR 与翻译集中在同一设置窗口的三个页签
- 每日自动检查 GitHub Releases；有新版时由宠物气泡提醒

## 系统要求

| 项目 | 要求 |
| --- | --- |
| macOS | 13.0 或更高版本 |
| 架构 | Intel `x86_64` / Apple Silicon `arm64` |
| 开发工具 | Apple Command Line Tools 或完整 Xcode |
| Swift | Swift 6 工具链；源码使用 Swift 5 语言模式 |
| 权限 | 使用选区 OCR/贴图时需要“屏幕录制”权限 |

## 快速开始

克隆或下载源码后，在项目目录中直接开发运行：

```bash
cd BoomPet
swift run BoomPet
```

应用启动后不会自动创建提醒。右键桌面宠物并选择“设置…”即可添加第一条任务。

## 构建 macOS 应用

项目提供了打包脚本，会分别编译 Intel 与 Apple Silicon 版本，然后合成为通用应用：

```bash
./scripts/build-app.sh
```

生成结果：

```text
dist/BoomPet.app
```

需要生成可上传到 GitHub Releases 的安装包时，先修改 `VERSION`，然后运行：

```bash
./scripts/package-release.sh
```

生成结果：

```text
dist/BoomPet-macOS-universal.dmg
dist/BoomPet-macOS-universal.dmg.sha256
dist/BoomPet-macOS-universal.zip
dist/BoomPet-macOS-universal.zip.sha256
```

`.dmg` 内包含 BoomPet 和“应用程序”快捷方式，适合普通用户拖拽安装；`.zip`
供程序自动更新或备用下载。脚本和 GitHub Actions 使用同一套打包流程，并从
`VERSION` 读取版本号。

未配置证书时脚本使用本地临时签名，适合开发和本机运行。设置
`BOOMPET_CODESIGN_IDENTITY` 后，打包脚本会使用对应 Developer ID 证书签名。
面向其他用户正式发布时，还应完成 Apple 公证。

构建产物不应提交到 Git，请通过 GitHub Releases 发布压缩后的应用。

## 使用说明

### 管理提醒

1. 右键宠物，选择“设置…”。
2. 输入提醒内容和周期分钟数。
3. 点击“添加”。
4. 使用任务行中的“预览”按钮立即查看 BOOM。
5. 双击任务标题可以修改内容。

例如在 `11:07:36` 创建每 1 分钟提醒，首次触发时间为 `11:08:00`，之后依次为 `11:09:00`、`11:10:00`，不会根据实际动画出现的时间继续累加。

### 移动宠物

- 直接拖拽宠物可以改变位置。
- 只有手动拖到屏幕左、右边缘时，宠物才会收起并显示固定爪印图标。
- 上、下边缘不会隐藏；自主巡游也会避开边缘安全区。
- 鼠标移到宠物身上会立刻暂停，移开后再继续巡游。
- 点击或拖动爪印图标即可恢复完整宠物。
- 在设置中可以关闭宠物的全屏自主巡游。
- “淘气气泡互动”可以单独关闭。

### 使用自定义宠物

在设置中选择“选择图片并自动抠图…”。

导入过程完全在本机完成。透明 PNG 或背景接近纯色的图片效果最好。复杂照片背景目前只能进行边缘背景识别，无法替代专业 AI 抠图工具。GIF 当前作为静态宠物图片显示。

需要真正的四足动作时，请在“宠物 → 骨骼、动作与路线配置”中导入包含
`pet-rig.json` 和透明 PNG 部件的文件夹。格式、字段和预览方法参见
[骨骼动作包格式](docs/pet-rig-format.md)。内置示例位于
[`DefaultPetRig`](Sources/BoomPet/Resources/DefaultPetRig)。

### 切换语言

设置窗口右上角提供：

- 跟随系统
- 中文
- English

系统界面、右键菜单和 BOOM 标题会切换语言；用户自己填写的任务内容保持原文。

### OCR、翻译与贴图

可以通过宠物右键菜单或全局快捷键调用：

| 快捷键 | 功能 |
| --- | --- |
| `⌥S` | 框选屏幕区域并使用 macOS Vision OCR |
| `⌥T` | 框选屏幕区域并创建置顶贴图 |
| `⌘⇧V` | 切换右上角 OCR、剪贴板历史面板 |

OCR 完全在本机完成，不需要 Key。翻译默认关闭；启用百度、OpenAI、DeepL 或 LibreTranslate 后，识别出的文字会按用户设置发送给对应服务商。

OCR 与贴图都调用 macOS 原生 `screencapture` 选区，截取当前 Space 中正在显示的
窗口内容。`⌥S` 的结果只进入 Vision OCR；`⌥T` 的结果只创建置顶贴图，两条
流程彼此独立。

`⌘⇧V` 会在鼠标所在显示器右上角切换 `300×440 pt` 的独立轻量历史面板（对齐旧版 Retina 下的 `600×880 px`）。它支持搜索正文、翻译和备注；备注以蓝色 `remark · 正文` 单行展示，备注、置顶与删除按钮仅在鼠标经过记录时出现。点击正文会复制完整内容并自动收起面板。重复内容不会新增第二条，而是保留备注/置顶并刷新时间。

## 在线更新与自动发版

BoomPet 使用公开的 GitHub Releases API：

```text
https://api.github.com/repos/vinfolhu/boom/releases/latest
```

应用启动约 5 秒后检查一次，此后最多每天自动检查一次。检测到更高的正式版本时，宠物会用气泡提醒；右键宠物选择“检查更新…”，或者点击历史窗口的“检查更新”，即可优先下载 Release 中的 `BoomPet-macOS-universal.dmg`，没有 DMG 时回退到同名 ZIP。若两者都不存在，则打开对应版本页面。

仓库已经包含 [release.yml](.github/workflows/release.yml)。发布步骤：

```bash
# 1. 修改 VERSION，例如 0.2.3，并提交
git add VERSION
git commit -m "chore: prepare v0.2.3"
git push origin master

# 2. 创建并推送同版本 tag
git tag v0.2.3
git push origin v0.2.3
```

推送 `v*` tag 后，GitHub Actions 会：

1. 执行 BoomPet 自检。
2. 分别构建 `x86_64` 与 `arm64`。
3. 合并 Universal 应用。
4. 生成 DMG 安装盘、ZIP 备用包及 SHA-256 校验文件。
5. 创建 GitHub Release 并上传四个二进制资产。

已经推送的版本标签不要移动。如果某次发布工作流本身存在问题，应先修复并
提交工作流，再增加补丁版本（例如从 `v0.2.0` 升到 `v0.2.1`）并推送新标签。
直接重新运行旧标签的任务，仍会使用该旧提交中的工作流文件。

也可以在 GitHub 的 Actions 页面手动运行工作流。手动运行只生成可下载的 Actions Artifact，不自动创建 Release。

GitHub 会在每个 Release 下自动附带 `Source code (zip)` 和
`Source code (tar.gz)`，这两个源码归档无法关闭。用户应下载我们上传的
`BoomPet-macOS-universal.dmg`，而不是 GitHub 自动生成的 Source code。

如果发布步骤提示 `Resource not accessible by integration`，请进入仓库：

```text
Settings → Actions → General → Workflow permissions
```

选择 `Read and write permissions` 后重新运行。

### Releases 还是 Packages？

桌面应用请选择 **Releases**。GitHub Packages 面向 npm、Maven、NuGet、RubyGems 和容器等包管理器，不提供通用的 macOS `.app` 分发格式。

未配置证书时脚本使用 ad-hoc 签名，适合开发测试。正式公开发布应配置 Apple Developer ID 签名与 notarization。完成正式签名之前，BoomPet 只负责下载 DMG/ZIP，不会静默替换正在运行的应用；用户需要退出旧版本并手动替换。

### 稳定权限与钥匙串身份

ad-hoc 签名会随每次构建改变代码身份，因此 macOS 可能在更新后重新询问钥匙串
或屏幕录制权限。BoomPet 不再在启动时读取翻译密钥；只有打开 OCR/翻译设置或
真正请求翻译时才访问钥匙串。要让公开版本升级后稳定继承权限，应使用同一张
Apple Developer ID Application 证书签署每个版本。

GitHub 仓库的 `Settings → Secrets and variables → Actions` 可配置：

| Secret | 内容 |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application `.p12` 的 Base64 内容 |
| `P12_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `KEYCHAIN_PASSWORD` | CI 临时钥匙串使用的随机密码 |
| `MACOS_CODESIGN_IDENTITY` | 完整签名名称，例如 `Developer ID Application: Name (TEAMID)` |

生成证书 Secret：

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

没有配置以上 Secrets 时，GitHub Actions 会继续生成 ad-hoc 测试包；配置后会
自动导入证书，并让打包脚本使用稳定身份签名。

首次使用框选功能时，请在“系统设置 → 隐私与安全性 → 屏幕录制”中允许 BoomPet，然后重新启动应用。

## 数据与隐私

BoomPet 不会上传提醒内容或宠物图片，也不包含遥测代码。只有在用户配置并调用翻译服务时，待翻译文本才会发送给选定的第三方服务商。

| 数据 | 保存位置 |
| --- | --- |
| 提醒、语言及宠物位置 | macOS `UserDefaults`，Bundle ID 为 `com.vinfol.boom` |
| 自定义宠物图片 | `~/Library/Application Support/BoomPet/custom-pet.png` |
| OCR 与剪贴板历史 | macOS `UserDefaults`，同时兼容镜像至 `~/.vinfol/history.json`，默认 200 条 |
| 翻译 API Key / Secret | macOS Keychain |
| 翻译兼容配置 | `~/.vinfol/ocr_trans.json`（密钥仍由 Keychain 管理） |

卸载应用不会自动删除以上用户数据。

首次运行新版时，如果检测到 `~/.vinfol/ocr_trans.json` 与 `~/.vinfol/history.json`，会只读迁移受支持的翻译设置和历史；旧文件不会被修改或删除。

## 智能行为与外部 API

BoomPet 是原生 Swift/AppKit + SwiftUI 应用，不包含 Tauri、React、WebView 或 Rust 运行时。当前“智能宠物”由本地行为引擎驱动，包括心情状态、可配置事件台词、冷却时间、全屏移动范围和随机探索。悬停、点击、拖拽、发呆与游走都能获得即时反馈；内置宠物还会眨眼、摆耳、张嘴、摆尾和活动前爪。不需要 API Key，也不会发送桌面行为数据。

翻译模块可以按用户配置访问第三方 API；它与宠物行为引擎相互独立。未来仍可增加可选的 LLM 对话插件，用于生成更长、更个性化的聊天内容。建议保持以下边界：

- 移动、提醒、动画和即时交互始终在本机执行。
- 外部 AI 必须由用户主动启用。
- 不要把服务商 API Key 写进客户端源码；正式服务应通过安全代理调用。
- 发送前明确展示将提交给外部服务的上下文。

## 项目结构

```text
.
├── Package.swift
├── Sources/BoomPet
│   ├── AppDelegate.swift
│   ├── PetController.swift
│   ├── BoomController.swift
│   ├── ReminderStore.swift
│   ├── ReminderScheduler.swift
│   ├── SettingsView.swift
│   ├── Localization.swift
│   ├── PetAssetStore.swift
│   ├── PetImageProcessor.swift
│   ├── ScreenRegionCapture.swift
│   ├── OCRServices.swift
│   ├── OCRCoordinator.swift
│   ├── OCRCenterView.swift
│   ├── GlobalHotKeyManager.swift
│   └── Resources
├── scripts/build-app.sh
└── ASSET_PROMPT.md
```

核心模块：

- `PetController`：悬浮窗口、多显示器跟随、拖拽、游走及边缘停靠。
- `PetBehaviorEngine`：本地心情状态、事件台词、频率控制及游走倾向。
- `PetDialogueStore`：六类互动场景的中英文台词配置与本地持久化。
- `PetBubbleController`：自动选择宠物上方或下方位置的思考气泡。
- `ReminderStore`：任务持久化和整分钟时间计算。
- `ReminderScheduler`：绝对时间调度、睡眠唤醒检查。
- `BoomController`：全屏提醒窗口和漫画动画。
- `PetImageProcessor`：本地背景去除与内容裁切。
- `LanguageStore`：系统语言检测及中英文切换。
- `ScreenRegionCapture`：鼠标所在显示器的交互式区域框选。
- `VisionOCRService`：macOS 本地文字识别。
- `OCRCoordinator`：OCR、翻译、结果窗口、历史与贴图流程。
- `GlobalHotKeyManager`：Carbon 全局快捷键注册。

## 自检

无需完整 Xcode 即可运行内置逻辑检查：

```bash
swift build
.build/debug/BoomPet --self-test
```

自检覆盖：

- 首次启动无默认任务
- 整分钟触发
- 周期不漂移
- 任务标题修改
- 纯色背景自动抠图
- 自动互译方向检测
- macOS Vision OCR

## 已知限制

- 当前仅支持 macOS，AppKit 代码不能直接编译成 Windows `.exe`。
- GIF 导入后暂时以静态图片显示。
- 自动抠图适合透明或纯色背景，不是通用的 AI 图像分割。
- 贴图目前支持置顶、移动和缩放，尚未移植原工具的马赛克与文字标注。
- 当前仅移植 macOS 本地 Vision OCR；云端 OCR 服务商尚未接入。
- 本地打包脚本生成的是临时签名应用，公开分发仍需开发者签名和公证。

## 贡献

欢迎提交 Issue 和 Pull Request。

建议在提交前运行：

```bash
swift build
.build/debug/BoomPet --self-test
```

请不要提交 `.build`、`dist`、签名证书、用户图片或其他本地生成文件。

## 宠物素材

仓库中的默认宠物是为本项目生成的原创素材。生成提示词与处理方式记录在 [ASSET_PROMPT.md](ASSET_PROMPT.md)。

## License

本仓库目前尚未包含开源许可证。正式公开前，请根据你的发布目标添加 `LICENSE` 文件，例如 MIT、Apache-2.0 或 GPL-3.0。未添加许可证时，代码在法律上默认保留所有权利。
