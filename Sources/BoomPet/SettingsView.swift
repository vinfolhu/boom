import AppKit
import SwiftUI

enum AppSettingsTab: String, Hashable {
    case reminders
    case pet
    case ocr
}

final class SettingsTabStore: ObservableObject {
    @Published var selected: AppSettingsTab = .reminders
}

struct SettingsView: View {
    @ObservedObject var store: ReminderStore
    @ObservedObject var ocrHistory: OCRHistoryStore
    @ObservedObject var ocrSettings: OCRSettingsStore
    @ObservedObject var language: LanguageStore
    @ObservedObject var tabStore: SettingsTabStore
    let onTestBoom: (String) -> Void
    let onChoosePetImage: () -> Void
    let onRestoreDefaultPet: () -> Void
    let onPetSizeChange: (CGFloat) -> Void
    let onStartOCR: () -> Void
    let onStartSticky: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("BoomPet")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Spacer()
                Picker(
                    language.text("语言", "Language"),
                    selection: $language.selection
                ) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(language.choiceName(choice)).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 128)
            }

            TabView(selection: $tabStore.selected) {
                ReminderSettingsTab(
                    store: store,
                    language: language,
                    onTestBoom: onTestBoom
                )
                .tabItem {
                    Label(language.text("提醒", "Reminders"), systemImage: "timer")
                }
                .tag(AppSettingsTab.reminders)

                PetSettingsTab(
                    language: language,
                    onChoosePetImage: onChoosePetImage,
                    onRestoreDefaultPet: onRestoreDefaultPet,
                    onPetSizeChange: onPetSizeChange
                )
                .tabItem {
                    Label(language.text("宠物", "Pet"), systemImage: "pawprint")
                }
                .tag(AppSettingsTab.pet)

                OCRSettingsTab(
                    history: ocrHistory,
                    settings: ocrSettings,
                    language: language,
                    onStartOCR: onStartOCR,
                    onStartSticky: onStartSticky
                )
                .tabItem {
                    Label(
                        language.text("OCR 与翻译", "OCR & Translation"),
                        systemImage: "text.viewfinder"
                    )
                }
                .tag(AppSettingsTab.ocr)
            }
        }
        .padding(20)
        .frame(minWidth: 680, minHeight: 560)
    }
}

private struct ReminderSettingsTab: View {
    @ObservedObject var store: ReminderStore
    @ObservedObject var language: LanguageStore
    let onTestBoom: (String) -> Void

    @State private var title = ""
    @State private var intervalMinutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(language.text(
                "只有你亲自添加并启用的提醒才会触发 BOOM。",
                "Only reminders you add and enable will trigger."
            ))
            .foregroundStyle(.secondary)

            GroupBox(language.text("新增间隔提醒", "New interval reminder")) {
                HStack(spacing: 12) {
                    TextField(
                        language.text(
                            "提醒内容，例如：起来活动一下",
                            "Reminder, e.g. Stand up and stretch"
                        ),
                        text: $title
                    )
                    .textFieldStyle(.roundedBorder)

                    Stepper(value: $intervalMinutes, in: 1...480) {
                        Text(language.text(
                            "\(intervalMinutes) 分钟",
                            "\(intervalMinutes) min"
                        ))
                        .frame(width: 76, alignment: .trailing)
                    }

                    Button(language.text("添加", "Add")) {
                        let fallback = language.text("休息一下", "Take a break")
                        store.add(
                            title: title.isEmpty ? fallback : title,
                            intervalMinutes: intervalMinutes
                        )
                        title = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 7)
            }

            if store.reminders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text(language.text("还没有定时任务", "No reminders yet"))
                        .font(.headline)
                    Text(language.text(
                        "在上方设置提醒内容和间隔，然后点击“添加”。",
                        "Set reminder text and an interval, then click Add."
                    ))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.reminders) { reminder in
                            ReminderRow(
                                reminder: reminder,
                                language: language,
                                onToggle: {
                                    store.setEnabled(id: reminder.id, enabled: $0)
                                },
                                onIntervalChange: {
                                    store.setInterval(id: reminder.id, minutes: $0)
                                },
                                onTitleChange: {
                                    store.setTitle(id: reminder.id, title: $0)
                                },
                                onPreview: { onTestBoom(reminder.title) },
                                onDelete: { store.delete(id: reminder.id) }
                            )
                        }
                    }
                }
            }

            HStack {
                Text(language.text(
                    "定时严格对齐整分钟的 00 秒。",
                    "Timers align exactly to :00."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(language.text("测试 BOOM", "Test BOOM")) {
                    onTestBoom(language.text(
                        "这是一次 BOOM 测试！",
                        "This is a BOOM preview!"
                    ))
                }
            }
        }
        .padding(14)
    }
}

