import Cocoa

final class ChatLiveSidebarWindowController: NSWindowController {
    static let shared = ChatLiveSidebarWindowController()

    private var containerView: NSVisualEffectView!
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var headerLabel: NSTextField!
    private var seenMessages: Set<String> = []

    var isSidebarVisible: Bool {
        return window?.isVisible ?? false
    }

    private init() {
        let initialRect = NSRect(x: 100, y: 100, width: 340, height: 500)
        let panel = NSPanel(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "TranslateBar • Live Telegram Stream"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = window else { return }

        containerView = NSVisualEffectView(frame: window.contentView!.bounds)
        containerView.material = .hudWindow
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 12
        containerView.layer?.masksToBounds = true
        containerView.autoresizingMask = [.width, .height]

        // Top Header
        let headerView = NSView(frame: NSRect(x: 0, y: window.contentView!.bounds.height - 44, width: 340, height: 44))
        headerView.autoresizingMask = [.width, .minYMargin]

        headerLabel = NSTextField(labelWithString: "💬 Live Telegram Translate")
        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        headerLabel.textColor = .labelColor
        headerLabel.frame = NSRect(x: 14, y: 12, width: 220, height: 20)
        headerView.addSubview(headerLabel)

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearEntries))
        clearButton.bezelStyle = .inline
        clearButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        clearButton.frame = NSRect(x: 270, y: 11, width: 56, height: 22)
        clearButton.autoresizingMask = [.minXMargin]
        headerView.addSubview(clearButton)

        containerView.addSubview(headerView)

        // Scroll View for Messages
        scrollView = NSScrollView(frame: NSRect(x: 10, y: 10, width: 320, height: window.contentView!.bounds.height - 58))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        documentView.autoresizingMask = [.width]
        scrollView.documentView = documentView

        // Stack View
        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor)
        ])

        containerView.addSubview(scrollView)
        window.contentView = containerView
    }

    /// Positions the sidebar alongside the Telegram window
    func dockToTelegramWindow(telegramFrame: CGRect) {
        guard let window = window, let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let width: CGFloat = 340
        let height: CGFloat = min(telegramFrame.height, visibleFrame.height - 40)

        // Try placing on the right side of Telegram
        var targetX = telegramFrame.maxX + 8
        if targetX + width > visibleFrame.maxX {
            // Place on the left side of Telegram if right side overflows
            targetX = max(visibleFrame.minX + 8, telegramFrame.minX - width - 8)
        }

        var targetY = telegramFrame.origin.y
        if targetY + height > visibleFrame.maxY {
            targetY = visibleFrame.maxY - height
        }
        if targetY < visibleFrame.minY {
            targetY = visibleFrame.minY + 8
        }

        window.setFrame(NSRect(x: targetX, y: targetY, width: width, height: height), display: true, animate: false)
        window.orderFrontRegardless()
    }

    /// Appends a new translated message bubble to the stream
    func addMessage(original: String, translated: String, alignment: MessageAlignment) {
        let cleanOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanOriginal.isEmpty, !seenMessages.contains(cleanOriginal) else { return }
        seenMessages.insert(cleanOriginal)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let bubble = self.createMessageBubble(original: cleanOriginal, translated: translated, alignment: alignment)
            self.stackView.addArrangedSubview(bubble)

            // Auto-scroll to latest message
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let documentView = self.scrollView.documentView {
                    let point = NSPoint(x: 0, y: documentView.frame.height - self.scrollView.contentView.bounds.height)
                    self.scrollView.contentView.scroll(to: point)
                    self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
                }
            }
        }
    }

    private func createMessageBubble(original: String, translated: String, alignment: MessageAlignment) -> NSView {
        let card = NSVisualEffectView()
        card.material = (alignment == .sender) ? .sidebar : .selection
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let isSender = (alignment == .sender)
        let icon = isSender ? "📥 Incoming" : "📤 You"
        
        let headerLbl = NSTextField(labelWithString: icon)
        headerLbl.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        headerLbl.textColor = isSender ? .systemBlue : .systemGreen
        headerLbl.translatesAutoresizingMaskIntoConstraints = false

        let translatedLbl = NSTextField(wrappingLabelWithString: translated)
        translatedLbl.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        translatedLbl.textColor = .labelColor
        translatedLbl.isSelectable = true
        translatedLbl.translatesAutoresizingMaskIntoConstraints = false

        let originalLbl = NSTextField(wrappingLabelWithString: original)
        originalLbl.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        originalLbl.textColor = .secondaryLabelColor
        originalLbl.isSelectable = true
        originalLbl.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = NSStackView()
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let copyBtn = PayloadButton(title: "Copy", payload: translated) { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        actionStack.addArrangedSubview(copyBtn)

        let speakBtn = PayloadButton(title: "🔊 Speak", payload: translated) { text in
            AudioSpeechHelper.shared.speak(text: text, languageCode: "EN")
        }
        actionStack.addArrangedSubview(speakBtn)

        card.addSubview(headerLbl)
        card.addSubview(translatedLbl)
        card.addSubview(originalLbl)
        card.addSubview(actionStack)

        NSLayoutConstraint.activate([
            headerLbl.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            headerLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            headerLbl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            translatedLbl.topAnchor.constraint(equalTo: headerLbl.bottomAnchor, constant: 4),
            translatedLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            translatedLbl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            originalLbl.topAnchor.constraint(equalTo: translatedLbl.bottomAnchor, constant: 4),
            originalLbl.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            originalLbl.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            actionStack.topAnchor.constraint(equalTo: originalLbl.bottomAnchor, constant: 6),
            actionStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            actionStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
        ])

        return card
    }

    @objc func clearEntries() {
        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        seenMessages.removeAll()
    }

    func toggleVisibility() {
        if isSidebarVisible {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class PayloadButton: NSButton {
    private let payload: String
    private let onAction: (String) -> Void

    init(title: String, payload: String, onAction: @escaping (String) -> Void) {
        self.payload = payload
        self.onAction = onAction
        super.init(frame: .zero)
        self.title = title
        self.bezelStyle = .inline
        self.font = NSFont.systemFont(ofSize: 10)
        self.target = self
        self.action = #selector(clicked)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func clicked() {
        onAction(payload)
        if title == "Copy" {
            title = "Copied! ✓"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.title = "Copy"
            }
        }
    }
}
