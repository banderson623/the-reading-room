import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Zoom")
struct ZoomLadderTests {
    @Test("Zooming in from 100% makes the page bigger")
    func zoomInGrows() {
        // The original bug: the first ⌘+ shrank the page to 50% and stuck there.
        let zoomed = ZoomLadder.next(above: 1.0)
        #expect(zoomed > 1.0)
        #expect(zoomed == 1.15)
    }

    @Test("Zooming out from 100% makes the page smaller")
    func zoomOutShrinks() {
        let zoomed = ZoomLadder.next(below: 1.0)
        #expect(zoomed < 1.0)
        #expect(zoomed == 0.85)
    }

    @Test("Every step moves, and in the right direction")
    func everyStepMoves() {
        var level = ZoomLadder.minimum
        var seen = [level]
        while level < ZoomLadder.maximum {
            let next = ZoomLadder.next(above: level)
            #expect(next > level, "stalled at \(level)")
            level = next
            seen.append(level)
        }
        #expect(seen == ZoomLadder.levels)
    }

    @Test("Zooming stops at the ends instead of running away")
    func clampsAtTheEnds() {
        #expect(ZoomLadder.next(above: ZoomLadder.maximum) == ZoomLadder.maximum)
        #expect(ZoomLadder.next(below: ZoomLadder.minimum) == ZoomLadder.minimum)
        #expect(ZoomLadder.next(above: 99) == ZoomLadder.maximum)
        #expect(ZoomLadder.next(below: 0.01) == ZoomLadder.minimum)
    }

    @Test("In then out returns to where it started")
    func roundTrip() {
        for level in ZoomLadder.levels.dropFirst().dropLast() {
            #expect(ZoomLadder.next(below: ZoomLadder.next(above: level)) == level)
            #expect(ZoomLadder.next(above: ZoomLadder.next(below: level)) == level)
        }
    }

    @Test("A level between steps snaps to the neighbouring one")
    func betweenSteps() {
        #expect(ZoomLadder.next(above: 1.05) == 1.15)
        #expect(ZoomLadder.next(below: 1.05) == 1.0)
    }

    @Test("A stored value from anywhere is brought into range")
    func clamping() {
        #expect(ZoomLadder.clamp(0.1) == ZoomLadder.minimum)
        #expect(ZoomLadder.clamp(10) == ZoomLadder.maximum)
        #expect(ZoomLadder.clamp(1.3) == 1.3)
    }

    @Test("Levels read as whole percentages")
    func percentages() {
        #expect(ZoomLadder.percent(1.0) == "100%")
        #expect(ZoomLadder.percent(0.67) == "67%")
        #expect(ZoomLadder.percent(1.15) == "115%")
        #expect(ZoomLadder.percent(3.0) == "300%")
    }

    @Test("100% is on the ladder, so Actual Size is reachable by stepping")
    func includesActualSize() {
        #expect(ZoomLadder.levels.contains(1.0))
        #expect(ZoomLadder.levels == ZoomLadder.levels.sorted())
    }
}
