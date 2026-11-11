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

final class TeardropShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 120, height: 40)

    func testMorphExtremesStayInsideTheirFrame() {
        for morph in [0.0, 0.5, 1.0] {
            let bounds = TeardropShape(morph: morph).path(in: rect).boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.01, "morph \(morph)")
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.01, "morph \(morph)")
            XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.01, "morph \(morph)")
            XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.01, "morph \(morph)")
        }
    }

    func testDropIsPointedAtTheTipAndCapsuleIsNot() {
        // Measured a hair below the top edge, at the frames the droplet
        // actually uses: a point when closed, nearly full width when open.
        let closed = CGRect(x: 0, y: 0, width: 26, height: 36)
        let open = CGRect(x: 0, y: 0, width: 128, height: 34)
        XCTAssertLessThan(width(of: TeardropShape(morph: 0), in: closed, at: 1), 5)
        XCTAssertGreaterThan(width(of: TeardropShape(morph: 1), in: open, at: 1), 90)
    }

    /// Horizontal extent of the filled shape at a given height.
    private func width(of shape: TeardropShape, in rect: CGRect, at y: CGFloat) -> CGFloat {
        let path = shape.path(in: rect).cgPath
        let hits = stride(from: rect.minX, through: rect.maxX, by: 0.25)
            .filter { path.contains(CGPoint(x: $0, y: y)) }
        guard let first = hits.first, let last = hits.last else { return 0 }
        return last - first
    }
}
