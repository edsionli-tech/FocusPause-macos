import SwiftUI
#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
#endif

struct BreakOverlayView: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale
    @State private var pendingReturnConfirmation = false
    @State private var showSnoozeOptions = false
    /// 休息界面添加二级待办时的父任务 id。
    @State private var overlayTodoParentId: UUID?

    private var breakMode: BreakOverlayDisplayMode {
        store.settings.resolvedBreakOverlayMode
    }

    var body: some View {
        overlayContent
            .onChange(of: store.todos) { _ in
                guard let pid = overlayTodoParentId else { return }
                if store.todos.first(where: { $0.id == pid && $0.parentId == nil }) == nil {
                    overlayTodoParentId = nil
                }
            }
    }

    @ViewBuilder
    private var overlayContent: some View {
        Group {
            switch breakMode {
            case .standard:
                standardOverlayBody
            case .disguise:
                disguiseOverlayBody
            }
        }
#if targetEnvironment(macCatalyst)
        .alert(Localized.string("overlay.confirm_return_title", locale: locale), isPresented: $pendingReturnConfirmation) {
            Button(Localized.string("overlay.confirm_return_cancel", locale: locale), role: .cancel) {}
            Button(Localized.string("overlay.confirm_return_ok", locale: locale), role: .destructive) {
                store.returnToWork()
            }
        } message: {
            Text(Localized.string("overlay.confirm_return_msg", locale: locale))
        }
        .confirmationDialog(Localized.string("overlay.snooze_title", locale: locale), isPresented: $showSnoozeOptions, titleVisibility: .visible) {
            Button(Localized.string("overlay.snooze_5", locale: locale)) {
                store.snoozeBreak(minutes: 5)
            }
            Button(Localized.string("overlay.snooze_15", locale: locale)) {
                store.snoozeBreak(minutes: 15)
            }
            Button(Localized.string("overlay.snooze_30", locale: locale)) {
                store.snoozeBreak(minutes: 30)
            }
            Button(Localized.string("common.cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(Localized.string("overlay.snooze_hint", locale: locale))
        }
#endif
    }

    // MARK: - 标准全屏

    private var standardOverlayBody: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.94), Color(red: 0.05, green: 0.07, blue: 0.12), Color.black.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            subtleNoise

            VStack(spacing: 22) {
                ProgressRingView(
                    progress: store.breakProgress,
                    timeText: store.currentTimeText,
                    size: 190,
                    lineWidth: 13
                )
                Text(Localized.string("overlay.break_title", locale: locale))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 42)

            VStack(spacing: 18) {
                Spacer(minLength: 210)
                standardContentGrid
                standardRestPrompt
                standardActionRow
                Text(Localized.string("overlay.cmd_hint", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 58)
            .padding(.bottom, 26)
        }
    }

    private var subtleNoise: some View {
        RadialGradient(
            colors: [.white.opacity(0.08), .clear],
            center: .top,
            startRadius: 20,
            endRadius: 650
        )
        .blendMode(.screen)
        .ignoresSafeArea()
    }

    private var standardContentGrid: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Label(store.usageScope.localizedPanelTitle(locale: locale), systemImage: "chart.bar.fill")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    UsageScopeSegmentedControl(
                        selection: Binding(
                            get: { store.usageScope },
                            set: { store.setUsageScope($0) }
                        ),
                        locale: locale,
                        compact: false
                    )
                    .accessibilityLabel(Localized.string("overlay.usage_picker", locale: locale))
                }

                ScrollView {
                    if store.usageItems.isEmpty {
                        Text(store.usageScope == .today ? Localized.string("overlay.usage_empty_today", locale: locale) : Localized.string("overlay.usage_empty_cycle", locale: locale))
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        UsageBarsView(usageItems: store.usageItems, totalMinutes: store.totalUsageMinutes, dark: true)
                            .foregroundStyle(.white)
                            .padding(.trailing, 16)
                    }
                }
                .scrollIndicators(.visible)
            }
            .padding(22)
            .frame(maxWidth: 500, minHeight: 190, maxHeight: 330)
            .background(.ultraThinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                TodoListDayHeader(
                    selectedDay: Binding(
                        get: { store.todoListSelectedNormalizedDay },
                        set: { store.setTodoListSelectedDay($0) }
                    ),
                    panelChrome: .glassCard,
                    progressText: "\(store.completedCount(forListDay: store.todoListSelectedNormalizedDay))/\(store.totalCount(forListDay: store.todoListSelectedNormalizedDay))"
                )

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        NotesChecklistTodoPanel(
                            store: store,
                            pendingParentId: $overlayTodoParentId,
                            prefersLightContent: true,
                            emptyStateHint: Localized.string("todo.empty_hint_overlay", locale: locale),
                            panelChrome: .glassCard,
                            hideDayHeader: true,
                            useLocalKeyMonitor: true,
                            scrollToRow: { rowId in
                                scrollProxy.scrollTo(rowId, anchor: .center)
                            }
                        )
                        .padding(.trailing, 14)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(22)
            .frame(maxWidth: 500, minHeight: 190, maxHeight: 330)
            .background(.ultraThinMaterial.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(minHeight: 190, maxHeight: 330)
    }

    private var standardRestPrompt: some View {
        HStack(spacing: 24) {
            Button {
                store.restTipIndex = (store.restTipIndex + store.restTipCount - 1) % store.restTipCount
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)

            Text(store.currentRestTip)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 420)

            Button {
                store.restTipIndex = (store.restTipIndex + 1) % store.restTipCount
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
        }
    }

    private var standardActionRow: some View {
        HStack(spacing: 22) {
            RestActionButton(title: Localized.string("overlay.snooze_break", locale: locale), systemImage: "bell.badge.fill", isPrimary: false) {
#if os(macOS) && !targetEnvironment(macCatalyst)
                presentMacSnoozeBreakDialog(locale: locale)
#else
                showSnoozeOptions = true
#endif
            }

            RestActionButton(title: Localized.string("overlay.extend_break", locale: locale), systemImage: "clock.arrow.circlepath", isPrimary: false) {
#if os(macOS) && !targetEnvironment(macCatalyst)
                resignBreakOverlayNativeEditingFocus()
#endif
                store.extendBreak()
            }

            RestActionButton(title: Localized.string("overlay.return_work", locale: locale), systemImage: "play.fill", isPrimary: true) {
#if os(macOS) && !targetEnvironment(macCatalyst)
                presentMacReturnToWorkConfirmation(locale: locale)
#else
                pendingReturnConfirmation = true
#endif
            }
        }
    }

    // MARK: - 伪装工作：内容仅右侧卡片（全屏遮罩与穿透层由 NSCompositeView 处理）

    private var disguiseOverlayBody: some View {
        Group {
            if store.breakOverlaySidebarCollapsed {
                disguiseCollapsedStrip
            } else {
                disguiseExpandedCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var disguiseExpandedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            disguiseExpandedTopToolbar

            VStack(spacing: 5) {
                Text(Localized.string("overlay.rest_remaining", locale: locale))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.52))
                Text(store.currentTimeText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .shadow(color: Color.black.opacity(0.28), radius: 2, x: 0, y: 1)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)

            disguiseRestPromptGlass

            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TodoListDayHeader(
                            selectedDay: Binding(
                                get: { store.todoListSelectedNormalizedDay },
                                set: { store.setTodoListSelectedDay($0) }
                            ),
                            panelChrome: .disguiseGlass,
                            progressText: "\(store.completedCount(forListDay: store.todoListSelectedNormalizedDay))/\(store.totalCount(forListDay: store.todoListSelectedNormalizedDay))"
                        )
                        .padding(.bottom, 8)

                        NotesChecklistTodoPanel(
                            store: store,
                            pendingParentId: $overlayTodoParentId,
                            prefersLightContent: true,
                            emptyStateHint: Localized.string("todo.empty_hint_overlay", locale: locale),
                            panelChrome: .disguiseGlass,
                            hideDayHeader: true,
                            useLocalKeyMonitor: true,
                            scrollToRow: { rowId in
                                scrollProxy.scrollTo(rowId, anchor: .center)
                            }
                        )

                        disguiseUsageSection
                            .padding(.bottom, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollIndicators(.visible)
            }

            disguiseGlassActionColumn

            Text(Localized.string("overlay.cmd_hint", locale: locale))
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.52))
                .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 0)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disguiseSidebarGlassChrome(cornerRadius: 23)
    }

    /// 顶栏左右对称：同款胶囊按钮 + 双行说明。
    private var disguiseExpandedTopToolbar: some View {
        let reveal = store.breakDesktopRevealActive
        return HStack(alignment: .top, spacing: 10) {
            disguiseExpandedToolbarPane(
                alignTrailing: false,
                icon: "square.grid.3x3.fill.square",
                title: Localized.string("overlay.organize_desktop", locale: locale),
                captionLine1: reveal ? Localized.string("overlay.organize_caption_on", locale: locale) : Localized.string("overlay.organize_caption_off", locale: locale),
                captionLine2: reveal ? Localized.string("overlay.organize_caption2_on", locale: locale) : Localized.string("overlay.organize_caption2_off", locale: locale),
                chipDisabled: reveal,
                helpText: Localized.string("overlay.organize_help", locale: locale),
                action: {
#if os(macOS) && !targetEnvironment(macCatalyst)
                    resignBreakOverlayNativeEditingFocus()
#endif
                    store.beginBreakDesktopOrganizeGracePeriodIfResting()
                }
            )

            disguiseExpandedToolbarPane(
                alignTrailing: true,
                icon: "rectangle.arrowtriangle.2.inward",
                title: Localized.string("overlay.collapse_sidebar", locale: locale),
                captionLine1: Localized.string("overlay.collapse_cap1", locale: locale),
                captionLine2: Localized.string("overlay.collapse_cap2", locale: locale),
                chipDisabled: false,
                helpText: Localized.string("overlay.collapse_help", locale: locale),
                action: {
#if os(macOS) && !targetEnvironment(macCatalyst)
                    resignBreakOverlayNativeEditingFocus()
#endif
                    store.setBreakOverlaySidebarCollapsed(true)
                }
            )
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func disguiseExpandedToolbarPane(
        alignTrailing: Bool,
        icon: String,
        title: String,
        captionLine1: String,
        captionLine2: String,
        chipDisabled: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        let chipAlign: Alignment = alignTrailing ? .trailing : .leading
        let textAlign: TextAlignment = alignTrailing ? .trailing : .leading
        let vAlign: HorizontalAlignment = alignTrailing ? .trailing : .leading

        VStack(alignment: vAlign, spacing: 5) {
            Button(action: action) {
                disguiseExpandedToolbarChipLabel(icon: icon, title: title, dimmed: chipDisabled)
            }
            .buttonStyle(.plain)
            .disabled(chipDisabled)
            .help(helpText)
            .frame(maxWidth: .infinity, alignment: chipAlign)

            VStack(alignment: vAlign, spacing: 2) {
                Text(captionLine1)
                Text(captionLine2)
            }
            .font(.system(size: 9))
            .foregroundStyle(Color.white.opacity(chipDisabled ? 0.36 : 0.44))
            .multilineTextAlignment(textAlign)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: chipAlign)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: chipAlign)
    }

    private func disguiseExpandedToolbarChipLabel(icon: String, title: String, dimmed: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(dimmed ? 0.34 : 0.72))
                .frame(width: 16, alignment: .center)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.white.opacity(dimmed ? 0.36 : 0.82))
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Color.white.opacity(dimmed ? 0.042 : 0.058),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(dimmed ? 0.075 : 0.11), lineWidth: 1)
        }
    }

    private var disguiseCollapsedStrip: some View {
        VStack(spacing: 0) {
            Button {
#if os(macOS) && !targetEnvironment(macCatalyst)
                resignBreakOverlayNativeEditingFocus()
#endif
                store.setBreakOverlaySidebarCollapsed(false)
            } label: {
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.072))
                            .frame(width: 34, height: 34)
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Text(Localized.string("overlay.expand", locale: locale))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.76))
                    Text(Localized.string("overlay.stats_todos", locale: locale))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Localized.string("overlay.expand_help", locale: locale))

            Divider()
                .opacity(0.35)
                .padding(.horizontal, 8)

            VStack(spacing: 6) {
                Text(Localized.string("overlay.rest_remaining", locale: locale))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.42))

                Text(store.currentTimeText)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.90))

                ProgressView(value: store.breakProgress)
                    .progressViewStyle(.linear)
                    .scaleEffect(x: 1, y: 0.72, anchor: .center)
                    .tint(Color(red: 0.48, green: 0.64, blue: 0.94))
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 10)

            Divider()
                .opacity(0.35)
                .padding(.horizontal, 8)

            VStack(spacing: 8) {
                Button {
#if os(macOS) && !targetEnvironment(macCatalyst)
                    presentMacReturnToWorkConfirmation(locale: locale)
#else
                    pendingReturnConfirmation = true
#endif
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                        Text(Localized.string("overlay.return_focus", locale: locale))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(
                        Color(red: 0.28, green: 0.53, blue: 0.96),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .help(Localized.string("overlay.return_focus_help", locale: locale))

                VStack(spacing: 2) {
                    Text(Localized.string("overlay.passthrough_1", locale: locale))
                    Text(Localized.string("overlay.passthrough_2", locale: locale))
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disguiseSidebarGlassChrome(cornerRadius: 15)
    }

    private var disguiseUsageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(store.usageScope.localizedPanelTitle(locale: locale), systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                Spacer(minLength: 8)
                UsageScopeSegmentedControl(
                    selection: Binding(
                        get: { store.usageScope },
                        set: { store.setUsageScope($0) }
                    ),
                    locale: locale,
                    compact: true
                )
                .accessibilityLabel(Localized.string("overlay.usage_picker", locale: locale))
            }

            if store.usageItems.isEmpty {
                Text(store.usageScope == .today ? Localized.string("overlay.usage_empty_today", locale: locale) : Localized.string("overlay.usage_empty_cycle", locale: locale))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.44))
                    .padding(.vertical, 10)
            } else {
                UsageBarsView(
                    usageItems: store.usageItems,
                    totalMinutes: store.totalUsageMinutes,
                    dark: true,
                    glassSidebarStyle: true
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.042), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 与标准全屏一致的轮换文案；半透明衬底 + 字阴影，在桌面透视背景下仍可辨认。
    private var disguiseRestPromptGlass: some View {
        HStack(spacing: 8) {
            Button {
                store.restTipIndex = (store.restTipIndex + store.restTipCount - 1) % store.restTipCount
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.09)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Text(store.currentRestTip)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.94))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .shadow(color: Color.black.opacity(0.42), radius: 3, x: 0, y: 1)
                .frame(maxWidth: .infinity)

            Button {
                store.restTipIndex = (store.restTipIndex + 1) % store.restTipCount
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 34, height: 36)
                    .background(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.09)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.72))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.26))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .padding(.bottom, 10)
    }

    /// 与标准遮罩相同的渐变胶囊按钮；纵向铺满以适应窄侧边栏。
    private var disguiseGlassActionColumn: some View {
        VStack(spacing: 6) {
            RestActionButton(title: Localized.string("overlay.snooze_break", locale: locale), systemImage: "bell.badge.fill", isPrimary: false, expandsToFill: true) {
#if os(macOS) && !targetEnvironment(macCatalyst)
                presentMacSnoozeBreakDialog(locale: locale)
#else
                showSnoozeOptions = true
#endif
            }

            RestActionButton(title: Localized.string("overlay.extend_break", locale: locale), systemImage: "clock.arrow.circlepath", isPrimary: false, expandsToFill: true) {
#if os(macOS) && !targetEnvironment(macCatalyst)
                resignBreakOverlayNativeEditingFocus()
#endif
                store.extendBreak()
            }

            RestActionButton(title: Localized.string("overlay.return_work", locale: locale), systemImage: "play.fill", isPrimary: true, expandsToFill: true) {
#if os(macOS) && !targetEnvironment(macCatalyst)
                presentMacReturnToWorkConfirmation(locale: locale)
#else
                pendingReturnConfirmation = true
#endif
            }
        }
        .padding(.top, 8)
    }
}

