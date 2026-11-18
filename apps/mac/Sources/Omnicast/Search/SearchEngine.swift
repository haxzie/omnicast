import Combine
import Foundation

/// Fans a query out to every provider, merges, ranks and publishes results.
///
/// Each keystroke cancels the previous round, and fast providers render
/// immediately rather than waiting for the slow ones (the metadata index), so
/// apps and commands appear the instant you type.
@MainActor
final class SearchEngine: ObservableObject {
    enum Mode: Hashable {
        /// The launcher proper: installed applications, nothing else.
        case applications
        case clipboard
        case dictation

        /// Clipboard history and recordings are chronological browsers, not
        /// ranked search: the newest entry belongs at the top whether or not
        /// you have ever pasted it.
        var isHistoryBrowser: Bool { self != .applications }

        var placeholder: String {
            switch self {
            case .applications: return "Search applications…"
            case .clipboard, .dictation: return "Type to filter entries…"
            }
        }

        /// Shown in the breadcrumb once you have descended into it.
        var title: String {
            switch self {
            case .applications: return "Omnicast"
            case .clipboard: return "Clipboard History"
            case .dictation: return "Recordings"
            }
        }

        var identifier: String {
            switch self {
            case .applications: return "applications"
            case .clipboard: return "clipboard"
            case .dictation: return "dictation"
            }
        }

        /// Browsers render as a list beside a detail pane.
        var isBrowser: Bool { self != .applications }
    }

    @Published private(set) var results: [SearchItem] = []
    @Published private(set) var isSearching = false
    @Published var selectedIndex = 0
    @Published private(set) var mode: Mode = .applications

    /// What was typed at the root, restored on the way back out.
    private var rootQuery = ""

    /// Descends into a browser, keeping the launcher open.
    func enter(_ mode: Mode) {
        guard mode != self.mode else { return }
        if self.mode == .applications { rootQuery = query }
        self.mode = mode
        hasUserSelection = false
        search("")
    }

    /// Returns to the application search. `false` when already there, which
    /// the launcher reads as "now close the panel".
    @discardableResult
    func goBack() -> Bool {
        guard mode != .applications else { return false }
        mode = .applications
        hasUserSelection = false
        search(rootQuery)
        return true
    }

    /// The live query. The launcher's text field binds straight to this, so
    /// there is only ever one copy of what the user typed.
    @Published private(set) var query = ""

    private let usage: UsageStore
    private let applicationProvider = ApplicationProvider()
    private var searchTask: Task<Void, Never>?
    private var applicationWatcher: DirectoryWatcher?

    init(usage: UsageStore = .shared) {
        self.usage = usage
    }
    /// Set while results for a different query are still being merged.
    private var publishedQuery: String?
    /// True once the user has arrowed or clicked away from the top result; only
    /// then is the highlight worth preserving as late results merge in.
    private var hasUserSelection = false

    func prepare() async {
        await applicationProvider.prepare()
        watchApplicationDirectories()
        // The index lands a beat after launch; refresh whatever is on screen.
        // Empty queries included — that is the predicted zero state, which has
        // nothing to show until the index exists.
        search(query)
    }

    /// Picks up apps installed, renamed or deleted while Omnicast is running,
    /// so the list is never stale until the next restart.
    private func watchApplicationDirectories() {
        guard applicationWatcher == nil else { return }
        let watcher = DirectoryWatcher(paths: ApplicationProvider.watchablePaths) {
            Task { @MainActor [weak self] in self?.reindexApplications() }
        }
        watcher.start()
        applicationWatcher = watcher
    }

    func reindexApplications() {
        Task {
            await applicationProvider.reindex()
            search(query)
        }
    }

    func search(_ text: String) {
        query = text
        searchTask?.cancel()

        let providers = providers(for: mode)
        searchTask = Task { [weak self] in
            guard let self else { return }
            // A short debounce keeps a fast typist from queueing eight searches.
            if !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(18))
                guard !Task.isCancelled else { return }
            }
            self.isSearching = true

            var merged: [SearchItem] = []
            await withTaskGroup(of: [SearchItem].self) { group in
                for provider in providers {
                    group.addTask { await provider.items(for: text) }
                }
                for await items in group {
                    guard !Task.isCancelled else { return }
                    merged.append(contentsOf: items)
                }
            }

