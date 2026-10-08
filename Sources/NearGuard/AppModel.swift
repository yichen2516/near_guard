import AppKit
import SwiftUI
import CoreBluetooth
import ApplicationServices
import NearGuardCore

enum MonitoringTransport: String, CaseIterable { case system, ble }

struct BLEDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Double
    var connectable: Bool
}

// Immutable session token: callbacks from a previous monitor/device never feed the engine.
final class PeripheralReader: NSObject, CBPeripheralDelegate {
    weak var owner: AppModel?
    let epoch: UInt64
    let device: UUID
    var pendingAt: Double?
    init(owner: AppModel, epoch: UInt64, device: UUID) { self.owner = owner; self.epoch = epoch; self.device = device }
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard let owner, let requested = pendingAt else { return }
        pendingAt = nil
        guard peripheral.identifier == device, error == nil, owner.now - requested <= 4 else { return }
        owner.receive(RSSI.doubleValue, device: device, epoch: epoch)
    }
}

final class AppModel: NSObject, ObservableObject, CBCentralManagerDelegate {
    static let companionService = CBUUID(string: "CA375B98-741B-4A73-AC6B-27D0D1A0C551")
    @Published var devices: [BLEDevice] = []
    @Published var selectedID: UUID?
    @Published var transport: MonitoringTransport = .ble
    @Published var systemDevices: [SystemPairedDevice] = []
    @Published var selectedSystemAddress: String?
    private let systemBluetooth = SystemBluetooth()
    private var systemPolling = SystemPollingSession()
    var systemQueries: Int { systemBluetooth.queries }
    var systemPairedEnumerations: Int { systemBluetooth.pairedEnumerations }
    var systemConnectionAttempts: Int { systemBluetooth.connectionAttempts }
    var hasSelection: Bool { transport == .system ? selectedSystemAddress != nil : selectedID != nil }
    @Published var selectedName = "尚未选择设备"
    @Published var running = false
    @Published var scanning = false
    @Published var bluetooth = "尚未请求蓝牙权限"
    @Published var status = "等待开始"
    @Published var detail = "先选择设备；观察模式绝不会锁屏。"
    @Published var rawRSSI: Double?
    @Published var smoothedRSSI: Double?
    @Published var armed = false
    @Published var realLock = false
    @Published private(set) var desiredAutomaticLock = false
    @Published private(set) var lockPreferenceStatus = "自动锁屏未勾选 · 只观察"
    @Published private(set) var loginStatus: LoginItemStatus = .notRegistered
    @Published private(set) var loginError: String?
    private let login = LoginItems.controller()
    private let preferences: MonitoringPreferences?
    var loginRegistrationAttempts: Int { login.registrationAttempts }
    var loginStatusReads: Int { login.statusReads }
    var showSettingsOnLaunch: Bool { smoke || simulation || !(preferences?.monitoringWanted == true || loginStatus == .enabled || loginStatus == .requiresApproval) }
    @Published var prepared = false
    @Published var near: Double = -65
    @Published var far: Double = -78
    @Published var grace: Double = 8
    @Published var stale: Double = 20
    @Published var events: [String] = []
    @Published var calibrationCount: Int?
    let simulation: Bool
    let smoke: Bool
    private(set) var managerCreated = false
    private(set) var lockRequests = 0
    private(set) var permissionRequests = 0
    private var manager: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selectedPeripheral: CBPeripheral?
    private var reader: PeripheralReader?
    private var session = SampleSession()
    private var engine = ProximityEngine()
    private var gate = LockGate()
    private var discoveryWanted = false
    private var sleeping = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var calibrating: [Double]?
    private var lastConnectAttempt = -Double.infinity
    private var discoveryDeadline: Double?
    private var trustTransition = TrustTransition()

