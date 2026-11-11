import SwiftUI
import Cocoa

public struct SettingsView: View {
    @ObservedObject var config = AppConfig.shared
    @ObservedObject var permission = PermissionManager.shared
    @ObservedObject var devices = DeviceDetector.shared
    @ObservedObject var launchManager = LaunchAtLoginManager.shared
    
    @State private var editingKeyId: String? = nil
    @State private var showingAddKeySheet: Bool = false
    
    // 实时按键/鼠标监视状态
    @State private var liveInputName: String = "等待按键或侧键..."
    @State private var liveActionDesc: String = ""
    @State private var liveEventTime: Date = Date()
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部 Header
            headerView
            
            Divider()
            
            // 2. 权限引导条（如果已获得权限则自动平滑隐藏，无需手动多点）
            if !permission.isAllGranted {
                permissionBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 3. 实时测试视窗
            liveEventMonitorView
            
            Divider()
            
            // 4. 按键与侧键配置主体
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 1. 鼠标与滚轮设置模块
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("🖱️ 鼠标与滚轮设置")
                                    .font(.system(size: 15, weight: .bold))
                                Text("精准接管侧边按键，自由翻转滚轮方向，不影响触控板")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "computermouse.fill")
                                    .font(.system(size: 11))
                                Text("当前设备: \(devices.detectedMouseName)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.purple.opacity(0.12))
                            .foregroundColor(.purple)
                            .cornerRadius(6)
                        }
                        
