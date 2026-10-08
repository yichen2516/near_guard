import XCTest
import Foundation
@testable import NearGuard
import NearGuardCore

final class AppStartupTests: XCTestCase {
    func testExplicitOffImmediatelyClearsIsolatedIntentWhilePausePreservesLockChoice() {
        let suite = "NearGuardTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let p = MonitoringPreferences(defaults: d)
        p.desiredAutomaticLock = true; p.monitoringWanted = true
        let m = AppModel(smoke: true, preferenceDefaults: d)
        m.stopMonitoring()
        XCTAssertFalse(p.monitoringWanted); XCTAssertTrue(p.desiredAutomaticLock)
        m.setAutomaticLock(false)
        XCTAssertFalse(m.desiredAutomaticLock); XCTAssertFalse(m.realLock)
        XCTAssertFalse(MonitoringPreferences(defaults: UserDefaults(suiteName: suite)!).desiredAutomaticLock)
        m.restoreMonitoringIfEligible()
        XCTAssertFalse(m.running); XCTAssertEqual(m.lockRequests, 0)
        m.shutdown()
    }
    func testSafeStartupReadsIsolatedIntentButNeverEnablesRuntimeOrHardware() {
        let suite = "NearGuardTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let p = MonitoringPreferences(defaults: d)
        p.desiredAutomaticLock = true; p.monitoringWanted = true
        let m = AppModel(smoke: true, preferenceDefaults: d)
        XCTAssertTrue(m.desiredAutomaticLock)
        m.restoreMonitoringIfEligible(); m.setLoginEnabled(true); m.refreshLoginStatus()
        m.requestAccessibility(); m.enableReal(); m.startMonitoring()
        XCTAssertFalse(m.running); XCTAssertFalse(m.realLock); XCTAssertFalse(m.managerCreated)
        XCTAssertEqual(m.permissionRequests, 0); XCTAssertEqual(m.lockRequests, 0)
        XCTAssertEqual(m.loginRegistrationAttempts, 0); XCTAssertEqual(m.loginStatusReads, 0)
        m.shutdown()
        XCTAssertTrue(p.desiredAutomaticLock); XCTAssertTrue(p.monitoringWanted)
    }
}
