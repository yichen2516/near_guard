# NearGuard

本地原生 macOS 菜单栏接近锁屏工具。使用 **Swift + AppKit/SwiftUI + IOBluetooth + CoreBluetooth**，无云端、无账号、无第三方包。提供系统蓝牙已有连接模式与原有 BLE 伴侣/标签模式。

**新安装默认 BLE、仅观察，不扫描、不枚举系统设备、不弹权限。** 首次需主动扫描、选择和开始；以后可安全恢复上次已开始的 BLE 监控。自动锁屏选择可以保存，但权限与靠近证据不保存，首次开启仍需勾选 + 独立风险确认。此版本 **只锁屏，不会自动解锁、保存密码或模拟输入密码**。

**重要：系统蓝牙模式的代码与本地安全测试已经实现，但 iPhone 实机兼容性未验证、手机耗电未测量。不是“任意 iPhone 都能配对后永久检测”或“绝对零耗电”的保证。**

## 直接打开

双击：

```text
dist/NearGuard.app
```

或：

```bash
open dist/NearGuard.app
```

首次打开显示“设备与设置”窗口；配置了登录启动或记住监控后，后续打开在菜单栏安静运行（手动打开也如此）。关闭窗口仍保留盾牌，随时可打开设置、暂停或退出。没有安装到 `/Applications`，构建和测试不会自动启用登录项或修改系统权限。

本仓库不包含预编译应用；本地构建生成 **arm64、ad-hoc 本地签名**的 `.app`，不是 Developer ID 公证发行版。代码签名校验和 LaunchServices 安全启动均通过。若把它下载/拷贝到另一台 Mac 后遇到 Gatekeeper，请使用系统正常的“右键 → 打开”流程；不要关闭 Gatekeeper。重新构建会改变 ad-hoc 签名，可能需要重新允许辅助功能权限。

## 系统蓝牙：不依赖 iPhone 伴侣进程（兼容性待验证）

1. 在 Mac 与手机的 **系统设置 → 蓝牙** 中尝试真正的系统配对。仅保存 BLE UUID 不算系统配对。普通 iPhone 不一定允许通用 Mac 蓝牙连接；只有系统已经提供可用连接时，此模式才有意义。
2. 在 NearGuard 的“设备”页选择 **系统蓝牙（无需 iPhone App，兼容性待验证）**，主动点击 **刷新系统配对设备**。只有此点击才调用 `IOBluetoothDevice.pairedDevices()`，可能需要系统蓝牙授权；不会自动选择列表首项。该 API 的配对列表可能包含此 Mac 其他用户配对的设备，界面只显示地址末尾。
3. 主动选择目标，点击 **开始观察**。Mac 每 **5 秒**检查已有连接 `isConnected()` 并读取 `rawRSSI()`。默认至少两个靠近样本、间隔约 5 秒才布防；不会在启动未连接时锁屏。模式与精确系统地址独立保存，绝不把 BLE UUID 当作系统配对地址。
4. 若“当前未连接”，请手动检查系统连接。此实现有意 **不调用 openConnection、closeConnection、不自动配对、不 inquiry、不扫描、不尝试重连**；连接尝试次数上限为 **0**，不会改变现有系统蓝牙链接。这样避免同步连接阻塞、重连洪泛和强行维持手机无线链接。
5. 若连接存在但 RSSI 返回 **127 或其他无效值**，明确显示“RSSI 不可用 / 不支持”，停止监控并关闭真实锁屏；绝不把这个哨兵伪造为远离或失联。系统蓝牙关闭/不可用也暂停。真正断连只在之前已见过稳定靠近布防时，按最后有效样本的失联超时产生事件。
6. 支持 RSSI 的真实连接下，校准、观察离开/返回后再决定是否开启真实锁屏。刷新、更换模式、重启监控、睡眠、异常与校准均清空旧证据并暂停实际锁屏，不清除已保存的自动锁屏选择。停止观察不关闭系统连接。

