import Foundation
import Carbon

// 动作大类
public enum ActionType: String, Codable, CaseIterable {
    case preset = "preset"                 // 常用预设库选取
    case customShortcut = "customShortcut" // 用户录制的自定义快捷键
    case launchApp = "launchApp"           // 打开应用程序
    case none = "none"                     // 默认不拦截（系统原生处理）
    
    public var displayName: String {
        switch self {
        case .preset: return "常用预设动作"
        case .customShortcut: return "自定义快捷键"
        case .launchApp: return "打开应用程序"
        case .none: return "原生默认(不拦截)"
        }
    }
}

// 预设分类
public enum PresetCategory: String, CaseIterable {
    case mouseNavigation = "🖱️ 鼠标与导航"
    case webAndTabs = "🌐 浏览器与标签页"
    case officeAndTools = "✂️ 截图与日常办公"
    case systemHardware = "🔒 系统与安全"
    case windowsAndSpaces = "🪟 窗口与多任务"
}

// 内置预设动作
public enum PresetAction: String, Codable, CaseIterable {
    // 鼠标与导航
    case backHistory = "back_history"
    case forwardHistory = "forward_history"
    case scrollToTop = "scroll_to_top"
    case scrollToBottom = "scroll_to_bottom"
    case cycleDpi = "cycle_dpi"
    case dpiUp = "dpi_up"
    case dpiDown = "dpi_down"
    
    // 浏览器与标签
    case refresh = "refresh"
    case forceRefresh = "force_refresh"
    case prevTab = "prev_tab"
    case nextTab = "next_tab"
    case newTab = "new_tab"
    case closeTab = "close_tab"
    case reopenTab = "reopen_tab"
    
    // 截图与办公
    case wechatScreenshot = "wechat_screenshot"
    case areaScreenshot = "area_screenshot"
    case fullScreenshot = "full_screenshot"
    case spotlightSearch = "spotlight_search"
    case emojiPicker = "emoji_picker"
    case pastePlainText = "paste_plain_text"
    
    // 系统控制
    case lockScreen = "lock_screen"
    case sleepMac = "sleep_mac"
    case muteToggle = "mute_toggle"
    case forceQuit = "force_quit"
    
    // 窗口与多任务
    case missionControl = "mission_control"
    case showDesktop = "show_desktop"
    case appSwitcher = "app_switcher"
    case toggleFullScreen = "toggle_full_screen"
    case minimizeWindow = "minimize_window"
    
    public var category: PresetCategory {
        switch self {
        case .backHistory, .forwardHistory, .scrollToTop, .scrollToBottom, .cycleDpi, .dpiUp, .dpiDown:
            return .mouseNavigation
        case .refresh, .forceRefresh, .prevTab, .nextTab, .newTab, .closeTab, .reopenTab:
            return .webAndTabs
        case .wechatScreenshot, .areaScreenshot, .fullScreenshot, .spotlightSearch, .emojiPicker, .pastePlainText:
            return .officeAndTools
        case .lockScreen, .sleepMac, .muteToggle, .forceQuit:
            return .systemHardware
        case .missionControl, .showDesktop, .appSwitcher, .toggleFullScreen, .minimizeWindow:
            return .windowsAndSpaces
        }
    }
    
