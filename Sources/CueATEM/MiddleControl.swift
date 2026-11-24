import Foundation
import Network

// Middle Control (MiddleThings): gimbal cameras.
//
// A camera on a DJI RS-series gimbal with a MiddleThings APC-R / APC-R Mini is driven
// through the Middle Control app on a Mac, which talks to the gimbal (CANBUS) and the
// camera (Bluetooth). Middle Control takes outside commands over TCP on port 11580,
// newline-terminated ASCII, the same interface the official Companion module uses
// (github.com/bitfocus/companion-module-middlethings-middlecontrol):
//
//   CAM<n>                         select camera n in Middle Control
//   PAN_L / PAN_R / PAN_IDLE       continuous pan, stop     (+ "@C<n>" to target a camera)
//   TILT_U / TILT_D / TILT_IDLE    continuous tilt, stop
//   ZOOM+ / ZOOM- / Z0             continuous zoom (lens motor), stop
//   PTS<0-100> / ZS<0-100>         pan/tilt speed and zoom speed (tenths below 10% on 4.1+)
//   aGLOB;aP<p>;aT<t>;aR<r>;aZ<z>;<seconds>
//                                  move the SELECTED camera to an absolute position over
//                                  that many seconds. Pan, tilt, roll -2048..2048, zoom
//                                  0..4096. An empty field leaves that axis alone.
//   PRESET<n>C<cam> / SPRESET<n>C<cam>   recall / save a Middle Control preset
//   AUTOFOCUS, FOCUS_IN / FOCUS_OUT / FOCUS_IDLE, RECENTER, GIMBALWAKE, GIMBALSLEEP
//   FEED_ALL1                      (4.1+) send a status frame for every camera, not only
//                                  the selected one
//
// Middle Control answers with "{tok;tok;...}\n" frames about every 200 ms: CAM<n>,
// aPAN, aTILT, aROLL, aZOOM, CAM_CON_LIST[..], APCR_CON_LIST[..] and camera settings.
//
// Units. CueVideo's tracking and stage scan work in Canon's units: pan and tilt in
// hundredths of a degree, zoom as the horizontal angle of view in hundredths of a degree.
// This link converts both ways using the camera's `GimbalSetup`: how many Middle Control
// counts make one degree, the top speed, and the lens (focal range and sensor width).
// Those defaults are a best estimate; calibrate them on the real rig (see `GimbalSetup`).

/// How one gimbal camera turns and what its lens sees. All optional in the config file.
public struct GimbalSetup: Codable, Hashable {
    /// Middle Control position counts in one degree of pan or tilt. The API runs -2048 to
    /// 2048; the default assumes that spans -180 to 180 degrees. Calibrate: note aPAN, turn
    /// the gimbal a measured 90 degrees, note aPAN again, divide the change by 90.
    public var countsPerDegree: Double = 2048.0 / 180.0
    /// Degrees a second the gimbal turns at pan/tilt speed 100. Auto tracking also learns
    /// the real figure as it runs, so this only needs to be in the right range.
    public var maxDegreesPerSecond: Double = 60
    /// Lens focal length at the zoom motor's wide and tele ends (zoom 0 and 4096), in mm.
    /// Equal for a prime, or a zoom lens with no motor on the zoom ring.
    public var focalWide: Double = 24
    public var focalTele: Double = 105
    /// Width of the part of the sensor that makes the picture, in mm. Pocket 6K (6K 2.4:1
    /// or 16:9 crop modes are narrower) 23.10, Pocket 4K 18.96, full frame 36. Divide by a
    /// Speed Booster's factor (0.71) and multiply in any extra crop.
    public var sensorWidth: Double = 23.10
    /// Mirror the axes if the gimbal is mounted so right or up come out backwards.
    public var invertPan = false
    public var invertTilt = false
    /// What sits on the gimbal, for people reading the setup (and for Claude).
    public var note: String?

    public init() {}