**手机端无 NearGuard 广播进程、定时器、扫描、定位、Wi-Fi 探测或 keepalive。** 因而这条实现路径不依赖 NearGuardPhone 是否前台、后台或被强退；但 **手机操作系统是否仍提供这个链接、控制器是否支持 RSSI、实际离开时能否可靠检测，必须真机测试**。配对成功不等于连接存在，更不等于 RSSI 可用。没有为建立连接开启个人热点、修改全局蓝牙配置或加入 AccessorySetupKit 占位实现。

**低功耗设计不等于零耗电：** 只在 Mac 端低频读取已有链接，没有手机伴侣常驻、没有连接/重连循环。控制器读取 RSSI 与已有无线链接仍可能带来耗电，尚未进行手机能耗测量。Mac 界面/判定 tick 为 1 秒，系统蓝牙读数受 5 秒节流控制。系统模式有效证据最大间隔为 **7 秒**，超过会重置近/远持续证据；BLE 保持 3 秒。默认失联 20 秒从最后有效样本起算；RSSI 平滑、5 秒采样、操作系统调度均增加检测延迟，**不能承诺“离开后 8 秒立即锁屏”**。

### 尚需实机验收

- 能否通过系统蓝牙配对，是否具有受支持的现有连接与负数 rawRSSI；如不可用，明确判定不支持而不是宣称完成。
- 不安装/不运行伴侣与强退伴侣时分别观察真实信号；手机锁屏、重启、系统链路中断/恢复、Mac 睡眠唤醒后验证重新布防。
- 多次实际离开/返回路线与无线干扰下验证误报、延迟；能耗需对照实验，不凭代码或截图下结论。
- 当前自动测试 **不枚举真实配对列表、不连接任何手机**。`hardwareCompatibility=NOT_VERIFIED`、`phoneEnergy=NOT_MEASURED`。

## BLE 伴侣 / 标签：先用观察模式试运行

1. 选择“BLE 伴侣 / 标签”，打开正在广播的 BLE 标签，或安装下方 iPhone 伴侣并保持在前台。
2. 点击 **扫描 30 秒**。此时才可能出现蓝牙授权。列表展示名称、标识后八位、RSSI、是否可连接、上次发现时间；**不会自动选择第一台设备**。
3. 选择目标设备，点击 **开始观察**。设备 UUID 和名称保存到本地偏好设置。上次明确开始且未暂停、已保存有效 UUID 并已有蓝牙授权时，重启自动恢复。暂停后不会由定时器、会话恢复或下次启动偷偷重启。
4. 在“校准与阈值”页，把设备放在正常工作位置，点击 **在此位置校准**。收集 12 个有效样本，用中位数确定靠近阈值与 12 dBm 的滞回间隔。校准期间实际只观察并清空旧状态；保存的自动锁屏选择不变，完成/取消后需重新稳定靠近。
5. 带着设备离开再返回，查看“事件记录”。请多次验证桌面、口袋、遮挡和实际离开路线，先不要启用真实锁屏。
6. 手动调阈值前先暂停，再保存。**dBm 是信号强度，不是米数**；更接近 0 表示更强。

可连接的所选设备会尝试建立 BLE 连接，连接后每秒调用 `readRSSI()`；不能连接的设备使用重复广播扫描回调。连接失败时继续观察广播并每 10 秒尝试重连。设备未广播/未连接时不会伪造信号。

### 开启真实锁屏（可选）

在已经开始监控后，进入“自动锁屏”页：

1. 勾选 **自动锁屏（记住我的选择）**，阅读独立风险弹窗并确认；不需要每天重复确认。取消弹窗不保存开启。
2. 如尚未授权，主动点击 **请求辅助功能权限…**，在系统设置 → 隐私与安全性 → 辅助功能中允许当前 `.app`。不会因登录启动自动弹权限。
3. 看清状态：勾选表示已保存意愿，**不表示实际已启用或已布防**。无辅助功能权限时显示“自动锁屏已记住，辅助功能权限待授权 / 实际只观察”。有权限、监控可用且新的稳定靠近完成后才实际生效。

