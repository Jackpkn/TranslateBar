import Cocoa
import Carbon.HIToolbox

enum TriggerMode: String {
    case manual = "manual" // Option + Enter or Option + T (Default, safe)
    case auto = "auto"     // Auto-translate on pause / Enter
}

/// Captures keystrokes system-wide, buffers what the user types, and translates
/// based on the selected TriggerMode (Manual via Option+Enter or Auto on pause/Enter).
final class KeyEventTap {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer: String = ""
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 1.0

    private let targetLanguageProvider: () -> String
    private let isEnabledProvider: () -> Bool
    private var isTranslating = false

    var triggerMode: TriggerMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "triggerMode") ?? TriggerMode.manual.rawValue
            return TriggerMode(rawValue: raw) ?? .manual
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "triggerMode")
        }
    }

    init(targetLanguageProvider: @escaping () -> String, isEnabledProvider: @escaping () -> Bool) {
        self.targetLanguageProvider = targetLanguageProvider
        self.isEnabledProvider = isEnabledProvider
    }

    func start() {
        let mask = 1 << CGEventType.keyDown.rawValue
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let instance = Unmanaged<KeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
                return instance.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            print("⚠️ Failed to create event tap. Grant Accessibility + Input Monitoring permission and restart.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Skip if TranslateBar is globally disabled or currently translating
        guard isEnabledProvider(), !isTranslating else {
            return Unmanaged.passRetained(event)
        }

        // Skip if active app is in the user's blacklist (e.g. Spotlight, Finder, Terminal, VS Code, Xcode)
        if AppFilter.shared.isCurrentAppBlacklisted() {
            return Unmanaged.passRetained(event)
        }

        guard type == .keyDown else { return Unmanaged.passRetained(event) }

        let nsEvent = NSEvent(cgEvent: event)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Let real shortcuts (Cmd+C, Cmd+Tab, Ctrl+C, etc.) pass through untouched.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return Unmanaged.passRetained(event)
        }

        let isEnterKey = (keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter)
        let isOptionPressed = flags.contains(.maskAlternate)

        if triggerMode == .manual {
            // MANUAL MODE: Only translate when user explicitly presses Option + Enter!
            if isEnterKey && isOptionPressed {
                if !buffer.isEmpty {
                    flushAndResend(afterReturn: true)
                    return nil
                }
            } else if isEnterKey {
                // Regular Enter without Option: reset buffer, pass key through untouched
                buffer = ""
                return Unmanaged.passRetained(event)
            }
        } else {
            // AUTO MODE: Translate on Enter or debounced pause
            if isEnterKey {
                if buffer.isEmpty { return Unmanaged.passRetained(event) }
                flushAndResend(afterReturn: true)
                return nil
            }
        }

        // Backspace: keep buffer in sync
        if keyCode == kVK_Delete {
            if !buffer.isEmpty { buffer.removeLast() }
            return Unmanaged.passRetained(event)
        }

        if let chars = nsEvent?.characters, !chars.isEmpty {
            buffer += chars
            if triggerMode == .auto {
                scheduleDebouncedFlush()
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func scheduleDebouncedFlush() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushAndResend(afterReturn: false)
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func flushAndResend(afterReturn: Bool) {
        guard !buffer.isEmpty, !isTranslating else {
            if afterReturn { sendReturnKey() }
            return
        }

        let textToTranslate = buffer
        let charCount = buffer.count
        buffer = ""
        isTranslating = true

        let targetLang = targetLanguageProvider()
        HUDWindowController.shared.show(message: "Translating to \(targetLang)...", icon: "⏳", autoDismissDelay: nil)

        DeepLService.shared.translate(text: textToTranslate, targetLang: targetLang) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch result {
                case .success(let translated):
                    PasteHelper.replace(originalCharCount: charCount, with: translated)
                    HUDWindowController.shared.show(message: "Done! (\(targetLang))", icon: "✅", autoDismissDelay: 1.2)
                case .failure(let error):
                    print("Translation failed: \(error)")
                    HUDWindowController.shared.show(message: error.localizedDescription, icon: "⚠️", autoDismissDelay: 3.0)
                }
                self.isTranslating = false
                if afterReturn { self.sendReturnKey() }
            }
        }
    }

    private func sendReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Return), keyDown: false)
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
