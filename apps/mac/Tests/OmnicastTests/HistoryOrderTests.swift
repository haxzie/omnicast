import XCTest

@testable import Omnicast

/// Recordings and clipboard history are chronological lists. Frecency ranking
/// used to apply to them too, so an old entry you had pasted once floated
/// above what you dictated a minute ago.
@MainActor
final class HistoryOrderTests: XCTestCase {
    /// Mirrors what `DictationProvider` emits while browsing: newest first,
    /// carrying its position as the score.
    private func recordings(_ titles: [String]) -> [SearchItem] {
        titles.enumerated().map { index, title in
            SearchItem(
                id: "dictation:\(title)", title: title, subtitle: "",
                kind: .dictation, icon: .symbol("waveform"),
                action: .copyText(title), weight: 0.9,
                score: Double(1_000 - index), section: "Today")
        }
    }

    private let newestFirst = ["newest", "middle", "oldest"]

    func testHistoryKeepsStoreOrderEvenWhenAnOldEntryWasUsedOften() {
        let ranked = SearchEngine.rank(
            recordings(newestFirst),
            // The browser passes no boost at all; this stands in for the
            // frecency the engine used to apply here.
            boost: { _ in 0 },
            isPrediction: false)
        XCTAssertEqual(ranked.map(\.title), newestFirst)
    }

    /// The bug, stated directly: with frecency applied, the entry you pasted
    /// before climbs to the top of a list that is supposed to be by time.
    func testFrecencyWouldReorderAHistoryList() {
        let ranked = SearchEngine.rank(
            recordings(newestFirst),
            boost: { $0 == "dictation:oldest" ? 500 : 0 },
            isPrediction: false)
        XCTAssertEqual(
            ranked.map(\.title), ["oldest", "newest", "middle"],
            "a boost reorders the list — which is why the browser must not pass one")
    }

    /// The wiring: which modes hand `rank` a boost at all.
    func testOnlyTheLauncherLearns() {
        XCTAssertTrue(SearchEngine.Mode.dictation.isHistoryBrowser)
        XCTAssertTrue(SearchEngine.Mode.clipboard.isHistoryBrowser)
        XCTAssertFalse(SearchEngine.Mode.applications.isHistoryBrowser)
    }

    /// The launcher itself still learns.
    func testApplicationsStillRankByLearnedUse() {
        let apps = ["Terminal", "TextEdit"].map { name in
            SearchItem(
                id: "app:\(name)", title: name, subtitle: "", kind: .application,
                icon: .symbol("app"), action: .openURL(URL(fileURLWithPath: "/")),
                weight: 1, score: 10)
        }
        let ranked = SearchEngine.rank(
            apps, boost: { $0 == "app:TextEdit" ? 50 : 0 }, isPrediction: false)
        XCTAssertEqual(ranked.first?.title, "TextEdit")
    }
}
