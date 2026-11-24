import XCTest
import CueATEM

/// A small repeatable random source, so planned shots are the same every run.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class CreativeShotsTests: XCTestCase {
    let framing = PTZPosition(pan: 1000, tilt: -200, zoom: 2000)  // 10 deg right, 20 deg view

    func testTempoSetsTheFeel() {
        XCTAssertEqual(SongFeel.from(bpm: 68), .slow)
        XCTAssertEqual(SongFeel.from(bpm: 100), .medium)
        XCTAssertEqual(SongFeel.from(bpm: 140), .fast)
        XCTAssertEqual(SongFeel.from(bpm: nil), .medium)
    }

    func testPushInGoesFromWideToTightThroughTheFraming() {
        var rng = SeededRandom(state: 1)
        let s = ShotPlanner().plan(framing: framing, subject: .person, feel: .slow, move: .pushIn, using: &rng)
        XCTAssertGreaterThan(s.start.zoom, framing.zoom)
        XCTAssertLessThan(s.end.zoom, framing.zoom)
        XCTAssertEqual(s.start.pan, framing.pan)
        XCTAssertEqual(s.end.pan, framing.pan)
        // The framing sits in the middle of the move (geometrically).
        XCTAssertEqual(sqrt(Double(s.start.zoom) * Double(s.end.zoom)), Double(framing.zoom), accuracy: 2)
    }

    func testPanCrossesTheFraming() {
        var rng = SeededRandom(state: 2)
        let s = ShotPlanner().plan(framing: framing, subject: .instrument, feel: .medium, move: .panRight, using: &rng)
        XCTAssertLessThan(s.start.pan, framing.pan)
        XCTAssertGreaterThan(s.end.pan, framing.pan)
        XCTAssertEqual(s.start.zoom, s.end.zoom)
    }

    func testInstrumentShotsAreBrief() {
        var rng = SeededRandom(state: 3)
        let p = ShotPlanner()
        for feel in SongFeel.allCases {
            for _ in 0..<50 {
                let inst = p.plan(framing: framing, subject: .instrument, feel: feel, using: &rng)
                XCTAssertLessThanOrEqual(inst.holdSeconds, 6)
                XCTAssertNotEqual(inst.move, .hold, "instrument shots always move")
            }
        }
    }

    func testSlowSongsFadeSlowlyAndFastSongsMostlyCut() {
        var rng = SeededRandom(state: 4)
        let p = ShotPlanner()
        for _ in 0..<50 {
            let t = p.transition(.slow, &rng)
            XCTAssertGreaterThanOrEqual(t.frames, 89)   // at least 3 s
            XCTAssertLessThanOrEqual(t.frames, 240)     // at most 8 s
        }
        let cuts = (0..<200).filter { _ in p.transition(.fast, &rng).isCut }.count
        XCTAssertGreaterThan(cuts, 140)
    }

    func testTheCameraKeepsMovingPastTheCutAway() {
        var rng = SeededRandom(state: 5)
        let s = ShotPlanner().plan(framing: framing, subject: .person, feel: .slow, move: .pullOut, using: &rng)
        XCTAssertGreaterThan(s.moveSeconds, s.holdSeconds)
    }

    func testMovesStayInsideTheLensLimits() {
        var rng = SeededRandom(state: 6)
        let tight = PTZPosition(pan: 0, tilt: 0, zoom: 320)  // 3.2 degrees
        let s = ShotPlanner().plan(framing: tight, subject: .instrument, feel: .slow, move: .pushIn, using: &rng)
        XCTAssertGreaterThanOrEqual(s.end.zoom, 300)
    }

    func testStyleLoadsWithPartsLeftOut() throws {
        let s = try JSONDecoder().decode(ProductionStyle.self, from: Data(#"{"fastFadeShare":0.3}"#.utf8))
        XCTAssertEqual(s.fastFadeShare, 0.3)
        XCTAssertEqual(s.instrumentZoomFactor, 1.6)
    }
}
