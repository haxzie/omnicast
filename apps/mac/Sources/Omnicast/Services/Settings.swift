import Combine
import Foundation

/// User preferences, persisted in `UserDefaults` and observed by the UI.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    @Published var launcherShortcut: Shortcut { didSet { store(launcherShortcut, "launcherShortcut") } }
    @Published var clipboardShortcut: Shortcut { didSet { store(clipboardShortcut, "clipboardShortcut") } }
    @Published var dictationShortcut: Shortcut { didSet { store(dictationShortcut, "dictationShortcut") } }

    @Published var clipboardHistoryEnabled: Bool { didSet { defaults.set(clipboardHistoryEnabled, forKey: "clipboardHistoryEnabled") } }
    @Published var clipboardRetentionDays: Int { didSet { defaults.set(clipboardRetentionDays, forKey: "clipboardRetentionDays") } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") } }

    @Published var selectedModelID: String? { didSet { defaults.set(selectedModelID, forKey: "selectedModelID") } }
    @Published var dictationLanguage: String { didSet { defaults.set(dictationLanguage, forKey: "dictationLanguage") } }
    @Published var fnKeyDictation: Bool { didSet { defaults.set(fnKeyDictation, forKey: "fnKeyDictation") } }
    @Published var autoPasteDictation: Bool { didSet { defaults.set(autoPasteDictation, forKey: "autoPasteDictation") } }
    @Published var playDictationSounds: Bool { didSet { defaults.set(playDictationSounds, forKey: "playDictationSounds") } }

    @Published var syncEnabled: Bool { didSet { defaults.set(syncEnabled, forKey: "syncEnabled") } }
    @Published var apiBaseURL: String { didSet { defaults.set(apiBaseURL, forKey: "apiBaseURL") } }
    @Published var apiToken: String { didSet { defaults.set(apiToken, forKey: "apiToken") } }

    private let defaults = UserDefaults.standard

    private init() {
        func shortcut(_ key: String, _ fallback: Shortcut) -> Shortcut {
            guard let data = UserDefaults.standard.data(forKey: key),
                let value = try? JSONDecoder().decode(Shortcut.self, from: data)
            else { return fallback }
            return value
        }

        launcherShortcut = shortcut("launcherShortcut", .launcher)
        clipboardShortcut = shortcut("clipboardShortcut", .clipboard)
        dictationShortcut = shortcut("dictationShortcut", .dictation)

        clipboardHistoryEnabled = defaults.object(forKey: "clipboardHistoryEnabled") as? Bool ?? true
        clipboardRetentionDays = defaults.object(forKey: "clipboardRetentionDays") as? Int ?? 30
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? false

        selectedModelID = defaults.string(forKey: "selectedModelID")
        dictationLanguage = defaults.string(forKey: "dictationLanguage") ?? "auto"
        fnKeyDictation = defaults.object(forKey: "fnKeyDictation") as? Bool ?? true
        autoPasteDictation = defaults.object(forKey: "autoPasteDictation") as? Bool ?? true
        playDictationSounds = defaults.object(forKey: "playDictationSounds") as? Bool ?? true

        syncEnabled = defaults.object(forKey: "syncEnabled") as? Bool ?? false
        apiBaseURL = defaults.string(forKey: "apiBaseURL") ?? "http://127.0.0.1:8787"
        apiToken = defaults.string(forKey: "apiToken") ?? ""
    }

    private func store(_ shortcut: Shortcut, _ key: String) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: key)
    }
}
