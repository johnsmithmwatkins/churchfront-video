import XCTest
import CueATEM

/// Runs the real Middle Control link against Tools/fake_middlecontrol.py on a spare port
/// (never 11580, where the real Middle Control listens), so nothing real can move.
final class MiddleControlLinkTests: XCTestCase {
    private var fake: Process?
    private var output = ""
    private let lock = NSLock()
    private let port: UInt16 = 11599

    override func setUpWithError() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tools/fake_middlecontrol.py")
        guard FileManager.default.fileExists(atPath: "/usr/bin/python3") else { throw XCTSkip("no python3") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-u", script.path, String(port), "1,2,4"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            self?.lock.lock(); self?.output += s; self?.lock.unlock()
        }
        try p.run()
        fake = p
        wait(3) { self.log.contains("fake Middle Control on") }
    }

    override func tearDown() {
        fake?.terminate()
        fake = nil
        UserDefaults.standard.removeObject(forKey: "ptzCameras")
    }

    private var log: String { lock.lock(); defer { lock.unlock() }; return output }

    private func wait(_ seconds: Double, until: () -> Bool = { false }) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    private func camera(_ n: Int, _ g: GimbalSetup) -> PTZCamera {
        var c = PTZCamera()
        c.name = "Cam \(n)"; c.host = "127.0.0.1"; c.port = port; c.proto = .middleControl
        c.mcCamera = n; c.gimbal = g
        return c
    }

    func testJoystickMovesAndStopsTheRightGimbal() {
        let cam2 = camera(2, .pocket6K70200)
        let ptz = PTZController(load: false)
        ptz.cameras = [cam2]
        wait(4) { ptz.online.contains(cam2.id) }
        XCTAssertTrue(ptz.online.contains(cam2.id), "camera comes online from the feed")
        XCTAssertTrue(log.contains(">> FEED_ALL1"))

        ptz.drive(x: 0.6, y: 0, camera: cam2.id)
        wait(0.6)
        ptz.stopDrive(camera: cam2.id)
        wait(0.8)
        XCTAssertTrue(log.contains(">> PAN_R@C2"), log)
        XCTAssertTrue(log.contains(">> PAN_IDLE@C2"), log)
        XCTAssertTrue(log.contains(">> PTS"), log)
        XCTAssertFalse(log.contains("@C1") || log.contains("@C4"), "only camera 2 is touched")

        var pos: PTZPosition?
        ptz.readPosition(camera: cam2.id) { pos = $0 }
        wait(1) { pos != nil }
        XCTAssertNotNil(pos)
        XCTAssertGreaterThan(pos?.pan ?? 0, 0, "panned right")
        // Zoom 0 on a 70-200 on a Pocket 6K is about 18.7 degrees across.
        XCTAssertEqual(Double(pos?.zoom ?? 0) / 100, 18.7, accuracy: 0.3)
    }

    func testGlideSelectsTheCameraAndTimesTheMove() {
        let cam4 = camera(4, .pocket6K24105)
        let ptz = PTZController(load: false)
        ptz.cameras = [cam4]
        wait(4) { ptz.online.contains(cam4.id) }

        let target = PTZPosition(pan: 1500, tilt: -300, zoom: 2500)  // 15 deg right, 3 down, 25 deg view
        ptz.autoGlide(to: target, seconds: 1.0, camera: cam4.id)
        wait(0.5)
        XCTAssertTrue(log.contains(">> CAM4"), log)
        XCTAssertTrue(log.contains(";1.00"), log)
        wait(1.5)

        var pos: PTZPosition?
        ptz.readPosition(camera: cam4.id) { pos = $0 }
        wait(1) { pos != nil }
        XCTAssertEqual(Double(pos?.pan ?? 0), 1500, accuracy: 15)
        XCTAssertEqual(Double(pos?.tilt ?? 0), -300, accuracy: 15)
        XCTAssertEqual(Double(pos?.zoom ?? 0), 2500, accuracy: 30)
    }

    func testRemovingTheCameraStopsIt() {
        let cam1 = camera(1, .pocket4KOlympus40150)
        let ptz = PTZController(load: false)
        ptz.cameras = [cam1]
        wait(4) { ptz.online.contains(cam1.id) }
        ptz.zoom(0.5, camera: cam1.id)
        wait(0.4)
        ptz.cameras = []
        wait(0.8)
        XCTAssertTrue(log.contains(">> ZOOM+@C1"), log)
        XCTAssertTrue(log.contains(">> Z0@C1"), "a camera going away is never left zooming")
    }
}