            guard !Task.isCancelled else { return }
            // One publish per query, not one per provider. Publishing as each
            // provider returned made sense when the slow system file index was
            // among them; now they are all in memory or a quick SQLite read,
            // and the extra renders only produced overlapping animations when
            // typing quickly.
            self.publish(self.rank(merged, query: text), for: text)
            self.isSearching = false
        }
    }

    /// Teaches the ranker from a launch: what was typed, what was on screen,
    /// and which row won.
    func recordUse(of item: SearchItem) {
        let shown = results.prefix(10).map { (id: $0.id, base: $0.base) }
        let index = results.firstIndex { $0.id == item.id } ?? 0
        usage.record(itemID: item.id, query: query, shown: Array(shown), pickedIndex: index)
    }

    /// Forgets everything learned so far.
    func resetLearning() {
        usage.reset()
        search(query)
    }

    var selectedItem: SearchItem? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func move(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(0, selectedIndex + offset), results.count - 1)
        hasUserSelection = true
    }

    func select(index: Int) {
        guard results.indices.contains(index) else { return }
        selectedIndex = index
        hasUserSelection = true
    }

    func reset() {
        searchTask?.cancel()
        mode = .applications
        rootQuery = ""
        query = ""
        publishedQuery = nil
        hasUserSelection = false
        selectedIndex = 0
        results = []
    }

    // MARK: - Internals

    private func providers(for mode: Mode) -> [SearchProvider] {
        switch mode {
        case .applications:
            return [applicationProvider, PaneProvider(), QuickLinkProvider(), URLProvider()]
        case .clipboard: return [ClipboardProvider(browsing: true)]
        case .dictation: return [DictationProvider(browsing: true)]
        }
    }

    /// An empty application search is a prediction, so it shows only what you
    /// have opened before. An empty filter in a browser is not — it must list
    /// everything that browser holds.
    nonisolated static func predicts(query: String, mode: Mode) -> Bool {
        query.isEmpty && mode == .applications
    }

    /// Backspace leaves a browser only once the filter is empty — before that
    /// it is still deleting what you typed.
    nonisolated static func backspaceExits(query: String, mode: Mode) -> Bool {
        query.isEmpty && mode.isBrowser
    }

    /// What an empty launcher offers: the handful of applications you open
    /// most, then the two browsers in a fixed order so muscle memory holds.
    static let quickLaunchApplications = 6

    nonisolated static func quickLaunch(from ranked: [SearchItem]) -> [SearchItem] {
        let applications = ranked
            .filter { $0.kind == .application }
            .prefix(quickLaunchApplications)
        let panes: [SearchItem] = [Mode.clipboard, Mode.dictation].compactMap { mode in
            ranked.first { $0.action == .openPane(mode) }
        }
        return Array(applications) + panes
    }

    private func rank(_ items: [SearchItem], query: String) -> [SearchItem] {
        // One snapshot per keystroke rather than a lookup per candidate.
        let memory = usage.memory(for: query)
        return Self.rank(
            items,
            // In a history browser the providers have already put the list in
            // the order the user expects — newest first. Letting frecency
            // reorder it floats whatever you happened to paste before above
            // what you said a minute ago, which reads as a broken sort rather
            // than as learning.
            boost: mode.isHistoryBrowser ? { _ in 0 } : { memory.boost(for: $0) },
            isPrediction: Self.predicts(query: query, mode: mode))
    }

    /// Scores and orders one round of candidates.
    ///
    /// Free of the engine's state so the ordering can be checked directly.
    nonisolated static func rank(
        _ items: [SearchItem], boost: (String) -> Double, isPrediction: Bool
    ) -> [SearchItem] {
        var seen = Set<String>()
        var ranked: [SearchItem] = []
        ranked.reserveCapacity(items.count)

        for var item in items where seen.insert(item.id).inserted {
            let learned = boost(item.id)
            // With nothing typed the list is pure prediction, so it only holds
            // things you have actually opened.
            // The two browsers are always on the quick-launch row, used or not.
            if isPrediction, learned <= 0, !item.isLauncherPane { continue }
            item.base = item.score * item.weight
            item.score = item.base + learned
            ranked.append(item)
        }
        ranked.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.title < rhs.title : lhs.score > rhs.score
        }
        return isPrediction ? Self.quickLaunch(from: ranked) : Array(ranked.prefix(50))
    }

    private func publish(_ items: [SearchItem], for query: String) {
        // A new query always starts at the top; within one query the highlight
        // stays on whatever row the user picked as late results merge in.
        let previousID = (publishedQuery == query && hasUserSelection) ? selectedItem?.id : nil
        if publishedQuery != query { hasUserSelection = false }
        publishedQuery = query
        results = items

        if let previousID, let index = items.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = 0
        }
    }
}
