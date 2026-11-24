import XCTest
import CueATEM

/// Middle Control's wire format and the unit conversions, checked without any hardware.
final class MiddleControlTests: XCTestCase {

    func testCommandsMatchTheCompanionModule() {
        XCTAssertEqual(MCCommand.pan(-1, cam: 2), "PAN_L@C2")
        XCTAssertEqual(MCCommand.pan(1, cam: 2), "PAN_R@C2")
        XCTAssertEqual(MCCommand.pan(0, cam: 2), "PAN_IDLE@C2")
        XCTAssertEqual(MCCommand.tilt(1, cam: 4), "TILT_U@C4")
        XCTAssertEqual(MCCommand.tilt(-1, cam: 4), "TILT_D@C4")
        XCTAssertEqual(MCCommand.tilt(0, cam: 4), "TILT_IDLE@C4")
        XCTAssertEqual(MCCommand.zoom(1, cam: 1), "ZOOM+@C1")
        XCTAssertEqual(MCCommand.zoom(-1, cam: 1), "ZOOM-@C1")
        XCTAssertEqual(MCCommand.zoom(0, cam: 1), "Z0@C1")
        XCTAssertEqual(MCCommand.select(3), "CAM3")
        XCTAssertEqual(MCCommand.recall(5, cam: 2), "PRESET5C2")
        XCTAssertEqual(MCCommand.store(5, cam: 2), "SPRESET5C2")
    }

    func testSpeedKeepsTenthsOnlyBelowTenPercent() {
        XCTAssertEqual(MCCommand.panTiltSpeed(2.5, cam: 1), "PTS2.5@C1")
        XCTAssertEqual(MCCommand.panTiltSpeed(3, cam: 1), "PTS3@C1")
        XCTAssertEqual(MCCommand.panTiltSpeed(42.6, cam: 1), "PTS43@C1")
        XCTAssertEqual(MCCommand.panTiltSpeed(250, cam: 1), "PTS100@C1")
        XCTAssertEqual(MCCommand.zoomSpeed(-5, cam: 1), "ZS0@C1")
    }

    func testGlideLeavesUnsetAxesEmpty() {
        XCTAssertEqual(MCCommand.glide(pan: 100, tilt: -20, zoom: 2048, seconds: 6),
                       "aGLOB;aP100;aT-20;aR;aZ2048;6.00")
        XCTAssertEqual(MCCommand.glide(pan: 100, tilt: nil, zoom: nil, seconds: 0.5),
                       "aGLOB;aP100;aT;aR;aZ;0.50")
    }

    func testFrameParsing() throws {
        let f = try XCTUnwrap(MCFrame.parse("{CAM2;SEL1;aPAN-120;aTILT35;aROLL0;aZOOM2048;aISO800;aI2.8;CAM_CON_LIST[1,2,4];APCR_CON_LIST[1,2]}"))
        XCTAssertEqual(f.cam, 2)
        XCTAssertEqual(f.selected, true)
        XCTAssertEqual(f.pan, -120)
        XCTAssertEqual(f.tilt, 35)
        XCTAssertEqual(f.zoom, 2048)
        XCTAssertEqual(f.iso, 800)
        XCTAssertEqual(f.iris, 2.8)
        XCTAssertEqual(f.cameras, [1, 2, 4])
        XCTAssertEqual(f.gimbals, [1, 2])
        XCTAssertNil(MCFrame.parse("{}"))
        // Unknown tokens are ignored.
        XCTAssertEqual(MCFrame.parse("{CAM1;BRANG_RUN1;aUI3}")?.cam, 1)
    }

    func testLensAngleOfView() {
        let g = GimbalSetup.pocket6K24105
        // 23.1 mm wide at 24 mm is about 51.4 degrees; at 105 mm about 12.6.
        XCTAssertEqual(g.fov(focal: 24), 51.4, accuracy: 0.2)
        XCTAssertEqual(g.fov(focal: 105), 12.5, accuracy: 0.2)
        XCTAssertEqual(g.focal(zoom: 0), 24, accuracy: 0.01)
        XCTAssertEqual(g.focal(zoom: 4096), 105, accuracy: 0.01)
        XCTAssertEqual(g.zoom(focal: g.focal(zoom: 1500)), 1500, accuracy: 1)
    }

    func testPositionsRoundTrip() {
        var g = GimbalSetup.pocket6K70200
        for invert in [false, true] {
            g.invertPan = invert
            let p = g.position(pan: 512, tilt: -100, zoom: 1000)
            let c = g.counts(p)
            XCTAssertEqual(c.pan, 512, accuracy: 1)
            XCTAssertEqual(c.tilt, -100, accuracy: 1)
            XCTAssertEqual(c.zoom, 1000, accuracy: 3)
        }
        // 2048 counts is 180 degrees by default.
        XCTAssertEqual(GimbalSetup().position(pan: 1024, tilt: 0, zoom: 0).pan, 9000)
    }

    func testSpeedConversion() {
        let g = GimbalSetup()  // 60 degrees a second at 100
        XCTAssertEqual(g.percent(hundredthsPerSecond: 3000), 50, accuracy: 0.01)
        XCTAssertEqual(g.percent(hundredthsPerSecond: -3000), 50, accuracy: 0.01)
        XCTAssertEqual(g.percent(hundredthsPerSecond: 999_999), 100)
    }

    func testOldConfigWithoutGimbalStillLoads() throws {
        let json = #"{"name":"Cam 2","host":"127.0.0.1","proto":"middleControl","mcCamera":2,"gimbal":{"focalWide":70,"focalTele":200}}"#
        let c = try JSONDecoder().decode(PTZCamera.self, from: Data(json.utf8))
        XCTAssertEqual(c.proto, .middleControl)
        XCTAssertEqual(c.port, 11580)
        XCTAssertEqual(c.mcCamera, 2)
        XCTAssertEqual(c.gimbal?.focalTele, 200)
        XCTAssertEqual(c.gimbal?.sensorWidth, 23.10)
    }
}