private struct PetSettingsTab: View {
    @ObservedObject var language: LanguageStore
    let onChoosePetImage: () -> Void
    let onRestoreDefaultPet: () -> Void
    let onPetSizeChange: (CGFloat) -> Void

    @AppStorage("BoomPet.petAutoRoam") private var petAutoRoam = true
    @AppStorage("BoomPet.petDialogueEnabled") private var petDialogueEnabled = true
    @AppStorage("BoomPet.petSize") private var petSize = 154.0
    @ObservedObject private var dialogueStore = PetDialogueStore.shared
    @State private var dialogueEvent: PetInteractionEvent = .hover
    @State private var editingChineseDialogue = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox(language.text("外观与动作", "Appearance & Motion")) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(language.text("宠物大小", "Pet Size"))
                                .frame(width: 90, alignment: .leading)
                            Slider(value: $petSize, in: 80...260, step: 2)
                                .onChange(of: petSize) {
                                    onPetSizeChange(CGFloat($0))
                                }
                            Text("\(Int(petSize)) px")
                                .monospacedDigit()
                                .frame(width: 62, alignment: .trailing)
                        }
                        HStack(spacing: 24) {
                            Toggle(
                                language.text("宠物自主活动", "Let the pet wander"),
                                isOn: $petAutoRoam
                            )
                            Toggle(
                                language.text("淘气气泡互动", "Playful speech bubbles"),
                                isOn: $petDialogueEnabled
                            )
                            Spacer()
                        }
                        HStack {
                            Text(language.text(
                                "拖到屏幕边缘会显示固定爪印。",
                                "Drop at a screen edge to show a paw icon."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Spacer()
                            Button(
                                language.text("恢复默认宠物", "Restore Default"),
                                action: onRestoreDefaultPet
                            )
                            Button(
                                language.text(
                                    "选择图片并自动抠图…",
                                    "Choose & Auto-Cutout…"
                                ),
                                action: onChoosePetImage
                            )
                        }
                    }
                    .padding(.vertical, 7)
                }

                GroupBox(language.text("互动台词", "Interaction Dialogue")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Picker(
                                language.text("场景", "Scene"),
                                selection: $dialogueEvent
                            ) {
                                ForEach(PetInteractionEvent.allCases) { event in
                                    Text(event.title(language: language)).tag(event)
                                }
                            }
                            .frame(width: 210)
                            Picker("", selection: $editingChineseDialogue) {
                                Text("中文").tag(true)
                                Text("English").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 160)
                            Spacer()
                            Button(language.text("恢复预设", "Reset Defaults")) {
                                dialogueStore.reset()
                            }
                            .controlSize(.small)
                        }
                        TextEditor(text: Binding(
                            get: {
                                dialogueStore.editableText(
                                    for: dialogueEvent,
                                    isChinese: editingChineseDialogue
                                )
                            },
                            set: {
                                dialogueStore.update(
                                    event: dialogueEvent,
                                    isChinese: editingChineseDialogue,
                                    text: $0
                                )
                            }
                        ))
                        .font(.body)
                        .frame(height: 150)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25))
                        )
                        Text(language.text(
                            "每行一句，宠物会按场景随机选择；全部在本机保存。",
                            "One phrase per line; everything stays on this Mac."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(14)
        }
    }
}