    var now: Double { ProcessInfo.processInfo.systemUptime }
    var selectedDescription: String {
        if transport == .system { return selectedSystemAddress.map { "系统配对 · …" + $0.suffix(5) } ?? "请主动刷新并选择系统配对设备" }
        return selectedID?.uuidString ?? "请选择正在广播的 BLE 设备"
    }
    var canUseBluetooth: Bool { !simulation && !smoke }

    init(simulation: Bool = false, smoke: Bool = false, preferenceDefaults: UserDefaults? = nil) {
        self.simulation = simulation; self.smoke = smoke
        preferences = preferenceDefaults.map { MonitoringPreferences(defaults: $0) } ?? (simulation || smoke ? nil : MonitoringPreferences(defaults: .standard))
        super.init()
        desiredAutomaticLock = preferences?.desiredAutomaticLock ?? false
        updateLockPreferenceStatus()
        if simulation {
            transport = .ble
            selectedName = "演示 BLE 标签 · 模拟数据"; selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
            rawRSSI = -58; smoothedRSSI = -59.2; status = "演示 · 未连接真实设备"
            detail = "模拟信号仅用于界面预览；蓝牙与锁屏均不可用。"
        } else if !smoke {
            let d = UserDefaults.standard
            transport = d.string(forKey: "transport").flatMap(MonitoringTransport.init(rawValue:)) ?? .ble

            selectedSystemAddress = d.string(forKey: "systemAddress")
            selectedID = d.string(forKey: "deviceID").flatMap(UUID.init(uuidString:))
            selectedName = d.string(forKey: "deviceName") ?? "尚未选择设备"
            if transport == .system { selectedName = d.string(forKey: "systemName") ?? "尚未选择系统配对设备" }
            var c = ProximityConfig()
            if d.object(forKey: "near") != nil { c.near = d.double(forKey: "near"); c.far = d.double(forKey: "far"); c.farGrace = d.double(forKey: "grace"); c.stale = d.double(forKey: "stale") }
            let validated = ProximityEngine(config: c).config
            near = validated.near; far = validated.far; grace = validated.farGrace; stale = validated.stale
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleep() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.returned() })
    }
    func refreshLoginStatus() {
        login.refresh(permitted: canUseBluetooth)
        loginStatus = login.status; loginError = login.error
    }
    func setLoginEnabled(_ wanted: Bool) {
        login.setEnabled(wanted, permitted: canUseBluetooth)
        loginStatus = login.status; loginError = login.error
    }
    func openLoginSettings() { guard canUseBluetooth else { return }; LoginItems.openSettings() }
    func restoreMonitoringIfEligible() {
        guard canUseBluetooth else { return }
        guard RestorePolicy().shouldRestore(monitoringWanted: preferences?.monitoringWanted ?? false, ble: transport == .ble,
                                            deviceID: selectedID?.uuidString, bluetoothAuthorized: CBManager.authorization == .allowedAlways, safeMode: !canUseBluetooth) else {
            updateLockPreferenceStatus()
            if preferences?.monitoringWanted == true { detail = "已记住监控选择；需要有效 BLE 设备及已有蓝牙授权才自动恢复。系统模式请主动刷新；未自动请求权限。" }
            return
        }
        startMonitoring(restoring: true)
    }
    private func updateLockPreferenceStatus() {
        guard desiredAutomaticLock else { lockPreferenceStatus = "自动锁屏未勾选 · 只观察"; return }
        if !canUseBluetooth { lockPreferenceStatus = "自动锁屏已记住 · 安全测试中不会生效" }
        else if !AXIsProcessTrusted() { lockPreferenceStatus = "自动锁屏已记住，辅助功能权限待授权 / 实际只观察" }
        else if realLock { lockPreferenceStatus = "自动锁屏实际已启用 · 每次请求再次检查权限" }
        else { lockPreferenceStatus = "自动锁屏已记住 · 暂未生效，等待监控及新的稳定靠近" }
    }
    private func refreshEffectiveLock() {
        guard canUseBluetooth, desiredAutomaticLock, running, engine.active, !sleeping, calibrating == nil else { disableReal(); return }
        let trusted = AXIsProcessTrusted()
        if trustTransition.update(trusted: trusted) {
            disableReal(); engine.manualReturn(now: now); armed = false; rawRSSI = nil; smoothedRSSI = nil
        }
        if !trusted { disableReal(); return }
        // Once qualified, keep the gate through departure. New sessions disable it.
        if !realLock && RestorePolicy().mayEnableLock(desired: desiredAutomaticLock, running: running, active: engine.active,
                                                     freshNear: engine.armed, trusted: trusted, calibrating: false, safeMode: false) {
            realLock = gate.enable(prepared: true, confirmed: true, trusted: trusted)
        }
        updateLockPreferenceStatus()
    }
    func setAutomaticLock(_ wanted: Bool) {
        if !wanted {
            desiredAutomaticLock = false; preferences?.desiredAutomaticLock = false
            disableReal(); return
        }
        guard canUseBluetooth else { return }
        prepared = true; enableReal()
    }
    deinit { timer?.invalidate(); for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }

    func log(_ text: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.insert("\(stamp)  \(text)", at: 0); events = Array(events.prefix(40))
        NSLog("NearGuard: %@", text)
    }
    private func ensureManager() {
        guard canUseBluetooth, transport == .ble, manager == nil else { return }
        managerCreated = true; permissionRequests += 1
        manager = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }
    private func renewManager() {
        // Separate central identity rejects queued discovery/connection callbacks
        // from the previous monitor, wake, or calibration session.
        detachPeripheral(); manager?.stopScan(); manager?.delegate = nil; manager = nil
        peripherals.removeAll(); scanning = false
    }
    func discover() {
        guard canUseBluetooth, transport == .ble else { return }
        discoveryWanted = true; discoveryDeadline = now + 30
        bluetooth = "正在检查蓝牙…"; ensureManager(); scanIfReady()
    }
    func stopDiscovery() {
        discoveryWanted = false; discoveryDeadline = nil
        if !running { manager?.stopScan(); scanning = false }
    }
    private func scanIfReady() {
        guard transport == .ble, let manager, manager.state == .poweredOn, !sleeping, discoveryWanted || running else { return }
        // Broad foreground discovery is deliberate. A service filter does NOT guarantee
        // Mac rediscovery of an iOS background peripheral's overflow advertisement.
        manager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        scanning = true
    }
    func select(_ device: BLEDevice) {
        guard canUseBluetooth, transport == .ble else { return }
        stopMonitoring()
        selectedID = device.id; selectedName = device.name
        UserDefaults.standard.set(device.id.uuidString, forKey: "deviceID")
        UserDefaults.standard.set(device.name, forKey: "deviceName")
        detail = "已保存设备。先点击开始，观察信号，再校准。"
    }
    func startMonitoring(restoring: Bool = false) {
        guard canUseBluetooth, hasSelection, !running else { return }
        if restoring && (transport != .ble || CBManager.authorization != .allowedAlways) { return }
        if transport == .system {
            guard systemDevices.contains(where: { $0.id == selectedSystemAddress }) else {
                status = "请先刷新系统配对设备"; detail = "保存地址不是当前连接；刷新后主动选择，不会自动配对或连接。"; return
            }
            preferences?.monitoringWanted = true
            running = true; sleeping = false; disableReal(); beginSession(); return
        }
        preferences?.monitoringWanted = true
        running = true; sleeping = false; disableReal(); renewManager(); ensureManager()
        persistSettings()
        if manager?.state == .poweredOn { beginSession(); scanIfReady(); connectSelected() }
        else { status = "等待蓝牙可用"; detail = "蓝牙不可用时不会触发锁屏。" }
    }
    private func beginSession() {
        guard running, !sleeping else { return }
        let identity = transport == .system ? selectedSystemAddress : selectedID?.uuidString
        guard let identity else { return }
        session.begin(device: identity)
        var config = ProximityConfig(); config.near = near; config.far = far; config.farGrace = grace; config.stale = stale
        if transport == .system { config.maximumEvidenceGap = 7; systemPolling.start(device: identity) }
        engine = ProximityEngine(config: config); engine.start(now: now)
        disableReal()
        // Every fresh session requalifies after grace, including duplicate power callbacks.
        engine.wake(now: now)
        rawRSSI = nil; smoothedRSSI = nil; armed = false
        status = "观察中 · 等待设备靠近"; detail = "需连续靠近 3 秒才会布防；启动时失联不会锁屏。"
        if transport == .system {
            bluetooth = "系统蓝牙 · 仅观察已有连接"
            detail = "Mac 每 5 秒读 RSSI；至少两个靠近样本才布防。手机无需运行伴侣；兼容性与额外耗电未实测。不会自动连接。"
        }
    }
    func stopMonitoring(preserveIntent: Bool = false) {
        if !preserveIntent { preferences?.monitoringWanted = false }
        running = false; session.end(); systemPolling.stop(); engine.stop(); disableReal(); detachPeripheral()
        calibrationCount = nil; calibrating = nil; rawRSSI = nil; smoothedRSSI = nil; armed = false
        status = "已暂停"; detail = "监控已停止；自动锁屏选择保留。主动恢复后需重新稳定靠近。"
        if !discoveryWanted { manager?.stopScan(); scanning = false }
    }
    private func detachPeripheral() {
        reader?.pendingAt = nil; selectedPeripheral?.delegate = nil
        if let peripheral = selectedPeripheral { manager?.cancelPeripheralConnection(peripheral) }
        selectedPeripheral = nil; reader = nil; lastConnectAttempt = -Double.infinity
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === manager else { return }
        switch central.state {
        case .poweredOn:
            bluetooth = "蓝牙可用"
            if running && !sleeping { beginSession(); connectSelected() }
            scanIfReady()
        case .poweredOff: unavailable("蓝牙已关闭")
        case .unauthorized: unavailable("蓝牙权限被拒绝：请在系统设置 → 隐私与安全性 → 蓝牙中允许 NearGuard")
        case .unsupported: unavailable("此 Mac 不支持 BLE")
        case .resetting: unavailable("蓝牙正在重置")
        case .unknown: unavailable("蓝牙状态未知")
        @unknown default: unavailable("蓝牙不可用")
        }
    }
    private func unavailable(_ message: String) {
        bluetooth = message; engine.suspend(); session.end(); detachPeripheral(); disableReal(); armed = false; scanning = false
        if running { status = "监控暂停 · 蓝牙不可用"; detail = "不会把蓝牙关闭或权限拒绝当作离开；恢复后重新等待靠近。" }
        log(message)
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === manager, scanning, !sleeping else { return }
        let rssi = RSSI.intValue
        guard rssi >= -127, rssi < 0 else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未命名 BLE 设备"
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        let device = BLEDevice(id: peripheral.identifier, name: name, rssi: rssi, lastSeen: now, connectable: connectable)
        peripherals[device.id] = peripheral
        if let i = devices.firstIndex(where: { $0.id == device.id }) { devices[i] = device } else { devices.append(device) }
        devices.sort { $0.rssi > $1.rssi }
        if running, selectedID == device.id {
            receive(Double(rssi), device: device.id, epoch: session.epoch)
            if connectable && selectedPeripheral == nil { connectSelected() }
        }
    }
    private func connectSelected() {
        guard let manager, manager.state == .poweredOn, let id = selectedID, running, !sleeping, now - lastConnectAttempt >= 10 else { return }
        if let p = selectedPeripheral, p.state == .connected || p.state == .connecting { return }
        guard let p = peripherals[id] ?? manager.retrievePeripherals(withIdentifiers: [id]).first else { return }
        if let d = devices.first(where: { $0.id == id }), !d.connectable { return }
        lastConnectAttempt = now; selectedPeripheral = p
        let delegate = PeripheralReader(owner: self, epoch: session.epoch, device: id)
        reader = delegate; p.delegate = delegate
        manager.connect(p, options: nil)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === manager, peripheral === selectedPeripheral, session.accepts(device: peripheral.identifier.uuidString, epoch: reader?.epoch ?? 0) else { return }
        detail = "已连接；每秒读取 RSSI。无法连接的广播设备使用扫描信号。"
        log("设备已连接；这不是加密身份验证")
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        disconnected(central, peripheral)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnected(central, peripheral)
    }
    private func disconnected(_ central: CBCentralManager, _ peripheral: CBPeripheral) {
        guard central === manager, peripheral === selectedPeripheral else { return }
        peripheral.delegate = nil; selectedPeripheral = nil; reader = nil
        detail = "连接中断，尝试重连并使用广播 RSSI；已布防时失联超时仍会触发离开事件。"
        log("连接中断；等待广播或重连")
    }
    func receive(_ rssi: Double, device: UUID, epoch: UInt64) {
        guard transport == .ble else { return }
        receiveValue(rssi, identity: device.uuidString, epoch: epoch)
    }
    private func receiveValue(_ rssi: Double, identity: String, epoch: UInt64) {
        guard running, !sleeping, session.accepts(device: identity, epoch: epoch), engine.active,
              rssi.isFinite, rssi >= -127, rssi < 0 else { return }
        rawRSSI = rssi; engine.sample(rssi: rssi, now: now); smoothedRSSI = engine.smooth; armed = engine.armed
        if var values = calibrating {
            values.append(rssi); calibrating = values; calibrationCount = values.count
            if values.count >= 12 {
                let median = values.sorted()[values.count / 2]
                near = min(-30, max(-90, median - 6)); far = max(-120, near - 12)
                calibrating = nil; calibrationCount = nil; persistSettings()
                // Calibration is observe-only and clears all old proximity state.
                disableReal(); session.end(); engine.stop()
                if transport == .system { systemPolling.stop(); beginSession() }
                else { renewManager(); ensureManager() }
                log("校准完成：靠近 \(Int(near)) / 离开 \(Int(far)) dBm")
                detail = "校准完成；请先离开再靠近，观察事件是否符合实际。"
            }
        }
    }
    func calibrate() {
        guard running, rawRSSI != nil, !simulation, !smoke else { return }
        disableReal(); calibrating = []; calibrationCount = 0
        detail = "请把设备放在日常工作位置，保持不动；收集 12 个有效样本。"
    }
    func cancelCalibration() {
        calibrating = nil; calibrationCount = nil; disableReal(); session.end(); engine.stop()
        if running { if transport == .system { beginSession() } else { renewManager(); ensureManager() } }
    }
    private func tick() {
        objectWillChange.send() // Refresh last-seen ages even while only discovering.
        if let deadline = discoveryDeadline, now >= deadline { stopDiscovery() }
        guard running, !sleeping, engine.active else { return }
        refreshEffectiveLock()
        if transport == .system {
            pollSystem()
            guard running, engine.active else { return }
        } else if let p = selectedPeripheral, p.state == .connected, let reader {
            if let pending = reader.pendingAt, now - pending > 4 { reader.pendingAt = nil }
            if reader.pendingAt == nil { reader.pendingAt = now; p.readRSSI() }
        } else { connectSelected() }
        let recommended = engine.tick(now: now); armed = engine.armed
        if recommended {
            let result = gate.perform(recommended: true, trust: { AXIsProcessTrusted() }, action: { [weak self] in self?.issueLockShortcut() ?? false })
            switch result {
            case .observed: status = "观察：检测到离开"; detail = "没有锁屏。返回且稳定靠近、冷却结束后才会再次布防。"; log("观察事件：离开；未执行锁屏")
            case .requestIssued: status = "已发出锁屏请求"; detail = "已发送 Control + Command + Q；未验证系统实际锁定。"; log("锁屏快捷键请求已发出（未验证锁定）")
            case .denied, .failed: disableReal(); status = "锁屏请求未执行"; detail = "权限不足或事件创建失败。已退回观察模式。"; log("锁屏请求被拒绝或失败；已退回观察")
            case .idle: break
            }
        } else if engine.armed && !status.contains("未连接") { status = realLock ? "自动锁屏已布防" : "观察中 · 已布防" }
        else if rawRSSI != nil && !status.contains("离开") && !status.contains("请求") && !status.contains("未连接") { status = "等待稳定靠近 / 冷却" }
    }
    private func issueLockShortcut() -> Bool {
        guard realLock, !smoke, !simulation, AXIsProcessTrusted(),
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 12, keyDown: false) else { return false }
        down.flags = [.maskControl, .maskCommand]; up.flags = [.maskControl, .maskCommand]
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap); lockRequests += 1
        return true
    }
    func enableReal() {
        guard canUseBluetooth, prepared, calibrating == nil else { return }
        let alert = NSAlert(); alert.messageText = "启用真实自动锁屏？"
        alert.informativeText = "离开或失联可能导致误锁。RSSI 不是距离或身份验证。此功能只发送 Control + Command + Q，不会自动解锁。请确认系统快捷键未被修改。"
        alert.addButton(withTitle: "确认启用"); alert.addButton(withTitle: "保持观察")
        let confirmed = alert.runModal() == .alertFirstButtonReturn
        guard confirmed else { prepared = false; return }
        desiredAutomaticLock = true; preferences?.desiredAutomaticLock = true
        disableReal()
        if running { engine.manualReturn(now: now); armed = false }
        log("用户两次确认，自动锁屏选择已保存；权限与稳定靠近仍需重新检查")
        detail = "选择已记住；实际生效需当前辅助功能权限、监控可用与新的稳定靠近。"
    }
    func disableReal() { gate.disable(); realLock = false; prepared = false; updateLockPreferenceStatus() }
    func requestAccessibility() {
        guard canUseBluetooth, prepared || desiredAutomaticLock else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        permissionRequests += 1
        _ = AXIsProcessTrustedWithOptions(options)
        detail = "在系统设置 → 隐私与安全性 → 辅助功能中允许当前 NearGuard；选择保留，授权后仍需重新冷却与稳定靠近。"
    }
    private func sleep() {
        guard running else { return }
        sleeping = true; engine.suspend(); session.end(); systemPolling.stop(); disableReal(); detachPeripheral(); manager?.stopScan(); scanning = false; armed = false
        status = "睡眠中 · 已暂停"
    }
    private func wake() {
        guard running else { return }
        sleeping = false
        if transport == .system {
            disableReal(); beginSession()
            status = "已唤醒 · 10 秒宽限"; return
        }
        guard manager?.state == .poweredOn else { unavailable("唤醒后蓝牙暂不可用"); return }
        session.end(); engine.stop(); renewManager(); ensureManager()
        // New central becomes poweredOn asynchronously; beginSession applies
        // fresh near qualification. Suppress arming for an additional wake grace.
        status = "已唤醒 · 10 秒宽限"; log("唤醒：清空旧信号，重新等待靠近")
    }
    private func returned() {
        guard running, engine.active else { return }
        engine.manualReturn(now: now); armed = false; rawRSSI = nil; smoothedRSSI = nil
        disableReal()
        status = "会话恢复 · 冷却 30 秒"; log("会话恢复：重新等待稳定靠近，不会自动解锁")
    }
    func persistSettings() {
        guard !smoke, !simulation else { return }
        var config = ProximityConfig(); config.near = near; config.far = far; config.farGrace = grace; config.stale = stale
        let c = ProximityEngine(config: config).config
        near = c.near; far = c.far; grace = c.farGrace; stale = c.stale
        let d = UserDefaults.standard; d.set(near, forKey: "near"); d.set(far, forKey: "far"); d.set(grace, forKey: "grace"); d.set(stale, forKey: "stale")
    }
    func shutdown() { stopMonitoring(preserveIntent: true); stopDiscovery(); manager?.delegate = nil; manager = nil; timer?.invalidate() }

    func changeTransport(_ value: MonitoringTransport) {
        guard value != transport else { return }
        stopMonitoring(); stopDiscovery(); renewManager(); transport = value
        if !canUseBluetooth { selectedName = value == .system ? "尚未选择系统配对设备" : "尚未选择 BLE 设备" }
        else { selectedName = value == .system ? (UserDefaults.standard.string(forKey: "systemName") ?? "尚未选择系统配对设备") : (UserDefaults.standard.string(forKey: "deviceName") ?? "尚未选择 BLE 设备") }
        bluetooth = value == .system ? "尚未读取系统配对列表" : "尚未请求 BLE 权限"
        detail = smoke ? "安全测试：已尝试两个模式的入口，均未请求蓝牙或锁屏。" : "更换模式已清空证据与真实锁屏授权。请主动刷新或扫描，再开始观察。"
        if canUseBluetooth { UserDefaults.standard.set(value.rawValue, forKey: "transport") }
    }
    func refreshSystemDevices() {
        guard canUseBluetooth, transport == .system else { return }
        stopMonitoring()
        systemDevices = systemBluetooth.refresh(permitted: canUseBluetooth)
        bluetooth = systemDevices.isEmpty ? "无系统配对设备（或读取未获授权）" : "已读取系统配对列表；不会自动选择"
        status = "等待选择系统配对设备"
        detail = "在系统设置 → 蓝牙完成真正配对与连接。iPhone 可能不提供可用连接；系统配对与 BLE 保存 UUID 不同。"
    }
    func selectSystemDevice(_ device: SystemPairedDevice) {
        guard canUseBluetooth, transport == .system, systemDevices.contains(where: { $0.id == device.id }) else { return }
        stopMonitoring(); selectedSystemAddress = device.id; selectedName = device.name
        UserDefaults.standard.set(device.id, forKey: "systemAddress")
        UserDefaults.standard.set(device.name, forKey: "systemName")
        status = device.connected ? "已选择 · 等待开始观察" : "已选择 · 当前未连接"
        detail = "只读取已有系统连接，不会自动配对、连接、重连或关闭连接。开始后检测连接与 RSSI 支持情况。"
    }
    private func pollSystem() {
        guard transport == .system, canUseBluetooth, let address = selectedSystemAddress else { return }
        let epoch = session.epoch // Immutable identity/epoch captured before this read.
        let result = systemPolling.poll(now: now, permitted: canUseBluetooth) { systemBluetooth.read(address: address, permitted: canUseBluetooth) }
        guard session.accepts(device: address, epoch: epoch), running, !sleeping else { return }
        switch result {
        case .idle: break
        case .sample(let rssi):
            status = "系统蓝牙 · 观察中"; receiveValue(rssi, identity: address, epoch: epoch)
        case .disconnected:
            rawRSSI = nil; status = "系统设备当前未连接"
            detail = "无自动重连。只有之前已经稳定靠近布防，才按上次有效样本起算失联超时；否则不触发。"
        case .unsupported, .unavailable:
            stopMonitoring(preserveIntent: true)
            status = result == .unsupported ? "RSSI 不可用 · 不支持，已暂停" : "系统蓝牙不可用 · 已暂停"
            detail = "连接存在但 RSSI 为 127/无效值时不是离开。已关闭真实锁屏；可检查系统设置后重新观察，或切换 BLE 模式。"
        }
    }
    func openBluetoothSettings() {
        guard canUseBluetooth, let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }
}
