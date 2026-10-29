import Foundation
import Testing

@testable import SheepdogCore

// frames samples an animation at 600 steps per second over its length.
private func frames(_ seconds: Double, _ pose: (Double) -> TugPose) -> [(time: Double, pose: TugPose)] {
    let count = Int(seconds * 600)
    return (0...count).map { i in
        let t = Double(i) / Double(count)
        return (t * seconds, pose(t))
    }
}

// testTugMotionNapEnds checks the lie-down starts sitting at rest and ends dozing still.
@Test func testTugMotionNapEnds() {
    #expect(TugMotion.nap(0) == .rest)
    let end = TugMotion.nap(1)
    #expect(end.shape == .dozing)
    #expect(abs(end.squash) < 1e-9)
    #expect(end.lift == 0)
}

// testTugMotionNapBeats checks he sinks slowly for at least 0.6 s before lying down, never leaves
// the ground, never moves fast except at the cut to lying, and breathes once after he settles.
@Test func testTugMotionNapBeats() {
    let all = frames(TugMotion.napSeconds, TugMotion.nap)
    let sitting = all.filter { $0.pose.shape == .sitting }
    #expect(sitting.last!.time >= 0.6)
    #expect(all.filter { $0.time > sitting.last!.time }.allSatisfy { $0.pose.shape == .dozing })
    #expect(all.allSatisfy { $0.pose.lift == 0 && $0.pose.drift == 0 })
    #expect(fastest(all) < 0.5)
    #expect(all.contains { $0.pose.shape == .dozing && $0.pose.squash < -0.03 })
}

// fastest returns the quickest change in squash per second between frames of the same drawing.
private func fastest(_ all: [(time: Double, pose: TugPose)]) -> Double {
    var top = 0.0
    for (a, b) in zip(all, all.dropFirst()) where a.pose.shape == b.pose.shape {
        top = max(top, abs(b.pose.squash - a.pose.squash) / (b.time - a.time))
    }
    return top
}

// testTugMotionSettle checks he sinks from dozing to lying slowly, for at least half a second, and
// ends lying still.
@Test func testTugMotionSettle() {
    let all = frames(TugMotion.settleSeconds, TugMotion.settle)
    #expect(all.first!.pose.shape == .dozing)
    #expect(abs(all.first!.pose.squash) < 1e-9)
    let dozing = all.filter { $0.pose.shape == .dozing }
    #expect(dozing.last!.time >= 0.5)
    #expect(all.filter { $0.time > dozing.last!.time }.allSatisfy { $0.pose.shape == .lying })
    #expect(fastest(all) < 0.5)
    #expect(TugMotion.settle(1) == TugPose(shape: .lying, lift: 0, drift: 0, squash: 0, tail: 0, fade: 1))
}

// testTugMotionLookUp checks he starts and ends lying still, holds his head up for at least a
// second and a half, and sinks back slowly.
@Test func testTugMotionLookUp() {
    let all = frames(TugMotion.lookSeconds, TugMotion.lookUp)
    let still = TugPose(shape: .lying, lift: 0, drift: 0, squash: 0, tail: 0, fade: 1)
    #expect(TugMotion.lookUp(0) == still)
    #expect(TugMotion.lookUp(1) == still)
    let up = all.filter { $0.pose.shape == .dozing }
    #expect(up.last!.time - up.first!.time >= 1.5)
    #expect(all.filter { $0.time > up.first!.time && $0.time < up.last!.time }.allSatisfy { $0.pose.shape == .dozing })
    #expect(fastest(all) < 0.5)
}

// testTugMotionWakeEnds checks the wake starts lying still and ends at rest.
@Test func testTugMotionWakeEnds() {
    let start = TugMotion.wake(0)
    #expect(start.shape == .lying)
    #expect(start.lift == 0)
    #expect(start.fade == 1)
    let end = TugMotion.wake(1)
    #expect(abs(end.lift) < 1e-9)
    #expect(abs(end.squash) < 1e-9)
    #expect(abs(end.tail) < 1e-9)
    #expect(end.shape == .sitting)
    #expect(TugMotion.wake(-1) == start)
    #expect(TugMotion.wake(2) == end)
}

