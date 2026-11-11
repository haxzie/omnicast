import SwiftUI
import XCTest

@testable import Omnicast

final class FuzzyMatcherTests: XCTestCase {
    func testRejectsNonSubsequence() {
        XCTAssertNil(FuzzyMatcher.match(needle: "xyz", haystack: "Safari"))
    }

    func testEmptyNeedleMatches() {
        XCTAssertNotNil(FuzzyMatcher.match(needle: "", haystack: "Safari"))
    }

    func testExactMatchBeatsPrefixBeatsScattered() {
        let exact = FuzzyMatcher.match(needle: "mail", haystack: "Mail")!.score
        let prefix = FuzzyMatcher.match(needle: "mail", haystack: "Mailbox Importer")!.score
        let scattered = FuzzyMatcher.match(needle: "mail", haystack: "Musical Instruments")?.score ?? -.infinity
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, scattered)
    }

    func testWordStartsOutrankMidWordMatches() {
        let wordStart = FuzzyMatcher.match(needle: "code", haystack: "Visual Studio Code")!.score
        let midWord = FuzzyMatcher.match(needle: "code", haystack: "Xcode Decoder")!.score
        XCTAssertGreaterThan(wordStart, midWord)
    }

    func testReportsMatchedIndicesForHighlighting() {
        let match = FuzzyMatcher.match(needle: "saf", haystack: "Safari")!
        XCTAssertEqual(match.indices, [0, 1, 2])
    }

    func testPrefersConsecutiveRuns() {
        let consecutive = FuzzyMatcher.match(needle: "term", haystack: "Terminal")!.score
        let split = FuzzyMatcher.match(needle: "term", haystack: "Tea Rooms Manager")?.score ?? -.infinity
        XCTAssertGreaterThan(consecutive, split)
    }
}

final class WhisperOutputTests: XCTestCase {
    func testStripsSilenceMarkers() {
        XCTAssertEqual(
            WhisperCLITranscriber.clean(" [BLANK_AUDIO] Ship the   glass panel. "),
            "Ship the glass panel.")
    }
}

final class ApplicationPathTests: XCTestCase {
    func testCryptexAppsAreShownWhereUsersExpectThem() {
        // Safari really lives in a sealed cryptex volume; /Applications is
        // where the symlink — and the user — expect it.
        let safari = URL(
            fileURLWithPath:
                "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app")
        XCTAssertEqual(ApplicationProvider.displayPath(of: safari), "/Applications")
    }

    func testOrdinaryPathsAreLeftAlone() {
        XCTAssertEqual(
            ApplicationProvider.displayPath(of: URL(fileURLWithPath: "/Applications/Slack.app")),
            "/Applications")
        XCTAssertEqual(
            ApplicationProvider.displayPath(
                of: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")),
            "/System/Applications/Utilities")
    }
}

final class LauncherChromeTests: XCTestCase {
    /// The window clips whatever is drawn outside it, so the hosted view has to
    /// carry a transparent margin wide enough for the glass panel's shadow —
    /// otherwise the shadow is sliced off at the corners.
    @MainActor
    func testHostedLauncherLeavesRoomForItsShadow() {
        let glass = Color.clear.frame(width: 200, height: 100).glassPanel()
        let padded = glass.padding(LauncherView.shadowInset)

        let bare = NSHostingView(rootView: glass).fittingSize
        let withMargin = NSHostingView(rootView: padded).fittingSize

        XCTAssertEqual(bare.width, 200, accuracy: 0.5)
        XCTAssertEqual(withMargin.width, 200 + LauncherView.shadowInset * 2, accuracy: 0.5)
        XCTAssertEqual(withMargin.height, 100 + LauncherView.shadowInset * 2, accuracy: 0.5)
    }

    func testPanelWidthAccountsForBothMargins() {
        XCTAssertEqual(
            LauncherView.panelWidth, LauncherView.width + LauncherView.shadowInset * 2)
    }
}