    private enum Keys: String, CodingKey {
        case countsPerDegree, maxDegreesPerSecond, focalWide, focalTele, sensorWidth, invertPan, invertTilt, note
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = GimbalSetup.make()
        countsPerDegree = try c.decodeIfPresent(Double.self, forKey: .countsPerDegree) ?? d.countsPerDegree
        maxDegreesPerSecond = try c.decodeIfPresent(Double.self, forKey: .maxDegreesPerSecond) ?? d.maxDegreesPerSecond
        focalWide = try c.decodeIfPresent(Double.self, forKey: .focalWide) ?? d.focalWide
        focalTele = try c.decodeIfPresent(Double.self, forKey: .focalTele) ?? d.focalTele
        sensorWidth = try c.decodeIfPresent(Double.self, forKey: .sensorWidth) ?? d.sensorWidth
        invertPan = try c.decodeIfPresent(Bool.self, forKey: .invertPan) ?? false
        invertTilt = try c.decodeIfPresent(Bool.self, forKey: .invertTilt) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
    private static func make() -> GimbalSetup { GimbalSetup() }

    /// Common bodies and lenses, so setup is a pick from a list.
    public static func preset(sensor: Double, wide: Double, tele: Double, note: String) -> GimbalSetup {
        var g = GimbalSetup(); g.sensorWidth = sensor; g.focalWide = wide; g.focalTele = tele; g.note = note; return g
    }
    public static let pocket4KOlympus40150 = preset(sensor: 18.96, wide: 40, tele: 150, note: "Pocket 4K + Olympus 40-150")
    public static let pocket6K70200 = preset(sensor: 23.10, wide: 70, tele: 200, note: "Pocket 6K + Canon 70-200")
    public static let pocket6K24105 = preset(sensor: 23.10, wide: 24, tele: 105, note: "Pocket 6K + Canon 24-105")

    // MARK: Conversions

    static let zoomMax = 4096.0
    static let rad = Double.pi / 180

    /// Horizontal angle of view in degrees at a focal length.
    public func fov(focal: Double) -> Double { 2 * atan(sensorWidth / (2 * max(1, focal))) / Self.rad }

    /// Focal length at a zoom motor position. A zoom ring is close to even steps in the
    /// logarithm of focal length, so this interpolates geometrically. Calibrate by checking
    /// the angle of view at the middle of the range if shots land too tight or too wide.
    public func focal(zoom: Int) -> Double {
        let t = min(1, max(0, Double(zoom) / Self.zoomMax))
        return focalWide * pow(focalTele / max(0.1, focalWide), t)
    }

    public func zoom(focal: Double) -> Int {
        guard focalTele > focalWide * 1.01 else { return 0 }
        let t = log(max(focalWide, min(focalTele, focal)) / focalWide) / log(focalTele / focalWide)
        return Int((t * Self.zoomMax).rounded())
    }

    public var fovRange: ClosedRange<Double> { fov(focal: focalTele)...fov(focal: focalWide) }

    /// Middle Control counts to CueVideo's position (hundredths of a degree; zoom as the
    /// angle of view in hundredths of a degree).
    public func position(pan: Double, tilt: Double, zoom: Double) -> PTZPosition {
        let p = pan / countsPerDegree * (invertPan ? -1 : 1)
        let t = tilt / countsPerDegree * (invertTilt ? -1 : 1)
        return PTZPosition(pan: Int((p * 100).rounded()), tilt: Int((t * 100).rounded()),
                           zoom: Int((fov(focal: focal(zoom: Int(zoom.rounded()))) * 100).rounded()))
    }

    /// CueVideo's position to Middle Control counts, clamped to the API's ranges.
    public func counts(_ p: PTZPosition) -> (pan: Int, tilt: Int, zoom: Int) {
        let pan = Double(p.pan) / 100 * countsPerDegree * (invertPan ? -1 : 1)
        let tilt = Double(p.tilt) / 100 * countsPerDegree * (invertTilt ? -1 : 1)
        // Angle of view back to focal length: f = w / (2 tan(fov/2)).
        let fovDeg = min(fovRange.upperBound, max(fovRange.lowerBound, Double(p.zoom) / 100))
        let f = sensorWidth / (2 * tan(fovDeg / 2 * Self.rad))
        return (Int(min(2048, max(-2048, pan.rounded()))), Int(min(2048, max(-2048, tilt.rounded()))), zoom(focal: f))
    }

