import Foundation

// TugShape is a drawing of Tug.
public enum TugShape: Sendable, CaseIterable {
    // lying is Tug asleep with his chin on his paws.
    case lying
    // dozing is Tug lying with his head up, drowsy.
    case dozing
    // sitting is Tug's everyday menu bar pose.
    case sitting
    // bow is Tug's play bow before he leaps.
    case bow
    // leap is Tug in the air.
    case leap
}

// TugPose is one frame of Tug's animations. Every part is a share from 0 to 1 except shape and tail.
public struct TugPose: Equatable, Sendable {
    // shape is the drawing shown. One drawing cuts straight to the next, as in hand-drawn animation,
    // since two different silhouettes crossfaded read as two dogs.
    public var shape: TugShape
    // lift is how high Tug is off the ground, as a share of the jump.
    public var lift: Double
    // drift is how far Tug has moved to the right, as a share of the jump.
    public var drift: Double
    // squash is how much Tug is pressed toward the ground, negative when stretched.
    public var squash: Double
    // tail is the sitting tail's swing about its root, in degrees.
    public var tail: Double
    // fade is Tug's opacity.
    public var fade: Double
    // bark is the opacity of the three bark lines in front of a sitting Tug's mouth.
    public var bark: Double = 0

    // rest is Tug sitting still in the menu bar.
    public static let rest = TugPose(shape: .sitting, lift: 0, drift: 0, squash: 0, tail: 0, fade: 1)
}

// TugMotion holds the timing of Tug's animations. At nap time he sinks slowly from sitting, lies
// down dozing with his head up, settles, and takes one slow breath. A moment later he lowers his
// chin onto his paws, and while he naps he now and then looks up and settles again. On wake he gathers, jumps up, turns from lying to
// sitting at the top of the jump, lands, barks twice while he wags, and settles. When Sheepdog opens
// he barks twice where he sits. On quit he drops into a play bow, holds
// it, sinks a little lower, then leaps up and out of the menu bar. Every function is pure.
public enum TugMotion {
    // napSeconds is how long the lie-down runs.
    public static let napSeconds = 1.6
    // napCut is when he goes from sinking while sitting to lying down, and napSettled when he has
    // settled, as shares of napSeconds.
    static let napCut = 0.5, napSettled = 0.75
    // settleSeconds is how long he takes to lower his chin onto his paws.
    public static let settleSeconds = 1.2
    // lookSeconds is how long a look up runs, from lifting his head to settling again.
    public static let lookSeconds = 3.0
    // wakeSeconds is how long the wake animation runs.
    public static let wakeSeconds = 1.3
    // exitSeconds is how long the quit animation runs before Sheepdog quits.
    public static let exitSeconds = 1.3
    // greetSeconds is how long the barks run when Sheepdog opens.
    public static let greetSeconds = 0.8
    // barkBeats are the two barks, each a start and end in seconds from the first. The lines cut in and
    // out at once, as in hand-drawn animation.
    static let barkBeats = [(start: 0.0, end: 0.18), (start: 0.32, end: 0.5)]
    // greetBark and wakeBark are when the first bark starts, in seconds from the start of the greeting
    // and from the start of the wake, just as he lands.
    static let greetBark = 0.12, wakeBark = 0.56
    // wakeJump is when the jump leaves the ground, peaks and lands, as shares of wakeSeconds.
    static let wakeJump = (start: 0.12, apex: 0.26, land: 0.42)
    // wagSpan is when the tail wags, as shares of wakeSeconds.
    static let wagSpan = (start: 0.3, end: 0.9)
    // wagCycles is how many times the tail swings there and back.
    static let wagCycles = 2.0
    // wagDegrees is how far the tail swings at its widest.
    static let wagDegrees = 22.0
    // bowStart is when Tug drops into the bow, springStart when he leaps, and springEnd when he is out
    // of sight, as shares of exitSeconds.
    static let bowStart = 0.12, springStart = 0.55, springEnd = 0.72

    // nap returns the lie-down frame at t, the share of napSeconds gone. A t outside 0...1 is clamped.
    public static func nap(_ t: Double) -> TugPose {
        let t = clamp(t)
        let sink = smooth(ramp(t, 0, napCut))
        let settle = smooth(ramp(t, napCut, napSettled))
        let breath = sin(.pi * ramp(t, napSettled - 0.03, 1))
        return TugPose(
            shape: t < napCut ? .sitting : .dozing, lift: 0, drift: 0,
            squash: t < napCut ? 0.2 * sink : 0.08 * (1 - settle) - 0.035 * breath, tail: 0, fade: 1
        )
    }

