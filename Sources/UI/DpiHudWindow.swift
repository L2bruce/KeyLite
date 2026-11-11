import SwiftUI
import Cocoa

public class DpiHudWindow: NSObject {
    public static let shared = DpiHudWindow()
    
    private var window: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    
    // 状态数据通过 Observable 桥接
    fileprivate class HudState: ObservableObject {
        @Published var dpi: Int = 1200
        @Published var speed: Double = 1.0
    }
    private let state = HudState()
    
    private override init() {
        super.init()
    }
    
    public func show(dpi: Int, speed: Double) {
        state.dpi = dpi
        state.speed = speed
        
        if window == nil {
            createWindow()
        }
        
        guard let panel = window else { return }
        
        // 定位到主屏幕居中偏下位置
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 100
            let y = screenRect.minY + 140
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        panel.alphaValue = 1.0
        panel.orderFrontRegardless()
        
        // 取消前一个计时器，启动 0.8 秒后淡出
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, let panel = self.window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25
                panel.animator().alphaValue = 0.0
            }, completionHandler: {
                if panel.alphaValue == 0.0 {
                    panel.orderOut(nil)
                }
            })
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
    }
    
    private func createWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 110),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        
        let contentView = DpiHudContentView(state: state)
        panel.contentView = NSHostingView(rootView: contentView)
        
        self.window = panel
    }
}

private struct DpiHudContentView: View {
    @ObservedObject var state: DpiHudWindow.HudState
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
            
            Text("\(state.dpi) DPI")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("指针速度: \(String(format: "%.2f", state.speed))x")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .frame(width: 200, height: 110)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .colorScheme(.dark)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
