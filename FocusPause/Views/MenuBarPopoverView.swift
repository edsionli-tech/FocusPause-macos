import SwiftUI

#if !targetEnvironment(macCatalyst)
import AppKit
#endif

struct MenuBarPopoverView: View {
    @ObservedObject var store: FocusPauseStore
    let openSettings: () -> Void
    let closePopover: () -> Void

    @Environment(\.locale) private var locale

    /// 添加二级待办时绑定的父任务 id；在输入框确认添加后清空。
    @State private var pendingTodoParentId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            timerHero
            actionRow
            todoPreview
            footer
        }
        .frame(width: 548)
        .background(.regularMaterial)
        .onAppear {
            store.resetTodoListDayToTodayOnPanelOpen()
        }
        .onChange(of: store.todos) { _ in
            guard let pid = pendingTodoParentId else { return }
            if store.todos.first(where: { $0.id == pid && $0.parentId == nil }) == nil {
                pendingTodoParentId = nil
            }
        }
        .overlay(alignment: .top) {
            if let message = store.popoverMessage ?? store.panicMessage {
                Text(message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FocusPauseBrandMark(size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("FocusPause")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(Localized.string("popover.tagline", locale: locale))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                closePopover()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.quaternary.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(28)
    }

    private var timerHero: some View {
        VStack(spacing: 12) {
            if store.isDoNotDisturbPopoverProminent {
                DoNotDisturbBadge(
                    title: store.dndStatusTitle,
                    isEnabled: true
                )
            }
            Text(store.currentTimeText)
                .font(.system(size: 78, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            timerRuleControls
        }
        .padding(.bottom, 26)
    }

    private var actionRow: some View {
        HStack(spacing: 14) {
            startFocusButton

            Button(action: store.startBreakNow) {
                Label(Localized.string("popover.break_now", locale: locale), systemImage: "cup.and.saucer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            doNotDisturbMenu
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var startFocusButton: some View {
        let button = Button(action: store.startFocus) {
            Label(Localized.string("popover.start_focus", locale: locale), systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }

        if store.isDoNotDisturbPausingTimer {
            button
                .buttonStyle(.bordered)
                .controlSize(.large)
        } else {
            button
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var timerRuleControls: some View {
        HStack(spacing: 8) {
            ruleMenu(
                title: String(format: Localized.string("popover.work_duration_menu", locale: locale), store.settings.minWorkMinutes),
                values: Array(stride(from: 15, through: 60, by: 5)),
                currentValue: store.settings.minWorkMinutes
            ) { value in
                store.updateReminderDurations(minWork: value)
            }

            ruleMenu(
                title: String(format: Localized.string("popover.break_duration_menu", locale: locale), store.settings.breakMinutes),
                values: Array(stride(from: 5, through: 20, by: 5)),
                currentValue: store.settings.breakMinutes
            ) { value in
                store.updateReminderDurations(breakMinutes: value)
            }
        }
    }

    private func ruleMenu(
        title: String,
        values: [Int],
        currentValue: Int,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in
                Button {
                    onSelect(value)
                } label: {
                    Label(String(format: Localized.string("format.minutes_suffix", locale: locale), value), systemImage: value == currentValue ? "checkmark" : "clock")
                }
            }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var doNotDisturbMenu: some View {
        let menu = Menu {
            Button {
                store.setDoNotDisturb(.morning)
            } label: {
                Label(DoNotDisturbPeriod.morning.localizedPickerTitle(locale: locale), systemImage: store.settings.dndPeriod == .morning ? "checkmark" : "sunrise")
            }
            Button {
                store.setDoNotDisturb(.afternoon)
            } label: {
                Label(DoNotDisturbPeriod.afternoon.localizedPickerTitle(locale: locale), systemImage: store.settings.dndPeriod == .afternoon ? "checkmark" : "sun.max")
            }
            Button {
                store.setDoNotDisturb(.allDay)
            } label: {
                Label(DoNotDisturbPeriod.allDay.localizedPickerTitle(locale: locale), systemImage: store.settings.dndPeriod == .allDay ? "checkmark" : "moon.zzz")
            }
            Divider()
            Button {
                store.setDoNotDisturb(.off)
            } label: {
                Label(DoNotDisturbPeriod.off.localizedPickerTitle(locale: locale), systemImage: store.settings.dndPeriod == .off ? "checkmark" : "bell")
            }
        } label: {
            Label(Localized.string("popover.dnd_menu", locale: locale), systemImage: "moon.fill")
                .frame(maxWidth: .infinity)
        }

        if store.isDoNotDisturbPopoverProminent {
            menu
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
        } else {
            menu
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
    }

    private var todoPreview: some View {
        VStack(spacing: 6) {
            TodoListDayHeader(
                selectedDay: Binding(
                    get: { store.todoListSelectedNormalizedDay },
                    set: { store.setTodoListSelectedDay($0) }
                ),
                panelChrome: .popoverCard,
                progressText: "\(store.completedCount(forListDay: store.todoListSelectedNormalizedDay))/\(store.totalCount(forListDay: store.todoListSelectedNormalizedDay))"
            )
            .padding(.horizontal, 8)

            ScrollView {
                TodoChecklistEditorView(
                    store: store,
                    pendingParentId: $pendingTodoParentId,
                    prefersLightContent: false,
                    emptyStateHint: Localized.string("todo.empty_hint_popover", locale: locale),
                    panelChrome: .popoverCard
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 296)
            .scrollIndicators(.visible)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .padding(8)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Label(Localized.string("popover.settings", locale: locale), systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
#if !targetEnvironment(macCatalyst)
                NSApplication.shared.terminate(nil)
#endif
            } label: {
                Label(Localized.string("popover.quit", locale: locale), systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
}
