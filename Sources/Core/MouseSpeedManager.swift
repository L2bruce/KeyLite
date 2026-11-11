import Foundation
import Cocoa
import IOKit
import IOKit.hidsystem

public struct DpiPreset: Identifiable, Equatable {
    public var id: Int { dpi }
    public let dpi: Int
    public let speed: Double
    public let name: String
    
    public init(dpi: Int, speed: Double, name: String) {
        self.dpi = dpi
        self.speed = speed
        self.name = name
    }
}

public class MouseSpeedManager: ObservableObject {
    public static let shared = MouseSpeedManager()
    
    // 经典常用 DPI 预设档位
    public static let presets: [DpiPreset] = [
        DpiPreset(dpi: 400,  speed: 0.5,  name: "400 精准"),
        DpiPreset(dpi: 800,  speed: 0.75, name: "800 办公"),
        DpiPreset(dpi: 1200, speed: 1.0,  name: "1200 标准"),
        DpiPreset(dpi: 1600, speed: 1.5,  name: "1600 敏捷"),
        DpiPreset(dpi: 2400, speed: 2.0,  name: "2400 顺滑"),
        DpiPreset(dpi: 3200, speed: 3.0,  name: "3200 极速")
    ]
    
    private init() {}
    
    /// 将当前配置中的鼠标速度写入 IOKit HID 与系统偏好设置
    @discardableResult
    public func applyCurrentSpeed() -> Bool {
        let speed = AppConfig.shared.mouseSpeed
        return setSystemMouseScaling(speed)
    }
    
    /// 设置并应用指定的鼠标速度
    public func setSpeed(_ speed: Double, showHud: Bool = false) {
        let clamped = max(0.1, min(speed, 5.0))
        AppConfig.shared.mouseSpeed = clamped
        AppConfig.shared.saveToFile()
        _ = setSystemMouseScaling(clamped)
        
        KeyInterceptor.shared.log("🖱️ 调整鼠标指针速度: \(String(format: "%.2f", clamped))x")
        
        if showHud {
            let dpi = approximateDpi(for: clamped)
            DispatchQueue.main.async {
                DpiHudWindow.shared.show(dpi: dpi, speed: clamped)
            }
        }
    }
    
    /// 循环切换下一个 DPI 预设档位
    public func cycleDpi() {
        let currentSpeed = AppConfig.shared.mouseSpeed
        let presets = Self.presets
        
        // 查找最接近当前速度的档位索引
        var closestIdx = 0
        var minDiff = Double.greatestFiniteMagnitude
        for (i, p) in presets.enumerated() {
            let diff = abs(p.speed - currentSpeed)
            if diff < minDiff {
                minDiff = diff
                closestIdx = i
            }
        }
        
        // 切到下一个档位
        let nextIdx = (closestIdx + 1) % presets.count
        let target = presets[nextIdx]
        setSpeed(target.speed, showHud: true)
    }
    
    /// 调高一级 DPI / 速度
    public func increaseSpeed() {
        let currentSpeed = AppConfig.shared.mouseSpeed
        let presets = Self.presets
        if let next = presets.first(where: { $0.speed > currentSpeed + 0.05 }) {
            setSpeed(next.speed, showHud: true)
        } else {
            setSpeed(min(5.0, currentSpeed + 0.25), showHud: true)
        }
    }
    
    /// 调低一级 DPI / 速度
    public func decreaseSpeed() {
        let currentSpeed = AppConfig.shared.mouseSpeed
        let presets = Self.presets
        if let prev = presets.last(where: { $0.speed < currentSpeed - 0.05 }) {
            setSpeed(prev.speed, showHud: true)
        } else {
            setSpeed(max(0.2, currentSpeed - 0.25), showHud: true)
        }
    }
    
    /// 根据倍率近似计算感官 DPI 标签
    public func approximateDpi(for speed: Double) -> Int {
        // 以 1.0x 对应 1200 DPI 为基准线性映射
        return Int((speed * 1200.0).rounded())
    }
    
    /// 读取当前系统的 mouse scaling
    public func readSystemMouseScaling() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return 1.0 }
        var handle: io_connect_t = 0
        let status = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle)
        IOObjectRelease(service)
        guard status == KERN_SUCCESS else { return 1.0 }
        
        var val: Double = 1.0
        let key = kIOHIDMouseAccelerationType as CFString
        IOHIDGetAccelerationWithKey(handle, key, &val)
        IOServiceClose(handle)
        return val >= 0 ? val : 1.0
    }
    
    /// 底层设置 macOS 鼠标指针加速度/倍率
    private func setSystemMouseScaling(_ val: Double) -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return false }
        var handle: io_connect_t = 0
        let status = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &handle)
        IOObjectRelease(service)
        guard status == KERN_SUCCESS else { return false }
        
        let key = kIOHIDMouseAccelerationType as CFString
        let ret = IOHIDSetAccelerationWithKey(handle, key, val)
        IOServiceClose(handle)
        
        // 同步持久化写入系统 defaults，确保与系统偏好保持一致
        CFPreferencesSetAppValue("com.apple.mouse.scaling" as CFString, "\(val)" as CFString, kCFPreferencesAnyApplication)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        
        return ret == KERN_SUCCESS
    }
}
