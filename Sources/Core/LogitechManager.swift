import Foundation
import IOKit
import IOKit.hid

public class LogitechManager {
    public static let shared = LogitechManager()
    
    private var hidManager: IOHIDManager?
    private var targetDevice: IOHIDDevice?
    private var reprogFeatureIndex: UInt8? = nil
    private var isTopButtonPressed: Bool = false
    
    // Top Button CID: 0x00FD
    public static let topButtonCID: UInt16 = 0x00FD
    
    private init() {}
    
    public func start() {
        if hidManager != nil { return }
        
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        
        // 匹配所有 HID 设备
        IOHIDManagerSetDeviceMatching(manager, nil)
        
        // 监听设备插入与移除
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let mgr = Unmanaged<LogitechManager>.fromOpaque(context).takeUnretainedValue()
            mgr.checkAndAttachDevice(device)
        }, Unmanaged.passUnretained(self).toOpaque())
        
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context = context else { return }
            let mgr = Unmanaged<LogitechManager>.fromOpaque(context).takeUnretainedValue()
            if mgr.targetDevice == device {
                mgr.targetDevice = nil
                mgr.reprogFeatureIndex = nil
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        
        // 监听 HID++ 报告
        IOHIDManagerRegisterInputReportCallback(manager, { context, result, sender, type, reportID, report, reportLength in
            guard let context = context else { return }
            let mgr = Unmanaged<LogitechManager>.fromOpaque(context).takeUnretainedValue()
            mgr.handleInputReport(reportID: reportID, report: report, length: reportLength)
        }, Unmanaged.passUnretained(self).toOpaque())
        
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openRet = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager
        
        if openRet == KERN_SUCCESS {
            scanExistingDevices()
        }
    }
    
    public func scanExistingDevices() {
        guard let manager = hidManager else { return }
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for dev in devices {
                checkAndAttachDevice(dev)
            }
        }
    }
    
    private func checkAndAttachDevice(_ device: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? ""
        let vendorId = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        
        // 罗技 Vendor ID 0x046d
        if vendorId == 0x046d || name.contains("Logi") || name.contains("Logitech") {
            let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int ?? 0
            // 匹配鼠标或通用控制节点
            if page == 0x01 || page == 0xff43 || page == 0xff00 {
                self.targetDevice = device
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.setupReprogControls(device: device)
                }
            }
        }
    }
    
    /// 向鼠标查询 0x1B04 (REPROG_CONTROLS_V4) 特征索引，并对顶部按键 0x00FD 开启重定向 (Divert)
    public func setupReprogControls(device: IOHIDDevice) {
        // 查询 IRoot (0x00) -> 0x1B04
        let query: [UInt8] = [
            0x11, 0xff, 0x00, 0x00, 0x1b, 0x04, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00
        ]
        _ = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x11, query, query.count)
    }
    
    private func handleInputReport(reportID: UInt32, report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length >= 7 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        
        // HID++ Long Report 0x11 或 Short Report 0x10
        guard bytes[0] == 0x11 || bytes[0] == 0x10 else { return }
        
        // 1. IRoot 查询 0x1B04 特征的回复: [0x11, 0xff, 0x00, 0x00, featureIndex, ...]
        if bytes[2] == 0x00 && bytes[3] == 0x00 && bytes[4] > 0 {
            let featureIdx = bytes[4]
            self.reprogFeatureIndex = featureIdx
            
            // 拿到 featureIndex 后，发送 setCidReporting 将 0x00FD (顶部按键) 开启 Divert (flags = 0x01)
            guard let dev = targetDevice else { return }
            let divertCmd: [UInt8] = [
                0x11, 0xff, featureIdx, 0x20, 0x00, 0xfd, 0x01, 0x00,
                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                0x00, 0x00, 0x00, 0x00
            ]
            _ = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0x11, divertCmd, divertCmd.count)
            KeyInterceptor.shared.log("🖱️ 成功向罗技设备注册顶部按键 (0x00FD) 重定向监听！")
            return
        }
        
        // 2. 监听重定向事件 (divertedButtonsEvent): [0x11, 0xff, featureIndex, 0x00, cid_MSB, cid_LSB, state, ...]
        if let featureIdx = self.reprogFeatureIndex, bytes[2] == featureIdx {
            // 事件通知通常 funcIndex 为 0x00
            let cid = (UInt16(bytes[4]) << 8) | UInt16(bytes[5])
            if cid == Self.topButtonCID || cid == 0x0052 || cid == 0x00d2 {
                // bytes[6] 包含按键状态：0x01 为按下，0x00 为松开
                let isDown = (bytes[6] & 0x01) != 0
                if isDown != isTopButtonPressed {
                    isTopButtonPressed = isDown
                    if isDown {
                        DispatchQueue.main.async {
                            KeyInterceptor.shared.handleLogitechTopButtonClick()
                        }
                    }
                }
            }
        }
    }
}
