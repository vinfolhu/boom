import AppKit
import SwiftUI

struct OCRHistoryPopupView: View {
    @ObservedObject var history: OCRHistoryStore
    @ObservedObject var language: LanguageStore
    let onClose: () -> Void
    let onSettings: () -> Void
    let onClear: () -> Void
    let onCheckUpdate: () -> Void
    let onQuit: () -> Void
    let onOCR: () -> Void
    let onSticky: () -> Void
    let onCopyAndClose: (String) -> Void

    @State private var query = ""
    @State private var hoveredID: UUID?
    @State private var editingRemarkID: UUID?
    @State private var remarkDraft = ""

    private var filteredItems: [OCRHistoryItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return history.items }
        return history.items.filter {
            $0.originalText.localizedCaseInsensitiveContains(needle)
                || ($0.translatedText?.localizedCaseInsensitiveContains(needle) ?? false)
                || ($0.remark?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                toolbarButton(language.text("关闭", "Close"), action: onClose)
                toolbarButton(language.text("设置", "Settings"), action: onSettings)
                toolbarButton(language.text("清空", "Clear"), action: onClear)
                toolbarButton(language.text("检查更新", "Update"), action: onCheckUpdate)
                toolbarButton(language.text("退出", "Quit"), action: onQuit)
            }
            .frame(maxWidth: .infinity)
            .padding(8)

            Divider()

            HStack(spacing: 18) {
                Text("⌘⇧V \(language.text("历史", "History"))")
                Button("⌥S OCR", action: onOCR)
                Button("⌥T \(language.text("贴图", "Sticky"))", action: onSticky)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))

            Divider()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    language.text("搜索正文、翻译或备注", "Search text, translation, or notes"),
                    text: $query
                )
                .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if let editingRemarkID {
                remarkEditor(id: editingRemarkID)
            }

            Divider()

            if filteredItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(query.isEmpty
                         ? language.text(
                            "暂无记录，复制文本或使用 ⌥S OCR",
                            "No history. Copy text or press ⌥S."
                         )
                         : language.text("没有匹配的历史记录", "No matching history"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            historyRow(item)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(width: 300, height: 440)
    }

    private func toolbarButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private func historyRow(_ item: OCRHistoryItem) -> some View {
        HStack(spacing: 8) {
            Button {
                onCopyAndClose(copyText(for: item))
            } label: {
                HStack(spacing: 7) {
                    if item.isPinned {
                        Text("📌")
                    }
                    historyText(item)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hoveredID == item.id || editingRemarkID == item.id {
                HStack(spacing: 4) {
                    actionButton("pencil", help: language.text("备注", "Note")) {
                        editingRemarkID = item.id
                        remarkDraft = item.remark ?? ""
                    }
                    actionButton(
                        item.isPinned ? "pin.fill" : "pin",
                        help: language.text(
                            item.isPinned ? "取消置顶" : "置顶",
                            item.isPinned ? "Unpin" : "Pin"
                        )
                    ) {
                        history.togglePin(id: item.id)
                    }
                    actionButton("xmark", help: language.text("删除", "Delete")) {
                        history.delete(id: item.id)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(item.isPinned ? Color.orange.opacity(0.07) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                if hovering {
                    hoveredID = item.id
                } else if hoveredID == item.id {
                    hoveredID = nil
                }
            }
        }
    }

    private func historyText(_ item: OCRHistoryItem) -> Text {
        if let remark = item.remark, !remark.isEmpty {
            return Text(singleLine(remark))
                .foregroundColor(.blue)
                .fontWeight(.semibold)
                + Text(" · ").foregroundColor(.secondary)
                + Text(singleLine(item.originalText)).foregroundColor(.primary)
        }
        return Text(singleLine(item.originalText)).foregroundColor(.primary)
    }

    private func actionButton(
        _ systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 17, height: 17)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(help)
    }

    private func remarkEditor(id: UUID) -> some View {
        HStack(spacing: 7) {
            Text(language.text("备注", "Note"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                language.text(
                    "输入备注，留空保存即清除",
                    "Enter a note; save empty to clear"
                ),
                text: $remarkDraft
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveRemark(id: id) }
            Button(language.text("保存", "Save")) {
                saveRemark(id: id)
            }
            .controlSize(.small)
            Button(language.text("取消", "Cancel")) {
                editingRemarkID = nil
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
    }

    private func saveRemark(id: UUID) {
        history.setRemark(id: id, remark: remarkDraft)
        editingRemarkID = nil
    }

    private func copyText(for item: OCRHistoryItem) -> String {
        if let translated = item.translatedText, !translated.isEmpty {
            return "\(item.originalText)\n\n—— \(language.text("翻译", "Translation")) ——\n\(translated)"
        }
        return item.originalText
    }

    private func singleLine(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class OCRHistoryPopupPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           !modifiers.contains(.option),
           !modifiers.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "a",
           firstResponder?.tryToPerform(#selector(NSText.selectAll(_:)), with: nil) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