private struct OCRSettingsTab: View {
    @ObservedObject var history: OCRHistoryStore
    @ObservedObject var settings: OCRSettingsStore
    @ObservedObject var language: LanguageStore
    let onStartOCR: () -> Void
    let onStartSticky: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(language.text(
                    "历史记录仍使用右上角独立弹窗（⌘⇧V）。",
                    "History remains in the top-right popup (⌘⇧V)."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Text(language.text(
                    "\(history.items.count) 条记录",
                    "\(history.items.count) records"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(action: onStartSticky) {
                    Label(language.text("选区贴图", "Sticky"), systemImage: "pin")
                }
                Button(action: onStartOCR) {
                    Label(language.text("开始 OCR", "Start OCR"), systemImage: "viewfinder")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            OCRConfigurationView(
                settings: settings,
                history: history,
                language: language
            )

            GroupBox(language.text("数据文件位置", "Data File Locations")) {
                VStack(alignment: .leading, spacing: 8) {
                    pathRow(
                        language.text("翻译配置", "Translation Config"),
                        url: OCRDataPaths.settings
                    )
                    pathRow(
                        language.text("历史记录", "History"),
                        url: OCRDataPaths.history
                    )
                    Text(language.text(
                        "API Key 与 Secret 保存在 macOS 钥匙串；兼容文件保留旧项目路径。",
                        "API keys and secrets stay in macOS Keychain; compatibility files use the legacy paths."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func pathRow(_ title: String, url: URL) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: 96, alignment: .leading)
            Text(shortPath(url))
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
                ClipboardMonitor.markAppWrite()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(language.text("复制路径", "Copy Path"))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(language.text("在访达中显示", "Show in Finder"))
        }
    }

    private func shortPath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}

private struct ReminderRow: View {
    let reminder: Reminder
    @ObservedObject var language: LanguageStore
    let onToggle: (Bool) -> Void
    let onIntervalChange: (Int) -> Void
    let onTitleChange: (String) -> Void
    let onPreview: () -> Void
    let onDelete: () -> Void

    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle(
                "",
                isOn: Binding(
                    get: { reminder.isEnabled },
                    set: onToggle
                )
            )
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                if isEditingTitle {
                    TextField("", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .focused($titleIsFocused)
                        .onSubmit(commitTitle)
                        .onExitCommand(perform: cancelTitleEditing)
                        .onChange(of: titleIsFocused) { focused in
                            if !focused, isEditingTitle {
                                commitTitle()
                            }
                        }
                } else {
                    Text(reminder.title)
                        .font(.headline)
                        .onTapGesture(count: 2, perform: beginTitleEditing)
                        .help(language.text(
                            "双击修改提醒内容",
                            "Double-click to edit"
                        ))
                }
                Text(nextFireText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Stepper(
                value: Binding(
                    get: { reminder.intervalMinutes },
                    set: onIntervalChange
                ),
                in: 1...480
            ) {
                Text(language.text(
                    "每 \(reminder.intervalMinutes) 分钟",
                    "Every \(reminder.intervalMinutes) min"
                ))
                .frame(width: 108, alignment: .trailing)
            }

            Button(action: onPreview) {
                Label(
                    language.text("预览", "Preview"),
                    systemImage: "sparkles.rectangle.stack"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var nextFireText: String {
        guard reminder.isEnabled else {
            return language.text("已停用", "Disabled")
        }
        guard let date = reminder.nextFireDate else {
            return language.text("等待计时", "Waiting")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return language.text(
            "下次：\(formatter.string(from: date))",
            "Next: \(formatter.string(from: date))"
        )
    }

    private func beginTitleEditing() {
        draftTitle = reminder.title
        isEditingTitle = true
        DispatchQueue.main.async {
            titleIsFocused = true
        }
    }

    private func commitTitle() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onTitleChange(trimmed)
        }
        isEditingTitle = false
    }

    private func cancelTitleEditing() {
        isEditingTitle = false
    }
}
