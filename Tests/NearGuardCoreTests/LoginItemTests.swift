import XCTest
@testable import NearGuardCore

final class LoginItemTests: XCTestCase {
    func testNoopEnableDoesNotRegisterAlreadyEnabledTarget() {
        var writes = 0
        let c = LoginItemController(read: { .enabled }, register: { writes += 1 }, unregister: {})
        c.refresh(permitted: true)
        c.setEnabled(true, permitted: true)
        XCTAssertEqual(writes, 0)
        XCTAssertTrue(c.enabled)
    }
    func testDisabledEntrancesNeverReadOrRegister() {
        let c = LoginItemController(read: { XCTFail("live read"); return .enabled }, register: { XCTFail("register") }, unregister: { XCTFail("unregister") })
        c.refresh(permitted: false); c.setEnabled(true, permitted: false); c.setEnabled(false, permitted: false)
        XCTAssertEqual(c.registrationAttempts, 0); XCTAssertEqual(c.statusReads, 0)
    }
    func testEnabledAndUnregisterReadback() {
        var actual = LoginItemStatus.notRegistered
        let c = LoginItemController(read: { actual }, register: { actual = .enabled }, unregister: { actual = .notRegistered })
        c.setEnabled(true, permitted: true); XCTAssertTrue(c.enabled)
        c.setEnabled(false, permitted: true); XCTAssertFalse(c.enabled)
        XCTAssertEqual(c.statusReads, 2)
    }
    func testFailureStillReadsTruthAndRefreshNeverRetries() {
        enum Failure: Error { case denied }
        var writes = 0
        let c = LoginItemController(read: { .notFound }, register: { writes += 1; throw Failure.denied }, unregister: {})
        c.setEnabled(true, permitted: true)
        XCTAssertNotNil(c.error); XCTAssertFalse(c.enabled); XCTAssertEqual(c.status, .notFound)
        c.refresh(permitted: true); XCTAssertEqual(writes, 1)
    }
    func testExplicitEnableReadsActualStatusAfterRegistration() {
        var calls = [String]()
        let c = LoginItemController(read: { calls.append("read"); return .requiresApproval }, register: { calls.append("register") }, unregister: { calls.append("unregister") })
        c.setEnabled(true, permitted: true)
        XCTAssertEqual(calls, ["register", "read"])
        XCTAssertEqual(c.status, .requiresApproval)
        XCTAssertFalse(c.enabled)
    }
}
