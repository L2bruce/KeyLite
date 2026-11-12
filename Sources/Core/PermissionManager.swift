import Foundation
import Cocoa
import ApplicationServices

public class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()
    
    @Published public var hasAccessibility: Bool = false
    @Published public var hasInputMonitoring: Bool = false
    @Published public var isInterceptorActive: Bool = false
    
    public var isAllGranted: Bool {
        return hasAccessibility && isInterceptorActive
    }
    
    private var timer: Timer?
    
    public init() {
        // 初始化仅执行一次无开销被动检查，严禁启动无限轮询，保护 macOS App Nap 与电池续航
        refresh()
    }
    
    public func refresh() {
        let ax = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        let running = KeyInterceptor.shared.isRunning
        
        DispatchQueue.main.async {
            self.hasAccessibility = ax
            self.hasInputMonitoring = im
            self.isInterceptorActive = running
            
            // 只要辅助功能权限就绪且拦截器未运行，即刻拉起
            if ax && !running {
                let success = KeyInterceptor.shared.start()
                self.isInterceptorActive = success
                if success {
                    AppDelegate.shared?.updateMenu()
                }
            } else {
                AppDelegate.shared?.updateMenu()
            }
        }
    }
    
    public func startPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            // 提高前台授权时的响应敏感度（0.4s），用户在系统设置勾选后切回秒级感知
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let oldAX = self.hasAccessibility
                let ax = AXIsProcessTrusted()
                let im = CGPreflightListenEventAccess()
                let running = KeyInterceptor.shared.isRunning
                
                self.hasAccessibility = ax
                self.hasInputMonitoring = im
                self.isInterceptorActive = running
                
                // 辅助功能已就绪且拦截器未启动：自动激活拦截器
                if (!oldAX || !running) && ax {
                    KeyInterceptor.shared.log("🎉 检测到辅助功能权限已授予，自动激活按键拦截器！")
                    let success = KeyInterceptor.shared.start()
                    self.isInterceptorActive = success
                    AppDelegate.shared?.updateMenu()
                }
                
                // 关键安全防线：若辅助功能被明确撤销，必须立即彻底注销释放 EventTap
                if !ax && running {
                    KeyInterceptor.shared.log("⚠️ 检测到辅助功能权限被撤销，立即注销并释放按键拦截器！")
                    KeyInterceptor.shared.stop()
                    self.isInterceptorActive = false
                    AppDelegate.shared?.updateMenu()
                }
                
                // 权限就绪且拦截器处于运行状态时，暂停高频轮询，避免后台消耗 CPU
                if ax && self.isInterceptorActive {
                    self.stopPolling()
                }
            }
        }
    }
    
    public func stopPolling() {
        DispatchQueue.main.async { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }
    
    public func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        
        // 同时精准打开 macOS 辅助功能设置面板
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }
    
    public func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        
        // 同时精准打开 macOS 输入监控设置面板
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        startPolling()
    }
    
    public func tryManualActivate() -> Bool {
        refresh()
        let success = KeyInterceptor.shared.start()
        refresh()
        return success
    }
}
