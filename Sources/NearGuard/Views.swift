import SwiftUI
import AppKit

struct GuardSummary: View {
    @ObservedObject var model: AppModel
    var compact = false
    var openSettings: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: model.realLock ? "lock.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 30)).foregroundStyle(model.realLock ? Color.orange : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NearGuard").font(.title2.bold())
                    Text(model.simulation ? "模拟演示 · 不会锁屏" : (model.realLock ? "真实锁屏模式" : "安全观察模式"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.running { Text("监控中").font(.caption.bold()).padding(6).background(Color.accentColor.opacity(0.12), in: Capsule()) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.status).font(.headline)
                Text(model.selectedName).lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(model.smoothedRSSI.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: compact ? 36 : 44, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("dBm · 平滑信号").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(model.armed ? "已布防" : "未布防").font(.caption.bold())
                }.accessibilityElement(children: .combine)
                if let r = model.rawRSSI { Text("原始信号 \(Int(r)) dBm · 不是米数").font(.caption).foregroundStyle(.secondary) }
                Text(model.detail).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button(model.running ? "暂停监控" : "开始观察", systemImage: model.running ? "pause.fill" : "play.fill") {
                    if model.running { model.stopMonitoring() } else { model.startMonitoring() }
                }.buttonStyle(.borderedProminent).disabled(!model.canUseBluetooth || (!model.running && !model.hasSelection))
                if compact { Button("设备与设置…", action: openSettings) }
                Spacer()
            }
            if compact {
                Text(model.bluetooth).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Text("只锁屏 · 不自动解锁").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
                }
            }
        }.padding(compact ? 20 : 0).frame(width: compact ? 360 : nil)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    init(model: AppModel, initialTab: Int = 0) {
        self.model = model; self._tab = State(initialValue: min(4, max(0, initialTab)))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GuardSummary(model: model)
            Picker("设置页面", selection: $tab) {
                Text("设备").tag(0); Text("校准与阈值").tag(1); Text("自动锁屏").tag(2); Text("事件记录").tag(3); Text("启动与偏好").tag(4)
            }.pickerStyle(.segmented)
            Group {
                switch tab {
                case 0: devicePane
                case 1: thresholdPane
                case 2: safetyPane
                case 4: startupPane
                default: eventPane
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            Text("蓝牙信号会受遮挡、休眠和干扰影响，也可能被仿冒。请保留系统自动锁定；NearGuard 不是身份验证或唯一安全措施。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(24).frame(minWidth: 590, idealWidth: 640, minHeight: 820, idealHeight: 860)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private var devicePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("监控方式", selection: Binding(get: { model.transport }, set: { model.changeTransport($0) })) {
                Text("系统蓝牙（无需 iPhone App，兼容性待验证）").tag(MonitoringTransport.system)
                Text("BLE 伴侣 / 标签").tag(MonitoringTransport.ble)
            }.disabled(!model.canUseBluetooth)
            if model.transport == .system { systemDevicePane } else { bleDevicePane }
        }
    }
    private var systemDevicePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("刷新系统配对设备") { model.refreshSystemDevices() }.disabled(!model.canUseBluetooth)
                Button("打开系统蓝牙设置…") { model.openBluetoothSettings() }.disabled(!model.canUseBluetooth)
            }
            Text(model.bluetooth).font(.subheadline)
            Text("先在系统设置完成配对与连接，再刷新。普通 iPhone 可能不出现在可用列表，或不支持 RSSI；不保证所有 iPhone 可用。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.systemDevices.isEmpty {
                Text("尚无列表 · 启动不会读取系统设备或请求权限").font(.headline).padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.systemDevices) { device in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name).font(.headline)
                                    Text("…\(device.id.suffix(5)) · \(device.connected ? "刷新时已连接" : "刷新时未连接")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(model.selectedSystemAddress == device.id ? "已选" : "选择") { model.selectSystemDevice(device) }
                            }
                            Divider()
                        }
                    }
                }.frame(maxHeight: 130)
            }
            Text("已选：\(model.selectedDescription)").font(.caption)
            Text("Mac 每 5 秒读取已有连接，不扫描、不重连。无需手机伴侣常驻或定时唤醒，但蓝牙无线耗电不等于零，尚未测量。失联默认 20 秒；RSSI 平滑及采样会增加离开检测延迟，不保证 8 秒内锁屏。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var bleDevicePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(model.devices.count) 个发现的设备").font(.headline)
                Spacer()
                Button(model.scanning && !model.running ? "停止扫描" : "扫描 30 秒", systemImage: "antenna.radiowaves.left.and.right") {
                    if model.scanning && !model.running { model.stopDiscovery() } else { model.discover() }
                }.disabled(!model.canUseBluetooth)
            }
            Text(model.bluetooth).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if model.devices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.largeTitle).accessibilityHidden(true)
                    Text("首次请点击扫描并授权蓝牙").font(.headline)
                    Text("打开 iPhone 伴侣并保持前台，或使用正在广播的 BLE 标签。普通 iPhone 蓝牙名称并不能保证可发现。")
                        .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 170).padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.devices) { device in
                            HStack(spacing: 12) {
                                Image(systemName: model.selectedID == device.id ? "checkmark.circle.fill" : "sensor.tag.radiowaves.forward")
                                    .foregroundStyle(Color.accentColor).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(device.name).font(.headline)
                                    Text("\(device.id.uuidString.suffix(8)) · \(device.connectable ? "可连接" : "广播设备") · \(max(0, Int(model.now - device.lastSeen))) 秒前")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(device.rssi) dBm").monospacedDigit().font(.subheadline)
                                Button(model.selectedID == device.id ? "已选" : "选择") { model.select(device) }
                                    .disabled(model.selectedID == device.id)
                                    .accessibilityLabel("选择 \(device.name)，标识 \(device.id.uuidString.suffix(8))")
                            }.padding(.vertical, 10)
                            Divider()
                        }
                    }
                }.frame(minHeight: 150, maxHeight: 230)
            }
            Text("已选标识：\(model.selectedDescription)").font(.caption).textSelection(.enabled)
            Text("iPhone 必须前台完成首次选择。退到后台后，Mac 重新发现/重连不保证可用；设备重启或强退伴侣也可能失联。配对仅保存设备标识，不是加密认证。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var thresholdPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("先观察，再校准").font(.headline)
            Text("将设备放在日常工作位置，开始观察后收集 12 个有效样本。校准暂时禁用真实锁屏，不清除选择；完成或取消后重新等待靠近。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(model.calibrationCount.map { "正在校准：\($0)/12" } ?? "在此位置校准", systemImage: "scope") { model.calibrate() }
                    .disabled(!model.running || model.rawRSSI == nil || model.calibrationCount != nil || !model.canUseBluetooth)
                if model.calibrationCount != nil { Button("取消") { model.cancelCalibration() } }
            }
            Form {
                thresholdSlider("靠近阈值", value: $model.near, range: -90 ... -35, suffix: "dBm")
                thresholdSlider("离开阈值", value: $model.far, range: -110 ... min(-38, model.near - 3), suffix: "dBm")
                thresholdSlider("持续离开", value: $model.grace, range: 3 ... 60, suffix: "秒")
                thresholdSlider("失联超时", value: $model.stale, range: 10 ... 90, suffix: "秒")
            }.disabled(model.running || !model.canUseBluetooth)
            Text("手动调整前请暂停。离开阈值至少低 3 dBm。平滑 0.25；靠近持续至少 3 秒（系统模式至少两个 5 秒间隔样本）；请求后冷却 30 秒；唤醒宽限 10 秒。系统模式校准约 60 秒，BLE 约 12 秒。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("保存阈值") { model.persistSettings() }.disabled(model.running || !model.canUseBluetooth)
        }
    }
    private func thresholdSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        HStack {
            Text(title).frame(width: 85, alignment: .leading)
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
            Text("\(Int(value.wrappedValue)) \(suffix)").monospacedDigit().frame(width: 78, alignment: .trailing)
        }
    }
    private var safetyPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(model.realLock ? "真实锁屏实际已启用" : "当前未执行真实锁屏", systemImage: "lock.shield").font(.headline)
            Text("勾选后需在独立弹窗确认误锁风险。保存的是你的选择，不是权限或布防状态；退出、重启、暂停、睡眠与校准不会清除选择。取消勾选立即停用。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Toggle("自动锁屏（记住我的选择）", isOn: Binding(get: { model.desiredAutomaticLock }, set: { model.setAutomaticLock($0) }))
                .disabled(!model.canUseBluetooth || model.calibrationCount != nil)
            Text(model.lockPreferenceStatus).font(.subheadline).foregroundStyle(model.realLock ? Color.orange : Color.secondary).fixedSize(horizontal: false, vertical: true)
            Button("请求辅助功能权限…") { model.requestAccessibility() }
                .disabled(!model.desiredAutomaticLock || !model.canUseBluetooth)
            Button("取消自动锁屏 · 只观察") { model.setAutomaticLock(false) }.disabled(!model.desiredAutomaticLock || !model.canUseBluetooth)
            Divider()
            Text("发送系统快捷键 Control + Command + Q。若已改快捷键、键盘映射或软件拦截，它可能不起作用；应用只记录“请求已发出”，不冒充已验证锁定。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("不会保存或输入密码，不会自动解锁或修改系统自动锁定设置。登录项是“启动与偏好”中的独立选择。辅助功能权限失效时实际只观察，选择仍保留；不会自动弹出授权。恢复后清空旧证据，重新等待稳定靠近。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var startupPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("登录后自动启动", systemImage: "power").font(.headline)
            Toggle("登录后自动启动 NearGuard", isOn: Binding(get: { model.loginStatus == .enabled }, set: { model.setLoginEnabled($0) }))
                .disabled(!model.canUseBluetooth)
            Text(loginStatusText).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let error = model.loginError { Text("操作未完成：\(error)").foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("刷新实际状态") { model.refreshLoginStatus() }.disabled(!model.canUseBluetooth)
                Button("打开系统登录项设置…") { model.openLoginSettings() }.disabled(!model.canUseBluetooth)
            }
            if model.loginStatus == .requiresApproval {
                Button("撤销待批准的登录项") { model.setLoginEnabled(false) }.disabled(!model.canUseBluetooth)
            }
            Text("这是用户登录后的启动，不是登录前开机服务。只有你操作开关才注册/注销；状态来自系统读回。待批准不代表已启用，也不会反复自动注册。请保持此 .app 路径稳定。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("自动恢复上次的 BLE 监控").font(.headline)
            Text("记住“开始 / 暂停”的选择。上次仍在监控、保存了有效 BLE UUID 且已授权蓝牙时，重新打开会在菜单栏安静恢复；若曾暂停则不会自动恢复。新安装、不曾授权或未选择设备时不扫描、不弹授权。系统蓝牙模式仍需主动刷新。")
                .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Text("自动锁屏选择在独立页面。恢复时仍需当前辅助功能权限、10 秒启动/唤醒宽限与新的稳定靠近；启动时远离或失联不会锁屏。只锁屏，不自动解锁。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var loginStatusText: String {
        if !model.canUseBluetooth { return "安全测试 / 演示：未读取或修改真实系统登录项" }
        switch model.loginStatus {
        case .enabled: return "系统实际状态：已启用，后续登录将启动"
        case .requiresApproval: return "系统实际状态：等待系统批准，尚未启用；请打开系统登录项设置"
        case .notRegistered: return "系统实际状态：未注册 / 未启用"
        case .notFound: return "系统实际状态：未找到此服务；请从完整 .app 打开"
        }
    }
    private var eventPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本次运行 · 最近 40 条").font(.headline)
            Text("事件记录在内存中；系统日志记录状态变化，不含密码。没有云端或账号。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.events.isEmpty { Text("暂无事件。请先在观察模式测试离开与返回。").foregroundStyle(.secondary) }
                    ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in Text(event).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 200)
        }
    }
}