                        VStack(spacing: 8) {
                            mouseSpeedCard
                            mouseInvertCard
                            keyRow(keyId: "MouseMiddle")
                            keyRow(keyId: "MouseBack")
                            keyRow(keyId: "MouseForward")
                        }
                    }
                    
                    // 2. 键盘设置模块 (统一顺序：F1 ~ F12, PageUp, PageDown)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("⌨️ 键盘按键设置")
                                    .font(.system(size: 15, weight: .bold))
                                Text("按序展示功能键 F1 ~ F12 以及右上角 PgUp / PgDn")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 5) {
                                Image(systemName: "keyboard.fill")
                                    .font(.system(size: 11))
                                Text("当前设备: \(devices.detectedKeyboardName)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                        }
                        
                        let sequentialKeys = [
                            "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "PageUp", "PageDown"
                        ]
                        VStack(spacing: 8) {
                            ForEach(sequentialKeys, id: \.self) { id in
                                keyRow(keyId: id)
                            }
                        }
                    }
                    
                    // 3. 自定义按键区 (放在键盘模块后面)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("🛠️ 自定义按键区")
                                    .font(.system(size: 15, weight: .bold))
                                Text("支持录制并添加任意按键进行个性化接管与模拟")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { showingAddKeySheet = true }) {
                                Label("添加按键", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        let customKeys = config.mappings.values.filter { $0.isCustom }
                        if customKeys.isEmpty {
                            Text("暂未添加自定义按键，点击右上角「添加按键」可录制键盘上的任意按键。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(customKeys.sorted(by: { $0.keyId < $1.keyId })) { mapping in
                                    keyRow(keyId: mapping.keyId)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // 5. 底部工具栏
            bottomBar
        }
        .frame(minWidth: 720, minHeight: 580)
        .onAppear {
            devices.startPolling()
            KeyInterceptor.shared.onLiveEvent = { input, action in
                self.liveInputName = input
                self.liveActionDesc = action
                self.liveEventTime = Date()
            }
        }
        .onDisappear {
            devices.stopPolling()
            permission.stopPolling()
            KeyInterceptor.shared.onLiveEvent = nil
        }
        .sheet(item: Binding<KeyMapping?>(
            get: {
                if let id = editingKeyId {
                    return config.mappings[id]
                }
                return nil
            },
            set: { editingKeyId = $0?.keyId }
        )) { mapping in
            EditMappingSheet(mapping: mapping) { updated in
                config.updateMapping(updated)
                editingKeyId = nil
            }
        }
        .sheet(isPresented: $showingAddKeySheet) {
            AddCustomKeySheet { newMapping in
                config.updateMapping(newMapping)
                showingAddKeySheet = false
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 26))
                .foregroundColor(.accentColor)
            
            Text("KeyLite")
                .font(.system(size: 18, weight: .bold))
            
            Spacer()
            
            // 状态胶囊
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12))
            .cornerRadius(12)
            
            Toggle("拦截开关", isOn: $config.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: config.enabled) { _ in
                    config.saveToFile()
                    AppDelegate.shared?.updateMenu()
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    private var statusColor: Color {
        if !permission.isAllGranted { return .orange }
        if !config.enabled { return .gray }
        return .green
    }
    
    private var statusText: String {
        if !permission.isAllGranted { return "等待权限" }
        if !config.enabled { return "已暂停" }
        return "生效中"
    }
    
    // MARK: - 权限横幅 (响应式自动消失)
    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 15))
                Text("macOS 权限提示：需要开启「辅助功能」权限以接管按键与鼠标侧键：")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button("🔄 检查并激活") {
                    let ok = permission.tryManualActivate()
                    if ok {
                        AppDelegate.shared?.updateMenu()
                    }
                }
                .controlSize(.small)
            }
            
            Text("💡 提示：点击「去授权」并在系统设置中开启「KeyLite」，完成后切回本窗口将秒级自动激活并关闭此提示。")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // 辅助功能 (核心必需权限)
                HStack(spacing: 6) {
                    Image(systemName: permission.hasAccessibility ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(permission.hasAccessibility ? .green : .red)
                    Text("系统辅助功能 (必需)")
                        .font(.system(size: 11, weight: .medium))
                    if !permission.hasAccessibility {
                        Button("去授权") {
                            permission.requestAccessibility()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    } else {
                        Text("已就绪")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .animation(.easeInOut(duration: 0.3), value: permission.isAllGranted)
    }
    
    // MARK: - 实时测试视窗
    private var liveEventMonitorView: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.green)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("实时捕获反馈：")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(liveInputName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                }
                if !liveActionDesc.isEmpty {
                    Text(liveActionDesc)
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Text("实时响应中")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
    }
    
    // MARK: - 鼠标速度与 DPI 调节卡片
    private var mouseSpeedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "cursorarrow.rays")
                    .foregroundColor(.indigo)
                    .font(.system(size: 20))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("鼠标指针速度与 DPI 调节")
                            .font(.system(size: 13, weight: .semibold))
                        Text(String(format: "%.2fx (约 %d DPI)", config.mouseSpeed, MouseSpeedManager.shared.approximateDpi(for: config.mouseSpeed)))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.indigo.opacity(0.15))
                            .foregroundColor(.indigo)
                            .cornerRadius(4)
                    }
                    Text("底层 IOKit 极速注入，即时生效无需重启，0% 额外 CPU 消耗")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                Text("慢")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Slider(
                    value: Binding<Double>(
                        get: { config.mouseSpeed },
                        set: { newVal in
                            MouseSpeedManager.shared.setSpeed(newVal)
                        }
                    ),
                    in: 0.25...4.0,
                    step: 0.05
                )
                .tint(.indigo)
                
                Text("快")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                Text("预设档位:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                
                ForEach(MouseSpeedManager.presets) { preset in
                    let isSelected = abs(config.mouseSpeed - preset.speed) < 0.08
                    Button(action: {
                        MouseSpeedManager.shared.setSpeed(preset.speed, showHud: true)
                    }) {
                        Text(preset.name)
                            .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(isSelected ? .indigo : .secondary)
                }
                Spacer()
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
    }
    
    // MARK: - 翻转鼠标卡片
    private var mouseInvertCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.and.down.circle.fill")
                .foregroundColor(.purple)
                .font(.system(size: 22))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("翻转鼠标滚轮滚动方向")
                        .font(.system(size: 13, weight: .semibold))
                    Text(config.invertScroll ? "已开启翻转" : "系统默认方向")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(config.invertScroll ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.15))
                        .foregroundColor(config.invertScroll ? .purple : .secondary)
                        .cornerRadius(4)
                }
                Text("反转鼠标垂直滚轮滚动方向（保持 Mac 自带触控板的双指自然滑动不变）")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("翻转滚轮", isOn: $config.invertScroll)
                .toggleStyle(.switch)
                .labelsHidden()
                .onChange(of: config.invertScroll) { _ in
                    config.saveToFile()
                    AppDelegate.shared?.updateMenu()
                }
        }
        .padding(12)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(8)
    }
    
    // MARK: - 单行按键项
    private func keyRow(keyId: String) -> some View {
        guard let mapping = config.mappings[keyId] else { return AnyView(EmptyView()) }
        
        return AnyView(
            HStack {
                // 图标
                Image(systemName: mapping.isMouse ? "computermouse.fill" : "keyboard")
                    .foregroundColor(mapping.isMouse ? .purple : .blue)
                    .frame(width: 20)
                
                // 按键标识
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapping.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    if mapping.isMouse || mapping.isCustom {
                        Text(mapping.keyId)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 170, alignment: .leading)
                
                // 箭头
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                // 触发动作
                HStack {
                    Text(actionSummary(mapping))
                        .font(.system(size: 12))
                        .foregroundColor(mapping.actionType == .none ? .secondary : .primary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
                
                // 操作按钮
                Button("修改") {
                    editingKeyId = mapping.keyId
                }
                .controlSize(.small)
                
                if mapping.isCustom {
                    Button(action: { config.removeCustomMapping(keyId: mapping.keyId) }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.03))
            .cornerRadius(8)
        )
    }
    
    private func actionSummary(_ mapping: KeyMapping) -> String {
        switch mapping.actionType {
        case .none:
            return "原生默认(不拦截)"
        case .preset:
            return mapping.presetAction?.displayName ?? "未选择动作"
        case .customShortcut:
            return "⌨️ \(mapping.shortcut?.displayString ?? "未录制")"
        case .launchApp:
            let name = mapping.appPath != nil ? URL(fileURLWithPath: mapping.appPath!).deletingPathExtension().lastPathComponent : "未选择应用"
            return "🚀 打开 \(name)"
        }
    }
    
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }
    
    // MARK: - 底部栏
    private var bottomBar: some View {
        HStack(spacing: 16) {
            Toggle("菜单栏显示图标", isOn: $config.showMenuBarIcon)
                .font(.system(size: 12))
                .onChange(of: config.showMenuBarIcon) { _ in
                    config.saveToFile()
                    AppDelegate.shared?.syncStatusItemVisibility()
                }
            
            Toggle("开机自动启动", isOn: Binding(
                get: { launchManager.isEnabled },
                set: { launchManager.setEnabled($0); AppDelegate.shared?.updateMenu() }
            ))
            .font(.system(size: 12))
            
            Spacer()
            
            Button("恢复默认快捷键") {
                let alert = NSAlert()
                alert.messageText = "确认恢复默认设置？"
                alert.informativeText = "将重置 F6 刷新、F7 锁屏、F8 微信截图、PgUp/Dn 切换标签以及鼠标侧键前进/后退。"
                alert.addButton(withTitle: "确定重置")
                alert.addButton(withTitle: "取消")
                if alert.runModal() == .alertFirstButtonReturn {
                    config.loadDefaults()
                    config.saveToFile()
                }
            }
            .controlSize(.small)
            
            Button("关闭窗口") {
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.04))
    }
}

// MARK: - 编辑按键动作弹窗
struct EditMappingSheet: View {
    @State var mapping: KeyMapping
    var onSave: (KeyMapping) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedActionType: ActionType
    @State private var selectedPreset: PresetAction
    @State private var recordedShortcut: ShortcutDef?
    @State private var isRecording: Bool = false
    @State private var selectedAppPath: String = ""
    
    init(mapping: KeyMapping, onSave: @escaping (KeyMapping) -> Void) {
        self._mapping = State(initialValue: mapping)
        self.onSave = onSave
        self._selectedActionType = State(initialValue: mapping.actionType)
        self._selectedPreset = State(initialValue: mapping.presetAction ?? .refresh)
        self._recordedShortcut = State(initialValue: mapping.shortcut)
        self._selectedAppPath = State(initialValue: mapping.appPath ?? "")
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("设置按键动作: \(mapping.displayName)")
                        .font(.system(size: 16, weight: .bold))
                    Text("为 \(mapping.keyId) 指定按下时触发的系统行为")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Divider()
            
            // 动作类型选择（各 TAB 之间带明显分割线）
            HStack(spacing: 0) {
                ForEach(Array(ActionType.allCases.enumerated()), id: \.element) { index, type in
                    let isSelected = selectedActionType == type
                    Button(action: {
                        selectedActionType = type
                    }) {
                        HStack {
                            Spacer()
                            Text(type.displayName)
                                .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                                .foregroundColor(isSelected ? .accentColor : .primary)
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if index < ActionType.allCases.count - 1 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: 18)
                    }
                }
            }
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            
            // 模式内容
            VStack(alignment: .leading, spacing: 12) {
                switch selectedActionType {
                case .preset:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("从精选预设中选择：")
                            .font(.system(size: 12, weight: .medium))
                        
                        Picker("预设动作", selection: $selectedPreset) {
                            ForEach(PresetCategory.allCases, id: \.self) { cat in
                                Section(header: Text(cat.rawValue)) {
                                    ForEach(PresetAction.allCases.filter { $0.category == cat }, id: \.self) { act in
                                        Text(act.displayName).tag(act)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                case .customShortcut:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("录制您自己的快捷键组合：")
                            .font(.system(size: 12, weight: .medium))
                        
                        HStack {
                            Text(recordedShortcut?.displayString ?? "尚未录制快捷键")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            
                            Button(isRecording ? "🔴 请敲击键盘..." : "🎙️ 点击开始录制") {
                                startRecording()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if isRecording {
                            Text("正在监听中... 请直接在键盘上按下您想绑定的组合键（如 ⌘ + ⌥ + C）")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        }
                    }
                    
                case .launchApp:
                    VStack(alignment: .leading, spacing: 8) {
                        Text("指定要启动的应用程序：")
                            .font(.system(size: 12, weight: .medium))
                        
                        HStack {
                            Text(selectedAppPath.isEmpty ? "未选择任何应用" : selectedAppPath)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            
                            Button("浏览...") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.application]
                                panel.allowsMultipleSelection = false
                                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                                if panel.runModal() == .OK, let url = panel.url {
                                    selectedAppPath = url.path
                                }
                            }
                        }
                    }
                    
                case .none:
                    Text("设置为默认行为后，KeyLite 将不拦截该按键，完全放行给系统原生处理。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            
            Divider()
            
            // 底部按钮
            HStack {
                Button("取消") {
                    stopRecording()
                    presentationMode.wrappedValue.dismiss()
                }
                
                Spacer()
                
                Button("保存配置") {
                    stopRecording()
                    var updated = mapping
                    updated.actionType = selectedActionType
                    updated.presetAction = selectedActionType == .preset ? selectedPreset : nil
                    updated.shortcut = selectedActionType == .customShortcut ? recordedShortcut : nil
                    updated.appPath = selectedActionType == .launchApp ? selectedAppPath : nil
                    onSave(updated)
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 620)
        .onDisappear {
            stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        KeyInterceptor.shared.onRawKeyDown = { keyCode, flags in
            // 支持按 Esc (53) 取消录制
            if keyCode == 53 {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
                return true
            }
            
            let cmd = flags.contains(.maskCommand)
            let ctrl = flags.contains(.maskControl)
            let opt = flags.contains(.maskAlternate)
            let shift = flags.contains(.maskShift)
            
            let def = ShortcutDef(keyCode: keyCode, cmd: cmd, ctrl: ctrl, opt: opt, shift: shift)
            DispatchQueue.main.async {
                self.recordedShortcut = def
                self.stopRecording()
            }
            return true
        }
    }
    
    private func stopRecording() {
        isRecording = false
        KeyInterceptor.shared.onRawKeyDown = nil
    }
}

// MARK: - 添加自定义按键弹窗 (支持键盘与鼠标按键双模捕获)
struct AddCustomKeySheet: View {
    var onAdd: (KeyMapping) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var keyName: String = ""
    @State private var capturedKeyCode: UInt16? = nil
    @State private var capturedMouseButton: Int64? = nil
    @State private var isListening: Bool = false
    
    private var capturedTitle: String {
        if let btn = capturedMouseButton {
            switch btn {
            case 2: return "🖱️ 已捕获鼠标按键: 顶部/中键 (Button 2)"
            case 3: return "🖱️ 已捕获鼠标按键: 侧键 (Button 4 / 后退)"
            case 4: return "🖱️ 已捕获鼠标按键: 侧键 (Button 5 / 前进)"
            default: return "🖱️ 已捕获鼠标按键: Button \(btn + 1)"
            }
        } else if let code = capturedKeyCode {
            return "⌨️ 已捕获键盘按键: \(ShortcutDef.keyCodeToString(code)) (键码: \(code))"
        } else {
            return "请点击右侧按钮，随后敲击键盘或按下鼠标上的任意按键"
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("添加自定义按键")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("第一步：敲击键盘或按下鼠标按键捕获")
                    .font(.system(size: 12, weight: .bold))
                
                HStack {
                    Text(capturedTitle)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    
                    Button(isListening ? "🔴 等待按下按键..." : "🎙️ 捕获按键") {
                        startListening()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Text("第二步：输入显示名称（可选）")
                    .font(.system(size: 12, weight: .bold))
                    .padding(.top, 4)
                
                TextField("如：鼠标顶部按键 / 截图按键", text: $keyName)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
            
            HStack {
                Button("取消") {
                    stopListening()
                    presentationMode.wrappedValue.dismiss()
                }
                
                Spacer()
                
                Button("确定添加") {
                    stopListening()
                    let trimmedName = keyName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let btn = capturedMouseButton {
                        let newMapping = AppConfig.shared.addCustomMouseMapping(buttonNumber: btn, name: trimmedName)
                        onAdd(newMapping)
                        presentationMode.wrappedValue.dismiss()
                    } else if let code = capturedKeyCode {
                        let defaultName = ShortcutDef.keyCodeToString(code)
                        let newMapping = AppConfig.shared.addCustomMapping(keyCode: code, name: trimmedName.isEmpty ? defaultName : trimmedName)
                        onAdd(newMapping)
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(capturedKeyCode == nil && capturedMouseButton == nil)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onDisappear {
            stopListening()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopListening()
        }
    }
    
    private func startListening() {
        isListening = true
        // 键盘按键监听
        KeyInterceptor.shared.onRawKeyDown = { keyCode, _ in
            // 支持按 Esc (53) 取消录制
            if keyCode == 53 {
                DispatchQueue.main.async {
                    self.stopListening()
                }
                return true
            }
            
            DispatchQueue.main.async {
                self.capturedKeyCode = keyCode
                self.capturedMouseButton = nil
                self.stopListening()
            }
            return true
        }
        
        // 鼠标按键监听
        KeyInterceptor.shared.onRawMouseDown = { buttonNumber in
            DispatchQueue.main.async {
                self.capturedMouseButton = buttonNumber
                self.capturedKeyCode = nil
                self.stopListening()
            }
            return true
        }
    }
    
    private func stopListening() {
        isListening = false
        KeyInterceptor.shared.onRawKeyDown = nil
        KeyInterceptor.shared.onRawMouseDown = nil
    }
}
