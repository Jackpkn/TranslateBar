import Cocoa
import Vision

enum MessageAlignment {
    case sender    // Left side (incoming messages)
    case receiver  // Right side (outgoing messages)
}

final class SubtitlePillWindowController: NSWindowController {
    private var label: NSTextField!
    private var containerView: NSVisualEffectView!

    init(translatedText: String, textFrame: CGRect, alignment: MessageAlignment = .sender) {
        let pillWidth = max(180, min(textFrame.width + 40, 480))
        let pillHeight: CGFloat = 28

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight),
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
        setupViews(text: translatedText, textFrame: textFrame, alignment: alignment, pillWidth: pillWidth, pillHeight: pillHeight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(text: String, textFrame: CGRect, alignment: MessageAlignment, pillWidth: CGFloat, pillHeight: CGFloat) {
        guard let window = window else { return }

        containerView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        containerView.material = .hudWindow
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 7
        containerView.layer?.masksToBounds = true

        // Distinct icon & alignment for sender (incoming) vs receiver (outgoing)
        let iconPrefix = (alignment == .sender) ? "📥 " : "📤 "
        label = NSTextField(labelWithString: iconPrefix + text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.alignment = (alignment == .sender) ? .left : .right
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.frame = NSRect(x: 8, y: 4, width: pillWidth - 16, height: 20)

        containerView.addSubview(label)
        window.contentView = containerView

        // Position directly below text bubble:
        // Sender messages (left) -> align to textFrame.origin.x
        // Receiver messages (right) -> align to textFrame.maxX - pillWidth
        var targetX: CGFloat
        if alignment == .sender {
            targetX = textFrame.origin.x
        } else {
            targetX = textFrame.maxX - pillWidth
        }

        // In Cocoa screen coordinates, (0,0) is bottom-left. Position directly below text baseline.
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

            // Clamp Y within visible screen bounds
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

    /// Finds the on-screen window bounds of the active frontmost application
    private func getFrontmostWindowBounds() -> (cgRect: CGRect, cocoaRect: CGRect)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let screen = NSScreen.main else { return nil }
        let pid = frontApp.processIdentifier
        let screenHeight = screen.frame.height

        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat,
                  width > 250, height > 250 else { continue }

            let cgRect = CGRect(x: x, y: y, width: width, height: height)
            let cocoaY = screenHeight - y - height
            let cocoaRect = CGRect(x: x, y: cocoaY, width: width, height: height)
            return (cgRect, cocoaRect)
        }
        return nil
    }

    func scanAndOverlayChatSubtitles(showHUD: Bool = true, targetLanguageProvider: @escaping () -> String) {
        if !activeSubtitles.isEmpty {
            clearSubtitles()
            return
        }

        guard !isScanning else { return }
        isScanning = true

        if showHUD {
            HUDWindowController.shared.show(message: "Translating Chat Messages...", icon: "💬", autoDismissDelay: 1.5)
        }

        guard let mainScreen = NSScreen.main else {
            isScanning = false
            return
        }

        let screenFrame = mainScreen.frame
        let windowBounds = getFrontmostWindowBounds()
        let targetCocoaRect = windowBounds?.cocoaRect ?? screenFrame
        let winWidth = targetCocoaRect.width
        let winHeight = targetCocoaRect.height

        // Chat pane horizontal boundaries
        let chatAreaMinX: CGFloat = (winWidth > 550) ? (targetCocoaRect.minX + winWidth * 0.28) : targetCocoaRect.minX
        let chatAreaWidth = targetCocoaRect.maxX - chatAreaMinX
        let chatAreaMidX = chatAreaMinX + (chatAreaWidth / 2.0)

        // 1. Try Native Accessibility API Tree first (100% pixel-accurate bubble coordinates)
        let axElements = AccessibilityHelper.shared.extractVisibleChatElements()
        var detectedItems: [(text: String, frame: CGRect, alignment: MessageAlignment)] = []

        if !axElements.isEmpty {
            for element in axElements {
                let text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count > 1, !self.isUIString(text) else { continue }
                let rect = element.cocoaFrame

                // Filter elements outside chat pane (e.g. sidebar, titlebar, bottom input)
                if winWidth > 550 {
                    guard rect.minX >= (chatAreaMinX - 20) else { continue }
                }
                if winHeight > 300 {
                    guard rect.minY > (targetCocoaRect.minY + 50), rect.maxY < (targetCocoaRect.maxY - 45) else { continue }
                }

                let alignment: MessageAlignment = (rect.midX < chatAreaMidX) ? .sender : .receiver
                detectedItems.append((text: text, frame: rect, alignment: alignment))
            }
        }

        if !detectedItems.isEmpty {
            self.translateAndDisplayItems(detectedItems: detectedItems, targetLanguageProvider: targetLanguageProvider)
            return
        }

        // 2. Fallback to Vision OCR if Accessibility tree is not available
        self.performVisionScanFallback(targetCocoaRect: targetCocoaRect, chatAreaMidX: chatAreaMidX, targetLanguageProvider: targetLanguageProvider)
    }

    private func translateAndDisplayItems(detectedItems: [(text: String, frame: CGRect, alignment: MessageAlignment)], targetLanguageProvider: @escaping () -> String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let targetLang = targetLanguageProvider()
            let group = DispatchGroup()
            let prominentItems = Array(detectedItems.prefix(12))

            // Get window bounds and dock companion sidebar on MAIN thread
            let windowBounds = self.getFrontmostWindowBounds()
            if let cocoaRect = windowBounds?.cocoaRect {
                ChatLiveSidebarWindowController.shared.dockToTelegramWindow(telegramFrame: cocoaRect)
            }

            for item in prominentItems {
                group.enter()
                DeepLService.shared.smartTranslate(text: item.text, configuredTargetLang: targetLang) { result in
                    DispatchQueue.main.async {
                        if case .success(let translation) = result {
                            ChatLiveSidebarWindowController.shared.addMessage(
                                original: item.text,
                                translated: translation.translatedText,
                                alignment: item.alignment
                            )
                        }
                        group.leave()
                    }
                }
            }

            group.notify(queue: .main) {
                self.isScanning = false
            }
        }
    }