    // settle returns the frame at t, the share of settleSeconds gone, as he sinks from dozing to
    // lying with his chin on his paws. A t outside 0...1 is clamped.
    public static func settle(_ t: Double) -> TugPose {
        let t = clamp(t)
        let sink = smooth(ramp(t, 0, 0.6))
        let ease = smooth(ramp(t, 0.6, 0.9))
        return TugPose(
            shape: t < 0.6 ? .dozing : .lying, lift: 0, drift: 0,
            squash: t < 0.6 ? 0.12 * sink : 0.06 * (1 - ease), tail: 0, fade: 1
        )
    }

    // lookUp returns the frame at t, the share of lookSeconds gone, as he lifts his head from his paws,
    // holds it up a moment, and sinks back. A t outside 0...1 is clamped.
    public static func lookUp(_ t: Double) -> TugPose {
        let t = clamp(t)
        let rise = smooth(ramp(t, 0.06, 0.2))
        let sink = smooth(ramp(t, 0.7, 0.88))
        let ease = smooth(ramp(t, 0.88, 1))
        let squash: Double
        let shape: TugShape
        if t < 0.06 {
            (shape, squash) = (.lying, 0)
        } else if t < 0.88 {
            (shape, squash) = (.dozing, -0.04 * (1 - rise) + 0.1 * sink)
        } else {
            (shape, squash) = (.lying, 0.05 * (1 - ease))
        }
        return TugPose(shape: shape, lift: 0, drift: 0, squash: squash, tail: 0, fade: 1)
    }

    // wake returns the wake frame at t, the share of wakeSeconds gone. A t outside 0...1 is clamped.
    public static func wake(_ t: Double) -> TugPose {
        let t = clamp(t)
        let gather = smooth(ramp(t, 0, wakeJump.start)) * (1 - ramp(t, wakeJump.start, wakeJump.start + 0.04))
        let up = ramp(t, wakeJump.start, wakeJump.apex)
        let down = ramp(t, wakeJump.apex, wakeJump.land)
        let lift = t < wakeJump.apex ? 1 - (1 - up) * (1 - up) : 1 - down * down
        let landing = sin(.pi * ramp(t, wakeJump.land, wakeJump.land + 0.1))
        let wag = ramp(t, wagSpan.start, wagSpan.end)
        let tail = sin(2 * .pi * wagCycles * wag) * (1 - wag * wag) * wagDegrees
        return TugPose(
            shape: t < wakeJump.apex ? .lying : .sitting, lift: lift, drift: 0,
            squash: 0.1 * gather + 0.08 * landing, tail: tail, fade: 1,
            bark: barks(t * wakeSeconds - wakeBark)
        )
    }

    // greet returns the frame at t, the share of greetSeconds gone, as Tug barks twice where he sits
    // when Sheepdog opens. A t outside 0...1 is clamped.
    public static func greet(_ t: Double) -> TugPose {
        var pose = TugPose.rest
        pose.bark = barks(clamp(t) * greetSeconds - greetBark)
        return pose
    }

    // barks returns whether the bark lines show at seconds after the first bark starts, as 1 or 0.
    static func barks(_ seconds: Double) -> Double {
        barkBeats.contains { seconds >= $0.start && seconds < $0.end } ? 1 : 0
    }

    // exit returns the quit frame at t, the share of exitSeconds gone. A t outside 0...1 is clamped.
    public static func exit(_ t: Double) -> TugPose {
        let t = clamp(t)
        let shape: TugShape = t < bowStart ? .sitting : t < springStart ? .bow : .leap
        let drop = sin(.pi * ramp(t, bowStart, bowStart + 0.1))
        let dip = shape == .bow ? smooth(ramp(t, springStart - 0.1, springStart)) : 0
        let spring = ramp(t, springStart, springEnd)
        return TugPose(
            shape: shape, lift: spring * spring, drift: spring,
            squash: 0.06 * drop + 0.08 * dip, tail: 0,
            fade: 1 - smooth(ramp(t, springStart + 0.08, springEnd))
        )
    }

    // ramp returns where t sits between a and b as a share from 0 to 1.
    static func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
        clamp((t - a) / (b - a))
    }

    // smooth eases x in and out.
    static func smooth(_ x: Double) -> Double {
        x * x * (3 - 2 * x)
    }

    // clamp keeps x between 0 and 1.
    static func clamp(_ x: Double) -> Double {
        min(max(x, 0), 1)
    }
}