退出、重启、暂停、睡眠、蓝牙异常、校准不会清除选择；**取消勾选立即取消保存的意愿并关闭实际门禁**。暂停保留锁屏选择但保存“不自动恢复监控”；主动恢复后重新等待靠近。应用退出保留“上次仍在监控”，不等同于用户暂停。任何恢复都不沿用旧 RSSI/布防，BLE 启动有 10 秒宽限；启动时设备已远离/失联绝不直接锁屏。辅助功能权限变化也清空证据并重新冷却。

应用发送 **Control + Command + Q**（系统锁屏快捷键），不会使用 `pmset displaysleepnow`、私有 loginwindow API 或密码输入。每次请求前再次检查辅助功能权限，拒绝/失败则退回观察模式。**日志只说“请求已发出”，没有宣称已验证系统实际锁定。** 如果你改变系统快捷键、键盘映射或有软件拦截快捷键，它可能不工作，请自行验证系统配置。

请手动解锁 Mac。没有靠近自动解锁。收到会话恢复通知时清空旧信号、冷却再布防；该通知不是锁屏状态验证，不能保证每次手动解锁都送达。即使通知未送达，NearGuard 自己发出的每次离开事件也会立即解除布防，只有冷却结束且再次稳定靠近后才可能再请求，避免离开状态持续导致反复锁屏。

## 登录后自动启动与安全恢复

进入 **启动与偏好**，主动勾选“登录后自动启动 NearGuard”。使用 macOS 公共 `SMAppService.mainApp`，并在每次注册/注销后读取同一服务的实际状态；不是写一个乐观的偏好开关。状态有“已启用 / 等待批准 / 未注册 / 未找到服务”，失败显示错误；待批准时使用按钮打开系统登录项设置批准或撤销。应用激活或点击刷新会重新读取外部系统设置变化，不自动重试注册。

“开机启动”实际是 **用户登录后启动**，不是登录前的后台服务。必须从完整 `dist/NearGuard.app` 使用；保持路径稳定。不会安装 LaunchAgent，也不会自动开启这个开关。真实 OS 注册、注销及重启/登录验收尚未执行，避免替你改变全局设置。

自动启动与自动锁屏是两个独立选择：上次手动开始监控且没有暂停、保存有效 BLE UUID、`CBManager.authorization == .allowedAlways` 时，启动才创建 manager 并恢复针对已保存设备的监控/重连。缺设备、无授权、新安装或安全测试不会盲扫或弹授权；系统模式保留原选择但需手动刷新。自动锁屏未勾选也可以恢复观察；已勾选但无辅助功能权限仅观察并提示待授权。启动/唤醒清空证据、有宽限，仍必须先见到新的稳定靠近才布防，不能把启动失联当离开。退出保留监控意愿，明确暂停则阻止下一次自动恢复。临时运行暂停不清除锁屏意愿。

## 判定规则与安全边界

