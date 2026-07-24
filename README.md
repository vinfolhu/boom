# BoomPet

一个原生、轻量的 macOS 桌面宠物与全屏提醒应用。

BoomPet 会把宠物保持在鼠标所在的显示器与桌面空间中。你可以创建自定义周期提醒；到达设定时间时，宠物会用全屏漫画式 **BOOM** 动画提醒你休息、喝水或处理下一件事。

> The interface supports Chinese, English, and following the macOS system language.

## 功能亮点

- 原生 Swift、SwiftUI 与 AppKit 实现，无 Electron 运行时
- 支持 Intel 与 Apple Silicon
- 支持多显示器、多个 Space 及全屏应用
- 宠物可拖拽、记忆位置并进行小范围自动活动
- 拖到屏幕边缘后，宠物会隐藏身体并露出小脑袋
- 自定义周期任务，任务列表首次启动时为空
- 提醒严格对齐整分钟的 `00` 秒，连续运行不会逐次漂移
- 每个任务可启用、停用、删除或立即预览 BOOM
- 双击任务标题即可修改提醒内容
- 漫画式全屏 BOOM、冲击波、粒子及提醒文字
- 支持导入 PNG、JPG、GIF 与 WebP 宠物图片
- 导入时自动去除边缘纯色背景并裁切透明空白
- 支持跟随系统、中文和 English
- 所有任务和图片均在本机处理，不依赖网络服务

## 系统要求

| 项目 | 要求 |
| --- | --- |
| macOS | 13.0 或更高版本 |
| 架构 | Intel `x86_64` / Apple Silicon `arm64` |
| 开发工具 | Apple Command Line Tools 或完整 Xcode |
| Swift | Swift 6 工具链；源码使用 Swift 5 语言模式 |

## 快速开始

克隆或下载源码后，在项目目录中直接开发运行：

```bash
cd BoomPet
swift run BoomPet
```

应用启动后不会自动创建提醒。右键桌面宠物并选择“提醒设置…”即可添加第一条任务。

## 构建 macOS 应用

项目提供了打包脚本，会分别编译 Intel 与 Apple Silicon 版本，然后合成为通用应用：

```bash
./scripts/build-app.sh
```

生成结果：

```text
dist/BoomPet.app
```

脚本使用本地临时签名，适合开发和本机运行。面向其他用户正式发布时，需要使用 Apple Developer ID 签名并完成 Apple 公证。

构建产物不应提交到 Git，请通过 GitHub Releases 发布压缩后的应用。

## 使用说明

### 管理提醒

1. 右键宠物，选择“提醒设置…”。
2. 输入提醒内容和周期分钟数。
3. 点击“添加”。
4. 使用任务行中的“预览”按钮立即查看 BOOM。
5. 双击任务标题可以修改内容。

例如在 `11:07:36` 创建每 1 分钟提醒，首次触发时间为 `11:08:00`，之后依次为 `11:09:00`、`11:10:00`，不会根据实际动画出现的时间继续累加。

### 移动宠物

- 直接拖拽宠物可以改变位置。
- 拖到屏幕任意边缘后，宠物会进入探头停靠状态。
- 再次拖动露出的小脑袋即可恢复完整宠物。
- 在设置中可以关闭宠物的自动小范围活动。

### 使用自定义宠物

在设置中选择“选择图片并自动抠图…”。

导入过程完全在本机完成。透明 PNG 或背景接近纯色的图片效果最好。复杂照片背景目前只能进行边缘背景识别，无法替代专业 AI 抠图工具。GIF 当前作为静态宠物图片显示。

### 切换语言

设置窗口右上角提供：

- 跟随系统
- 中文
- English

系统界面、右键菜单和 BOOM 标题会切换语言；用户自己填写的任务内容保持原文。

## 数据与隐私

BoomPet 不会上传提醒内容或宠物图片，也不包含遥测代码。

| 数据 | 保存位置 |
| --- | --- |
| 提醒、语言及宠物位置 | macOS `UserDefaults`，Bundle ID 为 `com.local.BoomPet` |
| 自定义宠物图片 | `~/Library/Application Support/BoomPet/custom-pet.png` |

卸载应用不会自动删除以上用户数据。

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
│   └── Resources
├── scripts/build-app.sh
└── ASSET_PROMPT.md
```

核心模块：

- `PetController`：悬浮窗口、多显示器跟随、拖拽、游走及边缘停靠。
- `ReminderStore`：任务持久化和整分钟时间计算。
- `ReminderScheduler`：绝对时间调度、睡眠唤醒检查。
- `BoomController`：全屏提醒窗口和漫画动画。
- `PetImageProcessor`：本地背景去除与内容裁切。
- `LanguageStore`：系统语言检测及中英文切换。

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

## 已知限制

- 当前仅支持 macOS，AppKit 代码不能直接编译成 Windows `.exe`。
- GIF 导入后暂时以静态图片显示。
- 自动抠图适合透明或纯色背景，不是通用的 AI 图像分割。
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
