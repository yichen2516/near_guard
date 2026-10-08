import IOBluetooth
import NearGuardCore

struct SystemPairedDevice: Identifiable {
    let id: String // Exact OS address, not a CoreBluetooth UUID.
    let name: String
    let connected: Bool
}

/// Observe existing OS links only. Never pair, connect, disconnect or inquire.
/// All callers must use the explicit-action and smoke gates in AppModel.
final class SystemBluetooth {
    private var devices: [String: IOBluetoothDevice] = [:]
    private(set) var queries = 0
    private(set) var pairedEnumerations = 0
    let connectionAttempts = 0 // This transport intentionally has no connection path.
    func refresh(permitted: Bool) -> [SystemPairedDevice] {
        guard permitted else { return [] }
        pairedEnumerations += 1
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        devices.removeAll()
        return paired.compactMap { device in
            guard let address = device.addressString, !address.isEmpty else { return nil }
            devices[address] = device
            return SystemPairedDevice(id: address, name: device.name ?? "未命名系统配对设备", connected: device.isConnected())
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func read(address: String, permitted: Bool) -> SystemBluetoothReading {
        guard permitted else { return .init(available: false, connected: false, rssi: nil) }
        queries += 1
        guard let controller = IOBluetoothHostController.default(), controller.powerState == kBluetoothHCIPowerStateON,
              let device = devices[address] else { return .init(available: false, connected: false, rssi: nil) }
        guard device.isConnected() else { return .init(available: true, connected: false, rssi: nil) }
        let rssi = Double(device.rawRSSI())
        // Sentinel after a concurrently lost link is absence, not unsupported.
        let connected = device.isConnected()
        return .init(available: true, connected: connected, rssi: connected ? rssi : nil)
    }
}
