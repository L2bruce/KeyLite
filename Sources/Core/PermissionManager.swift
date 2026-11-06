import Foundation
import Cocoa
import ApplicationServices

public class PermissionManager: ObservableObject {
    public static let shared = PermissionManager()
    
    @Published public var hasAccessibility: Bool = false
    @Published public var hasInputMonitoring: Bool = false
    @Published public var isInterceptorActive: Bool = false
    
    public var isAllGranted: Bool {
        return hasAccessibility && hasInputMonitoring
    }
    
    private var timer: Timer?
    
    public init() {
        refresh()
        startPolling()
    }
    
    public func refresh() {
        let ax = AXIsProcessTrusted()
        let im = CGPreflightListenEventAccess()
        let running = KeyInterceptor.shared.isRunning
        
        DispatchQueue.main.async {
            self.hasAccessibility = ax
            self.hasInputMonitoring = im
            self.isInterceptorActive = running
        }
    }
    
    public func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let oldAX = self.hasAccessibility
            let oldIM = self.hasInputMonitoring
            
            let ax = AXIsProcessTrusted()
            let im = CGPreflightListenEventAccess()
            let running = KeyInterceptor.shared.isRunning
            
            DispatchQueue.main.async {
                self.hasAccessibility = ax
                self.hasInputMonitoring = im
                self.isInterceptorActive = running
                
                // 如果用户刚刚在系统设置里开启了权限，且拦截器尚未启动，则自动拉起拦截器！
                if (!oldAX || !oldIM) && ax && im && !running {
                    KeyInterceptor.shared.log("🎉 检测到系统权限已授予，自动激活按键拦截器！")
                    let success = KeyInterceptor.shared.start()
                    self.isInterceptorActive = success
                }
                
                // 权限已全部就绪且拦截器处于运行状态时，暂停高频轮询，避免后台消耗 CPU
                if ax && im && running {
                    self.stopPolling()
                }
            }
        }
    }
    
    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    public func requestAccessibility() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
        
        // 同时精准打开 macOS 辅助功能设置面板
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        
        // 同时精准打开 macOS 输入监控设置面板
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func tryManualActivate() -> Bool {
        refresh()
        let success = KeyInterceptor.shared.start()
        refresh()
        return success
    }
}
