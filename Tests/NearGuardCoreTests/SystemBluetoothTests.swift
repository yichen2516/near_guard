import XCTest
@testable import NearGuardCore
final class SystemBluetoothTests: XCTestCase {
    func testSmokeStopAndInvalidClockNeverQueryAdapter() {
        var s = SystemPollingSession(); s.start(device: "phone")
        let forbidden: () -> SystemBluetoothReading = { XCTFail("Forbidden live read"); return .init(available: true, connected: true, rssi: -50) }
        XCTAssertEqual(s.poll(now: 0, permitted: false, read: forbidden), .idle)
        XCTAssertEqual(s.poll(now: .nan, permitted: true, read: forbidden), .idle)
        XCTAssertEqual(s.poll(now: .infinity, permitted: true, read: forbidden), .idle)
        _ = s.poll(now: 10, permitted: true) { .init(available: true, connected: false, rssi: nil) }
        XCTAssertEqual(s.poll(now: 9, permitted: true, read: forbidden), .idle)
        let oldEpoch = s.epoch; s.stop(); XCTAssertNotEqual(s.epoch, oldEpoch)
        XCTAssertEqual(s.poll(now: 100, permitted: true, read: forbidden), .idle)
    }
    func testDisconnectedSentinelIsAbsenceNotUnsupported() {
        var s = SystemPollingSession(); s.start(device: "phone")
        XCTAssertEqual(s.poll(now: 0, permitted: true) { .init(available: true, connected: false, rssi: 127) }, .disconnected)
        XCTAssertEqual(s.poll(now: 5, permitted: true) { .init(available: true, connected: true, rssi: -50) }, .sample(-50))
    }
    func testInvalidConnectedValuesPause() {
        for r in [127.0, 0, -128, Double.nan, Double.infinity] {
            var s = SystemPollingSession(); s.start(device: "phone")
            XCTAssertEqual(s.poll(now: 0, permitted: true) { .init(available: true, connected: true, rssi: r) }, .unsupported)
            XCTAssertEqual(s.poll(now: 10, permitted: true) { XCTFail(); return .init(available: true, connected: true, rssi: -50) }, .idle)
        }
    }
    func testFiveSecondLossRequiresWitnessedNear() {
        var c = ProximityConfig(); c.maximumEvidenceGap = 7; c.alpha = 1
        var e = ProximityEngine(config: c); e.start(now: 0)
        XCTAssertFalse(e.tick(now: 100), "Initial disconnect cannot lock")
        e.start(now: 101); e.sample(rssi: -50, now: 101); e.sample(rssi: -50, now: 106)
        XCTAssertTrue(e.armed); XCTAssertFalse(e.tick(now: 125)); XCTAssertTrue(e.tick(now: 126))
    }
    func testSystemNearGapAndFarGapDoNotAccumulate() {
        var c = ProximityConfig(); c.maximumEvidenceGap = 7; c.alpha = 1
        var e = ProximityEngine(config: c); e.start(now: 0)
        e.sample(rssi: -50, now: 0); e.sample(rssi: -50, now: 8); XCTAssertFalse(e.armed)
        e.sample(rssi: -50, now: 13); XCTAssertTrue(e.armed)
        e.sample(rssi: -90, now: 18); XCTAssertFalse(e.tick(now: 26))
        e.sample(rssi: -90, now: 28); e.sample(rssi: -90, now: 33); XCTAssertFalse(e.tick(now: 35))
        e.sample(rssi: -90, now: 38); XCTAssertTrue(e.tick(now: 38))
    }
    func testEvidenceGapSanitizedWithoutChangingBLEDefault() {
        XCTAssertEqual(ProximityEngine().config.maximumEvidenceGap, 3)
        for invalid in [Double.nan, Double.infinity, -1] {
            var c = ProximityConfig(); c.maximumEvidenceGap = invalid
            let gap = ProximityEngine(config: c).config.maximumEvidenceGap
            XCTAssertTrue(gap.isFinite); XCTAssertGreaterThanOrEqual(gap, 1)
        }
    }
    func testUnavailablePausesUntilExplicitRestart() {
        var s = SystemPollingSession(); s.start(device: "phone")
        XCTAssertEqual(s.poll(now: 0, permitted: true) { .init(available: false, connected: false, rssi: nil) }, .unavailable)
        XCTAssertEqual(s.poll(now: 5, permitted: true) { XCTFail("Paused adapter must not read"); return .init(available: true, connected: true, rssi: -50) }, .idle)
        s.start(device: "phone")
        XCTAssertEqual(s.poll(now: 6, permitted: true) { .init(available: true, connected: true, rssi: -50) }, .sample(-50))
    }
    func testConnectedSentinelPausesWithoutInventingLoss() {
        var s = SystemPollingSession(); s.start(device: "phone"); var reads = 0
        XCTAssertEqual(s.poll(now: 0, permitted: true) { reads += 1; return .init(available: true, connected: true, rssi: 127) }, .unsupported)
        XCTAssertEqual(s.poll(now: 5, permitted: true) { reads += 1; return .init(available: true, connected: true, rssi: -50) }, .idle)
        XCTAssertEqual(reads, 1, "Unsupported transport needs an explicit restart")
    }
    func testPollsOnlyEveryFiveSecondsAfterExplicitStart() {
        var s = SystemPollingSession(); var reads = 0
        let read: () -> SystemBluetoothReading = { reads += 1; return .init(available: true, connected: true, rssi: -50) }
        XCTAssertEqual(s.poll(now: 0, permitted: true, read: read), .idle)
        s.start(device: "paired-address")
        XCTAssertEqual(s.poll(now: 0, permitted: true, read: read), .sample(-50))
        for t in 1...4 { XCTAssertEqual(s.poll(now: Double(t), permitted: true, read: read), .idle) }
        XCTAssertEqual(s.poll(now: 5, permitted: true, read: read), .sample(-50))
        XCTAssertEqual(reads, 2)
    }
}
