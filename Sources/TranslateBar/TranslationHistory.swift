import Foundation

struct TranslationRecord: Codable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let targetLanguage: String
    let timestamp: Date

    init(originalText: String, translatedText: String, targetLanguage: String) {
        self.id = UUID()
        self.originalText = originalText
        self.translatedText = translatedText
        self.targetLanguage = targetLanguage
        self.timestamp = Date()
    }
}

final class TranslationHistory {
    static let shared = TranslationHistory()
    private let userDefaultsKey = "translationHistoryRecords"
    private let maxRecords = 50

    private(set) var records: [TranslationRecord] = []

    private init() {
        loadRecords()
    }

    func addRecord(original: String, translated: String, targetLang: String) {
        let record = TranslationRecord(originalText: original, translatedText: translated, targetLanguage: targetLang)
        records.insert(record, at: 0)

        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }

        saveRecords()
    }

    func clearHistory() {
        records.removeAll()
        saveRecords()
    }

    private func loadRecords() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data) {
            records = decoded
        }
    }

    private func saveRecords() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }
}