#if os(macOS) && !targetEnvironment(macCatalyst)
private extension BreakOverlayView {
    func breakOverlaySheetAnchorWindow() -> NSWindow? {
        if let w = NSApp.keyWindow, w.isVisible { return w }
        return NSApp.windows.first { w in
            w.isVisible && w.level == .screenSaver && w.styleMask.contains(.borderless)
        }
    }

    /// 待办 `NSTextView` 为第一响应者时，偶现 SwiftUI 按钮无法可靠触发；遮盖工具条操作前先摘掉原生键盘焦点。
    func resignBreakOverlayNativeEditingFocus() {
        guard store.status == .resting else { return }
        breakOverlaySheetAnchorWindow()?.makeFirstResponder(nil)
    }

    func presentMacReturnToWorkConfirmation(locale: Locale) {
        resignBreakOverlayNativeEditingFocus()
        DispatchQueue.main.async {
            let store = self.store
            guard let window = self.breakOverlaySheetAnchorWindow() else {
                store.returnToWork()
                return
            }
            let alert = NSAlert()
            alert.messageText = Localized.string("overlay.confirm_return_title", locale: locale)
            alert.informativeText = Localized.string("overlay.confirm_return_msg", locale: locale)
            alert.alertStyle = .warning
            alert.addButton(withTitle: Localized.string("overlay.confirm_return_cancel", locale: locale))
            alert.addButton(withTitle: Localized.string("overlay.confirm_return_ok", locale: locale))
            alert.beginSheetModal(for: window) { response in
                if response == .alertSecondButtonReturn {
                    store.returnToWork()
                }
            }
        }
    }

