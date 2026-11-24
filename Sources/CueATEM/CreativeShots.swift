import Foundation

// Creative shots: shots with slow motion in them, and the pace of cutting, for worship.
//
// A creative shot is a framing (a saved shot or one auto tracking found) plus a slow move
// through it: a push in or pull out, a pan across, or both, timed to the song. The camera
// is put on the move's start while it is on Next, the move begins as it is taken Live, and
// it keeps moving gently through the shot. Gimbal cameras on Middle Control time the move
// themselves (aGLOB with a duration), so it is smooth however busy the Mac is.
//
// The song sets the pace (`SongFeel`): slow songs get long shots, long slow moves and slow
// fades (up to about 8 seconds); fast songs get quick cuts and shorter, livelier moves.
// Instrument shots (piano keys, guitar frets, drums) are always kept brief.
//
// All of this is pure planning, so it can be tested and tuned without cameras. Positions
// are CueVideo's units: pan and tilt in hundredths of a degree, zoom as the horizontal
// angle of view in hundredths of a degree (smaller is tighter).

/// How a song feels, from its tempo.
public enum SongFeel: String, Codable, CaseIterable {
    case slow, medium, fast

    /// Below 82 BPM is slow, above 118 fast. No tempo known: medium.
    public static func from(bpm: Double?) -> SongFeel {
        guard let bpm, bpm > 0 else { return .medium }
        if bpm < 82 { return .slow }
        if bpm > 118 { return .fast }
        return .medium
    }
}

/// What a shot is of. Instruments are kept brief.
public enum ShotSubject: String, Codable, CaseIterable {
    case person        // a singer, the worship leader, the preacher
    case instrument    // piano keys, guitar frets, drums
    case group         // the band, the choir
    case wide          // the whole stage or room
}

/// The motion through a shot.
public enum MoveKind: String, Codable, CaseIterable {
    case hold                       // still (fast songs, or a tight person shot)
    case pushIn, pullOut            // slow zoom in or out
    case panLeft, panRight          // slow pan across
    case pushInPanLeft, pushInPanRight, pullOutPanLeft, pullOutPanRight

    var zoomDirection: Int {
        switch self {
        case .pushIn, .pushInPanLeft, .pushInPanRight: return 1
        case .pullOut, .pullOutPanLeft, .pullOutPanRight: return -1
        default: return 0
        }
    }
    var panDirection: Int {
        switch self {
        case .panLeft, .pushInPanLeft, .pullOutPanLeft: return -1
        case .panRight, .pushInPanRight, .pullOutPanRight: return 1
        default: return 0
        }
    }
    public var label: String {
        switch self {
        case .hold: return "Hold"
        case .pushIn: return "Slow push in"
        case .pullOut: return "Slow pull out"
        case .panLeft: return "Slow pan left"
        case .panRight: return "Slow pan right"
        case .pushInPanLeft: return "Push in, pan left"
        case .pushInPanRight: return "Push in, pan right"
        case .pullOutPanLeft: return "Pull out, pan left"
        case .pullOutPanRight: return "Pull out, pan right"
        }
    }
}

/// How a shot is taken Live.
public struct Transition: Equatable, Codable {
    /// 0 is a cut; otherwise a mix (fade) this many frames long (the ATEM takes 1 to 250).
    public var frames: Int
    public var isCut: Bool { frames == 0 }
    public static let cut = Transition(frames: 0)
    public init(frames: Int) { self.frames = max(0, min(250, frames)) }
}

/// One planned shot: where the camera starts, where it glides to, how long it stays Live,
/// and how it is taken.
public struct CreativeShot: Equatable {
    public var move: MoveKind
    public var start: PTZPosition
    public var end: PTZPosition
    /// How long the glide takes. A little longer than the time Live, so the camera is still
    /// moving when the next shot takes over, never stopping on air.
    public var moveSeconds: Double
    /// How long it stays Live before the next shot.
    public var holdSeconds: Double
    public var transition: Transition
}

