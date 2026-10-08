import Foundation
import ServiceManagement
import NearGuardCore

/// Only explicit user toggles invoke writes. Construction performs no SM calls.
enum LoginItems {
    static func controller() -> LoginItemController {
        LoginItemController(read: {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            case .notRegistered: return .notRegistered
            case .notFound: return .notFound
            @unknown default: return .notFound
            }
        }, register: {
            guard Bundle.main.bundleURL.pathExtension == "app" else {
                throw NSError(domain: "NearGuard", code: 1, userInfo: [NSLocalizedDescriptionKey: "请从 dist/NearGuard.app 打开；裸可执行文件不能注册登录项。"])
            }
            try SMAppService.mainApp.register()
        }, unregister: { try SMAppService.mainApp.unregister() })
    }
    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
