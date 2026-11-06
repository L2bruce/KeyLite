import Cocoa
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public static var shared: AppDelegate?
    
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        
        // 单实例保护：避免多开造成按键重复拦截
        let bundleId = Bundle.main.bundleIdentifier ?? "com.bruce.keylite"
        let currentPid = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        if let existing = runningApps.first(where: { $0.processIdentifier != currentPid }) {
            existing.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }
        
        // 纯菜单栏应用模式（不占用 Dock 栏）
        NSApp.setActivationPolicy(.accessory)
        
        // 注册睡眠与屏幕唤醒通知，保证合盖/锁屏后自动无缝自愈
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWakeNotification),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        
        // 1. 初始化菜单栏
        syncStatusItemVisibility()
        
        // 2. 尝试启动拦截器
        let started = KeyInterceptor.shared.start()
        KeyInterceptor.shared.log("应用启动完成，按键拦截器状态: \(started)")
        
        // 3. 如果未获得权限，稍后自动呼出设置与引导窗口
        if !started {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.openSettingsWindow()
            }
        }
    }
    
    @objc private func handleWakeNotification() {
        KeyInterceptor.shared.log("☀️ 系统唤醒，检查并自动激活拦截器状态...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            _ = KeyInterceptor.shared.start()
            PermissionManager.shared.refresh()
            DeviceDetector.shared.refreshDevices()
            self.updateMenu()
        }
    }
    
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettingsWindow()
        return true
    }
    
    public func syncStatusItemVisibility() {
        if AppConfig.shared.showMenuBarIcon {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                if let button = item.button {
                    if #available(macOS 11.0, *) {
                        button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyLite")
                    } else {
                        button.title = "⌨️"
                    }
                }
                statusItem = item
                updateMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }
    
    public func updateMenu() {
        guard let statusItem = statusItem else { return }
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "KeyLite 按键助手", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let isRunning = KeyInterceptor.shared.isRunning
        let statusTitle = isRunning
            ? (AppConfig.shared.enabled ? "🟢 状态：生效中" : "⏸️ 状态：已手动暂停")
            : "🟡 状态：等待授权"
        let statusMenuItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let settingsItem = NSMenuItem(title: "⚙️ 打开按键设置...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let lockItem = NSMenuItem(title: "🔒 立即安全锁屏", action: #selector(triggerLock), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)
        
        let wechatItem = NSMenuItem(title: "✂️ 触发微信截图", action: #selector(triggerWechat), keyEquivalent: "")
        wechatItem.target = self
        menu.addItem(wechatItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let launchItem = NSMenuItem(
            title: LaunchAtLoginManager.shared.isEnabled ? "✓ 🚀 开机自动启动" : "🚀 开机自动启动",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        menu.addItem(launchItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "❌ 退出 KeyLite", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc public func openSettingsWindow() {
        DeviceDetector.shared.startPolling()
        if !PermissionManager.shared.isAllGranted {
            PermissionManager.shared.startPolling()
        }
        
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let view = SettingsView()
        let hostingController = NSHostingController(rootView: view)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "KeyLite - 键盘与鼠标按键助手"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 780, height: 680))
        window.minSize = NSSize(width: 720, height: 550)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        // 窗口关闭时立刻停止前台轮询，进入 0 CPU 深度省电模式
        DeviceDetector.shared.stopPolling()
    }
    
    @objc public func toggleLaunchAtLogin() {
        let current = LaunchAtLoginManager.shared.isEnabled
        LaunchAtLoginManager.shared.setEnabled(!current)
        updateMenu()
    }
    
    @objc public func triggerLock() {
        ShortcutSimulator.shared.lockScreen()
    }
    
    @objc public func triggerWechat() {
        ShortcutSimulator.shared.executePresetAction(.wechatScreenshot)
    }
    
    @objc public func quitApp() {
        KeyInterceptor.shared.stop()
        NSApplication.shared.terminate(nil)
    }
}
