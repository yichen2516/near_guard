public enum LockResult: String { case idle, observed, denied, requestIssued, failed }
public struct LockGate {
    public private(set) var enabled = false
    public init() {}
    public mutating func enable(prepared: Bool, confirmed: Bool, trusted: Bool) -> Bool {
        enabled = prepared && confirmed && trusted; return enabled
    }
    public mutating func disable() { enabled = false }
    public func perform(recommended: Bool, trust: () -> Bool, action: () -> Bool) -> LockResult {
        guard recommended else { return .idle }
        guard enabled else { return .observed }
        guard trust() else { return .denied }
        return action() ? .requestIssued : .failed
    }
}
public struct SampleSession {
    public private(set) var epoch: UInt64 = 0
    public private(set) var device: String?
    public private(set) var running = false
    public init() {}
    public mutating func begin(device: String) { epoch &+= 1; self.device = device; running = true }
    public mutating func end() { epoch &+= 1; running = false; device = nil }
    public func accepts(device: String, epoch: UInt64) -> Bool {
        running && device == self.device && epoch == self.epoch
    }
}
