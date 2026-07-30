import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var keyTap: KeyEventTap?
    private var enabled = true
    private var usageMenuItem: NSMenuItem?

    // Target languages supported by DeepL
    let languages: [(code: String, name: String)] = [
        ("EN-US", "English"),
        ("ES", "Spanish"),
        ("FR", "French"),
        ("DE", "German"),
        ("HI", "Hindi"),
        ("JA", "Japanese"),
        ("ZH", "Chinese"),
        ("PT-BR", "Portuguese (BR)"),
        ("RU", "Russian"),
        ("IT", "Italian"),
        ("VI", "Vietnamese"),
    ]

    private var targetLanguage: String {
        get { UserDefaults.standard.string(forKey: "targetLanguage") ?? "ES" }
        set { UserDefaults.standard.set(newValue, forKey: "targetLanguage") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        keyTap = KeyEventTap(
            targetLanguageProvider: { [weak self] in self?.targetLanguage ?? "ES" },
            isEnabledProvider: { [weak self] in self?.enabled ?? true }
        )
        keyTap?.start()

        setupStatusItem()
        requestAccessibilityPermission()

        // Setup Quick Palette target provider
        QuickPaletteWindowController.shared.targetLanguageProvider = { [weak self] in
            self?.targetLanguage ?? "ES"
        }

        // Setup Global Hotkeys: Option + T (Selection) & Option + Shift + T (Chat Scan)
        GlobalHotkeyManager.shared.startMonitoring(
            onSelectionHotkey: { [weak self] in
                self?.handleSelectionHotkey()
            },
            onChatScanHotkey: { [weak self] in
                self?.handleChatScanHotkey()
            }
        )

        // Start Clipboard Monitoring
        ClipboardMonitor.shared.startMonitoring { [weak self] in
            self?.targetLanguage ?? "ES"
        }

        // Fetch DeepL Usage Statistics initially
        refreshUsageStats()
    }

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "🌐"

        let menu = NSMenu()

        // Enable / Disable Toggle
        let toggleItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = enabled ? .on : .off
        menu.addItem(toggleItem)

        // Active App Blacklist Toggle
        if let (appName, _, isBlacklisted) = AppFilter.shared.currentActiveAppInfo() {
            let activeAppTitle = isBlacklisted ? "Bypassing: \(appName)" : "Active for: \(appName)"
            let blacklistMenuItem = NSMenuItem(title: activeAppTitle, action: #selector(toggleCurrentAppBlacklist(_:)), keyEquivalent: "")
            blacklistMenuItem.target = self
            blacklistMenuItem.state = isBlacklisted ? .off : .on
            menu.addItem(blacklistMenuItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Trigger Mode Submenu (Manual vs Auto)
        let modeSubmenu = NSMenu()
        let modes: [(code: TriggerMode, label: String)] = [
            (.manual, "Manual (Press Option+Enter to Translate)"),
            (.auto, "Auto (Translate on Pause or Enter)")
        ]
        let currentMode = keyTap?.triggerMode ?? .manual
        for mode in modes {
            let item = NSMenuItem(title: mode.label, action: #selector(selectTriggerMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.code.rawValue
            item.state = (mode.code == currentMode) ? .on : .off
            modeSubmenu.addItem(item)
        }
        let modeMenuItem = NSMenuItem(title: "Trigger Mode", action: nil, keyEquivalent: "")
        modeMenuItem.submenu = modeSubmenu
        menu.addItem(modeMenuItem)

        // Quick Translate Palette
        let paletteItem = NSMenuItem(title: "Quick Translate Palette...", action: #selector(openQuickPalette(_:)), keyEquivalent: "t")
        paletteItem.keyEquivalentModifierMask = [.command, .shift]
        paletteItem.target = self
        menu.addItem(paletteItem)

        // Selection Hotkey indicator
        let selHotkeyItem = NSMenuItem(title: "Hotkey: Option+T (Translate Selection)", action: nil, keyEquivalent: "")
        selHotkeyItem.isEnabled = false
        menu.addItem(selHotkeyItem)

        // Chat Screen Subtitle Hotkey indicator
        let chatHotkeyItem = NSMenuItem(title: "Hotkey: Option+Shift+T (Auto Chat Subtitles)", action: nil, keyEquivalent: "")
        chatHotkeyItem.isEnabled = false
        menu.addItem(chatHotkeyItem)

        // Voice Audio Speech Toggle (Disabled by default)
        let voiceItem = NSMenuItem(title: "Voice Audio Pronunciation", action: #selector(toggleVoiceAudio(_:)), keyEquivalent: "")
        voiceItem.target = self
        voiceItem.state = AudioSpeechHelper.shared.isVoiceEnabled ? .on : .off
        menu.addItem(voiceItem)

        // Clipboard Auto-Translate Toggle
        let clipboardItem = NSMenuItem(title: "Clipboard Auto-Translate", action: #selector(toggleClipboardAutoTranslate(_:)), keyEquivalent: "")
        clipboardItem.target = self
        clipboardItem.state = ClipboardMonitor.shared.isEnabled ? .on : .off
        menu.addItem(clipboardItem)

        menu.addItem(NSMenuItem.separator())

        // Target Language Submenu
        let langSubmenu = NSMenu()
        for lang in languages {
            let item = NSMenuItem(title: lang.name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.code
            item.state = (lang.code == targetLanguage) ? .on : .off
            langSubmenu.addItem(item)
        }
        let langMenuItem = NSMenuItem(title: "Target Language", action: nil, keyEquivalent: "")
        langMenuItem.submenu = langSubmenu
        menu.addItem(langMenuItem)

        // Formality Submenu
        let formalityMenu = NSMenu()
        let formalities = [("default", "Default"), ("more", "Formal"), ("less", "Informal")]
        let currentFormality = DeepLService.shared.formality
        for (code, label) in formalities {
            let item = NSMenuItem(title: label, action: #selector(selectFormality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (code == currentFormality) ? .on : .off
            formalityMenu.addItem(item)
        }
        let formalityMenuItem = NSMenuItem(title: "Tone / Formality", action: nil, keyEquivalent: "")
        formalityMenuItem.submenu = formalityMenu
        menu.addItem(formalityMenuItem)

        menu.addItem(NSMenuItem.separator())

        // DeepL Usage Stats item
        let usageItem = NSMenuItem(title: "DeepL Usage: Loading...", action: #selector(refreshUsageClicked(_:)), keyEquivalent: "")
        usageItem.target = self
        self.usageMenuItem = usageItem
        menu.addItem(usageItem)

        // Translation History
        let historyItem = NSMenuItem(title: "Translation History...", action: #selector(showHistory(_:)), keyEquivalent: "h")
        historyItem.target = self
        menu.addItem(historyItem)

        // Glossary / Custom Terms
        let glossaryItem = NSMenuItem(title: "Custom Glossary Terms...", action: #selector(manageGlossary(_:)), keyEquivalent: "g")
        glossaryItem.target = self
        menu.addItem(glossaryItem)

        menu.addItem(NSMenuItem.separator())

        // Settings / Keychain API Key
        let apiKeyItem = NSMenuItem(title: "Set DeepL API Key...", action: #selector(promptForAPIKey(_:)), keyEquivalent: "")
        apiKeyItem.target = self
        menu.addItem(apiKeyItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit TranslateBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func refreshUsageStats() {
        DeepLService.shared.fetchUsage { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let tracker) = result {
                    self?.usageMenuItem?.title = "DeepL Usage: \(tracker.usageString)"
                } else {
                    self?.usageMenuItem?.title = "DeepL Usage: Click to Refresh"
                }
            }
        }
    }

    @objc private func toggleVoiceAudio(_ sender: NSMenuItem) {
        AudioSpeechHelper.shared.isVoiceEnabled.toggle()
        sender.state = AudioSpeechHelper.shared.isVoiceEnabled ? .on : .off
    }

    @objc private func selectTriggerMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = TriggerMode(rawValue: raw) else { return }
        keyTap?.triggerMode = mode
        for item in sender.menu?.items ?? [] {
            if let itemCode = item.representedObject as? String {
                item.state = (itemCode == raw) ? .on : .off
            }
        }
    }

    @objc private func refreshUsageClicked(_ sender: NSMenuItem) {
        refreshUsageStats()
    }

    @objc private func openQuickPalette(_ sender: NSMenuItem) {
        QuickPaletteWindowController.shared.showPalette()
    }

    @objc private func toggleClipboardAutoTranslate(_ sender: NSMenuItem) {
        ClipboardMonitor.shared.isEnabled.toggle()
        sender.state = ClipboardMonitor.shared.isEnabled ? .on : .off
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        enabled.toggle()
        sender.state = enabled ? .on : .off
    }

    @objc private func toggleCurrentAppBlacklist(_ sender: NSMenuItem) {
        if let (appName, isBlacklisted) = AppFilter.shared.toggleCurrentAppBlacklist() {
            sender.title = isBlacklisted ? "Bypassing: \(appName)" : "Active for: \(appName)"
            sender.state = isBlacklisted ? .off : .on
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        targetLanguage = code
        for item in sender.menu?.items ?? [] {
            if let itemCode = item.representedObject as? String {
                item.state = (itemCode == code) ? .on : .off
            }
        }
    }

    @objc private func selectFormality(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        DeepLService.shared.formality = code
        for item in sender.menu?.items ?? [] {
            if let itemCode = item.representedObject as? String {
                item.state = (itemCode == code) ? .on : .off
            }
        }
    }

    @objc private func showHistory(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Translation History (Last 50)"
        let records = TranslationHistory.shared.records
        if records.isEmpty {
            alert.informativeText = "No translation records yet."
        } else {
            let historyLines = records.prefix(15).map { record in
                "[\(record.targetLanguage)] \(record.originalText) ➔ \(record.translatedText)"
            }.joined(separator: "\n\n")
            alert.informativeText = historyLines
        }
        alert.addButton(withTitle: "Close")
        if !records.isEmpty {
            alert.addButton(withTitle: "Clear History")
        }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            TranslationHistory.shared.clearHistory()
        }
    }

    @objc private func manageGlossary(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Custom Glossary & Protected Terms"
        let currentTerms = Array(GlossaryManager.shared.terms).joined(separator: ", ")
        alert.informativeText = "Current protected terms (words that will NOT be translated):\n\(currentTerms)\n\nEnter a new term to protect:"
        alert.addButton(withTitle: "Add Term")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newTerm = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newTerm.isEmpty {
                GlossaryManager.shared.addTerm(newTerm)
            }
        }
    }

    @objc private func promptForAPIKey(_ sender: NSMenuItem) {
        let alert = NSAlert()
        alert.messageText = "Set DeepL API Key"
        alert.informativeText = "Enter your DeepL API key (Free tier keys end in :fx). It will be saved securely in macOS Keychain."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        if let currentKey = DeepLService.shared.apiKey {
            input.stringValue = currentKey
        }
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newKey = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newKey.isEmpty {
                _ = KeychainHelper.saveAPIKey(newKey)
                refreshUsageStats()
                HUDWindowController.shared.show(message: "API Key saved in Keychain!", subMessage: "Ready to translate", icon: "🔑", autoDismissDelay: 2.0)
            }
        }
    }

    /// Triggered by Option + T: Translates highlighted/selected text
    private func handleSelectionHotkey() {
        HUDWindowController.shared.show(message: "Translating Selection...", icon: "⏳", autoDismissDelay: nil)

        VisionTextScanner.shared.scanTextAtCursor { [weak self] scannedText, textFrame in
            guard let self = self else { return }

            AccessibilityHelper.shared.getSelectedText { selectedText in
                let targetText = selectedText ?? scannedText

                guard let textToTranslate = targetText, !textToTranslate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    HUDWindowController.shared.show(message: "No text selected", subMessage: "Highlight text and press Option+T", icon: "⚠️", autoDismissDelay: 2.5)
                    return
                }

                let targetLang = self.targetLanguage

                DeepLService.shared.smartTranslate(text: textToTranslate, configuredTargetLang: targetLang) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let translation):
                            let langInfo = "Detected: \(translation.detectedSourceLang) ➔ \(translation.targetLangUsed)"
                            HUDWindowController.shared.show(
                                message: translation.translatedText,
                                subMessage: langInfo,
                                icon: "🌐",
                                speakText: translation.translatedText,
                                targetLang: translation.targetLangUsed,
                                textFrame: textFrame,
                                autoDismissDelay: 10.0
                            )
                        case .failure(let error):
                            HUDWindowController.shared.show(message: "Translation Error", subMessage: error.localizedDescription, icon: "⚠️", autoDismissDelay: 3.0)
                        }
                    }
                }
            }
        }
    }

    /// Triggered by Option + Shift + T: Auto scans full chat screen and renders subtitles below all messages
    private func handleChatScanHotkey() {
        ChatSubtitleOverlayManager.shared.scanAndOverlayChatSubtitles { [weak self] in
            self?.targetLanguage ?? "ES"
        }
    }
}
