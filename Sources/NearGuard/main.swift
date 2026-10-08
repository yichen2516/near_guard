import AppKit
import SwiftUI
import NearGuardCore

// Runs before NSApplication/AppModel: no BLE, AX, UI, or ServiceManagement calls.
private func runPreferenceProbe() -> Never {
    let args = CommandLine.arguments
    guard args.count == 4, args[1] == "--preferences-probe", args[2].hasPrefix("NearGuard.PersistenceProbe."),
          UUID(uuidString: String(args[2].dropFirst("NearGuard.PersistenceProbe.".count))) != nil,
          ["read", "true", "false", "cleanup"].contains(args[3]),
          let defaults = UserDefaults(suiteName: args[2]) else { exit(64) }
    let store = MonitoringPreferences(defaults: defaults)
    if args[3] == "true" || args[3] == "false" {
        store.desiredAutomaticLock = args[3] == "true"; store.monitoringWanted = args[3] == "true"
    } else if args[3] == "cleanup" { defaults.removePersistentDomain(forName: args[2]) }
    defaults.synchronize()
    let result: [String: Any] = ["desiredAutomaticLock": store.desiredAutomaticLock, "monitoringWanted": store.monitoringWanted, "runtimeGateEnabled": LockGate().enabled, "suite": args[2]]
    let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!); exit(0)
}
if CommandLine.arguments.contains("--preferences-probe") { runPreferenceProbe() }

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow?
    private let smoke = CommandLine.arguments.contains("--smoke-test")
    private let demo = CommandLine.arguments.contains("--demo")
    private lazy var model = AppModel(simulation: demo, smoke: smoke)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "NearGuard 接近锁屏")
            button.image?.isTemplate = true; button.toolTip = "NearGuard · 默认安全观察"
            button.target = self; button.action = #selector(togglePopover)
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: GuardSummary(model: model, compact: true, openSettings: { [weak self] in self?.showSettings() }))
        model.refreshLoginStatus()
        model.restoreMonitoringIfEligible()
        if model.showSettingsOnLaunch { showSettings() }
        if smoke {
            // Exercise denied entry points, not merely an idle window.
            model.refreshSystemDevices(); model.discover(); model.startMonitoring()
            model.calibrate(); model.requestAccessibility(); model.enableReal()
            model.setLoginEnabled(true); model.setLoginEnabled(false); model.refreshLoginStatus()
            model.restoreMonitoringIfEligible(); model.setAutomaticLock(true); model.setAutomaticLock(false)
            if !demo {
                model.changeTransport(.ble); model.discover(); model.startMonitoring()
                model.changeTransport(.system); model.refreshSystemDevices(); model.startMonitoring()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.finishSmoke() }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshLoginStatus() }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    private func showSettings() {
        popover.performClose(nil)
        if window == nil {
            var initialTab = 0
            if smoke, let index = CommandLine.arguments.firstIndex(of: "--smoke-tab"), index + 1 < CommandLine.arguments.count { initialTab = Int(CommandLine.arguments[index + 1]) ?? 0 }
            let controller = NSHostingController(rootView: SettingsView(model: model, initialTab: initialTab))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 860), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = smoke ? "NearGuard · 安全启动验证" : (demo ? "NearGuard · 模拟演示" : "NearGuard · 设备与设置")
            w.contentViewController = controller; w.minSize = NSSize(width: 590, height: 820)
            w.isReleasedWhenClosed = false; w.center(); window = w
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func finishSmoke() {
        let view = window?.contentView
        let rendered = (window?.isVisible ?? false) && (view?.bounds.width ?? 0) > 0
        var report: [String: Any] = ["app": "NearGuard", "nativeWindowRendered": rendered, "runLoopExercised": true, "bluetoothManagerCreated": model.managerCreated, "monitoring": model.running, "realLockEnabled": model.realLock, "lockRequests": model.lockRequests, "permissionPromptsRequested": model.permissionRequests, "mode": demo ? "simulated-demo-smoke" : "safe-smoke", "passed": rendered && !model.managerCreated && !model.running && !model.realLock && model.lockRequests == 0 && model.permissionRequests == 0]
        report["systemQueries"] = model.systemQueries
        report["systemPairedEnumerations"] = model.systemPairedEnumerations
        report["systemConnectionAttempts"] = model.systemConnectionAttempts
        report["transport"] = model.transport.rawValue
        report["loginRegistrationAttempts"] = model.loginRegistrationAttempts
        report["loginStatusReads"] = model.loginStatusReads
        report["desiredAutomaticLock"] = model.desiredAutomaticLock
        report["loginOSRegistration"] = "NOT_TESTED"
        report["hardwareCompatibility"] = "NOT_VERIFIED"
        report["phoneEnergy"] = "NOT_MEASURED"
        report["passed"] = (report["passed"] as? Bool == true) && model.systemQueries == 0 && model.systemPairedEnumerations == 0 && model.systemConnectionAttempts == 0 && model.loginRegistrationAttempts == 0 && model.loginStatusReads == 0
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-report"), index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            if let view, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) {
                    let image = (path as NSString).deletingPathExtension + ".png"
                    do { try data.write(to: URL(fileURLWithPath: image)); report["snapshot"] = image } catch { report["snapshotError"] = String(describing: error) }
                }
            }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                do { try data.write(to: URL(fileURLWithPath: path)) } catch { report["reportWriteError"] = String(describing: error); report["passed"] = false }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
        let success = report["passed"] as? Bool == true
        model.shutdown()
        fflush(stdout)
        exit(success ? 0 : 1)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
