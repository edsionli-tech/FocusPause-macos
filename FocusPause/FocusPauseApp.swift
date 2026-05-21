import SwiftUI

#if !targetEnvironment(macCatalyst)
import AppKit
import Combine
#endif

@main
struct FocusPauseMain {
    static func main() {
#if targetEnvironment(macCatalyst)
        FocusPauseCatalystApp.main()
#else
        let app = NSApplication.shared
        let delegate = AppDelegate()
        FocusPauseRuntime.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
#endif
    }
}

#if targetEnvironment(macCatalyst)
struct FocusPauseCatalystApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(Localized.string("catalyst.title", locale: Locale.autoupdatingCurrent))
                    .font(.title2.bold())
                Text(Localized.string("catalyst.body", locale: Locale.autoupdatingCurrent))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
            }
            .padding(40)
        }
    }
}
#else

private enum FocusPauseRuntime {
    static var delegate: AppDelegate?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = FocusPauseStore()
    private var hotkeyController: GlobalHotkeyController?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private let overlayController = OverlayWindowController()
    private var settingsCancellable: AnyCancellable?
    private var overlayLayoutRefreshCancellable: AnyCancellable?
    private var overlayCollapseRefreshCancellable: AnyCancellable?
    private var breakOverlayStatusCancellable: AnyCancellable?
    private var breakDesktopRevealCancellable: AnyCancellable?
    private var statusItemContextMenu: NSMenu?
    private var selfRetainer: AppDelegate?

    private enum StatusBarContextMenuTag: Int {
        case overlayStandard = 401
        case overlayDisguise = 402
        case settings = 403
        case quit = 404
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        selfRetainer = self
        NSApplication.shared.setActivationPolicy(.accessory)
        setupMenuBar()
        setupHotkey()
        observeSettings()
        observeBreakOverlay()
        observeBreakDesktopReveal()
        observeOverlayLayoutRefresh()
        observeBreakOverlaySidebarCollapse()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyController?.stop()
        settingsCancellable = nil
        overlayLayoutRefreshCancellable = nil
        overlayCollapseRefreshCancellable = nil
        breakOverlayStatusCancellable = nil
        breakDesktopRevealCancellable = nil
        popover?.performClose(nil)
        overlayController.close()
        selfRetainer = nil
    }