    /// A speed in hundredths of a degree a second to Middle Control's 0-100 speed.
    public func percent(hundredthsPerSecond v: Int) -> Double {
        min(100, max(0.1, Double(abs(v)) / 100 / max(1, maxDegreesPerSecond) * 100))
    }
}

/// Builds Middle Control's wire commands. Pure, so the tests can check every byte.
public enum MCCommand {
    static func at(_ cmd: String, _ cam: Int) -> String { "\(cmd)@C\(cam)" }

    /// Pan/tilt speed with Middle Control 4.1's tenths below 10%, whole numbers above.
    public static func panTiltSpeed(_ percent: Double, cam: Int) -> String {
        let v = min(100, max(0, percent))
        let text: String
        if v < 10 {
            let tenths = (v * 10).rounded() / 10
            text = tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)
        } else {
            text = String(Int(v.rounded()))
        }
        return at("PTS" + text, cam)
    }
    public static func zoomSpeed(_ percent: Double, cam: Int) -> String {
        at("ZS\(Int(min(100, max(0, percent)).rounded()))", cam)
    }
    public static func pan(_ dir: Int, cam: Int) -> String { at(dir < 0 ? "PAN_L" : dir > 0 ? "PAN_R" : "PAN_IDLE", cam) }
    public static func tilt(_ dir: Int, cam: Int) -> String { at(dir > 0 ? "TILT_U" : dir < 0 ? "TILT_D" : "TILT_IDLE", cam) }
    public static func zoom(_ dir: Int, cam: Int) -> String { at(dir > 0 ? "ZOOM+" : dir < 0 ? "ZOOM-" : "Z0", cam) }
    public static func select(_ cam: Int) -> String { "CAM\(cam)" }

    /// Absolute move of the selected camera; nil axes are left alone.
    public static func glide(pan: Int?, tilt: Int?, zoom: Int?, seconds: Double) -> String {
        let s = String(format: "%.2f", max(0, seconds))
        return "aGLOB;aP\(pan.map(String.init) ?? "");aT\(tilt.map(String.init) ?? "");aR;aZ\(zoom.map(String.init) ?? "");\(s)"
    }
    public static func recall(_ n: Int, cam: Int) -> String { "PRESET\(n)C\(cam)" }
    public static func store(_ n: Int, cam: Int) -> String { "SPRESET\(n)C\(cam)" }
}

/// One status frame from Middle Control, as far as CueVideo needs it.
public struct MCFrame: Equatable {
    public var cam: Int?
    public var pan: Double?, tilt: Double?, roll: Double?, zoom: Double?
    public var selected: Bool?
    public var cameras: [Int]?      // CAM_CON_LIST
    public var gimbals: [Int]?      // APCR_CON_LIST
    public var iso: Double?, iris: Double?, shutter: Double?, wb: Double?

