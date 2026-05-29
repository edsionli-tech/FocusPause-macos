#if !targetEnvironment(macCatalyst)
import AppKit
import Combine
import SwiftUI

/// 全屏多屏遮盖：记录用户当前在哪块屏编辑待办，供聚焦与弹窗锚点使用。
enum FocusPauseOverlayEditingContext {
    private static weak var preferredWindow: NSWindow?

    static var preferredOverlayWindow: NSWindow? {
        if let preferredWindow, preferredWindow.isVisible {
            return preferredWindow
        }
        if let key = NSApp.keyWindow, isOverlayWindow(key) {
            return key
        }
        return NSApp.windows.first { isOverlayWindow($0) && $0.isVisible }
    }

    static func noteOverlayWindow(_ window: NSWindow?) {
        guard let window, isOverlayWindow(window) else { return }
        preferredWindow = window
    }

    private static func isOverlayWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "FocusPauseOverlayWindow" || window.level == .screenSaver
    }
}

@MainActor
final class OverlayWindowController {
    private static let overlayWindowIdentifier = NSUserInterfaceItemIdentifier("FocusPauseOverlayWindow")

    private var windowsByScreenID: [String: NSWindow] = [:]
    private var windowsPendingClose: [NSWindow] = []
    private weak var activeStore: FocusPauseStore?
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let activeStore = self.activeStore, activeStore.status == .resting else {
                    self?.close()
                    return
                }
                self.show(store: activeStore)
            }
        }
    }

    func show(store: FocusPauseStore) {
        guard store.status == .resting else {
            close()
            return
        }

        activeStore = store
        closeUntrackedOverlayWindows()

        let currentScreenIDs = Set(NSScreen.screens.map(screenID))
        for staleID in Array(windowsByScreenID.keys) where !currentScreenIDs.contains(staleID) {
            closeOverlayWindow(windowsByScreenID.removeValue(forKey: staleID))
        }

        let mode = store.settings.resolvedBreakOverlayMode

        for screen in NSScreen.screens {
            let id = screenID(screen)
            let window = windowsByScreenID[id] ?? makeWindow(for: screen, mode: mode)
            configureOverlayWindow(window, screen: screen, mode: mode)
            applyContentView(to: window, store: store, mode: mode)
            window.orderFrontRegardless()
            windowsByScreenID[id] = window
        }

        focusPreferredOverlayWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 同步关闭所有遮罩窗口；同时销毁未被字典记录的孤儿窗口，避免 `.screenSaver` 层级窗口残留。
    func close() {
        let windows = trackedAndOrphanOverlayWindows()
        windowsByScreenID.removeAll()
        activeStore = nil
        for window in windows {
            closeOverlayWindow(window)
        }
    }

    func refresh(store: FocusPauseStore) {
        guard activeStore != nil, store.status == .resting else {
            close()
            return
        }
        activeStore = store
        closeUntrackedOverlayWindows()
        let mode = store.settings.resolvedBreakOverlayMode
        let currentIDs = Set(NSScreen.screens.map(screenID))
        for staleID in Array(windowsByScreenID.keys) where !currentIDs.contains(staleID) {
            closeOverlayWindow(windowsByScreenID.removeValue(forKey: staleID))
        }
        for screen in NSScreen.screens {
            let id = screenID(screen)
            let window = windowsByScreenID[id] ?? makeWindow(for: screen, mode: mode)
            configureOverlayWindow(window, screen: screen, mode: mode)
            applyContentView(to: window, store: store, mode: mode)
            window.orderFrontRegardless()
            windowsByScreenID[id] = window
        }
        focusPreferredOverlayWindow()
    }

    /// 收起/展开时更新侧边栏所在区域（全屏窗口不变）。
    func relayoutDisguiseCompositeIfNeeded(store: FocusPauseStore) {
        guard activeStore != nil, store.status == .resting else {
            close()
            return
        }
        guard store.settings.resolvedBreakOverlayMode == .disguise else { return }
        activeStore = store
        for window in windowsByScreenID.values {
            guard let composite = window.contentView as? DisguiseOverlayCompositeView else { continue }
            composite.needsLayout = true
            composite.layoutSubtreeIfNeeded()
        }
    }

    /// 暂时隐藏遮罩窗口（仍保留 `activeStore` 与视图层级），用于「整理桌面」短时放行桌面操作。
    func setTemporaryHidden(_ hidden: Bool) {
        guard activeStore?.status == .resting else {
            close()
            return
        }

        for window in windowsByScreenID.values {
            if hidden {
                window.orderOut(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
        if !hidden {
            focusPreferredOverlayWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private func applyContentView(to window: NSWindow, store: FocusPauseStore, mode: BreakOverlayDisplayMode) {
        switch mode {
        case .standard:
            let root = FocusPauseLocalizedRoot(store: store) {
                BreakOverlayView(store: store)
            }
            if let hosting = window.contentView as? NSHostingView<FocusPauseLocalizedRoot<BreakOverlayView>> {
                hosting.rootView = root
            } else {
                window.contentView = NSHostingView(rootView: root)
            }
        case .disguise:
            if window.contentView is DisguiseOverlayCompositeView {
                return
            }
            window.contentView = DisguiseOverlayCompositeView(store: store)
        }
    }

    private func makeWindow(for screen: NSScreen, mode: BreakOverlayDisplayMode) -> NSWindow {
        let window = FocusPauseOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.identifier = Self.overlayWindowIdentifier
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        configureOverlayWindow(window, screen: screen, mode: mode)
        window.displaysWhenScreenProfileChanges = true
        return window
    }

    private func configureOverlayWindow(_ window: NSWindow, screen: NSScreen, mode: BreakOverlayDisplayMode) {
        window.setFrame(screen.frame, display: true)

        switch mode {
        case .standard:
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = NSColor.black.withAlphaComponent(0.86)
            window.isOpaque = false
            window.hasShadow = false
        case .disguise:
            /// 不用 fullScreenAuxiliary，避免额外全屏辅助层异常。
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
        }
    }

    private func trackedAndOrphanOverlayWindows() -> [NSWindow] {
        var result = Array(windowsByScreenID.values)
        for window in NSApp.windows where isOverlayWindow(window) && !result.contains(where: { $0 === window }) {
            result.append(window)
        }
        return result
    }

    private func closeUntrackedOverlayWindows() {
        let tracked = Array(windowsByScreenID.values)
        for window in NSApp.windows where isOverlayWindow(window) && !tracked.contains(where: { $0 === window }) {
            closeOverlayWindow(window)
        }
    }

    private func closeOverlayWindow(_ window: NSWindow?) {
        guard let window else { return }

        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }

        // Make the overlay harmless immediately, then let AppKit finish any sheet/action callback
        // before actually closing the parent window.
        window.level = .normal
        window.ignoresMouseEvents = true
        window.contentView = nil
        window.orderOut(nil)

        guard !windowsPendingClose.contains(where: { $0 === window }) else { return }
        windowsPendingClose.append(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak window] in
            guard let self, let window else { return }
            window.close()
            self.windowsPendingClose.removeAll { $0 === window }
        }
    }

    private func isOverlayWindow(_ window: NSWindow) -> Bool {
        if window.identifier == Self.overlayWindowIdentifier { return true }
        if window is FocusPauseOverlayWindow { return true }
        return false
    }

    private func screenID(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return number.stringValue
        }
        return "\(screen.frame.origin.x)-\(screen.frame.origin.y)-\(screen.frame.width)-\(screen.frame.height)"
    }

    /// 多屏遮盖仅将「当前编辑/主屏」窗口设为 key，避免循环 `makeKeyAndOrderFront` 把焦点偷到另一块屏。
    private func focusPreferredOverlayWindow() {
        if let preferred = FocusPauseOverlayEditingContext.preferredOverlayWindow,
           windowsByScreenID.values.contains(where: { $0 === preferred }) {
            preferred.makeKeyAndOrderFront(nil)
            return
        }
        if let main = NSScreen.main,
           let mainWindow = windowsByScreenID[screenID(main)] {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - 伪装模式：全屏轻遮盖 + 右侧面板（遮盖层鼠标穿透）

/// 轻微暗色全屏层，`hitTest` 恒为 `nil`，点击可落到下层桌面与其它应用。
private final class PassThroughBackdropNSView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.072).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class DisguiseOverlayCompositeView: NSView {
    private let store: FocusPauseStore
    private let backdrop = PassThroughBackdropNSView()
    private let hostingView: NSHostingView<FocusPauseLocalizedRoot<BreakOverlayView>>
    private var collapseObservation: AnyCancellable?

    init(store: FocusPauseStore) {
        self.store = store
        self.hostingView = NSHostingView(rootView: FocusPauseLocalizedRoot(store: store) {
            BreakOverlayView(store: store)
        })
        super.init(frame: .zero)
        addSubview(backdrop)
        addSubview(hostingView)
        collapseObservation = store.$breakOverlaySidebarCollapsed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsLayout = true
            }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        collapseObservation?.cancel()
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds

        guard let window, let screen = window.screen else {
            hostingView.frame = .zero
            return
        }

        let vf = screen.visibleFrame
        let collapsed = store.breakOverlaySidebarCollapsed
        let margin: CGFloat = 18

        /// 收起态：窄条占位尽量小；宽度过低会撑破中文竖排按钮。
        let panelW: CGFloat = collapsed ? 110 : 408
        let panelH: CGFloat
        if collapsed {
            /// 略小于旧版（292×128），且不低于内容固有高度，避免裁切。
            panelH = min(246, max(220, vf.height * 0.275))
        } else {
            panelH = max(420, vf.height - 112)
        }

        let rectOnScreen = NSRect(
            x: vf.maxX - panelW - margin,
            y: vf.minY + (vf.height - panelH) * 0.5,
            width: panelW,
            height: panelH
        )

        hostingView.frame = window.convertFromScreen(rectOnScreen)
    }
}

private final class FocusPauseOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif
