import Cocoa
import Vision

final class SubtitlePillWindowController: NSWindowController {
    private var label: NSTextField!
    private var containerView: NSVisualEffectView!

    init(translatedText: String, textFrame: CGRect) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: max(180, min(textFrame.width + 40, 460)), height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = true

        super.init(window: panel)
        setupViews(text: translatedText, textFrame: textFrame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(text: String, textFrame: CGRect) {
        guard let window = window else { return }

        let pillWidth = window.frame.width
        let pillHeight: CGFloat = 28

        containerView = NSVisualEffectView(frame: window.contentRect(forFrameRect: window.frame))
        containerView.material = .hudWindow
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 6
        containerView.layer?.masksToBounds = true

        label = NSTextField(labelWithString: "💬 " + text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 6, y: 4, width: pillWidth - 12, height: 20)

        containerView.addSubview(label)
        window.contentView = containerView

        // In Cocoa screen coordinates, (0,0) is bottom-left. Position directly below text baseline.
        var targetX = textFrame.origin.x
        var targetY = textFrame.origin.y - pillHeight - 4

        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame

            // Clamp X within visible screen width
            if targetX + pillWidth > visibleFrame.maxX {
                targetX = visibleFrame.maxX - pillWidth - 10
            }
            if targetX < visibleFrame.minX {
                targetX = visibleFrame.minX + 10
            }

            // Clamp Y within visible screen bounds without flipping to top of screen
            let minY = visibleFrame.minY + 6
            let maxY = visibleFrame.maxY - pillHeight - 6
            targetY = max(minY, min(targetY, maxY))
        }

        window.setFrameOrigin(NSPoint(x: targetX, y: targetY))
        window.orderFrontRegardless()
    }
}

final class ChatSubtitleOverlayManager {
    static let shared = ChatSubtitleOverlayManager()

    private var activeSubtitles: [SubtitlePillWindowController] = []
    private var isScanning = false

    private init() {}

    func clearSubtitles() {
        for controller in activeSubtitles {
            controller.window?.orderOut(nil)
        }
        activeSubtitles.removeAll()
    }

    func scanAndOverlayChatSubtitles(targetLanguageProvider: @escaping () -> String) {
        if !activeSubtitles.isEmpty {
            clearSubtitles()
            return
        }

        guard !isScanning else { return }
        isScanning = true

        HUDWindowController.shared.show(message: "Scanning Chat Screen...", icon: "⏳", autoDismissDelay: 1.5)

        guard let mainScreen = NSScreen.main else {
            isScanning = false
            return
        }

        let screenFrame = mainScreen.frame

        // Capture full screen image
        guard let cgImage = CGWindowListCreateImage(
            screenFrame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            isScanning = false
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self, error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                self?.isScanning = false
                return
            }

            let targetLang = targetLanguageProvider()
            let group = DispatchGroup()
            var detectedItems: [(text: String, frame: CGRect)] = []

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)

                // Filter out short UI buttons, times, and single characters
                guard text.count > 2, !self.isUIString(text) else { continue }

                // Vision boundingBox: (0,0) is bottom-left of screen in 0.0..1.0 range
                let bbox = observation.boundingBox
                let textX = bbox.origin.x * screenFrame.width
                let textY = bbox.origin.y * screenFrame.height
                let textW = bbox.size.width * screenFrame.width
                let textH = bbox.size.height * screenFrame.height
                let rect = CGRect(x: textX, y: textY, width: textW, height: textH)

                detectedItems.append((text: text, frame: rect))
            }

            // Take prominent chat text lines to display subtitles
            let prominentItems = Array(detectedItems.prefix(8))

            for item in prominentItems {
                group.enter()
                DeepLService.shared.smartTranslate(text: item.text, configuredTargetLang: targetLang) { result in
                    DispatchQueue.main.async {
                        if case .success(let translation) = result {
                            let controller = SubtitlePillWindowController(
                                translatedText: translation.translatedText,
                                textFrame: item.frame
                            )
                            self.activeSubtitles.append(controller)
                        }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                self.isScanning = false
                // Automatically dismiss all subtitles after 14 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 14.0) {
                    self.clearSubtitles()
                }
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }

    private func isUIString(_ text: String) -> Bool {
        let lower = text.lowercased()
        let uiKeywords = ["search", "type a message", "online", "yesterday", "today", "calls", "chats", "settings", "status", "edit"]
        if uiKeywords.contains(lower) { return true }
        // Filter timestamps like 10:45 AM
        if lower.range(of: #"^\d{1,2}:\d{2}\s?(am|pm)?$"#, options: .regularExpression) != nil { return true }
        return false
    }
}
