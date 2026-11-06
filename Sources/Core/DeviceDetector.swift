import Foundation
import IOKit
import IOKit.hid

public class DeviceDetector: ObservableObject {
    public static let shared = DeviceDetector()
    
    @Published public var detectedMouseName: String = "检测中..."
    @Published public var detectedKeyboardName: String = "检测中..."
    
    private var timer: Timer?
    
    public init() {
        refreshDevices()
    }
    
    public func startPolling() {
        timer?.invalidate()
        refreshDevices()
        // 设置窗口在前台时，每 2 秒检测一次外接键鼠插拔
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }
    
    public func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
    
    public func refreshDevices() {
        // 无需 IOHIDManagerOpen（免权限只读探测设备列表）
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        
        var keyboards: [String] = []
        var mice: [String] = []
        
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                guard let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String,
                      !name.isEmpty else { continue }
                
                let isKeyboard = IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard))
                let isMouse = IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Mouse)) ||
                              IOHIDDeviceConformsTo(device, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Pointer))
                
                if isKeyboard && !keyboards.contains(name) {
                    keyboards.append(name)
                }
                if isMouse && !mice.contains(name) {
                    mice.append(name)
                }
            }
        }
        
        // 过滤苹果自带触控板/键盘，优先显示外部连接的键鼠设备
        let externalMice = mice.filter {
            !$0.contains("Apple Internal") && !$0.contains("Trackpad") && !$0.contains("Virtual") && !$0.contains("BTM") && !$0.contains("Headset")
        }
        let externalKeyboards = keyboards.filter {
            !$0.contains("Apple Internal") && !$0.contains("Virtual")
        }
        
        let mouseName = externalMice.first ?? mice.first(where: { !$0.contains("Virtual") }) ?? "未识别到外接鼠标"
        let keyboardName = externalKeyboards.first ?? keyboards.first(where: { !$0.contains("Virtual") }) ?? "未识别到外接键盘"
        
        DispatchQueue.main.async {
            if self.detectedMouseName != mouseName {
                self.detectedMouseName = mouseName
            }
            if self.detectedKeyboardName != keyboardName {
                self.detectedKeyboardName = keyboardName
            }
        }
    }
}
