import Foundation
import Cocoa
import Carbon

public class KeyInterceptor {
    public static let shared = KeyInterceptor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    public private(set) var isRunning: Bool = false
    
    // 按键录制监听钩子：(keyCode, flags) -> 是否消费
    public var onRawKeyDown: ((UInt16, CGEventFlags) -> Bool)?
    
    // 鼠标按键录制监听钩子：(buttonNumber) -> 是否消费
    public var onRawMouseDown: ((Int64) -> Bool)?
    
    // 实时按键/鼠标状态反馈钩子：(inputName, actionDescription) -> Void
    public var onLiveEvent: ((String, String) -> Void)?
    
    private let logQueue = DispatchQueue(label: "com.keylite.logger", qos: .utility)
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()
    
    // 使用不可变 let，避免 lazy var 在多线程并发访问时的竞态隐患
    private let logURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".keylite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log")
    }()
    
    private let oldLogURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".keylite", isDirectory: true)
        return dir.appendingPathComponent("app.log.old")
    }()
    
    // 节流与退避状态记录
    private var lastLiveEventDispatchTime: DispatchTime = .now()
    private var isReEnabling = false
    private var logWriteCounter: Int = 0
    
    public init() {}
    
    public func log(_ message: String) {
        let line = "[\(Self.dateFormatter.string(from: Date()))] \(message)\n"
        print(line, terminator: "")
        
        // 异步后台落盘，严禁在 CGEventTap 回调的主流程中同步操作磁盘导致事件超时被挂起
        logQueue.async { [weak self] in
            guard let self = self else { return }
            let path = self.logURL.path
            self.logWriteCounter += 1
            
            // 日志保护与安全轮转：每写入 20 条日志检查一次文件大小，大于 2MB 时执行原子文件轮转
            // 彻底杜绝二进制切片截断 UTF-8 中文字符造成的乱码，且避免每次击键都查询磁盘属性
            if self.logWriteCounter % 20 == 0 {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? Int64, size > 2 * 1024 * 1024 {
                    try? FileManager.default.removeItem(at: self.oldLogURL)
                    try? FileManager.default.moveItem(at: self.logURL, to: self.oldLogURL)
                }
            }
            
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: path) {
                    if let fileHandle = try? FileHandle(forWritingTo: self.logURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        try? fileHandle.close()
                    }
                } else {
                    try? data.write(to: self.logURL)
                }
            }
        }
    }
    
    public func start() -> Bool {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                log("🔄 重新激活系统挂起的 EventTap")
            }
            if CGEvent.tapIsEnabled(tap: tap) {
                self.isRunning = true
                return true
            }
            // 若重新使能失败（如休眠唤醒后 MachPort 彻底失效），彻底注销并重新创建
            stop()
        }
        
        let trustedAX = AXIsProcessTrusted()
        let trustedInput = CGPreflightListenEventAccess()
        log("🚀 启动按键/鼠标拦截器: Accessibility=\(trustedAX), InputMonitoring=\(trustedInput)")
        
        // 监听: 键盘按下/弹起 + 鼠标侧键按下/弹起 + 滚轮滚动
        let eventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let refcon = refcon {
                    let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
                    interceptor.scheduleReEnable()
                }
                // 超时/用户输入禁用是系统状态通知，严禁将其作为普通用户按键放行，必须返回 nil
                return nil
            }
            
            guard let refcon = refcon else {
                return Unmanaged.passUnretained(event)
            }
            let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            return interceptor.handleEvent(proxy: proxy, type: type, event: event)
        }
        
        // 1. 尝试以 Session + defaultTap 创建 (拥有完整事件拦截与重写能力)
        var tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: observer
        )
        
        // 2. 如果 Session 失败，尝试以 HID 级创建
        if tap == nil {
            tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: observer
            )
        }
        
        guard let validTap = tap else {
            log("❌ 无法创建 CGEventTap，请确保已授予「辅助功能」与「输入监控」权限")
            return false
        }
        
        self.eventTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
        
        self.isRunning = true
        log("✅ 按键与鼠标拦截器成功启动！")
        return true
    }
    
    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CFMachPortInvalidate(tap)
            self.eventTap = nil
            self.runLoopSource = nil
        }
        self.isRunning = false
        log("⏹️ 按键拦截器已停止")
    }
    
    public func scheduleReEnable() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isReEnabling else { return }
            self.isReEnabling = true
            self.log("⚠️ CGEventTap 收到系统挂起/超时通知，执行 500ms 防抖退避重激活...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.isReEnabling = false
                self.reEnable()
            }
        }
    }
    
    public func reEnable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            // 检测 re-enable 是否真正成功（权限可能已被用户撤销或系统挂起）
            if CGEvent.tapIsEnabled(tap: tap) {
                log("🔄 CGEventTap 被系统挂起后已重新激活")
            } else {
                log("⚠️ CGEventTap 重新激活失败，权限已失效，立即彻底注销以释放输入管线")
                stop()
                PermissionManager.shared.refresh()
                PermissionManager.shared.startPolling()
            }
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // 1. 忽略自身模拟发送的快捷键，防止死循环
        let marker = event.getIntegerValueField(.eventSourceUserData)
        if marker == ShortcutSimulator.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        
        // 2. 滚轮翻转处理 (反转鼠标滚轮滚动方向)
        if type == .scrollWheel {
            if AppConfig.shared.enabled && AppConfig.shared.invertScroll {
                let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
                // 仅翻转实体鼠标滚轮 (isContinuous == 0)，不影响 MacBook 触控板自然双指滚动
                if isContinuous == 0 {
                    let deltaY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
                    let fixedDeltaY = event.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)
                    let pointDeltaY = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
                    
                    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -deltaY)
                    event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedDeltaY)
                    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pointDeltaY)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // 3. 鼠标按键处理 (Button 2: 中键, Button 3: 侧键后退, Button 4: 侧键前进 等)
        if type == .otherMouseDown || type == .otherMouseUp {
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            
            // 鼠标按键录制器监听 (在录制弹窗开启时捕获)
            if type == .otherMouseDown, let mouseRecorder = onRawMouseDown {
                if NSApp.isActive {
                    let handled = mouseRecorder(buttonNumber)
                    if handled {
                        return nil
                    }
                } else {
                    self.onRawMouseDown = nil
                }
            }
            
            // 查找鼠标按键规则
            let mouseMapping = AppConfig.shared.mappings.values.first(where: {
                $0.isMouse && $0.mouseButton == buttonNumber
            })
            
            let btnName: String
            switch buttonNumber {
            case 2: btnName = "鼠标中键 Button 2"
            case 3: btnName = "鼠标侧键(Button 4)"
            case 4: btnName = "鼠标侧键(Button 5)"
            default: btnName = "鼠标按键(Button \(buttonNumber + 1))"
            }
            
            if let mapping = mouseMapping, mapping.actionType != .none {
                if type == .otherMouseDown {
                    let desc = descriptionForAction(mapping)
                    log("🖱️ 捕获 \(btnName) -> 执行: \(desc)")
                    
                    if let onLiveEvent = self.onLiveEvent {
                        DispatchQueue.main.async {
                            onLiveEvent(btnName, desc)
                        }
                    }
                    self.triggerAction(mapping: mapping)
                }
                // 彻底消费该侧键，阻止系统默认或异常行为
                return nil
            } else if type == .otherMouseDown, let onLiveEvent = self.onLiveEvent {
                // 未配置规则时向监视器反馈原生事件
                DispatchQueue.main.async {
                    onLiveEvent(btnName, "未配置快捷指令 (原生放行)")
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // 4. 键盘按键处理
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let keyName = ShortcutDef.keyCodeToString(keyCode)
        
        // 录制器监听 (在录制弹窗开启时捕获)
        if type == .keyDown, let recorder = onRawKeyDown {
            // 安全机制：仅在 KeyLite 处于活跃前台时拦截录制，防止切到其他应用输入时吞噬按键或截获密码
            if NSApp.isActive {
                let handled = recorder(keyCode, event.flags)
                if handled {
                    return nil
                }
            } else {
                // 失焦时立刻注销录制器，恢复全局正常输入
                self.onRawKeyDown = nil
            }
        }
        
        // 全局暂停时放行
        guard AppConfig.shared.enabled else {
            if type == .keyDown, let onLiveEvent = self.onLiveEvent {
                DispatchQueue.main.async {
                    onLiveEvent(keyName, "KeyLite 已暂停 (放行原生按键)")
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        // 匹配键盘按键映射规则
        // 兼容性：罗技 K868 的 F8 在未开启 FnLock 时可能作为 PrintScreen(105) 发送
        var mapping = AppConfig.shared.mappings.values.first(where: { !$0.isMouse && $0.keyCode == keyCode })
        if mapping == nil && (keyCode == 100 || keyCode == 105) {
            mapping = AppConfig.shared.mappings["F8"]
        }
        
        if let mapping = mapping, mapping.actionType != .none {
            if type == .keyDown {
                // 关键防线：过滤 macOS 系统按键长按自动连发（keyboardEventAutorepeat），防止连续派发高频动作引发应用崩溃或卡死
                let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if isAutorepeat {
                    return nil
                }
                
                let actionDesc = descriptionForAction(mapping)
                log("⌨️ 捕获按键: [\(keyName)] -> 命中规则: [\(mapping.displayName)] -> 执行: \(actionDesc)")
                
                if let onLiveEvent = self.onLiveEvent {
                    DispatchQueue.main.async {
                        onLiveEvent("键盘 [\(keyName)]", actionDesc)
                    }
                }
                self.triggerAction(mapping: mapping)
            }
            // 彻底吞噬原物理按键，防止原生 F 键或系统自带截屏被触发
            return nil
        }
        
        // 未命中规则，正常放行给系统
        // 性能保护：仅在 UI 处于前台测试状态时且以 100ms 节流频率向主线程调度派发，避免 7*24 正常打字时产生 GCD 洪泛
        if type == .keyDown, let onLiveEvent = self.onLiveEvent {
            let now = DispatchTime.now()
            if now.uptimeNanoseconds - lastLiveEventDispatchTime.uptimeNanoseconds >= 100_000_000 {
                lastLiveEventDispatchTime = now
                DispatchQueue.main.async {
                    onLiveEvent("按键 [\(keyName)]", "未配置快捷指令 (原生放行)")
                }
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    private func descriptionForAction(_ mapping: KeyMapping) -> String {
        switch mapping.actionType {
        case .preset: return mapping.presetAction?.displayName ?? "预设动作"
        case .customShortcut: return mapping.shortcut?.displayString ?? "自定义快捷键"
        case .launchApp: return "打开应用: \(mapping.appPath ?? "")"
        case .none: return "默认放行"
        }
    }
    
    private func triggerAction(mapping: KeyMapping) {
        switch mapping.actionType {
        case .none:
            break
            
        case .preset:
            if let act = mapping.presetAction {
                ShortcutSimulator.shared.executePresetAction(act)
            }
            
        case .customShortcut:
            if let shortcut = mapping.shortcut {
                ShortcutSimulator.shared.postShortcut(shortcut)
            }
            
        case .launchApp:
            if let app = mapping.appPath, !app.isEmpty {
                ShortcutSimulator.shared.launchApp(at: app)
            }
        }
    }
}