| 规则 | 默认值 / 行为 |
| --- | --- |
| 时间 | 注入单调时间；运行时用 `ProcessInfo.systemUptime`，不用日期做状态计时 |
| 有效 RSSI | `-127...-1` dBm；拒绝 127 哨兵、0、越界、NaN、Infinity |
| 平滑 | EWMA，系数 0.25 |
| 连续样本 | BLE 最多间隔 3 秒；系统蓝牙 5 秒采样允许最大 7 秒间隔；超过清空靠近/远离持续计时，断流仅按独立失联超时处理 |
| 靠近 | 平滑信号 ≥ -65 dBm，连续有效靠近至少 3 秒才布防 |
| 离开 | 平滑信号 ≤ -78 dBm，持续 8 秒后产生一次事件 |
| 滞回 | 进入中间区间会取消持续远离计时；避免单个阈值附近抖动 |
| 失联 | 上次有效信号后 20 秒；**仅在已经见过稳定靠近/布防后生效** |
| 初始失联/远离 | 不布防，不锁屏 |
| 事件后 | 解除布防，30 秒冷却，并要求重新连续靠近 |
| 睡眠与唤醒 | 睡眠暂停，清空会话；唤醒清空旧 RSSI，至少 10 秒宽限并重新等待靠近 |
| 蓝牙关闭/权限拒绝/不支持 | 暂停并明确提示，**不直接当作离开事件**；实际锁屏暂停，保存的选择保留 |
| 过期回调 | 设备标识 + 不可变会话 epoch 门禁；停止/换设备后旧回调拒绝；重新开始/唤醒/校准采用新 central 身份拒绝旧扫描/连接回调 |
| 配置边界 | 阈值、计时与平滑系数有限值校验并限制范围 |

**RSSI 不是安全测距，也不是身份认证。** 无线干扰、人体遮挡、省电、设备休眠、断连和操作系统调度都会造成误判；设备名称、UUID、服务或广播也可能被仿冒。本工具只用于额外的“离开后锁屏”便利功能，**不能作为唯一安全控制**。请保留系统自身的自动锁定和口令要求。BLE 模式的“选择”只是保存 CoreBluetooth 标识；系统模式列出操作系统已配对设备，但这不把 RSSI 变成安全距离或 NearGuard 用户身份认证。

重复扫描与每秒读 RSSI 有功耗成本。设备实际支持情况须实测；蓝牙经典设备名称不等于可发现 BLE 广播，不保证任意耳机/手表/iPhone 都可以使用。

## iPhone 伴侣（已提供源码与可构建 Xcode 工程）

```text
iOS/NearGuardPhone.xcodeproj
```

要求 iOS 17+。用 Xcode 打开工程，选择 `NearGuardPhone` target，在 **Signing & Capabilities** 选择你自己的 Apple ID/开发团队，修改 Bundle ID（如发生冲突），选择你的 iPhone 构建安装。未替你登录 Apple ID、填写凭证或安装真机。

伴侣只有显式“开始广播/停止广播”与状态说明。使用 CoreBluetooth 外设模式，本地只读 GATT 服务：

```text
服务 UUID：CA375B98-741B-4A73-AC6B-27D0D1A0C551
只读特征：CB0871BA-D005-4DBD-A766-EE894EA62021
前台名称：NearGuard Phone
后台模式：bluetooth-peripheral
```

**首次发现/选择时必须让伴侣保持前台。后台重连不保证。** 普通切后台/锁手机不等于强制退出。当前伴侣没有实现 CoreBluetooth 状态保存与恢复，也没有使用 AccessorySetupKit；不能对所有设备承诺强退后的服务持续性。当前用户已确认强退并锁屏后仍有持续新信号、可以自动恢复连接；这是用户实机反馈，尚无助手独立采集日志。若实际失联，再主动打开伴侣。Mac 保存 UUID 只是设备选择记录，不是让 iOS 进程永久存活的系统配对。

iOS 已补上不透明 1024px AppIcon，接入 Debug/Release 资源编译；用 Xcode 再 Run 安装新版即可更新图标。`python3 Tests/test_ios_icon.py --built` 验证源图与编译后图标。 Apple 文档说明后台广告会忽略本地名称，并把服务 UUID 移到 overflow 区域，只能由显式扫描这些 UUID 的 **iOS** 设备发现。不能把它误读为“Mac 按服务过滤扫描即可可靠发现”。本 Mac 应用不声称解决这个限制，也不尝试私有 overflow 解码。

