import Cocoa

final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "clipboardAutoTranslateEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "clipboardAutoTranslateEnabled") }
    }

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func startMonitoring(targetLanguageProvider: @escaping () -> String) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isEnabled else { return }
            let pasteboard = NSPasteboard.general
            if pasteboard.changeCount != self.lastChangeCount {
                self.lastChangeCount = pasteboard.changeCount
                if let copiedText = pasteboard.string(forType: .string), !copiedText.isEmpty, copiedText.count < 1500 {
                    let targetLang = targetLanguageProvider()
                    DeepLService.shared.translate(text: copiedText, targetLang: targetLang) { result in
                        DispatchQueue.main.async {
                            if case .success(let translated) = result {
                                HUDWindowController.shared.show(
                                    message: "Clipboard Translated",
                                    subMessage: translated,
                                    icon: "📋",
                                    speakText: nil,
                                    targetLang: targetLang,
                                    autoDismissDelay: nil // Stays until user closes it with the ✕ button
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
