import XCTest
@testable import NearGuardCore
final class ProximityTests: XCTestCase {
    func fast() -> ProximityEngine {
        var c = ProximityConfig(); c.alpha = 1
        return ProximityEngine(config: c)
    }
    func armedEngine() -> ProximityEngine {
        var e = fast(); e.start(now: 0); e.sample(rssi: -50, now: 0); e.sample(rssi: -50, now: 3); return e
    }
    func testExplicitStart() {
        var e = fast(); XCTAssertFalse(e.active); e.start(now: 0); XCTAssertTrue(e.active)
    }
    func testOnlyStableNearArms() {
        var e = fast(); e.start(now: 0); e.sample(rssi: -50, now: 0)
        XCTAssertFalse(e.armed); e.sample(rssi: -50, now: 2); XCTAssertFalse(e.armed)
        e.sample(rssi: -50, now: 3); XCTAssertTrue(e.armed)
    }
    func testInvalidAndStoppedSamplesIgnored() {
        var e = fast(); e.sample(rssi: -50, now: 0); XCTAssertNil(e.smooth)
        e.start(now: 1)
        for r in [127.0, 0, -128, .nan, .infinity] { e.sample(rssi: r, now: 1) }
        XCTAssertNil(e.smooth)
        e.sample(rssi: -50, now: 2); XCTAssertEqual(e.smooth, -50)
    }
    func testEWMASmoothing() {
        var e = ProximityEngine(); e.start(now: 0)
        e.sample(rssi: -60, now: 0); e.sample(rssi: -100, now: 1)
        XCTAssertEqual(e.smooth!, -70, accuracy: 0.001)
    }
    func testSustainedFarAfterNearRequestsOnce() {
        var e = armedEngine()
        for t in 4...11 { e.sample(rssi: -90, now: Double(t)) }
        XCTAssertFalse(e.tick(now: 11)); e.sample(rssi: -90, now: 12)
        XCTAssertTrue(e.tick(now: 12)); XCTAssertFalse(e.tick(now: 13))
        var startup = fast(); startup.start(now: 0); startup.sample(rssi: -95, now: 1)
        XCTAssertFalse(startup.tick(now: 50))
    }
    func testRecoveryResetsFarGrace() {
        var e = armedEngine(); e.sample(rssi: -90, now: 4); e.sample(rssi: -70, now: 10)
        XCTAssertFalse(e.tick(now: 12)); e.sample(rssi: -90, now: 13)
        for t in 14...20 { e.sample(rssi: -90, now: Double(t)) }
        XCTAssertFalse(e.tick(now: 20)); e.sample(rssi: -90, now: 21); XCTAssertTrue(e.tick(now: 21))
    }
    func testShortSignalGapCannotCountAsContinuousNear() {
        var e = fast(); e.start(now: 0); e.sample(rssi: -50, now: 0)
        e.sample(rssi: -50, now: 10)
        XCTAssertFalse(e.armed, "A ten-second gap is not sustained near evidence")
        e.sample(rssi: -50, now: 11); e.sample(rssi: -50, now: 13)
        XCTAssertTrue(e.armed)
    }
    func testSilentFarSampleWaitsForLossTimeout() {
        var e = armedEngine(); e.sample(rssi: -90, now: 4)
        XCTAssertFalse(e.tick(now: 12), "One far sample followed by silence is not sustained far")
        XCTAssertFalse(e.tick(now: 23)); XCTAssertTrue(e.tick(now: 24))
    }
    func testFarSignalGapRestartsDuration() {
        var e = armedEngine(); e.sample(rssi: -90, now: 4)
        XCTAssertFalse(e.tick(now: 8))
        for t in 9...16 { e.sample(rssi: -90, now: Double(t)) }
        XCTAssertFalse(e.tick(now: 16))
        e.sample(rssi: -90, now: 17); XCTAssertTrue(e.tick(now: 17))
    }
    func testGapBreaksStableNear() {
        var e = fast(); e.start(now: 0); e.sample(rssi: -50, now: 0)
        e.sample(rssi: -50, now: 25); XCTAssertFalse(e.armed)
    }
    func testStaleOnlyAfterWitnessedNear() {
        var e = armedEngine(); XCTAssertFalse(e.tick(now: 22)); XCTAssertTrue(e.tick(now: 23))
        var startup = fast(); startup.start(now: 0); XCTAssertFalse(startup.tick(now: 100))
    }
    func testCooldownRequiresFreshStableReturn() {
        var e = armedEngine()
        for t in 4...12 { e.sample(rssi: -90, now: Double(t)) }
        XCTAssertTrue(e.tick(now: 12))
        e.sample(rssi: -50, now: 13); e.sample(rssi: -50, now: 16); XCTAssertFalse(e.armed)
        e.sample(rssi: -50, now: 42); XCTAssertFalse(e.armed)
        e.sample(rssi: -50, now: 45); XCTAssertTrue(e.armed)
    }
    func testStopClearsStateAndCannotLock() {
        var e = armedEngine(); e.stop(); XCTAssertFalse(e.active); XCTAssertFalse(e.armed); XCTAssertNil(e.smooth)
        e.sample(rssi: -95, now: 4); XCTAssertFalse(e.tick(now: 100))
        e.start(now: 101); XCTAssertFalse(e.tick(now: 150))
    }
    func testSleepAndWakeRequireNewNearAfterGrace() {
        var e = armedEngine(); e.suspend(); XCTAssertFalse(e.tick(now: 100))
        e.wake(now: 101); e.sample(rssi: -50, now: 102); e.sample(rssi: -50, now: 105); XCTAssertFalse(e.armed)
        e.sample(rssi: -50, now: 111); e.sample(rssi: -50, now: 114); XCTAssertTrue(e.armed)
    }
    func testBackwardTimeIgnored() {
        var e = armedEngine()
        for t in 4...11 { e.sample(rssi: -90, now: Double(t)) }
        XCTAssertFalse(e.tick(now: 11))
        e.sample(rssi: -50, now: 2); XCTAssertEqual(e.smooth, -90)
        XCTAssertFalse(e.tick(now: 1)); e.sample(rssi: -90, now: 12); XCTAssertTrue(e.tick(now: 12))
    }
    func testTickRejectsNaNAndAdvancesClock() {
        var e = armedEngine(); XCTAssertFalse(e.tick(now: .nan)); XCTAssertFalse(e.tick(now: .infinity))
        XCTAssertFalse(e.tick(now: 5)); e.sample(rssi: -90, now: 4); XCTAssertEqual(e.smooth, -50)
    }
    func testRestartClearsHistoryAndGrace() {
        var e = armedEngine(); e.start(now: 10); XCTAssertFalse(e.armed); XCTAssertNil(e.smooth)
        XCTAssertFalse(e.tick(now: 50))
    }
    func testDryRunNeverQueriesTrustOrLocks() {
        let gate = LockGate(); var queried = false; var locked = false
        XCTAssertEqual(gate.perform(recommended: true, trust: { queried = true; return true }, action: { locked = true; return true }), .observed)
        XCTAssertFalse(queried); XCTAssertFalse(locked)
    }
    func testTwoConsentsAndTrustRequired() {
        var gate = LockGate()
        XCTAssertFalse(gate.enable(prepared: false, confirmed: true, trusted: true))
        XCTAssertFalse(gate.enable(prepared: true, confirmed: false, trusted: true))
        XCTAssertFalse(gate.enable(prepared: true, confirmed: true, trusted: false))
        XCTAssertTrue(gate.enable(prepared: true, confirmed: true, trusted: true)); XCTAssertTrue(gate.enabled)
    }
    func testRealActionChecksCurrentTrustAndDeniesClosed() {
        var gate = LockGate(); _ = gate.enable(prepared: true, confirmed: true, trusted: true)
        var count = 0
        XCTAssertEqual(gate.perform(recommended: true, trust: { false }, action: { count += 1; return true }), .denied)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(gate.perform(recommended: true, trust: { true }, action: { count += 1; return true }), .requestIssued)
        XCTAssertEqual(count, 1)
        gate.disable(); XCTAssertEqual(gate.perform(recommended: true, trust: { XCTFail(); return true }, action: { XCTFail(); return true }), .observed)
    }
    func testLateAndOtherDeviceCallbacksRejected() {
        var s = SampleSession(); XCTAssertFalse(s.accepts(device: "a", epoch: 0))
        s.begin(device: "a"); let first = s.epoch
        XCTAssertTrue(s.accepts(device: "a", epoch: first)); XCTAssertFalse(s.accepts(device: "b", epoch: first))
        s.end(); XCTAssertFalse(s.accepts(device: "a", epoch: first))
        s.begin(device: "b"); XCTAssertFalse(s.accepts(device: "a", epoch: first))
        XCTAssertTrue(s.accepts(device: "b", epoch: s.epoch))
    }
    func testManualReturnCooldown() {
        var e = armedEngine(); e.manualReturn(now: 10)
        XCTAssertFalse(e.armed); e.sample(rssi: -50, now: 11); e.sample(rssi: -50, now: 14); XCTAssertFalse(e.armed)
        e.sample(rssi: -50, now: 40); e.sample(rssi: -50, now: 43); XCTAssertTrue(e.armed)
    }
    func testFiveSecondSystemCadenceCanArmWithConfiguredEvidenceGap() {
        var c = ProximityConfig(); c.maximumEvidenceGap = 7; c.alpha = 1
        var e = ProximityEngine(config: c); e.start(now: 0)
        e.sample(rssi: -50, now: 0); e.sample(rssi: -50, now: 5)
        XCTAssertTrue(e.armed)
        e.sample(rssi: -90, now: 10); XCTAssertFalse(e.tick(now: 18))
        XCTAssertFalse(e.tick(now: 29)); XCTAssertTrue(e.tick(now: 30))
    }
    func testUnsafeConfigSanitized() {
        var c = ProximityConfig(); c.near = .nan; c.far = 2; c.alpha = 4; c.farGrace = -2; c.stale = -9; c.nearStable = 0; c.cooldown = -2; c.wakeGrace = -1
        let e = ProximityEngine(config: c)
        XCTAssertTrue(e.config.near.isFinite); XCTAssertLessThan(e.config.far, e.config.near)
        XCTAssertLessThanOrEqual(e.config.alpha, 1); XCTAssertGreaterThanOrEqual(e.config.farGrace, 1)
        XCTAssertGreaterThanOrEqual(e.config.stale, 5); XCTAssertGreaterThanOrEqual(e.config.nearStable, 1)
        XCTAssertGreaterThanOrEqual(e.config.cooldown, 10); XCTAssertGreaterThanOrEqual(e.config.wakeGrace, 5)
    }
}