/// The house style: how long shots last, how far moves go and how slow fades are. Every
/// number has a default and can be tuned in the config file.
public struct ProductionStyle: Codable, Equatable {
    /// Seconds Live, as a range, by feel. Instruments use their own, shorter range.
    public var personHold: [String: [Double]] = ["slow": [9, 15], "medium": [5, 9], "fast": [2.5, 5]]
    public var instrumentHold: [String: [Double]] = ["slow": [4, 6], "medium": [2.5, 4], "fast": [1.5, 2.5]]
    public var wideHold: [String: [Double]] = ["slow": [7, 12], "medium": [4, 7], "fast": [2.5, 4]]
    /// Fade length in seconds by feel; 0 cuts. Slow songs fade slowly.
    public var fadeSeconds: [String: [Double]] = ["slow": [3, 8], "medium": [0.5, 1.5], "fast": [0, 0]]
    /// Share of shots on a fast song that still fade (briefly) instead of cutting.
    public var fastFadeShare = 0.15
    /// How far a push in or pull out goes: the angle of view changes by this factor over the
    /// move (1.35 is a gentle push; 1.8 a strong one). Instruments push further.
    public var zoomFactor: [String: Double] = ["slow": 1.35, "medium": 1.3, "fast": 1.25]
    public var instrumentZoomFactor = 1.6
    /// How far a pan travels, as a share of the angle of view.
    public var panShare: [String: Double] = ["slow": 0.22, "medium": 0.2, "fast": 0.18]
    public var instrumentPanShare = 0.3
    /// Never closer or wider than these angles of view, degrees.
    public var tightestFOV = 3.0
    public var widestFOV = 70.0
    /// Frames a second the switcher runs at, for fade lengths.
    public var framesPerSecond = 29.97

    public init() {}

    private enum Keys: String, CodingKey {
        case personHold, instrumentHold, wideHold, fadeSeconds, fastFadeShare, zoomFactor, instrumentZoomFactor,
             panShare, instrumentPanShare, tightestFOV, widestFOV, framesPerSecond
    }
    /// Lenient: any number left out of the config file keeps its default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = ProductionStyle.base
        personHold = try c.decodeIfPresent([String: [Double]].self, forKey: .personHold) ?? d.personHold
        instrumentHold = try c.decodeIfPresent([String: [Double]].self, forKey: .instrumentHold) ?? d.instrumentHold
        wideHold = try c.decodeIfPresent([String: [Double]].self, forKey: .wideHold) ?? d.wideHold
        fadeSeconds = try c.decodeIfPresent([String: [Double]].self, forKey: .fadeSeconds) ?? d.fadeSeconds
        fastFadeShare = try c.decodeIfPresent(Double.self, forKey: .fastFadeShare) ?? d.fastFadeShare
        zoomFactor = try c.decodeIfPresent([String: Double].self, forKey: .zoomFactor) ?? d.zoomFactor
        instrumentZoomFactor = try c.decodeIfPresent(Double.self, forKey: .instrumentZoomFactor) ?? d.instrumentZoomFactor
        panShare = try c.decodeIfPresent([String: Double].self, forKey: .panShare) ?? d.panShare
        instrumentPanShare = try c.decodeIfPresent(Double.self, forKey: .instrumentPanShare) ?? d.instrumentPanShare
        tightestFOV = try c.decodeIfPresent(Double.self, forKey: .tightestFOV) ?? d.tightestFOV
        widestFOV = try c.decodeIfPresent(Double.self, forKey: .widestFOV) ?? d.widestFOV
        framesPerSecond = try c.decodeIfPresent(Double.self, forKey: .framesPerSecond) ?? d.framesPerSecond
    }
    private static let base = ProductionStyle()

    static func range(_ table: [String: [Double]], _ feel: SongFeel, _ fallback: [Double]) -> ClosedRange<Double> {
        let r = table[feel.rawValue] ?? fallback
        let lo = r.first ?? 0, hi = r.count > 1 ? r[1] : lo
        return min(lo, hi)...max(lo, hi)
    }
}

/// Plans creative shots. Give it a random number generator to make tests repeatable.
public struct ShotPlanner {
    public var style: ProductionStyle
    public init(style: ProductionStyle = ProductionStyle()) { self.style = style }

    /// Which moves suit a shot. Fast songs hold still more often; instruments always move
    /// (the motion is the point of the shot); tight person shots favour a gentle push.
    public func moves(for subject: ShotSubject, feel: SongFeel) -> [MoveKind] {
        switch (subject, feel) {
        case (.instrument, _):
            return [.pushIn, .pullOut, .panLeft, .panRight, .pushInPanLeft, .pushInPanRight]
        case (.person, .fast):
            return [.hold, .hold, .pushIn, .pullOut]
        case (.person, _):
            return [.pushIn, .pushIn, .pullOut, .panLeft, .panRight, .hold]
        case (.group, _), (.wide, _):
            return [.panLeft, .panRight, .pushIn, .pullOut, .pushInPanLeft, .pullOutPanRight]
        }
    }

