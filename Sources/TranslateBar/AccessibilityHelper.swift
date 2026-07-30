import Cocoa
import ApplicationServices
import Carbon.HIToolbox

final class AccessibilityHelper {
    static let shared = AccessibilityHelper()

    private init() {}

    /// Checks if text is an image path, file URL, or binary graphic reference
    private func isImagePathOrURL(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasPrefix("file://") || lower.hasPrefix("data:image/") { return true }
        let imageExtensions = [".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".svg", ".ico", ".heic"]
        for ext in imageExtensions {
            if lower.hasSuffix(ext) { return true }
        }
        return false
    }

    /// Checks if Accessibility permissions are currently granted
    func isAccessibilityTrusted() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Queries the focused UI element of the currently frontmost application
    func getFocusedElement() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmostApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if result == .success, let element = focusedElement {
            return (element as! AXUIElement)
        }
        return nil
    }

    /// Attempts to read selected text using Accessibility API
    private func getSelectedTextViaAX() -> String? {
        guard let element = getFocusedElement() else { return nil }

        var selectedText: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        if result == .success, let text = selectedText as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !isImagePathOrURL(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    /// Retrieves selected text across ANY macOS app (combining Accessibility API with synthetic Cmd+C fallback)
    func getSelectedText(completion: @escaping (String?) -> Void) {
        // Method A: Try Accessibility AXUIElement first
        if let axText = getSelectedTextViaAX() {
            completion(axText)
            return
        }

        // Method B: Universal Cmd+C synthetic copy fallback for Electron apps (Telegram, WhatsApp, Slack, WebViews)
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let initialChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cmdUp?.flags = .maskCommand

        cmdDown?.post(tap: .cgSessionEventTap)
        cmdUp?.post(tap: .cgSessionEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { completion(nil); return }
            let newSelectedText = pasteboard.string(forType: .string)
            let didChange = pasteboard.changeCount != initialChangeCount

            // Restore user's original clipboard after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
            }

            if let text = newSelectedText {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !self.isImagePathOrURL(trimmed) && didChange {
                    completion(trimmed)
                    return
                } else if !trimmed.isEmpty && !self.isImagePathOrURL(trimmed) {
                    completion(trimmed)
                    return
                }
            }
            completion(nil)
        }
    }

    /// Gets current cursor screen location for HUD placement
    func getCursorScreenPosition() -> CGPoint {
        let mouseLocation = NSEvent.mouseLocation
        if let mainScreen = NSScreen.main {
            let screenHeight = mainScreen.frame.height
            return CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)
        }
        return mouseLocation
    }
}
