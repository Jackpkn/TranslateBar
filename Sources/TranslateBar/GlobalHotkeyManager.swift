import Cocoa
import Carbon.HIToolbox

final class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    private var globalMonitor: Any?

    private init() {}

    func startMonitoring(
        onSelectionHotkey: @escaping () -> Void,
        onChatScanHotkey: @escaping () -> Void
    ) {
        // Monitor global keydown for Option + T and Option + Shift + T / Cmd + Option + T
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isTKey = event.keyCode == kVK_ANSI_T

            guard isTKey else { return }

            let hasOption = flags.contains(.option)
            let hasShift = flags.contains(.shift)
            let hasCommand = flags.contains(.command)
            let hasControl = flags.contains(.control)

            // Option + T (Selection Translation)
            if hasOption && !hasShift && !hasCommand && !hasControl {
                DispatchQueue.main.async {
                    onSelectionHotkey()
                }
                return
            }

            // Option + Shift + T or Cmd + Option + T (Chat Screen Auto-Scan Subtitles)
            if (hasOption && hasShift && !hasCommand && !hasControl) || (hasCommand && hasOption && !hasControl) {
                DispatchQueue.main.async {
                    onChatScanHotkey()
                }
                return
            }
        }
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }
}