    private func performVisionScanFallback(targetCocoaRect: CGRect, chatAreaMidX: CGFloat, targetLanguageProvider: @escaping () -> String) {
        guard let mainScreen = NSScreen.main else {
            self.isScanning = false
            return
        }

        let windowBounds = getFrontmostWindowBounds()
        let captureCgRect = windowBounds?.cgRect ?? mainScreen.frame

        guard let cgImage = CGWindowListCreateImage(
            captureCgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            self.isScanning = false
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self, error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                self?.isScanning = false
                return
            }

            var detectedItems: [(text: String, frame: CGRect, alignment: MessageAlignment)] = []
            let winWidth = targetCocoaRect.width
            let winHeight = targetCocoaRect.height
            let chatAreaMinLocalX: CGFloat = (winWidth > 550) ? (winWidth * 0.28) : 0

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count > 1, !self.isUIString(text) else { continue }

                let bbox = observation.boundingBox
                let localX = bbox.origin.x * winWidth
                let localY = bbox.origin.y * winHeight
                let localW = bbox.size.width * winWidth
                let localH = bbox.size.height * winHeight

                if winHeight > 300 {
                    guard localY > 65, localY < (winHeight - 55) else { continue }
                }
                if winWidth > 550 {
                    guard localX >= chatAreaMinLocalX else { continue }
                }

                let screenX = targetCocoaRect.origin.x + localX
                let screenY = targetCocoaRect.origin.y + localY
                let screenRect = CGRect(x: screenX, y: screenY, width: localW, height: localH)
                let alignment: MessageAlignment = (screenRect.midX < chatAreaMidX) ? .sender : .receiver

                detectedItems.append((text: text, frame: screenRect, alignment: alignment))
            }

            self.translateAndDisplayItems(detectedItems: detectedItems, targetLanguageProvider: targetLanguageProvider)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }

    private func isUIString(_ text: String) -> Bool {
        let lower = text.lowercased()
        let uiKeywords = [
            "search", "type a message", "write a message", "online", "yesterday", "today",
            "calls", "chats", "settings", "status", "edit", "explorer", "translatebar",
            "appdelegate", ".build", ".swift", "sources", "telegram", "окно", "window",
            "terminal", "saved messages", "mute", "unmute", "pin", "pinned"
        ]
        for kw in uiKeywords {
            if lower == kw || lower.hasPrefix(kw + " ") || lower.hasSuffix(" " + kw) {
                return true
            }
        }
        // Filter timestamps like 10:45 AM, 12:30, 22:15
        if lower.range(of: #"^\d{1,2}:\d{2}\s?(am|pm)?$"#, options: .regularExpression) != nil { return true }
        // Filter single/two char symbols
        if text.count <= 1 { return true }
        return false
    }
}