    /// Plans one shot around `framing` (the picture the shot is about, framed as wanted).
    /// The move passes through the framing: a push in starts wider and ends tighter than it,
    /// a pan starts on one side and ends on the other, so the middle of the move is the
    /// planned framing.
    public func plan<R: RandomNumberGenerator>(framing: PTZPosition, subject: ShotSubject, feel: SongFeel,
                                               move chosen: MoveKind? = nil, using rng: inout R) -> CreativeShot {
        let move = chosen ?? moves(for: subject, feel: feel).randomElement(using: &rng) ?? .hold
        let hold = holdSeconds(subject, feel, &rng)
        let fov = Double(framing.zoom) / 100

        // Zoom: the angle of view changes by `factor` over the move, centred on the framing.
        let factor = subject == .instrument ? style.instrumentZoomFactor : (style.zoomFactor[feel.rawValue] ?? 1.3)
        let half = sqrt(max(1, factor))
        var fovStart = fov, fovEnd = fov
        switch move.zoomDirection {
        case 1: fovStart = fov * half; fovEnd = fov / half      // wide to tight
        case -1: fovStart = fov / half; fovEnd = fov * half     // tight to wide
        default: break
        }
        fovStart = clampFOV(fovStart); fovEnd = clampFOV(fovEnd)

        // Pan: travel a share of the (wider) angle of view, across the framing.
        let share = subject == .instrument ? style.instrumentPanShare : (style.panShare[feel.rawValue] ?? 0.2)
        let travel = Double(move.panDirection) * share * max(fovStart, fovEnd)
        let panStart = Double(framing.pan) / 100 - travel / 2, panEnd = Double(framing.pan) / 100 + travel / 2

        let start = PTZPosition(pan: Int((panStart * 100).rounded()), tilt: framing.tilt, zoom: Int((fovStart * 100).rounded()))
        let end = PTZPosition(pan: Int((panEnd * 100).rounded()), tilt: framing.tilt, zoom: Int((fovEnd * 100).rounded()))
        // Keep moving a bit past the cut away, so the camera never comes to rest on air.
        let moveSeconds = move == .hold ? 0 : hold * 1.25 + 1
        return CreativeShot(move: move, start: start, end: end, moveSeconds: moveSeconds,
                            holdSeconds: hold, transition: transition(feel, &rng))
    }

    public func plan(framing: PTZPosition, subject: ShotSubject, feel: SongFeel, move: MoveKind? = nil) -> CreativeShot {
        var g = SystemRandomNumberGenerator()
        return plan(framing: framing, subject: subject, feel: feel, move: move, using: &g)
    }

    func holdSeconds<R: RandomNumberGenerator>(_ subject: ShotSubject, _ feel: SongFeel, _ rng: inout R) -> Double {
        let r: ClosedRange<Double>
        switch subject {
        case .instrument: r = ProductionStyle.range(style.instrumentHold, feel, [2.5, 4])
        case .wide, .group: r = ProductionStyle.range(style.wideHold, feel, [4, 7])
        case .person: r = ProductionStyle.range(style.personHold, feel, [5, 9])
        }
        return r.lowerBound == r.upperBound ? r.lowerBound : Double.random(in: r, using: &rng)
    }

    /// Slow songs fade slowly, medium songs fade briefly, fast songs mostly cut.
    public func transition<R: RandomNumberGenerator>(_ feel: SongFeel, _ rng: inout R) -> Transition {
        if feel == .fast {
            return Double.random(in: 0..<1, using: &rng) < style.fastFadeShare
                ? Transition(frames: Int((0.4 * style.framesPerSecond).rounded())) : .cut
        }
        let r = ProductionStyle.range(style.fadeSeconds, feel, [0.5, 1.5])
        let s = r.lowerBound == r.upperBound ? r.lowerBound : Double.random(in: r, using: &rng)
        return s <= 0 ? .cut : Transition(frames: Int((s * style.framesPerSecond).rounded()))
    }

    func clampFOV(_ v: Double) -> Double { min(style.widestFOV, max(style.tightestFOV, v)) }
}