    func presentMacSnoozeBreakDialog(locale: Locale) {
        resignBreakOverlayNativeEditingFocus()
        DispatchQueue.main.async {
            let store = self.store
            guard let window = self.breakOverlaySheetAnchorWindow() else { return }
            let alert = NSAlert()
            alert.messageText = Localized.string("overlay.snooze_title", locale: locale)
            alert.informativeText = Localized.string("overlay.snooze_hint", locale: locale)
            alert.alertStyle = .informational
            alert.addButton(withTitle: Localized.string("common.cancel", locale: locale))
            alert.addButton(withTitle: Localized.string("overlay.snooze_5", locale: locale))
            alert.addButton(withTitle: Localized.string("overlay.snooze_15", locale: locale))
            alert.addButton(withTitle: Localized.string("overlay.snooze_30", locale: locale))
            alert.beginSheetModal(for: window) { response in
                let base = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                switch response.rawValue - base {
                case 1: store.snoozeBreak(minutes: 5)
                case 2: store.snoozeBreak(minutes: 15)
                case 3: store.snoozeBreak(minutes: 30)
                default: break
                }
            }
        }
    }
}
#endif

private extension View {
    /// 参考示意图：厚磨砂 + 深色半透明罩层，压低高光；细渐变描边与柔和悬浮阴影。
    func disguiseSidebarGlassChrome(cornerRadius: CGFloat) -> some View {
        self
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.thickMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(red: 0.07, green: 0.09, blue: 0.13).opacity(0.44))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.055)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.42), radius: 38, x: 0, y: 18)
            .preferredColorScheme(.dark)
    }
}

