import Foundation

public struct TrustTransition {
    private var previous: Bool?
    public init() {}
    public mutating func update(trusted: Bool) -> Bool {
        defer { previous = trusted }
        return previous.map { $0 != trusted } ?? false
    }
}

public struct RestorePolicy {
    public func mayEnableLock(desired: Bool, running: Bool, active: Bool, freshNear: Bool, trusted: Bool, calibrating: Bool, safeMode: Bool) -> Bool {
        desired && running && active && freshNear && trusted && !calibrating && !safeMode
    }
    public init() {}
    public func shouldRestore(monitoringWanted: Bool, ble: Bool, deviceID: String?, bluetoothAuthorized: Bool, safeMode: Bool) -> Bool {
        !safeMode && monitoringWanted && ble && bluetoothAuthorized && deviceID.flatMap(UUID.init(uuidString:)) != nil
    }
}

/// Stores user intent, never OS authorization or live proximity evidence.
public final class MonitoringPreferences {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    public var monitoringWanted: Bool {
        get { defaults.bool(forKey: "monitoringWanted") }
        set { defaults.set(newValue, forKey: "monitoringWanted") }
    }
    public var desiredAutomaticLock: Bool {
        get { defaults.bool(forKey: "desiredAutomaticLock") }
        set { defaults.set(newValue, forKey: "desiredAutomaticLock") }
    }
}