    /// Splits "{CAM2;aPAN-120;...}" into what it says. Unknown tokens are ignored, as the
    /// Companion module does, so newer Middle Control versions don't break anything.
    public static func parse(_ line: String) -> MCFrame? {
        var body = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("{") { body.removeFirst() }
        if body.hasSuffix("}") { body.removeLast() }
        guard !body.isEmpty else { return nil }
        var f = MCFrame()
        func num(_ s: Substring) -> Double? { Double(s.trimmingCharacters(in: .whitespaces)) }
        func list(_ s: Substring) -> [Int] {
            s.replacingOccurrences(of: "]", with: "").split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        for tok in body.split(separator: ";") {
            // Longest prefixes first, so CAM_CON_LIST is never read as CAM, aPAN never as aP.
            if tok.hasPrefix("CAM_CON_LIST[") { f.cameras = list(tok.dropFirst(13)) }
            else if tok.hasPrefix("APCR_CON_LIST[") { f.gimbals = list(tok.dropFirst(14)) }
            else if tok.hasPrefix("CAM"), f.cam == nil { f.cam = Int(tok.dropFirst(3)) }
            else if tok.hasPrefix("SEL") { f.selected = tok.dropFirst(3) == "1" }
            else if tok.hasPrefix("aPAN") { f.pan = num(tok.dropFirst(4)) }
            else if tok.hasPrefix("aTILT") { f.tilt = num(tok.dropFirst(5)) }
            else if tok.hasPrefix("aROLL") { f.roll = num(tok.dropFirst(5)) }
            else if tok.hasPrefix("aZOOM") { f.zoom = num(tok.dropFirst(5)) }
            else if tok.hasPrefix("aISO") { f.iso = num(tok.dropFirst(4)) }
            else if tok.hasPrefix("aSHUT") { f.shutter = num(tok.dropFirst(5)) }
            else if tok.hasPrefix("aWB") { f.wb = num(tok.dropFirst(3)) }
            else if tok.hasPrefix("aI"), !tok.hasPrefix("aISO") { f.iris = num(tok.dropFirst(2)) }
        }
        return f
    }
}

// MARK: - Connection to one Middle Control

/// One TCP connection to a Middle Control app, shared by every camera it drives. Reconnects
/// by itself, keeps the newest frame per camera, and sends commands in order.
final class MiddleControlHub {
    let host: String
    let port: UInt16
    private let queue: DispatchQueue
    private var conn: NWConnection?
    private var rx = ""
    private var stopped = true
    private(set) var connected = false
    /// Newest frame per camera number, and the time it came in.
    private(set) var latest: [Int: (frame: MCFrame, at: Date)] = [:]
    private(set) var connectedCameras: Set<Int>?
    private(set) var connectedGimbals: Set<Int>?
    /// The camera Middle Control has selected, as far as this connection last told it.
    private var selectedCam: Int?
    var listeners: [UUID: () -> Void] = [:]

    private static var hubs: [String: MiddleControlHub] = [:]
    private static let lock = NSLock()

    /// The one hub for this address, made on first use. Call on the PTZ queue.
    static func shared(host: String, port: UInt16, queue: DispatchQueue) -> MiddleControlHub {
        lock.lock(); defer { lock.unlock() }
        let key = "\(host):\(port)"
        if let h = hubs[key] { return h }
        let h = MiddleControlHub(host: host, port: port, queue: queue)
        hubs[key] = h
        return h
    }

    private init(host: String, port: UInt16, queue: DispatchQueue) {
        self.host = host; self.port = port; self.queue = queue
    }

    func attach(_ id: UUID, _ changed: @escaping () -> Void) {
        listeners[id] = changed
        if stopped { start() }
    }

    func detach(_ id: UUID) {
        listeners[id] = nil
        if listeners.isEmpty { stop() }
    }

    private func start() {
        stopped = false
        open()
    }

    private func stop() {
        stopped = true
        conn?.cancel(); conn = nil
        setConnected(false)
    }

    private func setConnected(_ on: Bool) {
        guard on != connected else { return }
        connected = on
        if !on { latest = [:]; connectedCameras = nil; connectedGimbals = nil; selectedCam = nil }
        notify()
    }

    private func notify() { for l in listeners.values { l() } }

    private func open() {
        guard !stopped, conn == nil, let p = NWEndpoint.Port(rawValue: port) else { return }
        let c = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        conn = c
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.setConnected(true)
                // Ask for a frame per camera (Middle Control 4.1+; older versions ignore it).
                self.write("FEED_ALL1")
                self.receive(c)
            case .failed, .cancelled:
                self.lost(c)
            case .waiting:
                // No route or refused: try again shortly rather than wait on the OS.
                self.lost(c)
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func lost(_ c: NWConnection) {
        guard conn === c else { return }
        c.cancel()
        conn = nil
        rx = ""
        setConnected(false)
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.open() }
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self, self.conn === c else { return }
            if let data, !data.isEmpty { self.take(String(decoding: data, as: UTF8.self)) }
            if done || err != nil { self.lost(c); return }
            self.receive(c)
        }
    }

    /// Frames can arrive split or several at once: buffer and split on newlines.
    private func take(_ chunk: String) {
        rx += chunk
        if rx.count > 1_048_576 { rx = "" ; return }
        var changed = false
        while let r = rx.firstIndex(of: "\n") {
            let line = String(rx[..<r])
            rx = String(rx[rx.index(after: r)...])
            guard let f = MCFrame.parse(line) else { continue }
            if let l = f.cameras { connectedCameras = Set(l) }
            if let l = f.gimbals { connectedGimbals = Set(l) }
            if let cam = f.cam {
                latest[cam] = (f, Date())
                if f.selected == true { selectedCam = cam }
            }
            changed = true
        }
        if changed { notify() }
    }