    public var displayName: String {
        switch self {
        case .backHistory: return "返回上一页 (⌘ [)"
        case .forwardHistory: return "前进下一页 (⌘ ])"
        case .scrollToTop: return "回到顶部 (⌘ ↑)"
        case .scrollToBottom: return "回到底部 (⌘ ↓)"
        case .cycleDpi: return "🎯 循环切换鼠标 DPI 档位"
        case .dpiUp: return "🔼 调高鼠标指针速度"
        case .dpiDown: return "🔽 调低鼠标指针速度"
            
        case .refresh: return "刷新页面 (⌘ R)"
        case .forceRefresh: return "强制刷新 (⌘ ⇧ R)"
        case .prevTab: return "切换上一个标签 (⌃ ⇧ Tab)"
        case .nextTab: return "切换下一个标签 (⌃ Tab)"
        case .newTab: return "新建标签页 (⌘ T)"
        case .closeTab: return "关闭标签页 (⌘ W)"
        case .reopenTab: return "恢复刚关闭的标签 (⌘ ⇧ T)"
            
        case .wechatScreenshot: return "微信截图 (⌃ ⌘ A)"
        case .areaScreenshot: return "区域截图 (⌘ ⇧ 4)"
        case .fullScreenshot: return "全屏截图 (⌘ ⇧ 3)"
        case .spotlightSearch: return "聚焦搜索 (⌘ Space)"
        case .emojiPicker: return "表情键盘 (⌃ ⌘ Space)"
        case .pastePlainText: return "粘贴纯文本 (⌥ ⇧ ⌘ V)"
            
        case .lockScreen: return "🔒 立即安全锁屏"
        case .sleepMac: return "🌙 电脑睡眠"
        case .muteToggle: return "🔇 静音切换"
        case .forceQuit: return "强制退出程序面板 (⌥ ⌘ ⎋)"
            
        case .missionControl: return "调度中心 (⌃ ↑)"
        case .showDesktop: return "显示桌面 (⌘ F3)"
        case .appSwitcher: return "切换应用程序 (⌘ Tab)"
        case .toggleFullScreen: return "全屏切换 (⌃ ⌘ F)"
        case .minimizeWindow: return "最小化窗口 (⌘ M)"
        }
    }
}

public struct ShortcutDef: Codable, Equatable {
    public var keyCode: UInt16
    public var cmd: Bool
    public var ctrl: Bool
    public var opt: Bool
    public var shift: Bool
    public var displayString: String
    
    public init(keyCode: UInt16, cmd: Bool = false, ctrl: Bool = false, opt: Bool = false, shift: Bool = false, displayString: String = "") {
        self.keyCode = keyCode
        self.cmd = cmd
        self.ctrl = ctrl
        self.opt = opt
        self.shift = shift
        self.displayString = displayString.isEmpty ? Self.formatDisplayString(keyCode: keyCode, cmd: cmd, ctrl: ctrl, opt: opt, shift: shift) : displayString
    }
    
    public static func formatDisplayString(keyCode: UInt16, cmd: Bool, ctrl: Bool, opt: Bool, shift: Bool) -> String {
        var parts: [String] = []
        if ctrl { parts.append("⌃ Ctrl") }
        if opt { parts.append("⌥ Opt") }
        if shift { parts.append("⇧ Shift") }
        if cmd { parts.append("⌘ Cmd") }
        
        let keyName = keyCodeToString(keyCode)
        if !keyName.isEmpty {
            parts.append(keyName)
        }
        return parts.joined(separator: " + ")
    }
    
    public static func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return ↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "Tab ⇥"
        case 49: return "Space"
        case 50: return "`"
        case 51: return "Delete ⌫"
        case 53: return "Esc ⎋"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "PrintScreen / F13"
        case 109: return "F10"
        case 111: return "F12"
        case 115: return "Home"
        case 116: return "PageUp"
        case 118: return "F4"
        case 119: return "End"
        case 120: return "F2"
        case 121: return "PageDown"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key(\(keyCode))"
        }
    }
}

public struct KeyMapping: Codable, Identifiable {
    public var id: String { keyId }
    public var keyId: String       // e.g. "MouseBack", "MouseForward", "F6", "F8", "PageUp"
    public var keyCode: UInt16     // 键盘键码（如果是鼠标按键则为 0）
    public var isMouse: Bool       // 是否为鼠标按键
    public var mouseButton: Int64  // 鼠标按键号（3: 后退, 4: 前进, 2: 中键等）
    public var displayName: String // 显示名称
    public var category: String    // "鼠标侧键", "核心快捷区", "右上角按键", "F区", "自定义"
    public var actionType: ActionType
    public var presetAction: PresetAction?
    public var shortcut: ShortcutDef?
    public var appPath: String?
    public var isCustom: Bool = false
    
