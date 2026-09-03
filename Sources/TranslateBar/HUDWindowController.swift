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
        containerView.autoresizingMask = [.width, .height]

        iconLabel = NSTextField(labelWithString: "🌐")
        iconLabel.font = NSFont.systemFont(ofSize: 20)
        iconLabel.alignment = .center

        label = NSTextField(wrappingLabelWithString: "Translating...")
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0

        subLabel = NSTextField(wrappingLabelWithString: "")
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 0

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
            let windowWidth: CGFloat = 420
            let textWidth: CGFloat = 348

            // Measure dynamic text heights to fit all lines without truncating
            let titleHeight: CGFloat
            if !message.isEmpty {
                let rect = (message as NSString).boundingRect(
                    with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: label.font ?? NSFont.systemFont(ofSize: 13, weight: .bold)]
                )
                titleHeight = max(18, ceil(rect.height))
            } else {
                titleHeight = 0
            }

            let subHeight: CGFloat
            if !subMessage.isEmpty {
                let rect = (subMessage as NSString).boundingRect(
                    with: NSSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: subLabel.font ?? NSFont.systemFont(ofSize: 12, weight: .regular)]
                )
                subHeight = max(16, ceil(rect.height))
            } else {
                subHeight = 0
            }

            let spacing: CGFloat = (titleHeight > 0 && subHeight > 0) ? 6 : 0
            let contentHeight = titleHeight + subHeight + spacing
            let windowHeight: CGFloat = max(64, min(contentHeight + 24, 450))

            // Layout subviews
            iconLabel.frame = NSRect(x: 12, y: windowHeight - 38, width: 28, height: 26)

            if subHeight > 0 && titleHeight > 0 {
                label.frame = NSRect(x: 48, y: windowHeight - 12 - titleHeight, width: textWidth, height: titleHeight)
                subLabel.frame = NSRect(x: 48, y: windowHeight - 12 - titleHeight - spacing - subHeight, width: textWidth, height: subHeight)
            } else if subHeight > 0 {
                label.frame = .zero
                subLabel.frame = NSRect(x: 48, y: 12, width: textWidth, height: windowHeight - 24)
            } else {
                label.frame = NSRect(x: 48, y: 12, width: textWidth, height: windowHeight - 24)
                subLabel.frame = .zero
            }

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
                targetY = mouseLoc.y - windowHeight - 10
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
                if targetY + windowHeight > frame.maxY {
                    targetY = frame.maxY - windowHeight - 10
                }
            }

            window.setFrame(NSRect(x: targetX, y: targetY, width: windowWidth, height: windowHeight), display: true, animate: false)
            window.orderFrontRegardless()
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
