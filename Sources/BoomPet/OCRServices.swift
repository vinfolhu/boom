import AppKit
import CryptoKit
@preconcurrency import Vision

enum OCRServiceError: LocalizedError {
    case noText
    case invalidURL
    case missingAPIKey
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noText: return "未识别到文字 / No text recognized"
        case .invalidURL: return "API 地址无效 / Invalid API URL"
        case .missingAPIKey: return "请先填写 API Key / API Key required"
        case .invalidResponse: return "无法解析服务响应 / Invalid API response"
        }
    }
}

enum VisionOCRService {
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try recognizeSynchronously(image)
        }.value
    }

    static func recognizeSynchronously(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = request.results ?? []
        let sorted = observations.sorted {
            let rowDelta = abs($0.boundingBox.midY - $1.boundingBox.midY)
            if rowDelta > 0.025 {
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !text.isEmpty else { throw OCRServiceError.noText }
        return text
    }
}

enum TranslationService {
    static func translate(
        _ text: String,
        configuration: TranslationConfiguration
    ) async throws -> String {
        let resolved = TranslationConfiguration(
            provider: configuration.provider,
            apiURL: configuration.apiURL,
            apiKey: configuration.apiKey,
            apiSecret: configuration.apiSecret,
            model: configuration.model,
            targetLanguage: configuration.targetLanguage == "auto"
                ? defaultTargetLanguage(for: text)
                : configuration.targetLanguage
        )
        switch resolved.provider {
        case .disabled:
            return ""
        case .baidu:
            return try await baidu(text, configuration: resolved)
        case .openAI:
            return try await openAI(text, configuration: resolved)
        case .deepL:
            return try await deepL(text, configuration: resolved)
        case .libreTranslate:
            return try await libreTranslate(text, configuration: resolved)
        }
    }

    private static func baidu(
        _ text: String,
        configuration: TranslationConfiguration
    ) async throws -> String {
        guard !configuration.apiKey.isEmpty, !configuration.apiSecret.isEmpty else {
            throw OCRServiceError.missingAPIKey
        }
        guard let url = URL(string: configuration.apiURL) else {
            throw OCRServiceError.invalidURL
        }
        let salt = String(UInt64.random(in: 100_000...9_999_999))
        let signSource = configuration.apiKey + text + salt + configuration.apiSecret
        let digest = Insecure.MD5.hash(data: Data(signSource.utf8))
        let sign = digest.map { String(format: "%02x", $0) }.joined()
        let form = [
            "q": text,
            "from": "auto",
            "to": configuration.targetLanguage,
            "appid": configuration.apiKey,
            "salt": salt,
            "sign": sign
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = form.map {
            "\($0.key.urlEncoded)=\($0.value.urlEncoded)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = json?["trans_result"] as? [[String: Any]]
        let lines = results?.compactMap { $0["dst"] as? String } ?? []
        guard !lines.isEmpty else { throw OCRServiceError.invalidResponse }
        return lines.joined(separator: "\n")
    }

    static func detectedSourceLanguage(for text: String) -> String {
        let cjk = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        let latin = text.filter(\.isLetter).filter(\.isASCII).count
        return cjk >= latin && cjk > 0 ? "zh" : "en"
    }

    static func defaultTargetLanguage(for text: String) -> String {
        detectedSourceLanguage(for: text) == "zh" ? "en" : "zh"
    }

    private static func openAI(
        _ text: String,
        configuration: TranslationConfiguration
    ) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw OCRServiceError.missingAPIKey }
        guard let url = URL(string: configuration.apiURL) else {
            throw OCRServiceError.invalidURL
        }
        let target = languageName(configuration.targetLanguage)
        let payload: [String: Any] = [
            "model": configuration.model,
            "messages": [[
                "role": "user",
                "content": "Translate the following text to \(target). Output only the translation:\n\n\(text)"
            ]],
            "max_tokens": 2000
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(configuration.apiKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let result = message?["content"] as? String else {
            throw OCRServiceError.invalidResponse
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deepL(
        _ text: String,
        configuration: TranslationConfiguration
    ) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw OCRServiceError.missingAPIKey }
        guard let url = URL(string: configuration.apiURL) else {
            throw OCRServiceError.invalidURL
        }
        let form = [
            "auth_key": configuration.apiKey,
            "text": text,
            "target_lang": configuration.targetLanguage.uppercased()
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = form.map {
            "\($0.key.urlEncoded)=\($0.value.urlEncoded)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let translations = json?["translations"] as? [[String: Any]]
        guard let result = translations?.first?["text"] as? String else {
            throw OCRServiceError.invalidResponse
        }
        return result
    }

    private static func libreTranslate(
        _ text: String,
        configuration: TranslationConfiguration
    ) async throws -> String {
        guard let url = URL(string: configuration.apiURL) else {
            throw OCRServiceError.invalidURL
        }
        let payload: [String: Any] = [
            "q": text,
            "source": "auto",
            "target": configuration.targetLanguage,
            "format": "text",
            "api_key": configuration.apiKey
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let result = json?["translatedText"] as? String else {
            throw OCRServiceError.invalidResponse
        }
        return result
    }

    private static func languageName(_ code: String) -> String {
        switch code.lowercased() {
        case "zh": return "Chinese"
        case "en": return "English"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "fr": return "French"
        case "de": return "German"
        case "es": return "Spanish"
        default: return code
        }
    }
}

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
