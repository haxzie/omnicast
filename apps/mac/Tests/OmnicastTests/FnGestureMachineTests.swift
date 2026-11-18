import XCTest

@testable import Omnicast

final class FnGestureMachineTests: XCTestCase {
    func testHoldStartsAndReleaseFinishes() {
        var machine = FnGestureMachine()
        XCTAssertEqual(machine.fnPressed(at: 0), .start)
        XCTAssertEqual(machine.fnReleased(at: 1.2), .finish)
        XCTAssertEqual(machine.state, .idle)
    }

    func testTapLatchesAndSecondTapFinishes() {
        var machine = FnGestureMachine()
        XCTAssertEqual(machine.fnPressed(at: 0), .start)
        // Released inside the tap window: keep recording hands-free.
        XCTAssertEqual(machine.fnReleased(at: 0.15), .none)
        XCTAssertEqual(machine.state, .latched)

        XCTAssertEqual(machine.fnPressed(at: 4), .finish)
        XCTAssertEqual(machine.state, .idle)
        // The release of that second tap must not start anything.
        XCTAssertEqual(machine.fnReleased(at: 4.1), .none)
    }

    func testKeyRepeatWhileHeldDoesNotRestart() {
        var machine = FnGestureMachine()
        XCTAssertEqual(machine.fnPressed(at: 0), .start)
        XCTAssertEqual(machine.fnPressed(at: 0.05), .none)
    }

    func testChordWithAnotherKeyCancels() {
        var machine = FnGestureMachine()
        _ = machine.fnPressed(at: 0)
        // fn+F3 and friends are not dictation.
        XCTAssertEqual(machine.otherKeyPressed(isEscape: false), .cancel)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.fnReleased(at: 0.2), .none)
    }

    func testTypingDuringHandsFreeDoesNotCancelButEscapeDoes() {
        var machine = FnGestureMachine()
        _ = machine.fnPressed(at: 0)
        _ = machine.fnReleased(at: 0.1)

        XCTAssertEqual(machine.otherKeyPressed(isEscape: false), .none)
        XCTAssertEqual(machine.state, .latched)
        XCTAssertEqual(machine.otherKeyPressed(isEscape: true), .cancel)
        XCTAssertEqual(machine.state, .idle)
    }

    func testReleaseWithoutPressIsIgnored() {
        var machine = FnGestureMachine()
        XCTAssertEqual(machine.fnReleased(at: 3), .none)
    }
}