// testTugMotionWakeBeats checks he turns to sitting in the air, starts wagging no sooner than just
// before he lands, wags at least three swings, and the whole wake runs about a second.
@Test func testTugMotionWakeBeats() {
    let all = frames(TugMotion.wakeSeconds, TugMotion.wake)
    #expect(TugMotion.wakeSeconds >= 1 && TugMotion.wakeSeconds <= 1.5)
    let apex = all.max { $0.pose.lift < $1.pose.lift }!
    #expect(apex.pose.lift > 0.99)
    #expect(apex.pose.shape == .sitting)
    let airborne = all.filter { $0.pose.lift > 0.05 }
    #expect(airborne.first!.pose.shape == .lying)
    let landed = airborne.last!.time
    #expect(landed - airborne.first!.time <= 0.45)
    let wagging = all.filter { abs($0.pose.tail) > 1 }
    #expect(wagging.first!.time >= landed - 0.2)
    var swings = 0
    for (a, b) in zip(wagging, wagging.dropFirst()) where (a.pose.tail > 0) != (b.pose.tail > 0) {
        swings += 1
    }
    #expect(swings >= 3)
    #expect(wagging.allSatisfy { abs($0.pose.tail) <= TugMotion.wagDegrees })
}

// testTugMotionExitEnds checks the quit starts at rest and ends out of sight.
@Test func testTugMotionExitEnds() {
    #expect(TugMotion.exit(0) == .rest)
    let end = TugMotion.exit(1)
    #expect(end.fade == 0)
    #expect(end.lift == 1)
    #expect(end.drift == 1)
}

// testTugMotionExitBeats checks the bow holds long enough to read as deliberate, he sinks lowest
// while bowing, the leap is fast, and they come in that order.
@Test func testTugMotionExitBeats() {
    let all = frames(TugMotion.exitSeconds, TugMotion.exit)
    let bowing = all.filter { $0.pose.shape == .bow && $0.pose.lift == 0 }
    let hold = bowing.last!.time - bowing.first!.time
    #expect(hold >= 0.35)
    #expect(all.filter { $0.time < bowing.first!.time }.allSatisfy { $0.pose.shape == .sitting })
    let lowest = all.max { $0.pose.squash < $1.pose.squash }!
    #expect(lowest.pose.shape == .bow)
    #expect(lowest.pose.squash > 0)
    let leaving = all.first { $0.pose.lift > 0 }!
    let gone = all.first { $0.pose.fade == 0 }!
    #expect(leaving.time > bowing.last!.time)
    #expect(gone.pose.shape == .leap)
    #expect(gone.time - leaving.time <= 0.25)
    #expect(all.filter { $0.time < leaving.time }.allSatisfy { $0.pose.fade == 1 })
    #expect(TugMotion.exitSeconds <= 1.6)
}

// barkRuns returns each stretch of frames with the bark lines showing, as its first and last time.
private func barkRuns(_ all: [(time: Double, pose: TugPose)]) -> [(start: Double, end: Double)] {
    var runs: [(start: Double, end: Double)] = []
    var open: Double?
    var last = 0.0
    for frame in all {
        if frame.pose.bark > 0, open == nil {
            open = frame.time
        } else if frame.pose.bark == 0, let start = open {
            runs.append((start, last))
            open = nil
        }
        last = frame.time
    }
    if let start = open {
        runs.append((start, last))
    }
    return runs
}

// testTugMotionGreet checks Tug barks twice while sitting still when Sheepdog opens, each bark long
// enough to read, with a clear gap between, and starts and ends at rest.
@Test func testTugMotionGreet() {
    #expect(TugMotion.greet(0) == .rest)
    #expect(TugMotion.greet(1) == .rest)
    let all = frames(TugMotion.greetSeconds, TugMotion.greet)
    let runs = barkRuns(all)
    #expect(runs.count == 2)
    #expect(runs.allSatisfy { $0.end - $0.start >= 0.12 })
    #expect(runs[1].start - runs[0].end >= 0.1)
    #expect(all.allSatisfy { $0.pose.shape == .sitting && $0.pose.lift == 0 && $0.pose.squash == 0 })
    #expect(TugMotion.greetSeconds <= 1)
}

// testTugMotionWakeBarks checks Tug barks twice on wake, only once he has landed, sitting, and
// stops barking before the wake ends.
@Test func testTugMotionWakeBarks() {
    let all = frames(TugMotion.wakeSeconds, TugMotion.wake)
    let runs = barkRuns(all)
    #expect(runs.count == 2)
    let landed = all.filter { $0.pose.lift > 0.05 }.last!.time
    #expect(runs[0].start >= landed)
    #expect(runs[1].start - runs[0].end >= 0.1)
    #expect(all.filter { $0.pose.bark > 0 }.allSatisfy { $0.pose.shape == .sitting })
    #expect(TugMotion.wake(1).bark == 0)
}