private struct UsageScopeSegmentedControl: View {
    @Binding var selection: UsageScope
    let locale: Locale
    var compact: Bool

    var body: some View {
        let innerCorner: CGFloat = compact ? 6 : 7
        let outerCorner: CGFloat = compact ? 9 : 10
        HStack(spacing: 2) {
            ForEach(UsageScope.allCases) { scope in
                let selected = selection == scope
                Button {
                    selection = scope
                } label: {
                    Text(scope.localizedShortTitle(locale: locale))
                        .font(.system(size: compact ? 10 : 11, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.52))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .padding(.vertical, compact ? 6 : 8)
                        .padding(.horizontal, compact ? 7 : 9)
                        .frame(maxWidth: .infinity, minHeight: compact ? 32 : 36)
                        .background {
                            RoundedRectangle(cornerRadius: innerCorner, style: .continuous)
                                .fill(selected ? Color.white.opacity(0.30) : Color.clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: innerCorner, style: .continuous)
                                .strokeBorder(selected ? Color.white.opacity(0.50) : Color.clear, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(scope.localizedPickerDescription(locale: locale))
            }
        }
        .padding(3)
        .background(Color.black.opacity(compact ? 0.28 : 0.26), in: RoundedRectangle(cornerRadius: outerCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: outerCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(0.17), lineWidth: 1)
        }
        .frame(minWidth: compact ? 172 : 200)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct RestActionButton: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    /// 伪装侧边栏等窄容器：横向铺满，字号略收。
    var expandsToFill: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: expandsToFill ? 13 : 16, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(expandsToFill ? 0.28 : 0), radius: 2, x: 0, y: 1)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, expandsToFill ? 8 : 0)
                .frame(maxWidth: expandsToFill ? .infinity : nil, minHeight: expandsToFill ? 40 : 48)
                .frame(width: expandsToFill ? nil : 256)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(isPrimary ? 0.12 : 0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isPrimary ? 0.22 : 0.14), radius: expandsToFill ? 10 : 14, y: expandsToFill ? 5 : 8)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var background: some ShapeStyle {
        if isPrimary {
            AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.06, green: 0.36, blue: 0.92)],
                startPoint: .top,
                endPoint: .bottom
            ))
        } else {
            AnyShapeStyle(LinearGradient(
                colors: [Color.white.opacity(0.18), Color.white.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }
}
