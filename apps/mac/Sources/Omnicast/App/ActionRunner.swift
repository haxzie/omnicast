import AppKit
import Foundation

/// Performs whatever a search result promises.
@MainActor
enum ActionRunner {
    /// The address to remember when this result is opened, if any.
    ///
    /// Remembering the host is what lets "git" mean github.com next time, and
    /// what the favicon is keyed on — so it is worth a test of its own rather
    /// than living inline in a switch where it can quietly go missing.
    nonisolated static func websiteToRemember(_ item: SearchItem) -> URL? {
        guard item.kind == .website, case .openURL(let url) = item.action else { return nil }
        return url
    }

    static func run(_ item: SearchItem, from environment: AppEnvironment) {
        environment.searchEngine.recordUse(of: item)

        // Descending into a browser keeps the launcher open; everything else
        // acts and dismisses.
        if case .openPane(let mode) = item.action {
            environment.searchEngine.enter(mode)
            return
        }
        environment.hideLauncher()

        switch item.action {
        case .openPane:
            break
        case .openURL(let url):
            // `open` blocks the main thread while LaunchServices starts the
            // app, which freezes the launcher's exit animation and leaves it
            // on screen until the app is up. Hand it off so the panel can get
            // out of the way immediately.
            Task.detached(priority: .userInitiated) {
                NSWorkspace.shared.open(url)
            }
            if let site = Self.websiteToRemember(item) {
                URLHistoryStore.shared.record(site)
                Task.detached { await FaviconFetcher.shared.fetchIfNeeded(for: site) }
            }
        case .copyText(let text):
            TextInserter.copy(text)
        case .pasteText(let text):
            TextInserter.paste(text)
        case .openWindow(let tab):
            environment.openMainWindow(tab: tab)
        }
    }
}