已建立的连接 + 周期 RSSI 读取，以及保存 UUID 后的 `retrievePeripherals(withIdentifiers:)`/连接尝试可能有帮助，但后台断连后、手机重启、应用强退后的重连 **只有当前用户报告的信号与自动恢复连接观察，没有助手独立真机验证，不作普适保证**。失联时可能需要重新将伴侣打开到前台。在没有伴侣/有效 BLE 广播时，不承诺普通 iPhone 会被发现。

## 可重复构建与测试

要求 macOS 14+、Xcode/Swift 工具链；无外部 Swift 包依赖。测试是纯本地确定性状态机测试，不依赖真实蓝牙、不发锁屏快捷键。

```bash
cd near_guard
./Scripts/test.sh                 # Debug/Release XCTest + Python 原生集成静态检查
./Scripts/build.sh                # Release 可执行文件 → dist/NearGuard.app → ad-hoc 签名校验
./Scripts/smoke.sh                # 真实原生窗口、主 runloop、安全自退出
./Scripts/smoke-launchservices.sh # 通过 open/LaunchServices 启动同一 .app，读回验证 JSON
./Scripts/build-ios.sh            # iOS Simulator SDK，CODE_SIGNING_ALLOWED=NO
./Scripts/verify.sh --with-ios    # 以上整体检查
python3 Scripts/report-system.py # 从实际日志/签名/smoke 生成汇总，并校验 SHA-256
```

模拟器构建产物：`.build/iOS/Build/Products/Debug-iphonesimulator/NearGuardPhone.app`。**模拟器构建成功 ≠ BLE/真机运行成功。** 不声称进行了 iPhone、实际无线测距或真实屏幕锁定测试。

应用还提供完全隔离的可视模式：

```bash
# 模拟信号明确标记为演示，不创建 BLE manager，不可启用锁屏
dist/NearGuard.app/Contents/MacOS/NearGuard --demo

# 自动两秒退出，保存原生窗口截图和 JSON
# --smoke-tab 0/1/2/3/4 分别预览设备、阈值、安全、日志、启动与偏好页
dist/NearGuard.app/Contents/MacOS/NearGuard --smoke-test \
  --smoke-tab 2 --smoke-report "$PWD/evidence/my-safe-smoke.json"
```

`--smoke-test` 创建真实 NSApplication 主 runloop 和原生窗口，并主动尝试两个模式、登录项开关、自动恢复与锁屏开关的受限入口；禁用扫描、监控、辅助功能请求、系统登录项读取/注册以及锁屏路径，不构造 CBCentralManager、不执行任何 IOBluetooth 配对枚举/连接状态/RSSI 查询。JSON 的 `systemQueries`、`systemPairedEnumerations`、`systemConnectionAttempts` 及 `loginRegistrationAttempts`、`loginStatusReads` 与 manager/权限/锁屏计数来自实际程序状态；脚本读回并断言均为零。截图是 AppKit view 渲染缓存，不需要屏幕录制权限。不要把 `--demo` 的模拟数据当作真实设备测试。

## 已完成的本地验证

- 原有 33 项 XCTest 保留；新增偏好、恢复资格、权限变更、登录项读回与安全 AppModel 测试，累计实际 Debug/Release 总数见 `evidence/system-verification-summary.json`。新增隔离 UserDefaults 的真/假跨进程往返；静态集成检查不冒充硬件验证。
- Release 原生 `.app` 构建成功，Info.plist 与图标资源有效，`codesign --verify --deep --strict` 通过。
- 直接启动与 `open`/LaunchServices 启动均渲染真实窗口后正常自退出：BLE manager 未创建，IOBluetooth 三项计数、权限请求与锁屏请求均为 0、`passed=true`。
- 五个设置页（含启动与偏好）支持安全快照；新的启动与自动锁屏页已生成并检查。
- iOS Simulator target（arm64/x86_64）使用 `CODE_SIGNING_ALLOWED=NO` 得到 **BUILD SUCCEEDED**。Xcode 的无 AppIntents 元数据提示不影响构建。
- 未触发真正锁屏、未请求权限、未安装真机、未启用登录项、未收集密码。

