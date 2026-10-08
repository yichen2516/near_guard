import XCTest
import Foundation
@testable import NearGuardCore

final class PreferencesTests: XCTestCase {
    func testPermissionTransitionInvalidatesPreviouslyWitnessedNear() {
        var p = TrustTransition()
        XCTAssertFalse(p.update(trusted: false))
        XCTAssertFalse(p.update(trusted: false))
        XCTAssertTrue(p.update(trusted: true))
        XCTAssertFalse(p.update(trusted: true))
        XCTAssertTrue(p.update(trusted: false))
        var engine = ProximityEngine(); engine.start(now: 0)
        for t in 0...4 { engine.sample(rssi: -50, now: Double(t)) }
        XCTAssertTrue(engine.armed)
        if p.update(trusted: true) { engine.manualReturn(now: 5) }
        XCTAssertFalse(engine.armed); XCTAssertFalse(engine.tick(now: 100))
    }
    func testSavedIntentAloneCannotActivateGateWithoutFreshNearAndCurrentTrust() {
        let p = RestorePolicy()
        XCTAssertFalse(p.mayEnableLock(desired: true, running: true, active: true, freshNear: false, trusted: true, calibrating: false, safeMode: false))
        XCTAssertFalse(p.mayEnableLock(desired: true, running: true, active: true, freshNear: true, trusted: false, calibrating: false, safeMode: false))
        XCTAssertTrue(p.mayEnableLock(desired: true, running: true, active: true, freshNear: true, trusted: true, calibrating: false, safeMode: false))
        XCTAssertFalse(p.mayEnableLock(desired: false, running: true, active: true, freshNear: true, trusted: true, calibrating: false, safeMode: false))
        XCTAssertFalse(p.mayEnableLock(desired: true, running: false, active: true, freshNear: true, trusted: true, calibrating: false, safeMode: false))
        XCTAssertFalse(p.mayEnableLock(desired: true, running: true, active: false, freshNear: true, trusted: true, calibrating: false, safeMode: false))
        XCTAssertFalse(p.mayEnableLock(desired: true, running: true, active: true, freshNear: true, trusted: true, calibrating: true, safeMode: false))
        XCTAssertFalse(p.mayEnableLock(desired: true, running: true, active: true, freshNear: true, trusted: true, calibrating: false, safeMode: true))
    }
    func testExplicitPausePersistsButRuntimeSuspensionDoesNotEraseIntent() {
        let suite = "NearGuardTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let p = MonitoringPreferences(defaults: d)
        p.monitoringWanted = true; p.desiredAutomaticLock = true
        var gate = LockGate(); _ = gate.enable(prepared: true, confirmed: true, trusted: true)
        gate.disable() // Sleep, calibration, shutdown only disable runtime gate.
        XCTAssertTrue(p.monitoringWanted); XCTAssertTrue(p.desiredAutomaticLock)
        p.monitoringWanted = false
        XCTAssertFalse(MonitoringPreferences(defaults: UserDefaults(suiteName: suite)!).monitoringWanted)
        XCTAssertTrue(p.desiredAutomaticLock)
    }
    func testRestoreRequiresSavedBLEPriorAuthorizationAndRememberedMonitoring() {
        let p = RestorePolicy()
        XCTAssertTrue(p.shouldRestore(monitoringWanted: true, ble: true, deviceID: UUID().uuidString, bluetoothAuthorized: true, safeMode: false))
        XCTAssertFalse(p.shouldRestore(monitoringWanted: false, ble: true, deviceID: UUID().uuidString, bluetoothAuthorized: true, safeMode: false))
        XCTAssertFalse(p.shouldRestore(monitoringWanted: true, ble: false, deviceID: UUID().uuidString, bluetoothAuthorized: true, safeMode: false))
        for id in [nil, "bad-id"] as [String?] {
            XCTAssertFalse(p.shouldRestore(monitoringWanted: true, ble: true, deviceID: id, bluetoothAuthorized: true, safeMode: false))
        }
        XCTAssertFalse(p.shouldRestore(monitoringWanted: true, ble: true, deviceID: UUID().uuidString, bluetoothAuthorized: false, safeMode: false))
        XCTAssertFalse(p.shouldRestore(monitoringWanted: true, ble: true, deviceID: UUID().uuidString, bluetoothAuthorized: true, safeMode: true))
    }
    func testAutomaticLockIntentRoundTripsTrueAndFalseInFreshStore() {
        let suite = "NearGuardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MonitoringPreferences(defaults: defaults)
        XCTAssertFalse(store.desiredAutomaticLock)
        store.desiredAutomaticLock = true
        defaults.synchronize()
        XCTAssertTrue(MonitoringPreferences(defaults: UserDefaults(suiteName: suite)!).desiredAutomaticLock)
        store.desiredAutomaticLock = false
        defaults.synchronize()
        XCTAssertFalse(MonitoringPreferences(defaults: UserDefaults(suiteName: suite)!).desiredAutomaticLock)
    }
}
