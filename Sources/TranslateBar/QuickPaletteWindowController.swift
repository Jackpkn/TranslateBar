import Cocoa

final class QuickPaletteWindowController: NSWindowController, NSTextFieldDelegate {
    static let shared = QuickPaletteWindowController()

    private var inputField: NSTextField!
    private var outputLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var containerView: NSVisualEffectView!

    var targetLanguageProvider: (() -> String)?

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .titled],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.center()

        self.init(window: panel)
        setupViews()
    }

    private func setupViews() {
        guard let window = window else { return }

        containerView = NSVisualEffectView(frame: window.contentRect(forFrameRect: window.frame))
        containerView.material = .popover
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true

        let iconLabel = NSTextField(labelWithString: "🔍")
        iconLabel.font = NSFont.systemFont(ofSize: 20)
        iconLabel.frame = NSRect(x: 16, y: 115, width: 28, height: 28)

        inputField = NSTextField(frame: NSRect(x: 50, y: 112, width: 414, height: 32))
        inputField.font = NSFont.systemFont(ofSize: 16, weight: .regular)
        inputField.placeholderString = "Type text to translate and press Enter..."
        inputField.focusRingType = .none
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.delegate = self

        let divider = NSBox(frame: NSRect(x: 16, y: 100, width: 448, height: 1))
        divider.boxType = .separator

        outputLabel = NSTextField(labelWithString: "Translation will appear here...")
        outputLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        outputLabel.textColor = .labelColor
        outputLabel.lineBreakMode = .byWordWrapping
        outputLabel.frame = NSRect(x: 16, y: 35, width: 448, height: 55)

        statusLabel = NSTextField(labelWithString: "Press Enter to copy translation | Esc to close")
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 16, y: 10, width: 448, height: 18)

        containerView.addSubview(iconLabel)
        containerView.addSubview(inputField)
        containerView.addSubview(divider)
        containerView.addSubview(outputLabel)
        containerView.addSubview(statusLabel)
        window.contentView = containerView
    }

    func showPalette() {
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(inputField)
    }

    func controlTextDidChange(_ obj: Notification) {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            outputLabel.stringValue = "Translation will appear here..."
            return
        }

        let targetLang = targetLanguageProvider?() ?? "ES"
        DeepLService.shared.translate(text: text, targetLang: targetLang) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let translated):
                    self?.outputLabel.stringValue = translated
                    self?.statusLabel.stringValue = "Press Enter to copy '\(translated)' | Esc to close"
                case .failure(let error):
                    self?.outputLabel.stringValue = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let translated = outputLabel.stringValue
            if !translated.isEmpty, translated != "Translation will appear here..." {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(translated, forType: .string)
                HUDWindowController.shared.show(message: "Copied to Clipboard!", subMessage: translated, icon: "📋", autoDismissDelay: 2.0)
                window?.orderOut(nil)
            }
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            window?.orderOut(nil)
            return true
        }
        return false
    }
}
