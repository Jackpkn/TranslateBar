import Foundation

enum DeepLError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No DeepL API key found. Please set your key in TranslateBar settings."
        case .invalidResponse:
            return "Invalid response structure from DeepL API."
        case .httpError(let code):
            return "DeepL HTTP Error code: \(code)."
        case .networkError(let msg):
            return "Network Error: \(msg)"
        }
    }
}

struct TranslationResult {
    let translatedText: String
    let detectedSourceLang: String
    let targetLangUsed: String
}

final class DeepLService {
    static let shared = DeepLService()

    private init() {}

    /// Gets the current active API key (from Keychain first, then environment variable fallback)
    var apiKey: String? {
        if let storedKey = KeychainHelper.getAPIKey(), !storedKey.isEmpty {
            return storedKey
        }
        if let envKey = ProcessInfo.processInfo.environment["DEEPL_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        return nil
    }

    /// Formality preference: "default", "more", "less"
    var formality: String {
        get { UserDefaults.standard.string(forKey: "deeplFormality") ?? "default" }
        set { UserDefaults.standard.set(newValue, forKey: "deeplFormality") }
    }

    private func endpoint(for key: String, path: String = "/v2/translate") -> String {
        let base = key.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        return base + path
    }

    func translate(text: String, targetLang: String, completion: @escaping (Result<String, Error>) -> Void) {
        translateWithDetails(text: text, targetLang: targetLang) { result in
            switch result {
            case .success(let res):
                completion(.success(res.translatedText))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func translateWithDetails(text: String, targetLang: String, completion: @escaping (Result<TranslationResult, Error>) -> Void) {
        guard let key = apiKey, !key.isEmpty, key != "YOUR_DEEPL_API_KEY_HERE" else {
            completion(.failure(DeepLError.missingAPIKey))
            return
        }

        guard let url = URL(string: endpoint(for: key, path: "/v2/translate")) else {
            completion(.failure(DeepLError.invalidResponse))
            return
        }

        // Protect glossary terms
        let (protectedText, placeholders) = GlossaryManager.shared.protectTerms(in: text)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "text": [protectedText],
            "target_lang": targetLang
        ]

        if formality != "default" {
            body["formality"] = formality
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(DeepLError.networkError(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(DeepLError.httpError(code)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
                if let firstTranslation = decoded.translations.first {
                    let finalTranslated = GlossaryManager.shared.restoreTerms(in: firstTranslation.text, placeholders: placeholders)
                    let detectedLang = firstTranslation.detectedSourceLanguage ?? "EN"
                    
                    // Log into translation history
                    TranslationHistory.shared.addRecord(original: text, translated: finalTranslated, targetLang: targetLang)
                    // Fetch updated usage stats asynchronously
                    self.fetchUsage { _ in }

                    let result = TranslationResult(
                        translatedText: finalTranslated,
                        detectedSourceLang: detectedLang,
                        targetLangUsed: targetLang
                    )
                    completion(.success(result))
                } else {
                    completion(.failure(DeepLError.invalidResponse))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Smart Vice-Versa Translation:
    /// Auto-detects text language. If text is foreign (e.g. Russian), translates to English.
    /// If text is English, translates to configured target language (e.g. Russian).
    func smartTranslate(text: String, configuredTargetLang: String, completion: @escaping (Result<TranslationResult, Error>) -> Void) {
        // Step 1: Perform initial translation attempt to configuredTargetLang
        translateWithDetails(text: text, targetLang: configuredTargetLang) { [weak self] firstResult in
            guard let self = self else { return }
            switch firstResult {
            case .success(let result):
                let detectedLang = result.detectedSourceLang.uppercased()
                let targetLangPrefix = configuredTargetLang.components(separatedBy: "-").first?.uppercased() ?? configuredTargetLang.uppercased()

                // If detected source text is NOT English (e.g. RU, ES, FR, DE, HI) AND configured target is not English:
                // Vice-versa rule: foreign text -> translate into English!
                if detectedLang != "EN" && detectedLang == targetLangPrefix && targetLangPrefix != "EN" {
                    // Re-translate foreign text to English!
                    self.translateWithDetails(text: text, targetLang: "EN-US", completion: completion)
                } else if detectedLang != "EN" && targetLangPrefix != "EN" {
                    // Foreign text detected, flip to English
                    self.translateWithDetails(text: text, targetLang: "EN-US", completion: completion)
                } else {
                    // Text is English (or target is already English), return initial translation
                    completion(.success(result))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Fetches character usage statistics from DeepL /v2/usage
    func fetchUsage(completion: @escaping (Result<UsageTracker, Error>) -> Void) {
        guard let key = apiKey, !key.isEmpty, key != "YOUR_DEEPL_API_KEY_HERE" else {
            completion(.failure(DeepLError.missingAPIKey))
            return
        }

        guard let url = URL(string: endpoint(for: key, path: "/v2/usage")) else {
            completion(.failure(DeepLError.invalidResponse))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(DeepLError.networkError(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, let data = data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(DeepLError.httpError(code)))
                return
            }
            do {
                let usage = try JSONDecoder().decode(DeepLUsageResponse.self, from: data)
                UsageTracker.shared.updateUsage(count: usage.characterCount, limit: usage.characterLimit)
                completion(.success(UsageTracker.shared))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    /// Performs back-translation (translates target text back to English to verify nuances)
    func backTranslate(translatedText: String, completion: @escaping (Result<String, Error>) -> Void) {
        translate(text: translatedText, targetLang: "EN-US", completion: completion)
    }
}

private struct DeepLResponse: Decodable {
    struct Translation: Decodable {
        let text: String
        let detectedSourceLanguage: String?

        enum CodingKeys: String, CodingKey {
            case text
            case detectedSourceLanguage = "detected_source_language"
        }
    }
    let translations: [Translation]
}
