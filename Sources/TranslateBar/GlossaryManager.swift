import Foundation

final class GlossaryManager {
    static let shared = GlossaryManager()
    private let userDefaultsKey = "customGlossaryTerms"

    private(set) var terms: Set<String> = []

    private init() {
        loadTerms()
    }

    func addTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        terms.insert(trimmed)
        saveTerms()
    }

    func removeTerm(_ term: String) {
        terms.remove(term)
        saveTerms()
    }

    /// Replaces occurrences of glossary terms with temporary placeholders so they remain untouched during translation
    func protectTerms(in text: String) -> (protectedText: String, placeholders: [String: String]) {
        var result = text
        var placeholders: [String: String] = [:]
        var index = 0

        for term in terms where !term.isEmpty {
            if result.localizedCaseInsensitiveContains(term) {
                let placeholder = "__GLOSSARY_TERM_\(index)__"
                placeholders[placeholder] = term
                result = result.replacingOccurrences(of: term, with: placeholder, options: .caseInsensitive)
                index += 1
            }
        }

        return (result, placeholders)
    }

    /// Restores original protected terms from placeholders back into the translated output
    func restoreTerms(in text: String, placeholders: [String: String]) -> String {
        var result = text
        for (placeholder, originalTerm) in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: originalTerm)
        }
        return result
    }

    private func loadTerms() {
        let array = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? ["TranslateBar", "DeepL"]
        terms = Set(array)
    }

    private func saveTerms() {
        UserDefaults.standard.set(Array(terms), forKey: userDefaultsKey)
    }
}
