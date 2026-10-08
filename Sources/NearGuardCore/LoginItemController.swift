public enum LoginItemStatus: String { case enabled, requiresApproval, notRegistered, notFound }

/// Injected adapter: tests do not contact ServiceManagement.
public final class LoginItemController {
    public private(set) var status: LoginItemStatus = .notRegistered
    public private(set) var error: String?
    public private(set) var registrationAttempts = 0
    public private(set) var statusReads = 0
    private let read: () -> LoginItemStatus
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    public var enabled: Bool { status == .enabled }
    public init(read: @escaping () -> LoginItemStatus, register: @escaping () throws -> Void, unregister: @escaping () throws -> Void) {
        self.read = read; self.register = register; self.unregister = unregister
    }
    public func refresh(permitted: Bool) {
        guard permitted else { return }
        statusReads += 1; status = read()
    }
    public func setEnabled(_ wanted: Bool, permitted: Bool) {
        guard permitted else { return }
        if wanted && status == .enabled { refresh(permitted: true); return }
        error = nil; registrationAttempts += 1
        do { if wanted { try register() } else { try unregister() } }
        catch { self.error = String(describing: error) }
        refresh(permitted: true) // Read exact target even after a failed write.
    }
}