### 证据与主要文件

```text
Package.swift
Sources/NearGuardCore/ProximityEngine.swift   # 纯状态机
Sources/NearGuardCore/Safety.swift            # 锁屏门禁与样本会话门禁
Sources/NearGuard/AppModel.swift              # BLE、连接 RSSI、显式权限与锁屏请求
Sources/NearGuard/SystemBluetooth.swift       # 公共 IOBluetooth 已配对设备与已有连接读数
Sources/NearGuardCore/SystemPollingSession.swift # 5 秒节流与无效状态暂停
Sources/NearGuard/Views.swift                 # 中文原生设置与菜单摘要
Sources/NearGuard/main.swift                  # 菜单栏 AppKit 生命周期、安全 smoke
Tests/NearGuardCoreTests/ProximityTests.swift
Tests/NearGuardCoreTests/SystemBluetoothTests.swift
Tests/test_system_integration.py
Resources/Info.plist
Resources/NearGuard.icns
Scripts/{build,test,smoke,smoke-launchservices,verify,build-ios}.sh
Scripts/Icon.swift                           # 本地图标生成源码
iOS/NearGuardPhone.xcodeproj
iOS/NearGuardPhone/{NearGuardPhoneApp.swift,Info.plist}
dist/NearGuard.app
evidence/TDD.md                              # 包括失败实现尝试的诚实说明
evidence/tdd-index.json                      # 每轮 RED/GREEN 日志映射
evidence/tests-final.log
evidence/build-mac.log
evidence/codesign-verify.log
evidence/bundle-verification.log
evidence/smoke.json                          # 安全启动结果
evidence/launchservices-smoke.json
evidence/build-ios-simulator.log
evidence/{smoke,demo,threshold-pane,safety-pane,events-pane}.png
```

验证日志与截图在本地构建时生成，不随源码发布。

## Apple 原始资料

- [SMAppService：原生登录项](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [SMAppService.register：mainApp 在后续登录启动](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- [SMAppService.Status：已启用与待批准的区别](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum)

- [IOBluetoothDevice.pairedDevices](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/paireddevices())
- [IOBluetoothDevice.isConnected](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/isconnected())
- [IOBluetoothDevice.rawRSSI：须已连接，模块不支持或断连返回 127](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/rawrssi())

- [Mac keyboard shortcuts：Control-Command-Q 锁屏](https://support.apple.com/en-us/102650)
- [Core Bluetooth Background Processing for iOS Apps：后台外设广播限制](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
- [CBPeripheralManager.startAdvertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:))
- [AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

## 排查

- **系统模式无设备/无 RSSI：** 在系统设置检查真实配对与连接，再主动刷新/选择；普通 iPhone 可能不支持此连接。已连接仍返回 127 时此模式不适用，请保持暂停或改用 BLE；不要开启热点或修改安全配置来冒充验收。
- **BLE 看不到设备：** 确认它在做 BLE 广播；iPhone 伴侣请保持前台；重试扫描。名称为空的设备用标识区分。不要凭名称认定身份。
- **蓝牙权限拒绝：** 到系统设置的蓝牙隐私页允许应用，再重新打开/开始；没有自动修改系统设置。
- **已授权却不能启用：** 确认授权的是当前 `dist/NearGuard.app`；重新构建后可能需要重新允许。保持观察模式即可继续校准，不需要辅助功能权限。
- **误锁/容易失联：** 退回观察或暂停；增大持续离开/失联时间，调整阈值，比较无遮挡与口袋环境。不要用减少系统口令保护的方法解决。
- **卸载：** 退出菜单栏应用，删除这个项目目录即可；可在系统设置手动移除蓝牙/辅助功能授权。卸载前在“启动与偏好”关闭登录项或在系统设置移除。偏好保存模式、设备标识、名称、阈值、监控与自动锁屏选择，不保存系统权限、密码或靠近证据；NearGuard 不删除系统配对。
