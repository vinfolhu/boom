import AppKit
import SwiftUI

struct OCRConfigurationView: View {
    @ObservedObject var settings: OCRSettingsStore
    @ObservedObject var history: OCRHistoryStore
    @ObservedObject var language: LanguageStore

    var body: some View {
        Form {
            Section(language.text("本地 OCR", "Local OCR")) {
                LabeledContent(language.text("识别引擎", "OCR Engine")) {
                    Text("macOS Vision")
                }
                Text(language.text(
                    "识别在本机完成，无需 API Key。首次框选需要屏幕录制权限。",
                    "Recognition runs locally. Screen Recording permission is required."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(language.text("翻译", "Translation")) {
                Picker(
                    language.text("服务商", "Provider"),
                    selection: $settings.provider
                ) {
                    Text(language.text("关闭", "Disabled"))
                        .tag(TranslationProvider.disabled)
                    Text("百度翻译").tag(TranslationProvider.baidu)
                    Text("OpenAI Compatible").tag(TranslationProvider.openAI)
                    Text("DeepL").tag(TranslationProvider.deepL)
                    Text("LibreTranslate").tag(TranslationProvider.libreTranslate)
                }
                .onChange(of: settings.provider) {
                    settings.applyDefaults(for: $0)
                }

                if settings.provider != .disabled {
                    TextField("API URL", text: $settings.apiURL)
                    SecureField(
                        settings.provider == .baidu ? "APP ID" : "API Key",
                        text: $settings.apiKey
                    )
                    if settings.provider == .baidu {
                        SecureField(
                            language.text("应用密钥", "App Secret"),
                            text: $settings.apiSecret
                        )
                    }
                    if settings.provider == .openAI {
                        TextField(language.text("模型", "Model"), text: $settings.model)
                    }
                    Picker(
                        language.text("目标语言", "Target Language"),
                        selection: $settings.targetLanguage
                    ) {
                        Text(language.text("自动互译", "Auto Detect")).tag("auto")
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                        Text("日本語").tag("ja")
                        Text("한국어").tag("ko")
                        Text("Français").tag("fr")
                        Text("Deutsch").tag("de")
                    }
                    Toggle(
                        language.text(
                            "OCR 后自动翻译",
                            "Translate automatically after OCR"
                        ),
                        isOn: $settings.autoTranslate
                    )
                }
            }

            Section(language.text("剪贴板历史", "Clipboard History")) {
                Toggle(
                    language.text(
                        "记录复制的文本",
                        "Record copied text"
                    ),
                    isOn: $settings.clipboardHistoryEnabled
                )
                Text(language.text(
                    "默认关闭。启用后文本仅保存在本机历史中。",
                    "Disabled by default. Text remains in local history."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Stepper(
                    value: Binding(
                        get: { settings.historyMax },
                        set: {
                            settings.historyMax = $0
                            history.setMaximumCount($0)
                        }
                    ),
                    in: 20...2_000,
                    step: 20
                ) {
                    LabeledContent(
                        language.text("历史记录上限", "History Limit")
                    ) {
                        Text("\(settings.historyMax)")
                            .monospacedDigit()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            // Secrets are loaded only when the user opens OCR/translation
            // settings, never just because BoomPet launched.
            settings.loadSecretsIfNeeded()
        }
    }
}

struct OCRResultView: View {
    let itemID: UUID
    @State var originalText: String
    @State var translatedText: String
    @ObservedObject var settings: OCRSettingsStore
    @ObservedObject var history: OCRHistoryStore
    @ObservedObject var language: LanguageStore

    @State private var isTranslating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(language.text("OCR 结果", "OCR Result"))
                    .font(.title2.bold())
                Spacer()
                Button {
                    copy(originalText)
                } label: {
                    Label(language.text("复制原文", "Copy Text"), systemImage: "doc.on.doc")
                }
                Button(action: translate) {
                    if isTranslating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(language.text("翻译", "Translate"), systemImage: "character.book.closed")
                    }
                }
                .disabled(isTranslating || settings.provider == .disabled)
            }

            TextEditor(text: $originalText)
                .font(.body)
                .frame(minHeight: 150)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            if !translatedText.isEmpty {
                HStack {
                    Text(language.text("译文", "Translation")).font(.headline)
                    Spacer()
                    Button {
                        copy(translatedText)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                TextEditor(text: $translatedText)
                    .font(.body)
                    .foregroundColor(.blue)
                    .frame(minHeight: 130)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 430)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ClipboardMonitor.markAppWrite()
    }

    private func translate() {
        isTranslating = true
        errorMessage = nil
        let configuration = settings.configuration
        Task {
            do {
                let result = try await TranslationService.translate(
                    originalText,
                    configuration: configuration
                )
                translatedText = result
                history.updateTranslation(id: itemID, translation: result)
            } catch {
                errorMessage = error.localizedDescription
            }
            isTranslating = false
        }
    }
}
