import Cocoa

final class AppFilter {
    static let shared = AppFilter()

    /// Default set of app bundle IDs to bypass translation for (launchers, search bars, coding IDEs, terminals, password managers)
    private let defaultBlacklist: Set<String> = [
        "com.apple.Spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "com.sublimetext.4"
    ]

    private var userBlacklist: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: "blacklistedApps") ?? Array(defaultBlacklist)
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "blacklistedApps")
        }
    }

    private init() {}

    /// Checks if the frontmost active application should be ignored
    func isCurrentAppBlacklisted() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return false
        }
        return userBlacklist.contains(bundleIdentifier)
    }

    /// Toggles blacklisting for the currently active frontmost application
    func toggleCurrentAppBlacklist() -> (appName: String, isBlacklisted: Bool)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return nil
        }
        let appName = frontmostApp.localizedName ?? bundleIdentifier
        var set = userBlacklist
        let newlyBlacklisted: Bool
        if set.contains(bundleIdentifier) {
            set.remove(bundleIdentifier)
            newlyBlacklisted = false
        } else {
            set.insert(bundleIdentifier)
            newlyBlacklisted = true
        }
        userBlacklist = set
        return (appName, newlyBlacklisted)
    }

    /// Gets current active app info
    func currentActiveAppInfo() -> (name: String, bundleId: String, isBlacklisted: Bool)? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleIdentifier = frontmostApp.bundleIdentifier else {
            return nil
        }
        let appName = frontmostApp.localizedName ?? bundleIdentifier
        let isBlacklisted = userBlacklist.contains(bundleIdentifier)
        return (appName, bundleIdentifier, isBlacklisted)
    }
}
