import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ReminderStore
    @ObservedObject var language: LanguageStore
    let onTestBoom: (String) -> Void
    let onChoosePetImage: () -> Void
    let onRestoreDefaultPet: () -> Void

    @State private var title = ""
    @State private var intervalMinutes = 30
    @AppStorage("BoomPet.petAutoRoam") private var petAutoRoam = true
    @AppStorage("BoomPet.petDialogueEnabled") private var petDialogueEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            addReminderCard

            Divider()

            if store.reminders.isEmpty {
                emptyState
            } else {
                reminderList
            }

            Divider()
            petSettings
            Divider()
            footer
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("BoomPet")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text(language.text(
                    "任务列表初始为空。只有你亲自添加并启用的提醒才会触发 BOOM。",
                    "The task list starts empty. Only reminders you add and enable will trigger."
                ))
                .foregroundStyle(.secondary)
            }
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
    }

    private var addReminderCard: some View {
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
            .padding(.vertical, 8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(language.text("还没有定时任务", "No reminders yet"))
                .font(.headline)
            Text(language.text(
                "在上方设置提醒内容和间隔，然后点击“添加”。",
                "Set the reminder text and interval above, then click Add."
            ))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reminderList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.reminders) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        language: language,
                        onToggle: { store.setEnabled(id: reminder.id, enabled: $0) },
                        onIntervalChange: { store.setInterval(id: reminder.id, minutes: $0) },
                        onTitleChange: { store.setTitle(id: reminder.id, title: $0) },
                        onPreview: { onTestBoom(reminder.title) },
                        onDelete: { store.delete(id: reminder.id) }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(
                language.text(
                    "可拖拽宠物；拖到屏幕边缘会躲起来",
                    "Drag the pet; drop at a screen edge to make it peek"
                ),
                systemImage: "cursorarrow.motionlines"
            )
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

    private var petSettings: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                Toggle(
                    language.text(
                        "宠物自主活动",
                        "Let the pet wander"
                    ),
                    isOn: $petAutoRoam
                )
                Toggle(
                    language.text(
                        "淘气气泡互动",
                        "Playful speech bubbles"
                    ),
                    isOn: $petDialogueEnabled
                )
                Spacer()
            }
            HStack {
                Spacer()
                Button(
                    language.text("恢复默认宠物", "Restore Default"),
                    action: onRestoreDefaultPet
                )
                Button(
                    language.text("选择图片并自动抠图…", "Choose & Auto-Cutout…"),
                    action: onChoosePetImage
                )
            }
        }
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
            .help(language.text(
                "立即预览这条任务的 BOOM 效果",
                "Preview this reminder's BOOM effect"
            ))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(language.text("删除任务", "Delete reminder"))
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
