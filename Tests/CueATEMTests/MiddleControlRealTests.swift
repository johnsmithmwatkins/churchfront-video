import XCTest
import CueATEM

/// Moves a REAL gimbal through the real Middle Control on this Mac. Skipped unless you ask
/// for it, so a normal `swift test` never moves a camera:
///
///     CUEVIDEO_MC_REAL=4 swift test --filter MiddleControlRealTests
///
/// The number is the Middle Control camera to move (it should be a Pocket 6K + 24-105 for
/// the lens numbers below to be right). Clear the stage and watch the camera first.
final class MiddleControlRealTests: XCTestCase {

    override func tearDown() { UserDefaults.standard.removeObject(forKey: "ptzCameras") }

    private func wait(_ seconds: Double, until: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    func testSlowPushAndPanThenBack() throws {
        guard let raw = ProcessInfo.processInfo.environment["CUEVIDEO_MC_REAL"], let n = Int(raw) else {
            throw XCTSkip("set CUEVIDEO_MC_REAL=<camera number> to move a real gimbal")
        }
        var c = PTZCamera()
        c.name = "Cam \(n)"; c.host = "127.0.0.1"; c.port = 11580; c.proto = .middleControl
        c.mcCamera = n; c.gimbal = .pocket6K24105
        let ptz = PTZController(load: false)
        ptz.cameras = [c]
        defer { ptz.stopDrive(camera: c.id); ptz.zoom(0, camera: c.id); wait(0.5) }
        wait(5) { ptz.online.contains(c.id) }
        try XCTSkipUnless(ptz.online.contains(c.id), "camera \(n) isn't online in Middle Control")
        wait(0.5)

        func read() -> PTZPosition? {
            var p: PTZPosition?
            ptz.readPosition(camera: c.id) { p = $0 }
            wait(1) { p != nil }
            return p
        }
        func log(_ label: String, _ seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if let p = read() {
                    print(String(format: "%@ pan %.2f deg  tilt %.2f deg  view %.1f deg", label,
                                 Double(p.pan) / 100, Double(p.tilt) / 100, Double(p.zoom) / 100))
                }
                wait(0.5)
            }
        }

        let start = try XCTUnwrap(read())
        print("start:", start)
        // 3 degrees right, angle of view 15% narrower: a gentle push and pan.
        let target = PTZPosition(pan: start.pan + 300, tilt: start.tilt, zoom: Int(Double(start.zoom) * 0.85))
        ptz.autoGlide(to: target, seconds: 5, camera: c.id)
        log("out ", 7)
        let mid = try XCTUnwrap(read())
        print("arrived:", mid, "target:", target)

        ptz.autoGlide(to: start, seconds: 5, camera: c.id)
        log("back", 7)
        let end = try XCTUnwrap(read())
        print("end:", end, "start was:", start)

        XCTAssertEqual(Double(mid.pan), Double(target.pan), accuracy: 120, "pan reached about 3 degrees right")
        XCTAssertEqual(Double(end.pan), Double(start.pan), accuracy: 120, "back where it started")
        XCTAssertEqual(Double(end.tilt), Double(start.tilt), accuracy: 120)
    }
}
