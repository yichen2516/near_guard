public struct SystemBluetoothReading {
    public let available: Bool
    public let connected: Bool
    public let rssi: Double?
    public init(available: Bool, connected: Bool, rssi: Double?) {
        self.available = available; self.connected = connected; self.rssi = rssi
    }
}
public enum SystemPollResult: Equatable {
    case idle, sample(Double), disconnected, unsupported, unavailable
}
/// Mac-only reads. No scan, connection, pairing, retry or phone work.
public struct SystemPollingSession {
    public static let cadence: Double = 5
    private var session = SampleSession()
    private var lastPoll: Double?
    public var epoch: UInt64 { session.epoch }
    public init() {}
    public mutating func start(device: String) { session.begin(device: device); lastPoll = nil }
    public mutating func stop() { session.end(); lastPoll = nil }
    public mutating func poll(now: Double, permitted: Bool, read: () -> SystemBluetoothReading) -> SystemPollResult {
        guard permitted, now.isFinite, session.device != nil else { return .idle }
        if let lastPoll, now - lastPoll < Self.cadence { return .idle }
        lastPoll = now
        let value = read()
        guard value.available else { stop(); return .unavailable }
        guard value.connected else { return .disconnected }
        guard let rssi = value.rssi, rssi.isFinite, rssi >= -127, rssi < 0 else { stop(); return .unsupported }
        return .sample(rssi)
    }
}
