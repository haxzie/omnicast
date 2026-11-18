import XCTest

@testable import Omnicast

/// The launcher closing itself the moment it opened was a focus race, so the
/// rule that decides it is kept free of any window and tested here instead of
/// by driving the real menu bar.
final class LauncherFocusTests: XCTestCase {
    private typealias Panel = LauncherPanel

    /// Opening from the menu-bar menu: the panel wins key, then AppKit gives
    /// activation back to the app behind as the menu tears down.
    func testFlickerJustAfterPresentingRetakesFocus() {
        XCTAssertEqual(
            Panel.outcomeOnResign(
                visible: true, key: false, dismissing: false, hasHeldKey: true,
                sincePresented: 0.3),
            .retakeKey)
    }

    func testClickingAwayLaterDismisses() {
        XCTAssertEqual(
            Panel.outcomeOnResign(
                visible: true, key: false, dismissing: false, hasHeldKey: true,
                sincePresented: 4),
            .dismiss)
    }

    /// The boundary belongs to the dismiss side: past the grace period a lost
    /// key is taken at face value.
    func testGraceBoundary() {
        XCTAssertEqual(
            Panel.outcomeOnResign(
                visible: true, key: false, dismissing: false, hasHeldKey: true,
                sincePresented: Panel.focusGrace - 0.01),
            .retakeKey)
        XCTAssertEqual(
            Panel.outcomeOnResign(
                visible: true, key: false, dismissing: false, hasHeldKey: true,
                sincePresented: Panel.focusGrace),
            .dismiss)
    }

    /// A panel that never managed to take key must not read its own failure to
    /// focus as the user clicking away.
    func testNeverHeldKeyIsIgnored() {
        XCTAssertEqual(
            Panel.outcomeOnResign(
                visible: true, key: false, dismissing: false, hasHeldKey: false,
                sincePresented: 5),
            .ignore)
    }

    func testHiddenOrFocusedOrClosingPanelIsIgnored() {
        for (visible, key, dismissing) in [
            (false, false, false),  // already gone
            (true, true, false),  // has focus after all
            (true, false, true),  // a dismiss is already in flight
        ] {
            XCTAssertEqual(
                Panel.outcomeOnResign(
                    visible: visible, key: key, dismissing: dismissing, hasHeldKey: true,
                    sincePresented: 5),
                .ignore,
                "visible=\(visible) key=\(key) dismissing=\(dismissing)")
        }
    }
}
