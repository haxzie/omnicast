import AppKit
import Foundation

/// Performs whatever a search result promises.
@MainActor
enum ActionRunner {
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
            NSWorkspace.shared.open(url)
        case .copyText(let text):
            TextInserter.copy(text)
        case .pasteText(let text):
            TextInserter.paste(text)
        case .openWindow(let tab):
            environment.openMainWindow(tab: tab)
        }
    }
}