    public init(
        keyId: String,
        keyCode: UInt16 = 0,
        isMouse: Bool = false,
        mouseButton: Int64 = -1,
        displayName: String,
        category: String,
        actionType: ActionType = .none,
        presetAction: PresetAction? = nil,
        shortcut: ShortcutDef? = nil,
        appPath: String? = nil,
        isCustom: Bool = false
    ) {
        self.keyId = keyId
        self.keyCode = keyCode
        self.isMouse = isMouse
        self.mouseButton = mouseButton
        self.displayName = displayName
        self.category = category
        self.actionType = actionType
        self.presetAction = presetAction
        self.shortcut = shortcut
        self.appPath = appPath
        self.isCustom = isCustom
    }
}

public class AppConfig: ObservableObject {
    @Published public var enabled: Bool = true
    @Published public var showMenuBarIcon: Bool = true
    @Published public var invertScroll: Bool = false // 翻转鼠标滚轮方向
    @Published public var mouseSpeed: Double = 1.0   // 鼠标指针速度 / DPI (0.1 ~ 5.0)
    @Published public var mappings: [String: KeyMapping] = [:]
    
    public static let shared = AppConfig()
    
    private let configURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".keylite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()
    
    public init() {
        loadDefaults()
        if FileManager.default.fileExists(atPath: configURL.path) {
            loadFromFile()
        } else {
            saveToFile()
        }
    }
    
    public func loadDefaults() {
        var map: [String: KeyMapping] = [:]
        
        // 1. 鼠标按键 (各类多键鼠标)
        map["MouseMiddle"] = KeyMapping(
            keyId: "MouseMiddle",
            isMouse: true,
            mouseButton: 2,
            displayName: "鼠标中键 Button 2",
            category: "鼠标设置",
            actionType: .none
        )
        map["MouseBack"] = KeyMapping(
            keyId: "MouseBack",
            isMouse: true,
            mouseButton: 3,
            displayName: "鼠标侧键：Button 4",
            category: "鼠标设置",
            actionType: .preset,
            presetAction: .backHistory
        )
        map["MouseForward"] = KeyMapping(
            keyId: "MouseForward",
            isMouse: true,
            mouseButton: 4,
            displayName: "鼠标侧键：Button 5",
            category: "鼠标设置",
            actionType: .preset,
            presetAction: .forwardHistory
        )
        
        // 2. 键盘核心快捷键 (Logi K868)
        map["F6"] = KeyMapping(
            keyId: "F6",
            keyCode: 97,
            displayName: "F6",
            category: "核心快捷区",
            actionType: .preset,
            presetAction: .refresh
        )
        map["F7"] = KeyMapping(
            keyId: "F7",
            keyCode: 98,
            displayName: "F7",
            category: "核心快捷区",
            actionType: .preset,
            presetAction: .lockScreen
        )
        map["F8"] = KeyMapping(
            keyId: "F8",
            keyCode: 100,
            displayName: "F8",
            category: "核心快捷区",
            actionType: .preset,
            presetAction: .wechatScreenshot
        )
        map["PageUp"] = KeyMapping(
            keyId: "PageUp",
            keyCode: 116,
            displayName: "PgUp",
            category: "右上角按键",
            actionType: .preset,
            presetAction: .prevTab
        )
        map["PageDown"] = KeyMapping(
            keyId: "PageDown",
            keyCode: 121,
            displayName: "PgDn",
            category: "右上角按键",
            actionType: .preset,
            presetAction: .nextTab
        )
        
        // 3. F5 及 其余 F 区按键
        let otherFKeys: [(id: String, code: UInt16, name: String)] = [
            ("F1", 122, "F1"),
            ("F2", 120, "F2"),
            ("F3", 99, "F3"),
            ("F4", 118, "F4"),
            ("F5", 96, "F5"),
            ("F9", 101, "F9"),
            ("F10", 109, "F10"),
            ("F11", 103, "F11"),
            ("F12", 111, "F12")
        ]
        for k in otherFKeys {
            map[k.id] = KeyMapping(keyId: k.id, keyCode: k.code, displayName: k.name, category: "F区", actionType: .none)
        }
        
        self.mappings = map
    }
    
