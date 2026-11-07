import Foundation
import Cocoa
import Carbon
import Darwin

public class ShortcutSimulator {
    public static let shared = ShortcutSimulator()
    public static let syntheticEventMarker: Int64 = 0x54494C45 // "TILE" 标记，用于识别自己合成的按键事件
    
    // 专用串行模拟队列：确保组合按键严格先进先出（FIFO），彻底防止多按键并发交错导致修饰键卡死
    private let simulationQueue = DispatchQueue(label: "com.keylite.simulation", qos: .userInteractive)
    
    // 1. 模拟发送组合按键 (串行后台队列发送，保持按压 30ms 确保被系统和微信等应用正确捕获)
    public func postShortcut(_ shortcut: ShortcutDef) {
        simulationQueue.async {
            let src = CGEventSource(stateID: .combinedSessionState)
            
            var flags = CGEventFlags()
            if shortcut.cmd { flags.insert(.maskCommand) }
            if shortcut.ctrl { flags.insert(.maskControl) }
            if shortcut.opt { flags.insert(.maskAlternate) }
            if shortcut.shift { flags.insert(.maskShift) }
            
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false) else {
                return
            }
            
            keyDown.flags = flags
            keyUp.flags = flags
            
            keyDown.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            keyUp.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            
            // 发送 KeyDown
            keyDown.post(tap: .cghidEventTap)
            
            // 物理按下保持 30 毫秒
            usleep(30000)
            
            // 发送 KeyUp
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    // 2. 毫秒级原生即时锁屏 (调用 macOS 系统私有登录框架的即时锁屏入口，无需 AppleScript 延迟)
    // 注意：不对 login.framework 调用 dlclose，因为：
    //   1. 私有框架函数可能内部有异步操作，过早 close 可能导致 crash
    //   2. dyld 共享缓存中的系统框架 dlclose 实际是 no-op，不会释放内存
    private static var loginHandle: UnsafeMutableRawPointer? = {
        return dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
    }()
    
    public func lockScreen() {
        DispatchQueue.global(qos: .userInteractive).async {
            if let handle = Self.loginHandle,
               let sym = dlsym(handle, "SACLockScreenImmediate") {
                typealias LockFunction = @convention(c) () -> Void
                let lockFunc = unsafeBitCast(sym, to: LockFunction.self)
                lockFunc()
                KeyInterceptor.shared.log("🔒 已通过 SACLockScreenImmediate 毫秒级锁定屏幕")
                return
            }
            
            // 备用兜底方案：模拟 Ctrl + Cmd + Q (系统标准锁屏快捷键)
            KeyInterceptor.shared.log("🔒 备用方案：模拟 Ctrl + Cmd + Q 锁屏")
            self.postShortcut(ShortcutDef(keyCode: 12, cmd: true, ctrl: true))
        }
    }
    
    // 3. 睡眠 Mac（NSAppleScript 必须在主线程调度执行以确保线程安全）
    public func sleepMac() {
        DispatchQueue.main.async {
            let script = "tell application \"System Events\" to sleep"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    // 4. 静音切换（NSAppleScript 必须在主线程调度执行以确保线程安全）
    public func toggleMute() {
        DispatchQueue.main.async {
            let script = "set volume output muted (not (output muted of (get volume settings)))"
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
    
    // 5. 打开指定 App（需在主线程调用 NSWorkspace API）
    public func launchApp(at path: String) {
        let url = URL(fileURLWithPath: path)
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
    
    // 6. 执行预设动作分发
    public func executePresetAction(_ action: PresetAction) {
        KeyInterceptor.shared.log("⚡ 执行动作: \(action.displayName)")
        
        switch action {
        // 鼠标与导航
        case .backHistory:
            // 浏览器 / 访达后退: Cmd + [
            postShortcut(ShortcutDef(keyCode: 33, cmd: true))
            
        case .forwardHistory:
            // 浏览器 / 访达前进: Cmd + ]
            postShortcut(ShortcutDef(keyCode: 30, cmd: true))
            
        case .scrollToTop:
            // 顶部: Cmd + Up
            postShortcut(ShortcutDef(keyCode: 126, cmd: true))
            
        case .scrollToBottom:
            // 底部: Cmd + Down
            postShortcut(ShortcutDef(keyCode: 125, cmd: true))
            
        // 浏览器与标签
        case .refresh:
            // 刷新: Cmd + R
            postShortcut(ShortcutDef(keyCode: 15, cmd: true))
            
        case .forceRefresh:
            // 强制刷新: Cmd + Shift + R
            postShortcut(ShortcutDef(keyCode: 15, cmd: true, shift: true))
            
        case .prevTab:
            // 上一个标签: Ctrl + Shift + Tab (主流浏览器和编辑器通用)
            postShortcut(ShortcutDef(keyCode: 48, ctrl: true, shift: true))
            
        case .nextTab:
            // 下一个标签: Ctrl + Tab
            postShortcut(ShortcutDef(keyCode: 48, ctrl: true))
            
        case .newTab:
            // 新建标签: Cmd + T
            postShortcut(ShortcutDef(keyCode: 17, cmd: true))
            
        case .closeTab:
            // 关闭标签: Cmd + W
            postShortcut(ShortcutDef(keyCode: 13, cmd: true))
            
        case .reopenTab:
            // 恢复关闭的标签: Cmd + Shift + T
            postShortcut(ShortcutDef(keyCode: 17, cmd: true, shift: true))
            
        // 截图与办公
        case .wechatScreenshot:
            // 微信截图: Ctrl + Cmd + A (kVK_ANSI_A = 0)
            postShortcut(ShortcutDef(keyCode: 0, cmd: true, ctrl: true))
            
        case .areaScreenshot:
            // 区域截图: Cmd + Shift + 4
            postShortcut(ShortcutDef(keyCode: 21, cmd: true, shift: true))
            
        case .fullScreenshot:
            // 全屏截图: Cmd + Shift + 3
            postShortcut(ShortcutDef(keyCode: 20, cmd: true, shift: true))
            
        case .spotlightSearch:
            // 聚焦搜索: Cmd + Space
            postShortcut(ShortcutDef(keyCode: 49, cmd: true))
            
        case .emojiPicker:
            // 表情符号: Ctrl + Cmd + Space
            postShortcut(ShortcutDef(keyCode: 49, cmd: true, ctrl: true))
            
        case .pastePlainText:
            // 粘贴纯文本: Opt + Shift + Cmd + V
            postShortcut(ShortcutDef(keyCode: 9, cmd: true, opt: true, shift: true))
            
        // 系统控制
        case .lockScreen:
            lockScreen()
            
        case .sleepMac:
            sleepMac()
            
        case .muteToggle:
            toggleMute()
            
        case .forceQuit:
            // 强制退出: Opt + Cmd + Esc
            postShortcut(ShortcutDef(keyCode: 53, cmd: true, opt: true))
            
        // 窗口与多任务
        case .missionControl:
            // 调度中心: Ctrl + Up
            postShortcut(ShortcutDef(keyCode: 126, ctrl: true))
            
        case .showDesktop:
            // 显示桌面: Cmd + F3
            postShortcut(ShortcutDef(keyCode: 99, cmd: true))
            
        case .appSwitcher:
            // 切换应用: Cmd + Tab
            postShortcut(ShortcutDef(keyCode: 48, cmd: true))
            
        case .toggleFullScreen:
            // 全屏切换: Ctrl + Cmd + F
            postShortcut(ShortcutDef(keyCode: 3, cmd: true, ctrl: true))
            
        case .minimizeWindow:
            // 最小化窗口: Cmd + M
            postShortcut(ShortcutDef(keyCode: 46, cmd: true))
        }
    }
}