    private func write(_ cmd: String) {
        // Only printable ASCII goes out, so nothing can split one command into two.
        let safe = String(cmd.unicodeScalars.filter { $0.value >= 0x20 && $0.value <= 0x7E })
        guard !safe.isEmpty, let c = conn, connected else { return }
        c.send(content: Data((safe + "\n").utf8), completion: .contentProcessed { _ in })
    }

    func send(_ cmd: String) { write(cmd) }

    /// Absolute moves only act on Middle Control's selected camera, so select it first
    /// (Middle Control's own camera choice follows; turn its ATEM Link off so the switcher
    /// doesn't change it back mid-move).
    func sendToSelected(_ cam: Int, _ cmd: String) {
        if selectedCam != cam { write(MCCommand.select(cam)); selectedCam = cam }
        write(cmd)
    }

    func frame(_ cam: Int, maxAge: TimeInterval = 1.5) -> MCFrame? {
        guard let e = latest[cam], Date().timeIntervalSince(e.at) <= maxAge else { return nil }
        return e.frame
    }

    /// Whether the camera and its gimbal are both there, as far as Middle Control says.
    func isOnline(_ cam: Int) -> Bool {
        guard connected else { return false }
        if let g = connectedGimbals { return g.contains(cam) }
        if let c = connectedCameras { return c.contains(cam) }
        return true
    }
}

// MARK: - One gimbal camera

/// A camera on a gimbal, driven through Middle Control. `camera.host` is the Mac running
/// Middle Control (127.0.0.1 when CueVideo runs on the same Mac), `camera.mcCamera` the
/// camera's number in Middle Control.
final class MiddleControlLink: PTZLink {
    let camera: PTZCamera
    private let queue: DispatchQueue
    private let hub: MiddleControlHub
    private let token = UUID()
    private var setup: GimbalSetup { camera.gimbal ?? GimbalSetup() }
    private var cam: Int { camera.mcCamera ?? 1 }

    var onState: ((Bool) -> Void)?
    var onPresets: (([Int: String]) -> Void)?
    var onModel: ((String) -> Void)?
    var onExposurePresets: ((Set<Int>) -> Void)?
    var onExposure: ((CameraExposure) -> Void)?
    var onControl: ((Bool) -> Void)?
    private var online = false { didSet { if online != oldValue { onState?(online); onControl?(online) } } }

    // What was last sent, so a repeat isn't sent again and a stop is never skipped.
    private var lastPan = 0, lastTilt = 0, lastZoom = 0
    private var lastSpeed: String?, lastZoomSpeed: String?

    init(_ camera: PTZCamera, queue: DispatchQueue) {
        self.camera = camera
        self.queue = queue
        hub = MiddleControlHub.shared(host: camera.host.isEmpty ? "127.0.0.1" : camera.host,
                                      port: camera.port == 0 ? 11580 : camera.port, queue: queue)
    }

    func start() {
        hub.attach(token) { [weak self] in
            guard let self else { return }
            self.online = self.hub.isOnline(self.cam)
        }
        onModel?(setup.note ?? "Gimbal camera (Middle Control)")
        online = hub.isOnline(cam)
    }

    func stop() {
        // Never leave the gimbal moving when this link goes away.
        if online { stopMotion() }
        hub.detach(token)
        online = false
    }

    private func stopMotion() {
        hub.send(MCCommand.pan(0, cam: cam)); hub.send(MCCommand.tilt(0, cam: cam)); hub.send(MCCommand.zoom(0, cam: cam))
        lastPan = 0; lastTilt = 0; lastZoom = 0
    }

    private func speed(_ percent: Double) {
        let s = MCCommand.panTiltSpeed(percent, cam: cam)
        if s != lastSpeed { hub.send(s); lastSpeed = s }
    }

