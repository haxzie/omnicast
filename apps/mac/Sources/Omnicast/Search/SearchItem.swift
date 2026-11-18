import AppKit
import Foundation
import SwiftUI

/// What pressing Return on a result does.
enum SearchAction: Hashable {
    case openURL(URL)
    case copyText(String)
    /// Copies and then pastes into the frontmost app.
    case pasteText(String)
    case openWindow(MainWindowTab)
    /// Descends into a browser inside the launcher rather than acting.
    case openPane(SearchEngine.Mode)
}

/// The full record behind a result, for the detail pane to render.
enum ResultDetail: Hashable {
    case clipboard(ClipboardEntry)
    case dictation(DictationEntry)
}

enum SearchItemKind: String, Hashable {
    /// Search covers installed applications and a few Finder locations.
    /// Clipboard entries and past dictations are only ever listed by their
    /// own browsing modes.
    case application, folder, website, clipboard, dictation

    var label: String {
        switch self {
        case .application: return "App"
        case .folder: return "Folder"
        case .website: return "Website"
        case .clipboard: return "Clipboard"
        case .dictation: return "Dictation"
        }
    }

    var symbolName: String {
        switch self {
        case .application: return "app.dashed"
        case .folder: return "folder"
        case .website: return "globe"
        case .clipboard: return "doc.on.clipboard"
        case .dictation: return "waveform"
        }
    }
}

struct SearchItem: Identifiable, Hashable {
    enum Icon: Hashable {
        case file(URL)
        case symbol(String)
        /// An AppKit named image, for the few system icons that cannot be
        /// read off a path — the Trash being hidden, for one.
        case named(String)
        /// An image file on disk, such as a downloaded favicon.
        case image(URL)
        /// A drawn app icon for the launcher's own browsers, so they sit on
        /// the quick-launch row as equals to real applications.
        case builtIn(BuiltInIcon)
    }

    let id: String
    var title: String
    var subtitle: String
    var kind: SearchItemKind
    var icon: Icon
    var action: SearchAction
    /// Provider weight; nudges categories relative to one another.
    var weight: Double = 1
    /// Filled in by the engine.
    var score: Double = 0
    /// The score before anything learned was added — logged for replay.
    var base: Double = 0
    var titleMatch: [Int] = []
    /// Extra keywords the matcher may hit (e.g. an app's bundle id).
    var aliases: [String] = []
    /// Heading this row is grouped under, when browsing.
    var section: String?
    /// A shorter name for the quick-launch row, where a tile is 84pt wide.
    var compactTitle: String?
    /// Everything the detail pane needs; nil for plain results.
    var detail: ResultDetail?

    /// True for the two browsers built into the launcher.
    var isLauncherPane: Bool {
        if case .openPane = action { return true }
        return false
    }

    static func == (lhs: SearchItem, rhs: SearchItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Providers produce candidates for a query. Everything runs off the main
/// actor so typing never blocks on disk.
protocol SearchProvider: Sendable {
    var identifier: String { get }
    /// Called once at launch; cheap providers can no-op.
    func prepare() async
    func items(for query: String) async -> [SearchItem]
}

extension SearchProvider {
    func prepare() async {}
}

/// The launcher's own "apps", drawn rather than shipped: a full-bleed squircle
/// on Apple's corner curve with a white glyph, so they read as macOS icons at
/// any size without an asset catalogue.
enum BuiltInIcon: String, Hashable {
    case clipboard
    case recordings

    var symbol: String {
        switch self {
        case .clipboard: return "doc.on.clipboard.fill"
        case .recordings: return "waveform"
        }
    }

    /// Top-to-bottom gradient, deep enough that a white glyph carries.
    var colors: [Color] {
        switch self {
        case .clipboard:
            return [Color(red: 0.26, green: 0.26, blue: 0.29), Color(red: 0.11, green: 0.11, blue: 0.13)]
        case .recordings:
            return [Color(red: 0.45, green: 0.33, blue: 1.0), Color(red: 0.23, green: 0.17, blue: 0.65)]
        }
    }

    /// Apple's squircle is 0.2237 of the side; a plain circular corner at this
    /// size reads as subtly wrong beside real icons.
    static let cornerRatio = 0.2237
}
