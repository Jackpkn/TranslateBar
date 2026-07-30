import AVFoundation

final class AudioSpeechHelper: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = AudioSpeechHelper()

    private let synthesizer = AVSpeechSynthesizer()

    /// Voice Audio preference (Default: Disabled / Muted)
    var isVoiceEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "isVoiceEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "isVoiceEnabled") }
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Maps DeepL target language codes to BCP-47 language tags for AVSpeechSynthesis
    private func bcp47LanguageTag(for deepLLang: String) -> String {
        switch deepLLang.uppercased() {
        case "ES": return "es-ES"
        case "FR": return "fr-FR"
        case "DE": return "de-DE"
        case "HI": return "hi-IN"
        case "JA": return "ja-JP"
        case "ZH": return "zh-CN"
        case "PT-BR", "PT": return "pt-BR"
        case "RU": return "ru-RU"
        case "IT": return "it-IT"
        case "VI": return "vi-VN"
        case "EN-US", "EN-GB", "EN": return "en-US"
        default: return "en-US"
        }
    }

    /// Speaks the given text in the specified target language (Only if isVoiceEnabled == true)
    func speak(text: String, languageCode: String) {
        guard isVoiceEnabled else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.synthesizer.isSpeaking {
                self.synthesizer.stopSpeaking(at: .immediate)
            }

            let utterance = AVSpeechUtterance(string: trimmed)
            let langTag = self.bcp47LanguageTag(for: languageCode)

            if let voice = AVSpeechSynthesisVoice(language: langTag) {
                utterance.voice = voice
            } else if let fallbackVoice = AVSpeechSynthesisVoice(language: "en-US") {
                utterance.voice = fallbackVoice
            }

            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.volume = 1.0

            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            if self?.synthesizer.isSpeaking == true {
                self?.synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }
}
