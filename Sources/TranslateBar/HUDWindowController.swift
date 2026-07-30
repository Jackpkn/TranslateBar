import Cocoa

final class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()

    private var label: NSTextField!
    private var iconLabel: NSTextField!
    private var subLabel: NSTextField!
    private var containerView: NSVisualEffectView!
    private var dismissTimer: Timer?

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu // Always on top of WhatsApp/Telegram/Browsers
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = true

        self.init(window: panel)
        setupViews()
    }

    private func setupViews() {
        guard let window = window else { return }

        containerView = NSVisualEffectView(frame: window.contentRect(forFrameRect: window.frame))
        containerView.material = .hudWindow
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true

        iconLabel = NSTextField(labelWithString: "🌐")
        iconLabel.font = NSFont.systemFont(ofSize: 20)
        iconLabel.alignment = .center
        iconLabel.frame = NSRect(x: 10, y: 20, width: 28, height: 26)

        label = NSTextField(wrappingLabelWithString: "Translating...")
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.frame = NSRect(x: 44, y: 24, width: 320, height: 34)

        subLabel = NSTextField(labelWithString: "")
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byTruncatingTail
        subLabel.frame = NSRect(x: 44, y: 6, width: 320, height: 16)

        containerView.addSubview(iconLabel)
        containerView.addSubview(label)
        containerView.addSubview(subLabel)
        window.contentView = containerView
    }

    func show(
        message: String,
        subMessage: String = "",
        icon: String = "🌐",
        speakText: String? = nil,
        targetLang: String = "EN-US",
        textFrame: CGRect? = nil,
        autoDismissDelay: TimeInterval? = 10.0
    ) {
        dismissTimer?.invalidate()
        dismissTimer = nil

        label.stringValue = message
        subLabel.stringValue = subMessage
        iconLabel.stringValue = icon

        if let text = speakText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AudioSpeechHelper.shared.speak(text: text, languageCode: targetLang)
        }

        if let window = window {
            let windowWidth: CGFloat = 380
            let windowHeight: CGFloat = 64
            var targetX: CGFloat
            var targetY: CGFloat

            if let textRect = textFrame {
                // Position directly below text baseline
                targetX = textRect.origin.x
                targetY = textRect.origin.y - windowHeight - 8
            } else {
                // Position near mouse cursor
                let mouseLoc = NSEvent.mouseLocation
                targetX = mouseLoc.x + 15
                targetY = mouseLoc.y - 70
            }

            if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                if targetX + windowWidth > frame.maxX {
                    targetX = frame.maxX - windowWidth - 10
                }
                if targetX < frame.minX {
                    targetX = frame.minX + 10
                }
                if targetY < frame.minY {
                    targetY = textFrame != nil ? (textFrame!.origin.y + textFrame!.size.height + 8) : (NSEvent.mouseLocation.y + 15)
                }
            }

            window.setFrameOrigin(NSPoint(x: targetX, y: targetY))
            window.orderFrontRegardless() // Ensure visibility above WhatsApp, Telegram, etc.
        }

        if let delay = autoDismissDelay {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        window?.orderOut(nil)
    }
}