    /// Middle Control has one speed for pan and tilt together. Both axes move at the faster
    /// one's speed; an axis asked for much less than that is held still this tick (auto
    /// tracking corrects it on the next one), so a small tilt fix doesn't swing the camera.
    private func move(panDir: Int, tiltDir: Int, panPct: Double, tiltPct: Double) {
        var pd = panDir, td = tiltDir
        let top = max(panDir == 0 ? 0 : panPct, tiltDir == 0 ? 0 : tiltPct)
        if pd != 0, td != 0 {
            if tiltPct < panPct * 0.35 { td = 0 } else if panPct < tiltPct * 0.35 { pd = 0 }
        }
        if top > 0 { speed(top) }
        // Stops are always sent; moves only when they change.
        if pd != lastPan || pd == 0 { hub.send(MCCommand.pan(pd, cam: cam)) }
        if td != lastTilt || td == 0 { hub.send(MCCommand.tilt(td, cam: cam)) }
        lastPan = pd; lastTilt = td
        if pd == 0 && td == 0 { resendStop() }
    }

    /// One more stop shortly after, unless something newer moved it, so one lost stop can't
    /// leave the camera turning.
    private func resendStop() {
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.lastPan == 0, self.lastTilt == 0 else { return }
            self.hub.send(MCCommand.pan(0, cam: self.cam)); self.hub.send(MCCommand.tilt(0, cam: self.cam))
        }
    }

    func drive(pan: Double, tilt: Double) {
        let p = setup.invertPan ? -pan : pan, t = setup.invertTilt ? -tilt : tilt
        // Joystick feel like the Canon link: gentle near the middle, fast at the edge.
        func pct(_ v: Double) -> Double { min(100, 2 + v * v * 98) }
        move(panDir: p == 0 ? 0 : (p < 0 ? -1 : 1), tiltDir: t == 0 ? 0 : (t < 0 ? -1 : 1),
             panPct: pct(abs(p)), tiltPct: pct(abs(t)))
    }

    func driveRaw(pan: Int, tilt: Int) {
        let p = setup.invertPan ? -pan : pan, t = setup.invertTilt ? -tilt : tilt
        move(panDir: p.signum(), tiltDir: t.signum(),
             panPct: setup.percent(hundredthsPerSecond: p), tiltPct: setup.percent(hundredthsPerSecond: t))
    }

    func zoom(_ v: Double) {
        let dir = v == 0 ? 0 : (v > 0 ? 1 : -1)
        if dir != 0 {
            let s = MCCommand.zoomSpeed(min(100, 3 + abs(v) * 60), cam: cam)
            if s != lastZoomSpeed { hub.send(s); lastZoomSpeed = s }
        }
        if dir != lastZoom || dir == 0 { hub.send(MCCommand.zoom(dir, cam: cam)) }
        lastZoom = dir
    }

    func autoFocus(_ on: Bool) { if on { hub.send("AUTOFOCUS@C\(cam)") } }
    func focusOnce() { hub.send("AUTOFOCUS@C\(cam)") }
    func home() { hub.send("RECENTER@C\(cam)") }
    func recall(_ n: Int) { hub.send(MCCommand.recall(n, cam: cam)) }
    func store(_ n: Int) { hub.send(MCCommand.store(n, cam: cam)) }

    func readPosition(_ done: @escaping (PTZPosition?) -> Void) {
        guard let f = hub.frame(cam), let p = f.pan, let t = f.tilt else { done(nil); return }
        done(setup.position(pan: p, tilt: t, zoom: f.zoom ?? 0))
    }

    func goTo(_ p: PTZPosition) { glide(to: p, seconds: 1.0) }

    func glide(to p: PTZPosition, seconds: Double) {
        let c = setup.counts(p)
        let hasZoom = setup.focalTele > setup.focalWide * 1.01
        lastPan = 0; lastTilt = 0
        hub.sendToSelected(cam, MCCommand.glide(pan: c.pan, tilt: c.tilt, zoom: hasZoom ? c.zoom : nil, seconds: seconds))
    }

    func deletePreset(_ n: Int, _ done: @escaping (String?) -> Void) {
        done("Delete Middle Control presets in Middle Control itself.")
    }

    // Exposure for gimbal cameras goes through Middle Control's own controls for now;
    // CueVideo shows what the feed reports and leaves the setting alone.
    func readExposure() {}
    func setExposure(_ e: PTZExposure) {}
    func autoExposure() {}
}