    private func setupMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeMenuBarIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItemContextMenu = buildStatusContextMenu()
        self.statusItem = statusItem
    }

    private func buildStatusContextMenu() -> NSMenu {
        let menu = NSMenu()
        let locale = store.settings.resolvedLocale

        let standardItem = NSMenuItem(title: Localized.string("status_menu.break.standard", locale: locale), action: #selector(selectBreakOverlayStandard), keyEquivalent: "")
        standardItem.target = self
        standardItem.tag = StatusBarContextMenuTag.overlayStandard.rawValue

        let disguiseItem = NSMenuItem(title: Localized.string("status_menu.break.disguise", locale: locale), action: #selector(selectBreakOverlayDisguise), keyEquivalent: "")
        disguiseItem.target = self
        disguiseItem.tag = StatusBarContextMenuTag.overlayDisguise.rawValue

        menu.addItem(standardItem)
        menu.addItem(disguiseItem)
        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: Localized.string("status_menu.settings", locale: locale), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.tag = StatusBarContextMenuTag.settings.rawValue
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: Localized.string("status_menu.quit", locale: locale), action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        quitItem.tag = StatusBarContextMenuTag.quit.rawValue
        menu.addItem(quitItem)

        return menu
    }

    private func refreshStatusContextMenuTitles(locale: Locale) {
        guard let menu = statusItemContextMenu else { return }
        menu.item(withTag: StatusBarContextMenuTag.overlayStandard.rawValue)?.title =
            Localized.string("status_menu.break.standard", locale: locale)
        menu.item(withTag: StatusBarContextMenuTag.overlayDisguise.rawValue)?.title =
            Localized.string("status_menu.break.disguise", locale: locale)
        menu.item(withTag: StatusBarContextMenuTag.settings.rawValue)?.title =
            Localized.string("status_menu.settings", locale: locale)
        menu.item(withTag: StatusBarContextMenuTag.quit.rawValue)?.title =
            Localized.string("status_menu.quit", locale: locale)
    }

    private func refreshStatusContextMenuChecks() {
        guard let menu = statusItemContextMenu else { return }
        let mode = store.settings.breakOverlayDisplayMode ?? .disguise
        menu.item(withTag: StatusBarContextMenuTag.overlayStandard.rawValue)?.state = mode == .standard ? .on : .off
        menu.item(withTag: StatusBarContextMenuTag.overlayDisguise.rawValue)?.state = mode == .disguise ? .on : .off
    }

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            refreshStatusContextMenuChecks()
            if let button = statusItem?.button, let menu = statusItemContextMenu {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
        } else {
            togglePopover()
        }
    }

    @objc private func selectBreakOverlayStandard() {
        store.setBreakOverlayDisplayMode(.standard)
        refreshBreakOverlayLayoutIfResting()
    }

    @objc private func selectBreakOverlayDisguise() {
        store.setBreakOverlayDisplayMode(.disguise)
        refreshBreakOverlayLayoutIfResting()
    }

    @objc private func openSettingsFromMenu() {
        showSettingsWindow()
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshBreakOverlayLayoutIfResting() {
        guard store.status == .resting else { return }
        overlayController.refresh(store: store)
    }

    private func observeOverlayLayoutRefresh() {
        overlayLayoutRefreshCancellable = store.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                refreshBreakOverlayLayoutIfResting()
            }
    }

    private func observeBreakOverlaySidebarCollapse() {
        overlayCollapseRefreshCancellable = store.$breakOverlaySidebarCollapsed
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, store.status == .resting else { return }
                overlayController.relayoutDisguiseCompositeIfNeeded(store: store)
            }
    }

    private func makeMenuBarIcon() -> NSImage? {
#if targetEnvironment(macCatalyst)
        nil
#else
        FocusPauseMenuBarTemplateIcon.nsImage(side: 18)
#endif
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 548, height: 650)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: FocusPauseLocalizedRoot(store: self.store) {
                MenuBarPopoverView(store: self.store) { [weak self] in
                    self?.showSettingsWindow()
                } closePopover: { [weak self] in
                    self?.closePopover()
                }
            }
        )
        return popover
    }

    func popoverDidClose(_ notification: Notification) {
        if let closedPopover = notification.object as? NSPopover, closedPopover === popover {
            popover = nil
        }
    }

    private func observeSettings() {
        applySettings(store.settings)
        settingsCancellable = store.$settings
            .sink { [weak self] settings in
                self?.applySettings(settings)
            }
    }

    private func applySettings(_ settings: FocusPauseSettings) {
        statusItem?.isVisible = settings.showMenuBarIcon
        refreshStatusContextMenuTitles(locale: settings.resolvedLocale)
        refreshStatusContextMenuChecks()
        settingsWindow?.title = Localized.string("window.settings.title", locale: settings.resolvedLocale)

        switch settings.theme {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    private func setupHotkey() {
        hotkeyController = GlobalHotkeyController { [weak self] in
            guard let self else { return }
            guard store.status == .resting else { return }
            store.returnToFocusFromOverlay()
            overlayController.close()
        }
        hotkeyController?.start()
    }

    private func observeBreakOverlay() {
        breakOverlayStatusCancellable = store.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                store.breakOverlaySidebarCollapsed = false
                if status == .resting {
                    overlayController.show(store: store)
                } else {
                    overlayController.close()
                }
            }
    }

    private func observeBreakDesktopReveal() {
        breakDesktopRevealCancellable = store.$breakDesktopRevealActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                if active {
                    guard store.status == .resting else { return }
                    overlayController.setTemporaryHidden(true)
                } else {
                    overlayController.setTemporaryHidden(false)
                    // 勿调用 refresh：重建 NSHostingView 会重置滚动位置，且 orderOut/orderFront 已足够恢复遮盖。
                    if store.status == .resting {
                        overlayController.relayoutDisguiseCompositeIfNeeded(store: store)
                    }
                }
            }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover?.isShown == true {
            closePopover()
        } else {
            let popover = makePopover()
            self.popover = popover
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func closePopover() {
        guard let popover else { return }
        popover.performClose(nil)
    }

    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = Localized.string("window.settings.title", locale: store.settings.resolvedLocale)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: FocusPauseLocalizedRoot(store: self.store) {
            SettingsRootView(store: self.store)
        })
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}
#endif
