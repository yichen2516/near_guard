import SwiftUI
import CoreBluetooth

final class Beacon: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    static let service = CBUUID(string: "CA375B98-741B-4A73-AC6B-27D0D1A0C551")
    static let characteristic = CBUUID(string: "CB0871BA-D005-4DBD-A766-EE894EA62021")
    @Published var wanted = false
    @Published var advertising = false
    @Published var status = "尚未请求蓝牙权限"
    private var manager: CBPeripheralManager?
    private var ready = false
    func start() {
        wanted = true
        if manager == nil { manager = CBPeripheralManager(delegate: self, queue: .main) }
        else if manager?.state == .poweredOn { configure() }
    }
    func stop() {
        wanted = false; manager?.stopAdvertising(); manager?.removeAllServices()
        ready = false; advertising = false; status = "已停止广播"
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn: status = "蓝牙可用"; if wanted { configure() }
        case .poweredOff: ready = false; advertising = false; status = "蓝牙已关闭，广播暂停"
        case .unauthorized: ready = false; advertising = false; status = "权限被拒绝：请在设置 → 隐私与安全性 → 蓝牙中允许"
        case .unsupported: ready = false; advertising = false; status = "此设备不支持 BLE 外设"
        case .resetting, .unknown: ready = false; advertising = false; status = "等待蓝牙恢复"
        @unknown default: status = "蓝牙不可用"
        }
    }
    private func configure() {
        guard wanted, let manager, manager.state == .poweredOn else { return }
        if ready { advertise(); return }
        manager.removeAllServices()
        let service = CBMutableService(type: Self.service, primary: true)
        // Static read-only value. No password, account, cloud, or unlock command.
        let characteristic = CBMutableCharacteristic(type: Self.characteristic, properties: [.read], value: Data("NearGuard/1".utf8), permissions: [.readable])
        service.characteristics = [characteristic]
        manager.add(service); status = "正在建立本地 BLE 服务…"
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard wanted else { return }
        if let error { status = "服务失败：\(error.localizedDescription)"; ready = false; return }
        ready = true; advertise()
    }
    private func advertise() {
        guard wanted, ready, let manager else { return }
        manager.stopAdvertising()
        manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.service], CBAdvertisementDataLocalNameKey: "NearGuard Phone"])
    }
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard wanted else { return }
        advertising = error == nil
        status = error.map { "广播失败：\($0.localizedDescription)" } ?? "正在广播 NearGuard Phone"
    }
    func foreground() { if wanted && manager?.state == .poweredOn && ready { advertise() } }
}

@main
struct NearGuardPhoneApp: App {
    @StateObject private var beacon = Beacon()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 64)).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("NearGuard Phone").font(.largeTitle.bold())
                    Text("本地 BLE 伴侣 · 只辅助 Mac 锁屏").font(.headline)
                    Label(beacon.status, systemImage: beacon.advertising ? "antenna.radiowaves.left.and.right" : "pause.circle").font(.headline)
                    Button(beacon.wanted ? "停止广播" : "开始广播") { if beacon.wanted { beacon.stop() } else { beacon.start() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Text("首次设置").font(.title2.bold())
                    Text("1. 点击开始广播，允许蓝牙权限。\n2. 保持此页面在前台，在 Mac 扫描并选择 NearGuard Phone。\n3. 在 Mac 开始观察，校准信号，先测试离开与返回。")
                    Text("后台与重连限制").font(.title2.bold())
                    Text("退到后台后 iOS 会改变广播方式；Mac 不保证能重新发现。已有连接可能帮助持续读取 RSSI，但强退、重启、断连后可能需要重新打开本页面。不要把后台模式当作可靠保证。")
                    Text("没有云端、账号或密码。设备名称与服务 UUID 不是加密身份认证。不会解锁 Mac，RSSI 也不是距离测量。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 600, alignment: .leading).frame(maxWidth: .infinity)
            }.onChange(of: phase) { _, value in if value == .active { beacon.foreground() } }
        }
    }
}