    public func loadFromFile() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        struct SaveData: Codable {
            var enabled: Bool
            var showMenuBarIcon: Bool?
            var invertScroll: Bool?
            var mouseSpeed: Double?
            var mappings: [String: KeyMapping]
        }
        if let decoded = try? JSONDecoder().decode(SaveData.self, from: data) {
            self.enabled = decoded.enabled
            self.showMenuBarIcon = decoded.showMenuBarIcon ?? true
            self.invertScroll = decoded.invertScroll ?? false
            self.mouseSpeed = decoded.mouseSpeed ?? 1.0
            for (k, v) in decoded.mappings {
                var item = v
                if k == "MouseBack" && item.displayName.contains("后退") {
                    item.displayName = "鼠标侧键：Button 4"
                }
                if k == "MouseForward" && item.displayName.contains("前进") {
                    item.displayName = "鼠标侧键：Button 5"
                }
                if k == "MouseMiddle" {
                    item.displayName = "鼠标中键 Button 2"
                }
                if k == "MouseTop" { continue } // 彻底移除顶部按键
                if k == "F5" { item.displayName = "F5" }
                if k == "F6" { item.displayName = "F6" }
                if k == "F7" { item.displayName = "F7" }
                if k == "F8" { item.displayName = "F8" }
                if k == "PageUp" { item.displayName = "PgUp" }
                if k == "PageDown" { item.displayName = "PgDn" }
                self.mappings[k] = item
            }
            // 兼容老版本：如果配置中缺少 MouseMiddle，补充默认定义
            if self.mappings["MouseMiddle"] == nil {
                self.mappings["MouseMiddle"] = KeyMapping(
                    keyId: "MouseMiddle",
                    isMouse: true,
                    mouseButton: 2,
                    displayName: "鼠标中键 Button 2",
                    category: "鼠标设置",
                    actionType: .none
                )
            }
        }
    }
    
    public func saveToFile() {
        struct SaveData: Codable {
            var enabled: Bool
            var showMenuBarIcon: Bool
            var invertScroll: Bool
            var mouseSpeed: Double
            var mappings: [String: KeyMapping]
        }
        let save = SaveData(
            enabled: enabled,
            showMenuBarIcon: showMenuBarIcon,
            invertScroll: invertScroll,
            mouseSpeed: mouseSpeed,
            mappings: mappings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let encoded = try? encoder.encode(save) {
            try? encoded.write(to: configURL, options: .atomic)
        }
    }
    
    public func updateMapping(_ mapping: KeyMapping) {
        mappings[mapping.keyId] = mapping
        saveToFile()
    }
    
    public func addCustomMapping(keyCode: UInt16, name: String) -> KeyMapping {
        let id = "Custom_\(keyCode)"
        let newMapping = KeyMapping(
            keyId: id,
            keyCode: keyCode,
            displayName: name.isEmpty ? ShortcutDef.keyCodeToString(keyCode) : name,
            category: "自定义按键",
            actionType: .none,
            isCustom: true
        )
        mappings[id] = newMapping
        saveToFile()
        return newMapping
    }
    
    public func addCustomMouseMapping(buttonNumber: Int64, name: String) -> KeyMapping {
        let id = "Custom_Mouse_\(buttonNumber)"
        let defaultName: String
        switch buttonNumber {
        case 2: defaultName = "鼠标中键 Button 2"
        case 3: defaultName = "鼠标侧键 (Button 4)"
        case 4: defaultName = "鼠标侧键 (Button 5)"
        default: defaultName = "鼠标按键 (Button \(buttonNumber + 1))"
        }
        let newMapping = KeyMapping(
            keyId: id,
            keyCode: 0,
            isMouse: true,
            mouseButton: buttonNumber,
            displayName: name.isEmpty ? defaultName : name,
            category: "自定义按键",
            actionType: .none,
            isCustom: true
        )
        mappings[id] = newMapping
        saveToFile()
        return newMapping
    }
    
    public func removeCustomMapping(keyId: String) {
        mappings.removeValue(forKey: keyId)
        saveToFile()
    }
}
