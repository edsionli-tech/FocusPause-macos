import SwiftUI
#if !targetEnvironment(macCatalyst)
import AppKit
#endif

struct StatusBadge: View {
    let status: FocusStatus
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.color)
                .frame(width: 11, height: 11)
            Text(status.localizedTitle(locale: locale))
                .font(.headline)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }
}

struct DoNotDisturbBadge: View {
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isEnabled ? .orange : .secondary)
                .frame(width: 11, height: 11)
            Text(title)
                .font(.headline)
                .foregroundStyle(isEnabled ? .orange : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
    }
}

/// 待办列表面板样式（菜单栏 / 标准休息遮罩 / 伪装侧边栏）。
enum TodoListPanelChrome {
    case glassCard
    case popoverCard
    case disguiseGlass
}

// MARK: - 自定义日历（待办日期弹窗）

private struct TodoCalendarDayCell: Identifiable {
    let date: Date
    let dayNumber: Int
    let inDisplayedMonth: Bool

    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}

private enum TodoCalendarGridBuilder {
    static func cells(monthContaining anchor: Date, calendar: Calendar) -> [TodoCalendarDayCell] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: anchor)),
              let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count
        else { return [] }

        let weekdayFirst = calendar.component(.weekday, from: monthStart)
        let leading = (weekdayFirst - calendar.firstWeekday + 7) % 7

        var cells: [TodoCalendarDayCell] = []

        for k in 0..<leading {
            let offset = k - leading
            guard let d = calendar.date(byAdding: .day, value: offset, to: monthStart) else { continue }
            let dom = calendar.component(.day, from: d)
            cells.append(TodoCalendarDayCell(date: d, dayNumber: dom, inDisplayedMonth: false))
        }

        for day in 1...daysInMonth {
            guard let d = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            cells.append(TodoCalendarDayCell(date: d, dayNumber: day, inDisplayedMonth: true))
        }

        while cells.count % 7 != 0 {
            guard let last = cells.last?.date, let d = calendar.date(byAdding: .day, value: 1, to: last) else { break }
            let dom = calendar.component(.day, from: d)
            cells.append(TodoCalendarDayCell(date: d, dayNumber: dom, inDisplayedMonth: false))
        }

        return cells
    }

    static func startOfMonth(for day: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
    }
}

/// 深色半透明自定义月历（替代系统 DatePicker）。
private struct TodoDarkCalendarPopoverBody: View {
    @Binding var selectedDay: Date
    let pickRange: ClosedRange<Date>
    let todayStart: Date
    let accent: Color
    let calendarForPickerDisplay: Calendar

    @Environment(\.locale) private var locale
    @State private var visibleMonthAnchor: Date

    init(
        selectedDay: Binding<Date>,
        pickRange: ClosedRange<Date>,
        todayStart: Date,
        accent: Color,
        calendarForPickerDisplay: Calendar
    ) {
        _selectedDay = selectedDay
        self.pickRange = pickRange
        self.todayStart = todayStart
        self.accent = accent
        self.calendarForPickerDisplay = calendarForPickerDisplay
        let normalized = TodoDueDayFormatting.normalize(selectedDay.wrappedValue)
        let clamped = min(max(normalized, pickRange.lowerBound), pickRange.upperBound)
        _visibleMonthAnchor = State(initialValue: TodoCalendarGridBuilder.startOfMonth(for: clamped, calendar: calendarForPickerDisplay))
    }

    private var calendar: Calendar { calendarForPickerDisplay }

    private var normalizedSelection: Date {
        TodoDueDayFormatting.normalize(selectedDay)
    }

    private func clampDay(_ day: Date) -> Date {
        let n = TodoDueDayFormatting.normalize(day)
        return min(max(n, pickRange.lowerBound), pickRange.upperBound)
    }

    private var visibleMonthStart: Date {
        TodoCalendarGridBuilder.startOfMonth(for: visibleMonthAnchor, calendar: calendar)
    }

    private var earliestMonthStart: Date {
        TodoCalendarGridBuilder.startOfMonth(for: pickRange.lowerBound, calendar: calendar)
    }

    private var latestMonthStart: Date {
        TodoCalendarGridBuilder.startOfMonth(for: pickRange.upperBound, calendar: calendar)
    }

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.calendar = calendar
        fmt.setLocalizedDateFormatFromTemplate("yMMMM")
        return fmt.string(from: visibleMonthStart)
    }

    private var canGoPrevMonth: Bool { visibleMonthStart > earliestMonthStart }
    private var canGoNextMonth: Bool { visibleMonthStart < latestMonthStart }

    private var canGoPrevYear: Bool {
        guard let prevYearMonth = calendar.date(byAdding: .year, value: -1, to: visibleMonthStart) else { return false }
        return TodoCalendarGridBuilder.startOfMonth(for: prevYearMonth, calendar: calendar) >= earliestMonthStart
    }

    private var canGoNextYear: Bool {
        guard let nextYearMonth = calendar.date(byAdding: .year, value: 1, to: visibleMonthStart) else { return false }
        return TodoCalendarGridBuilder.startOfMonth(for: nextYearMonth, calendar: calendar) <= latestMonthStart
    }

    private var gridCells: [TodoCalendarDayCell] {
        TodoCalendarGridBuilder.cells(monthContaining: visibleMonthStart, calendar: calendar)
    }

    /// 非惰性网格布局：避免 LazyVGrid 首帧高度为 0 导致 Popover 背景铺不全。
    private var calendarGridRows: [[TodoCalendarDayCell]] {
        stride(from: 0, to: gridCells.count, by: 7).map { start in
            Array(gridCells[start ..< min(start + 7, gridCells.count)])
        }
    }

    private var weekdaySymbols: [String] {
        let syms = calendar.shortStandaloneWeekdaySymbols
        guard syms.count >= 7 else {
            return (0..<7).map { _ in "?" }
        }
        let fw = calendar.firstWeekday
        return (0..<7).map { offset in
            syms[(fw - 1 + offset) % 7]
        }
    }

    /// 单层底色铺满圆角区域（避免出现「外灰内黑」未对齐的视觉断层）。
    private static let panelFill = Color(red: 0.12, green: 0.13, blue: 0.15)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                }

            VStack(spacing: 10) {
                HStack(spacing: 4) {
                    navPair(iconLeading: "chevron.backward.2", iconTrailing: "chevron.backward", goLeading: { shiftMonth(-12) }, goTrailing: { shiftMonth(-1) }, canLeading: canGoPrevYear, canTrailing: canGoPrevMonth)
                    Spacer(minLength: 8)
                    Text(monthTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    navPair(iconLeading: "chevron.forward", iconTrailing: "chevron.forward.2", goLeading: { shiftMonth(1) }, goTrailing: { shiftMonth(12) }, canLeading: canGoNextMonth, canTrailing: canGoNextYear)
                }
                .padding(.horizontal, 2)

                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        ForEach(weekdaySymbols, id: \.self) { w in
                            Text(w)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.42))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(calendarGridRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 4) {
                            ForEach(row) { cell in
                                dayCell(cell)
                                    .frame(maxWidth: .infinity)
                            }
                            ForEach(0 ..< max(0, 7 - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: visibleMonthStart)

                Divider()
                    .overlay(Color.white.opacity(0.12))

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2.weight(.medium))
                    Text(Localized.string("todo.cal.hint", locale: locale))
                        .font(.caption2)
                }
                .foregroundStyle(Color.white.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 296, minHeight: 328)
        .preferredColorScheme(.dark)
        .onChange(of: selectedDay) { _ in
            let c = clampDay(normalizedSelection)
            if c != normalizedSelection {
                selectedDay = c
            }
            let ms = TodoCalendarGridBuilder.startOfMonth(for: c, calendar: calendar)
            if ms != visibleMonthStart {
                visibleMonthAnchor = ms
            }
        }
    }

    private func navPair(
        iconLeading: String,
        iconTrailing: String,
        goLeading: @escaping () -> Void,
        goTrailing: @escaping () -> Void,
        canLeading: Bool,
        canTrailing: Bool
    ) -> some View {
        HStack(spacing: 2) {
            navIcon(iconLeading, enabled: canLeading, action: goLeading)
            navIcon(iconTrailing, enabled: canTrailing, action: goTrailing)
        }
    }

    private func navIcon(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? Color.white.opacity(0.88) : Color.white.opacity(0.4))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(enabled ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func shiftMonth(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: visibleMonthStart) else { return }
        let ms = TodoCalendarGridBuilder.startOfMonth(for: next, calendar: calendar)
        visibleMonthAnchor = min(max(ms, earliestMonthStart), latestMonthStart)
    }

    private func isSelectable(_ day: Date) -> Bool {
        let n = TodoDueDayFormatting.normalize(day)
        return n >= pickRange.lowerBound && n <= pickRange.upperBound
    }

    private func dayCell(_ cell: TodoCalendarDayCell) -> some View {
        let n = TodoDueDayFormatting.normalize(cell.date)
        let selected = n == normalizedSelection
        let today = n == todayStart
        let selectable = isSelectable(cell.date)

        return Button {
            selectedDay = clampDay(cell.date)
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .fill(accent)
                        .frame(width: 30, height: 30)
                } else if today {
                    Circle()
                        .strokeBorder(accent.opacity(0.55), lineWidth: 1)
                        .frame(width: 30, height: 30)
                }

                Text("\(cell.dayNumber)")
                    .font(.system(size: 14, weight: selected ? .semibold : .medium))
                    .foregroundStyle(foregroundForDay(cell: cell, selected: selected, selectable: selectable))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
    }

    private func foregroundForDay(cell: TodoCalendarDayCell, selected: Bool, selectable: Bool) -> Color {
        if selected { return Color.white }
        if !selectable { return Color.white.opacity(0.18) }
        if cell.inDisplayedMonth { return Color.white.opacity(0.9) }
        return Color.white.opacity(0.34)
    }
}

// MARK: - 待办按日筛选头部

struct TodoListDayHeader: View {
    @Binding var selectedDay: Date
    let panelChrome: TodoListPanelChrome
    /// 与标题同行的进度文案，例如「3/5」。
    let progressText: String

    @Environment(\.locale) private var locale
    @State private var showSpecificDatePopover = false
    /// 日历按钮展示的日期：与列表选中无关（切「长期待办」时不改写）。
    @State private var calendarChipDay: Date = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { Calendar.current }
    private var todayStart: Date { calendar.startOfDay(for: Date()) }
    private var longTermStart: Date { TodoDueDayFormatting.longTermDueDay }
    private var tomorrowStart: Date { calendar.date(byAdding: .day, value: 1, to: todayStart)! }

    private var normalizedSelection: Date {
        TodoDueDayFormatting.normalize(selectedDay)
    }

    /// 日历可选：今天之前的日期（约 50 年内）至今天之后第 15 日。
    private var calendarPickRange: ClosedRange<Date> {
        let start = calendar.date(byAdding: .year, value: -50, to: todayStart)!
        let end = calendar.date(byAdding: .day, value: 15, to: todayStart)!
        return start ... end
    }

    private var calendarForPickerDisplay: Calendar {
        var c = Calendar.current
        c.locale = locale
        return c
    }

    private var isCustomDaySelected: Bool {
        let s = normalizedSelection
        let lt = TodoDueDayFormatting.longTermDueDay
        return !(s == lt || s == todayStart || s == tomorrowStart)
    }

    private var accent: Color {
        switch panelChrome {
        case .popoverCard:
            return Color(red: 0.22, green: 0.48, blue: 0.96)
        case .glassCard, .disguiseGlass:
            return Color(red: 0.38, green: 0.64, blue: 0.98)
        }
    }

    private var titleColor: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.primary
        case .glassCard, .disguiseGlass:
            return Color.white.opacity(0.94)
        }
    }

    private var progressColor: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.secondary
        case .glassCard, .disguiseGlass:
            return Color.white.opacity(0.55)
        }
    }

    private var mutedSegmentTitle: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.primary.opacity(0.55)
        case .glassCard, .disguiseGlass:
            return Color.white.opacity(0.72)
        }
    }

    private var barBackground: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.primary.opacity(0.06)
        case .glassCard:
            return Color.white.opacity(0.10)
        case .disguiseGlass:
            return Color.white.opacity(0.08)
        }
    }

    private var barStroke: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.primary.opacity(0.12)
        case .glassCard, .disguiseGlass:
            return Color.white.opacity(0.14)
        }
    }

    private var highlightFourthSegment: Bool {
        isCustomDaySelected || showSpecificDatePopover
    }

    /// 列表为「长期」时，日历弹窗仍锚定在日历按钮上的日期，避免落到 9999 锚点日。
    private var calendarPickerBinding: Binding<Date> {
        Binding(
            get: {
                let n = normalizedSelection
                if TodoDueDayFormatting.isLongTermDueDay(n) {
                    return TodoDueDayFormatting.normalize(calendarChipDay)
                }
                return selectedDay
            },
            set: { newVal in
                let norm = TodoDueDayFormatting.normalize(newVal)
                selectedDay = norm
                calendarChipDay = norm
            }
        )
    }

    private func syncCalendarChipFromListSelectionIfNotLongTerm() {
        let n = normalizedSelection
        guard !TodoDueDayFormatting.isLongTermDueDay(n) else { return }
        calendarChipDay = n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Localized.string("todo.list.title", locale: locale))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(titleColor)
                Spacer(minLength: 8)
                Text(progressText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(progressColor)
            }

            HStack(spacing: 0) {
                segmentButton(title: Localized.string("day.long_term", locale: locale), day: longTermStart)
                segmentDivider
                segmentButton(title: Localized.string("day.today", locale: locale), day: todayStart)
                segmentDivider
                segmentButton(title: Localized.string("day.tomorrow", locale: locale), day: tomorrowStart)
                segmentDivider
                specificDateSegmentButton
            }
            .padding(3)
            .background(barBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(barStroke, lineWidth: 1)
            }
        }
        .onAppear {
            syncCalendarChipFromListSelectionIfNotLongTerm()
        }
        .onChange(of: selectedDay) { _ in
            syncCalendarChipFromListSelectionIfNotLongTerm()
        }
    }

    private var calendarChipPrimaryText: String {
        TodoDueDayFormatting.digitsYyyyMmDd(for: TodoDueDayFormatting.normalize(calendarChipDay))
    }

    private var specificDateSegmentButton: some View {
        let digits = calendarChipPrimaryText
        let hi = highlightFourthSegment
        return Button {
            showSpecificDatePopover = true
        } label: {
            HStack(spacing: 5) {
                Text(digits)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(hi ? Color.white : mutedSegmentTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hi ? Color.white.opacity(0.95) : mutedSegmentTitle)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                hi ? (isCustomDaySelected ? accent : accent.opacity(0.42)) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if hi {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(accent.opacity(0.95), lineWidth: 1.5)
                }
            }
            }
            .buttonStyle(.plain)
        .popover(isPresented: $showSpecificDatePopover, arrowEdge: .bottom) {
            TodoDarkCalendarPopoverBody(
                selectedDay: calendarPickerBinding,
                pickRange: calendarPickRange,
                todayStart: todayStart,
                accent: accent,
                calendarForPickerDisplay: calendarForPickerDisplay
            )
        }
    }

    private var segmentDivider: some View {
        Rectangle()
            .fill(barStroke.opacity(0.65))
            .frame(width: 1, height: 28)
    }

    private func segmentButton(title: String, day: Date) -> some View {
        let on = normalizedSelection == TodoDueDayFormatting.normalize(day)
        return Button {
            showSpecificDatePopover = false
            selectedDay = day
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(on ? Color.white : mutedSegmentTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
                .background(
                    on ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                }
                .buttonStyle(.plain)
    }
}

/// 参考 Apple「备忘录」清单：空心圆 / 完成橙色打勾、回车新建下一行、空行退格删除、左侧抓手占位与对齐风格一致，次要操作进右键菜单。
struct NotesChecklistTodoPanel: View {
    fileprivate enum ListFocus: Hashable {
        case row(UUID)
    }

    @ObservedObject var store: FocusPauseStore
    @Binding var pendingParentId: UUID?
    var prefersLightContent: Bool
    var emptyStateHint: String
    var panelChrome: TodoListPanelChrome
    /// 为 true 时不渲染日期头（由外层固定展示），菜单栏待办仅滚动列表，切换日期不会跳到滚动区域顶端。
    var hideDayHeader: Bool = false
    /// 全屏休息遮罩等场景下 SwiftUI `ScrollView` 会先截获按键；为 true 时在 `NSTextView` 上用本地监视器优先处理编辑快捷键并与系统 `interpretKeyEvents` 对齐。
    var useLocalKeyMonitor: Bool = false
    /// 全屏遮盖等待办列表外层为 SwiftUI `ScrollView`；聚焦某行前应先滚到该行，否则新建行常在视口外且难以接续输入。
    var scrollToRow: ((UUID) -> Void)? = nil

    @Environment(\.locale) private var locale
    @FocusState private var listFocus: ListFocus?
    /// 行内编辑草稿（与 store 解耦，失焦时写回）。
    @State private var rowDrafts: [UUID: String] = [:]
    @State private var priorListFocus: ListFocus?

    var body: some View {
            Group {
            switch panelChrome {
            case .glassCard:
                dayHeaderAndChecklist
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            case .popoverCard:
                dayHeaderAndChecklist
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            case .disguiseGlass:
                dayHeaderAndChecklist
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .onAppear {
            primeRowDrafts()
            priorListFocus = listFocus
        }
        .onChange(of: store.todos.map(\.id)) { _ in
            primeRowDrafts()
            pruneRowDrafts()
        }
        .onChange(of: store.settings.todoListSelectedDay) { _ in
            primeRowDrafts()
        }
        .onChange(of: listFocus) { newFocus in
            defer { priorListFocus = newFocus }
            guard let previous = priorListFocus else { return }
            if case .row(let pid) = previous {
                let stillThatRow: Bool
                if case .row(let nid) = newFocus {
                    stillThatRow = nid == pid
                                } else {
                    stillThatRow = false
                                }
                if !stillThatRow {
                    flushRowEditing(for: pid)
                            }
                                }
                            }
                    }

    private var dayHeaderAndChecklist: some View {
        Group {
            if hideDayHeader {
                checklistContent
                } else {
                VStack(alignment: .leading, spacing: panelChrome == .popoverCard ? 8 : 12) {
                    TodoListDayHeader(
                        selectedDay: Binding(
                            get: { store.todoListSelectedNormalizedDay },
                            set: { store.setTodoListSelectedDay($0) }
                        ),
                        panelChrome: panelChrome,
                        progressText: "\(store.completedCount(forListDay: store.todoListSelectedNormalizedDay))/\(store.totalCount(forListDay: store.todoListSelectedNormalizedDay))"
                    )
                    checklistContent
                }
            }
        }
    }

    private var displayedTodos: [TodoItem] {
        store.todosForListDay(store.todoListSelectedNormalizedDay)
    }

    private var emptyDateHint: String {
        Localized.string("todo.empty_day", locale: locale)
    }

    @ViewBuilder
    private var checklistContent: some View {
        let expandEmptyTapZone = displayedTodos.isEmpty
        ZStack(alignment: .topLeading) {
            if expandEmptyTapZone {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .onTapGesture { beginEditingFirstTodoForEmptyDay() }
            }
            VStack(alignment: .leading, spacing: 0) {
                if store.todos.isEmpty {
                    Text(emptyStateHint)
                        .font(.body)
                        .foregroundStyle(secondaryText.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.leading, leadInsetComposer)
                            .contentShape(Rectangle())
                        .onTapGesture { beginEditingFirstTodoForEmptyDay() }
                } else if displayedTodos.isEmpty {
                    Text(emptyDateHint)
                        .font(.body)
                        .foregroundStyle(secondaryText.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.leading, leadInsetComposer)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEditingFirstTodoForEmptyDay() }
                }

                ForEach(displayedTodos) { todo in
                    NotesChecklistItemRow(
                        todo: todo,
                        draftTitle: bindingDraft(for: todo),
                        hasChildren: store.todos.contains { $0.parentId == todo.id },
                        indentLevel: todo.parentId == nil ? 0 : 1,
                        prefersLightContent: prefersLightContent,
                        softGlassContrast: panelChrome == .disguiseGlass,
                        panelChrome: panelChrome,
                        listFocus: $listFocus,
                        onToggle: { store.toggleTodo(todo.id) },
                        onCyclePriority: { store.cyclePriority(todo.id) },
                        onReturn: { collapsed, caretUTF16 in
                            handleReturn(after: todo, collapsedPlain: collapsed, caretUTF16: caretUTF16)
                        },
                        onBackspaceEmpty: { handleBackspaceEmpty(for: todo.id) },
                        onFocusPreviousRow: { focusAdjacentTodoRow(from: todo.id, delta: -1) },
                        onFocusNextRow: { focusAdjacentTodoRow(from: todo.id, delta: 1) },
                        onMergeBackward: { mergeTodoBackward(for: todo.id, currentPlain: $0) },
                        useLocalKeyMonitor: useLocalKeyMonitor,
                        onAddSubtask: { beginAddingSubtask(under: todo.id) },
                        onIndent: { store.indentTodo(todo.id) },
                        onOutdent: { store.outdentTodo(todo.id) },
                        onDelete: { store.deleteTodo(todo.id) },
                        onDeleteCascade: { store.deleteTodoIncludingChildren(todo.id) },
                        onSetDueDayRelativeToToday: { store.setTodoDueDayRelativeToToday(id: todo.id, daysFromToday: $0) },
                        onShiftDueDay: { store.shiftTodoDueDay(id: todo.id, by: $0) },
                        onSetDueDayLongTerm: { store.setTodoDueDayLongTerm(id: todo.id) },
                        todoCategories: store.settings.effectiveTodoCategories,
                        onSetTodoCategory: { store.setTodoCategory(id: todo.id, categoryId: $0) }
                    )
                    .id(todo.id)
                }

                trailingListTailDropZone
            }
        }
    }

    /// 列表尾部：点击在末尾追加空白待办并进入编辑（备忘录 checklist 点空白区行为）。
    private var trailingListTailDropZone: some View {
        Color.clear
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { focusChecklistTail() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 当日无待办：插入第一条空白行并聚焦。
    private func beginEditingFirstTodoForEmptyDay() {
        pendingParentId = nil
        guard let id = store.addBlankRootTodoForSelectedListDay() else { return }
        rowDrafts[id] = ""
        focusRow(id, placeCaretAtEnd: true)
    }

    /// 末尾若已有空白行则聚焦该行，否则新建空白行（与备忘录尾部输入一致）。
    private func focusChecklistTail() {
        pendingParentId = nil
        if let last = displayedTodos.last {
            let draft = (rowDrafts[last.id] ?? last.title).trimmingCharacters(in: .whitespacesAndNewlines)
            if draft.isEmpty {
                focusRow(last.id, placeCaretAtEnd: true)
                return
            }
        }
        guard let id = store.addBlankRootTodoForSelectedListDay() else { return }
        rowDrafts[id] = ""
        focusRow(id, placeCaretAtEnd: true)
    }

    private func beginAddingSubtask(under parentId: UUID) {
        pendingParentId = nil
        guard let id = store.addBlankChildTodo(under: parentId) else { return }
        rowDrafts[id] = ""
        focusRow(id, placeCaretAtEnd: true)
    }

    private func focusRow(_ id: UUID, placeCaretAtEnd: Bool = false, caretUTF16: Int? = nil) {
        listFocus = .row(id)
#if os(macOS) && !targetEnvironment(macCatalyst)
        DispatchQueue.main.async {
            scrollToRow?(id)
            let applyFocus = {
                TodoChecklistFieldBridge.shared.focus(rowId: id, placeCaretAtEnd: placeCaretAtEnd, caretUTF16: caretUTF16)
            }
            if scrollToRow != nil {
                DispatchQueue.main.async(execute: applyFocus)
            } else {
                applyFocus()
            }
        }
#endif
    }

    /// 行首删除：与上一条合并；子任务优先并入前方**同级**子任务，否则并入父任务；一级有待办带子任务时先将子任务迁到合并目标再删本条。
    private func mergeTodoBackward(for todoId: UUID, currentPlain: String) -> Bool {
        guard !currentPlain.isEmpty else { return false }
        guard let todo = store.todos.first(where: { $0.id == todoId }) else { return false }
        let listDay = store.todoListSelectedNormalizedDay

        let mergeTarget: UUID?
        if let parentId = todo.parentId {
            if let pred = store.orderedPredecessorId(of: todoId, listDay: listDay),
               let predTodo = store.todos.first(where: { $0.id == pred }),
               predTodo.parentId == parentId {
                mergeTarget = pred
            } else {
                mergeTarget = parentId
            }
        } else {
            mergeTarget = store.orderedPredecessorId(of: todoId, listDay: listDay)
        }
        guard let tid = mergeTarget else { return false }
        guard let targetTodo = store.todos.first(where: { $0.id == tid }) else { return false }

        let hadChildren = store.todos.contains { $0.parentId == todoId }
        if hadChildren {
            guard todo.parentId == nil, targetTodo.parentId == nil else { return false }
            store.moveChildren(fromParentId: todoId, toParentId: tid)
        }

        let targetBase = rowDrafts[tid] ?? targetTodo.title
        let mergedRaw = targetBase + currentPlain
        let mergedTrimmed = mergedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mergedTrimmed.isEmpty else { return false }

        let junctionUTF16 = (targetBase as NSString).length

        store.renameTodo(id: tid, to: mergedRaw)
        store.deleteTodo(todoId)
        rowDrafts.removeValue(forKey: todoId)
        if let kept = store.todos.first(where: { $0.id == tid }) {
            rowDrafts[tid] = kept.title
        }

        let finalTitle = rowDrafts[tid] ?? mergedTrimmed
        let safeCaret = min(junctionUTF16, (finalTitle as NSString).length)
        focusRow(tid, caretUTF16: safeCaret)
        return true
    }

    /// 与勾选框左缘对齐：抓手占位 + 间距 + 圆形勾选占位。
    private var leadInsetComposer: CGFloat { 22 + 8 + 22 }

    private var secondaryText: Color {
        if panelChrome == .disguiseGlass {
            return Color.white.opacity(0.46)
        }
        return prefersLightContent ? Color.white.opacity(0.62) : Color.secondary
    }

    private func bindingDraft(for todo: TodoItem) -> Binding<String> {
        Binding(
            get: { rowDrafts[todo.id] ?? todo.title },
            set: { rowDrafts[todo.id] = $0 }
        )
    }

    private func primeRowDrafts() {
        for t in displayedTodos where rowDrafts[t.id] == nil {
            rowDrafts[t.id] = t.title
        }
    }

    private func pruneRowDrafts() {
        let ids = Set(store.todos.map(\.id))
        rowDrafts = rowDrafts.filter { ids.contains($0.key) }
    }

    private func persistNonEmptyTitle(for todo: TodoItem) {
        let trimmed = (rowDrafts[todo.id] ?? todo.title).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed != todo.title {
            store.renameTodo(id: todo.id, to: trimmed)
        }
        rowDrafts[todo.id] = trimmed
    }

    private func flushRowEditing(for id: UUID) {
        guard let todo = store.todos.first(where: { $0.id == id }) else {
            rowDrafts.removeValue(forKey: id)
            return
        }
        let trimmed = (rowDrafts[todo.id] ?? todo.title).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            store.deleteTodo(todo.id)
            rowDrafts.removeValue(forKey: id)
            return
        }
        if trimmed != todo.title {
            store.renameTodo(id: todo.id, to: trimmed)
        }
        rowDrafts[todo.id] = trimmed
    }

    private func handleReturn(after todo: TodoItem, collapsedPlain: String, caretUTF16: Int) {
        let ns = collapsedPlain as NSString
        let len = ns.length
        let caret = min(max(0, caretUTF16), len)

        rowDrafts[todo.id] = collapsedPlain

        // 行首回车：在上方插入空白行（本条正文不下沉）
        if caret == 0, len > 0 {
            guard let newId = store.insertTodoBefore(todo.id, title: "") else { return }
            rowDrafts[newId] = ""
            focusRow(newId, placeCaretAtEnd: true)
            return
        }

        // 行尾回车：保持备忘录习惯，新建下一条空白待办
        if caret >= len {
            persistNonEmptyTitle(for: todo)
            guard let newId = store.addTodoAfter(todo.id, title: "") else { return }
            rowDrafts[newId] = ""
            focusRow(newId, placeCaretAtEnd: true)
            return
        }

        // 行中回车：前半留在本条，后半移到新行（光标在新行行首）。本条仍为第一响应者的一帧内需手动缩短 NSTextView。
        let before = ns.substring(to: caret)
        let after = ns.substring(from: caret)
        store.renameTodo(id: todo.id, to: before)
        if let kept = store.todos.first(where: { $0.id == todo.id }) {
            rowDrafts[todo.id] = kept.title
            TodoChecklistFieldBridge.shared.syncPlainWhileFirstResponder(rowId: todo.id, plain: kept.title)
        }
        guard let newId = store.addTodoAfter(todo.id, title: after) else { return }
        rowDrafts[newId] = after
        focusRow(newId, placeCaretAtEnd: false)
    }

    /// 方向键 / 删除键在全文边界切换行：`-1` 上一行（光标在末尾），`+1` 下一行（光标在行首）。
    private func focusAdjacentTodoRow(from todoId: UUID, delta: Int) -> Bool {
        let listDay = store.todoListSelectedNormalizedDay
        let ordered = displayedTodos
        guard let idx = ordered.firstIndex(where: { $0.id == todoId }) else { return false }

        if delta < 0 {
            guard idx > 0 else { return false }
            let neighborId = ordered[idx - 1].id
            flushRowEditing(for: todoId)
            if displayedTodos.contains(where: { $0.id == neighborId }) {
                focusRow(neighborId, placeCaretAtEnd: true)
                return true
            }
            return false
        }

        if idx + 1 < ordered.count {
            let neighborId = ordered[idx + 1].id
            flushRowEditing(for: todoId)
            if displayedTodos.contains(where: { $0.id == neighborId }) {
                focusRow(neighborId, placeCaretAtEnd: false)
                return true
            }
            return false
        }

        let predecessorId = store.orderedPredecessorId(of: todoId, listDay: listDay)
        let todo = ordered[idx]
        let trimmed = (rowDrafts[todoId] ?? todo.title).trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            flushRowEditing(for: todoId)
            if let p = predecessorId, displayedTodos.contains(where: { $0.id == p }) {
                focusRow(p, placeCaretAtEnd: true)
            } else if displayedTodos.isEmpty {
                beginEditingFirstTodoForEmptyDay()
            } else if let first = displayedTodos.first {
                focusRow(first.id, placeCaretAtEnd: true)
            } else {
                listFocus = nil
            }
            return true
        }

        return false
    }

    private func handleBackspaceEmpty(for todoId: UUID) {
        let prev = store.orderedPredecessorId(of: todoId, listDay: store.todoListSelectedNormalizedDay)
        store.deleteTodo(todoId)
        rowDrafts.removeValue(forKey: todoId)
        if let prev {
            focusRow(prev, placeCaretAtEnd: true)
        } else if displayedTodos.isEmpty {
            beginEditingFirstTodoForEmptyDay()
        } else {
            listFocus = nil
        }
    }
}

private struct NotesChecklistItemRow: View {
    let todo: TodoItem
    @Binding var draftTitle: String
    let hasChildren: Bool
    let indentLevel: Int
    let prefersLightContent: Bool
    var softGlassContrast: Bool = false
    let panelChrome: TodoListPanelChrome
    @FocusState.Binding var listFocus: NotesChecklistTodoPanel.ListFocus?

    let onToggle: () -> Void
    let onCyclePriority: () -> Void
    let onReturn: (String, Int) -> Void
    let onBackspaceEmpty: () -> Void
    let onFocusPreviousRow: () -> Bool
    let onFocusNextRow: () -> Bool
    let onMergeBackward: (String) -> Bool
    var useLocalKeyMonitor: Bool = false
    let onAddSubtask: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onDelete: () -> Void
    let onDeleteCascade: () -> Void
    let onSetDueDayRelativeToToday: (Int) -> Void
    let onShiftDueDay: (Int) -> Void
    let onSetDueDayLongTerm: () -> Void
    let todoCategories: [TodoCategoryDefinition]
    let onSetTodoCategory: (UUID?) -> Void

    @Environment(\.locale) private var locale
    @State private var hovering = false
    /// `NSTextView` 已成为第一响应者与 SwiftUI `FocusState` 对齐之间可能有半帧差，用于及时收起「待办事项」占位。
    @State private var nativeTodoEditorFocused = false
    /// 分类选择：`Menu` 在 macOS 上常见情况是盖住自定义胶囊，样式完全不生效；改为 Button + Popover。
    @State private var categoryPopoverPresented = false

    private let notesCheckAccentStrong = Color(red: 1.0, green: 0.58, blue: 0.0)

    private var notesCheckAccentTint: Color {
        if softGlassContrast {
            return Color(red: 0.98, green: 0.62, blue: 0.34)
        }
        return notesCheckAccentStrong
    }

    private var secondaryLine: Color {
        if softGlassContrast && prefersLightContent {
            return Color.white.opacity(0.38)
        }
        return prefersLightContent ? Color.white.opacity(0.52) : Color.secondary.opacity(0.95)
    }

    private var titleTint: Color {
        if todo.isDone {
            if softGlassContrast && prefersLightContent {
                return Color.white.opacity(0.48)
            }
            return prefersLightContent ? Color.white.opacity(0.58) : Color.secondary
        }
        if softGlassContrast && prefersLightContent {
            return Color.white.opacity(0.86)
        }
        return prefersLightContent ? Color.white : Color.primary
    }

    private var rowFocused: Bool {
        listFocus == .row(todo.id)
    }

    /// 一级抓手略醒目，二级沿用较轻存在感（与此前「仅一级可拖」视觉权重一致，已无拖拽）。
    private var gripUsesStrongPresence: Bool {
        todo.parentId == nil
    }

    private var gripVisible: Bool {
        hovering || rowFocused
    }

    private var gripOpacity: CGFloat {
        let base: CGFloat = gripUsesStrongPresence ? 0.34 : 0.14
        let hi: CGFloat = gripUsesStrongPresence ? 0.58 : 0.36
        return gripVisible ? hi : base
    }

    /// 与 `.font(.body)` 首行对齐：抓手、勾选圆圈、日期胶囊在该高度内垂直居中（多行正文向下延展）。
    private var notesChecklistBodyLineHeight: CGFloat {
#if os(macOS)
        let font = NSFont.preferredFont(forTextStyle: .body)
        return ceil(font.ascender - font.descender + font.leading)
#else
        return 22
#endif
    }

#if os(macOS) && !targetEnvironment(macCatalyst)
    private var titleEditingNSColor: NSColor {
        if todo.isDone {
            if softGlassContrast && prefersLightContent {
                return NSColor.white.withAlphaComponent(0.48)
            }
            return prefersLightContent ? NSColor.white.withAlphaComponent(0.58) : NSColor.secondaryLabelColor
        }
        if softGlassContrast && prefersLightContent {
            return NSColor.white.withAlphaComponent(0.86)
        }
        return prefersLightContent ? NSColor.white : NSColor.labelColor
    }

#endif

    @ViewBuilder
    private var gripControl: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(gripTint.opacity(gripOpacity))
            .frame(width: 14)
            .opacity(gripVisible ? 1 : 0)
            .accessibilityHidden(true)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            gripControl
                .frame(width: 14, height: notesChecklistBodyLineHeight, alignment: .center)

            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(todo.isDone ? notesCheckAccentTint : secondaryLine)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: notesChecklistBodyLineHeight, alignment: .center)

            Group {
#if os(macOS) && !targetEnvironment(macCatalyst)
                ZStack(alignment: .topLeading) {
                    if showsEmptyTitlePlaceholder {
                        Text(Localized.string("todo.placeholder", locale: locale))
                            .font(.body)
                            .foregroundStyle(promptTint)
                            .padding(.top, 2)
                            .allowsHitTesting(false)
                    }
                    TodoChecklistField(
                        rowId: todo.id,
                        text: $draftTitle,
                        font: NSFont.preferredFont(forTextStyle: .body),
                        textColor: titleEditingNSColor,
                        showsStrikethrough: todo.isDone && !rowFocused,
                        isFocused: rowFocused,
                        onBeginEditing: { listFocus = .row(todo.id) },
                        onReturn: onReturn,
                        onExitCommand: {
                            draftTitle = todo.title
                            listFocus = nil
                            nativeTodoEditorFocused = false
                        },
                        onTab: { shiftPressed in
                            if shiftPressed { onOutdent() } else { onIndent() }
                        },
                        onBackspaceEmpty: onBackspaceEmpty,
                        onFocusPreviousRow: onFocusPreviousRow,
                        onFocusNextRow: onFocusNextRow,
                        onMergeBackward: onMergeBackward,
                        useLocalKeyMonitor: useLocalKeyMonitor,
                        onNativeFocusChanged: { nativeTodoEditorFocused = $0 }
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { listFocus = .row(todo.id) }
#else
                TextField("", text: $draftTitle, prompt: Text(Localized.string("todo.placeholder", locale: locale)).foregroundColor(promptTint), axis: .vertical)
            .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(titleTint)
                    .strikethrough(todo.isDone)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1...)
                    .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
                    .focused($listFocus, equals: .row(todo.id))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit {
                        let w = draftTitle
                        let caret = (w as NSString).length
                        onReturn(w, caret)
                    }
                    .onExitCommand {
                        draftTitle = todo.title
                        listFocus = nil
                    }
                    .onTabKeyPress { shiftPressed in
                        if shiftPressed { onOutdent() } else { onIndent() }
            }
            .onBackspaceKeyPress {
                        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.isEmpty else { return false }
                        onBackspaceEmpty()
                    return true
                }
#endif
            }
            .layoutPriority(1)

            todoCategoryMenuChip
                .fixedSize(horizontal: true, vertical: true)
                .frame(height: notesChecklistBodyLineHeight, alignment: .center)
        }
        .padding(.leading, CGFloat(min(indentLevel, 1)) * 20)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if todo.parentId == nil {
                Button(Localized.string("todo.menu.add_sub", locale: locale), action: onAddSubtask)
            }
            Button(String(format: Localized.string("todo.menu.priority", locale: locale), todo.priority.localizedTitle(locale: locale)), action: onCyclePriority)
            Menu(Localized.string("todo.menu.category", locale: locale)) {
                Button(Localized.string("todo.uncategorized", locale: locale)) { onSetTodoCategory(nil) }
                Divider()
                ForEach(todoCategories) { cat in
                    Button {
                        onSetTodoCategory(cat.id)
                    } label: {
                        let label = cat.localizedTitle(locale: locale)
                        Text(todo.categoryId == cat.id ? "✓ \(label)" : "\(label)")
                    }
                }
            }
            Menu(Localized.string("todo.menu.due_date", locale: locale)) {
                Button(Localized.string("todo.menu.due_long_term", locale: locale), action: onSetDueDayLongTerm)
                Button(Localized.string("day.today", locale: locale)) { onSetDueDayRelativeToToday(0) }
                Button(Localized.string("day.tomorrow", locale: locale)) { onSetDueDayRelativeToToday(1) }
                Divider()
                Button(Localized.string("todo.menu.due_prev", locale: locale)) { onShiftDueDay(-1) }
                Button(Localized.string("todo.menu.due_next", locale: locale)) { onShiftDueDay(1) }
            }
            if todo.parentId == nil {
                Button(Localized.string("todo.menu.indent", locale: locale), action: onIndent)
            } else {
                Button(Localized.string("todo.menu.outdent", locale: locale), action: onOutdent)
            }
            Divider()
            Button(Localized.string("todo.menu.delete", locale: locale), role: .destructive, action: onDelete)
            if hasChildren {
                Button(Localized.string("todo.menu.delete_tree", locale: locale), role: .destructive, action: onDeleteCascade)
            }
        }
        .onChange(of: todo.title) { newTitle in
            guard listFocus != .row(todo.id) else { return }
            draftTitle = newTitle
        }
        .onChange(of: todo.id) { _ in
            draftTitle = todo.title
        }
        .onChange(of: rowFocused) { isFocused in
            if !isFocused {
                nativeTodoEditorFocused = false
            }
        }
    }

    private var resolvedTodoCategory: TodoCategoryDefinition? {
        guard let cid = todo.categoryId else { return nil }
        return todoCategories.first { $0.id == cid }
    }

    private var categoryChipTitle: String {
        guard let cat = resolvedTodoCategory else {
            return Localized.string("todo.uncategorized", locale: locale)
        }
        return cat.localizedTitle(locale: locale)
    }

    /// 右侧分类胶囊：按面板材质单独配色（全屏玻璃上与 `prefersLightContent` 路径下的次要灰字区分）。
    private var todoCategoryChipTextColor: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.secondary.opacity(0.94)
        case .glassCard:
            return Color.white.opacity(0.98)
        case .disguiseGlass:
            return Color.white.opacity(0.95)
        }
    }

    /// 全屏玻璃材质上会冲淡浅色字，加极弱阴影抬对比。
    private var todoCategoryChipTitleShadowColor: Color? {
        switch panelChrome {
        case .popoverCard:
            return nil
        case .glassCard:
            return Color.black.opacity(0.45)
        case .disguiseGlass:
            return Color.black.opacity(0.40)
        }
    }

    private var todoCategoryChipChevronColor: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.secondary.opacity(0.50)
        case .glassCard:
            return Color.white.opacity(0.72)
        case .disguiseGlass:
            return Color.white.opacity(0.66)
        }
    }

    private var todoCategoryChipFill: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.primary.opacity(0.065)
        case .glassCard:
            return Color.white.opacity(0.22)
        case .disguiseGlass:
            return Color.white.opacity(0.15)
        }
    }

    private var todoCategoryChipStrokeColor: Color {
        switch panelChrome {
        case .popoverCard:
            return Color.primary.opacity(0.10)
        case .glassCard:
            return Color.white.opacity(0.34)
        case .disguiseGlass:
            return Color.white.opacity(0.26)
        }
    }

    private var todoCategoryMenuChip: some View {
        Button {
            categoryPopoverPresented = true
        } label: {
            HStack(spacing: 0) {
                Text(categoryChipTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(todoCategoryChipTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .shadow(
                        color: todoCategoryChipTitleShadowColor ?? .clear,
                        radius: todoCategoryChipTitleShadowColor == nil ? 0 : 0.65,
                        x: 0,
                        y: todoCategoryChipTitleShadowColor == nil ? 0 : 0.85
                    )
                Image(systemName: "chevron.down")
                    .font(.system(size: 5.5, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(todoCategoryChipChevronColor)
                    .padding(.leading, 6)
                    .shadow(
                        color: todoCategoryChipTitleShadowColor ?? .clear,
                        radius: todoCategoryChipTitleShadowColor == nil ? 0 : 0.55,
                        x: 0,
                        y: todoCategoryChipTitleShadowColor == nil ? 0 : 0.75
                    )
            }
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .padding(.vertical, 3)
            .background(todoCategoryChipFill, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(todoCategoryChipStrokeColor, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $categoryPopoverPresented) {
            todoCategoryPopoverContent
        }
        .fixedSize(horizontal: true, vertical: true)
        .help(Localized.string("todo.category.help", locale: locale))
    }

    /// Popover 列表（替代 `Menu`，避免 macOS 吞噬自定义胶囊样式）。
    private var todoCategoryPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            todoCategoryPopoverRow(title: Localized.string("todo.uncategorized", locale: locale), selected: todo.categoryId == nil) {
                onSetTodoCategory(nil)
                categoryPopoverPresented = false
            }
            ForEach(todoCategories) { cat in
                Divider()
                todoCategoryPopoverRow(title: cat.localizedTitle(locale: locale), selected: todo.categoryId == cat.id) {
                    onSetTodoCategory(cat.id)
                    categoryPopoverPresented = false
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(minWidth: 176)
    }

    private func todoCategoryPopoverRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 16)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var gripTint: Color {
        if softGlassContrast && prefersLightContent {
            return Color.white.opacity(0.34)
        }
        return prefersLightContent ? Color.white : Color.secondary
    }

    private var showsEmptyTitlePlaceholder: Bool {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rowFocused
            && !nativeTodoEditorFocused
    }

    private var promptTint: Color {
        if softGlassContrast && prefersLightContent {
            return Color.white.opacity(0.32)
        }
        return prefersLightContent ? Color.white.opacity(0.42) : Color.secondary.opacity(0.75)
    }

    private var displayTitle: String {
        todo.title.isEmpty ? " " : todo.title
    }
}

private struct TabKeyPressModifier: ViewModifier {
    let onPress: (Bool) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress(.tab) {
                onPress(currentShiftPressed())
                return .handled
            }
        } else {
            content
        }
    }
}

private struct BackspaceKeyPressModifier: ViewModifier {
    let onPress: () -> Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onKeyPress(.delete) {
                onPress() ? .handled : .ignored
            }
        } else {
            content
        }
    }
}

private extension View {
    func onTabKeyPress(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(TabKeyPressModifier(onPress: action))
    }

    func onBackspaceKeyPress(_ action: @escaping () -> Bool) -> some View {
        modifier(BackspaceKeyPressModifier(onPress: action))
    }
}

private func currentShiftPressed() -> Bool {
#if !targetEnvironment(macCatalyst)
    NSEvent.modifierFlags.contains(.shift)
#else
    false
#endif
}

struct AddTodoField: View {
    @Binding var pendingParentId: UUID?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    /// `nil` 表示添加一级；非 `nil` 表示下一步添加为该父级的子待办。
    var prefersLightChrome: Bool = false
    /// `(标题, 父级 id)`；成功时调用方应清空 `pendingParentId`。
    let onSubmit: (String, UUID?) -> Bool

    @Environment(\.locale) private var locale

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var placeholder: String {
        pendingParentId == nil
            ? Localized.string("todo.add_root", locale: locale)
            : Localized.string("todo.add_child", locale: locale)
    }

    private var chromeForeground: Color {
        prefersLightChrome ? Color.white : Color.primary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(chromeForeground)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
                .focused($fieldFocused)
                .onSubmit(commit)
            if pendingParentId != nil {
                Button(Localized.string("todo.cancel_child", locale: locale)) {
                    pendingParentId = nil
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(prefersLightChrome ? Color.white.opacity(0.55) : Color.secondary)
            }
            Button(Localized.string("todo.add_button", locale: locale), action: commit)
                .buttonStyle(.borderless)
                .font(.callout)
                .foregroundStyle(trimmedDraft.isEmpty ? .secondary : Color.accentColor)
                .disabled(trimmedDraft.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            prefersLightChrome ? Color.white.opacity(0.10) : Color(NSColor.quaternaryLabelColor).opacity(0.18),
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    private func commit() {
        let title = trimmedDraft
        guard !title.isEmpty else { return }
        let pid = pendingParentId
        guard onSubmit(title, pid) else { return }
        draft = ""
        pendingParentId = nil
        fieldFocused = false
    }
}

struct UsageBarsView: View {
    let usageItems: [UsageItem]
    let totalMinutes: Int
    let dark: Bool
    /// 伪装侧边栏：柔和蓝色进度条与压低对比度的标签。
    var glassSidebarStyle: Bool = false

    @Environment(\.locale) private var locale

    /// 横向条形图：耗时长的排在前面。
    private var sortedUsageItems: [UsageItem] {
        usageItems.sorted { lhs, rhs in
            if lhs.minutes != rhs.minutes {
                return lhs.minutes > rhs.minutes
            }
            return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
    }

    private var disguiseBarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.40, green: 0.56, blue: 0.86).opacity(0.48),
                Color(red: 0.52, green: 0.70, blue: 0.98).opacity(0.62)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(sortedUsageItems) { item in
                HStack(spacing: 12) {
#if !targetEnvironment(macCatalyst)
                    usageTrackedAppIcon(for: item)
#else
                    Image(systemName: item.symbolName)
                        .font(.headline)
                        .foregroundStyle(glassSidebarStyle && dark ? Color.white.opacity(0.88) : Color.white)
                        .frame(width: 30, height: 30)
                        .background(
                            glassSidebarStyle && dark ? item.color.opacity(0.72) : item.color,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
#endif

                    Text(item.appName)
                        .font(.callout)
                        .foregroundStyle(glassSidebarStyle && dark ? Color.white.opacity(0.76) : Color.primary)
                        .frame(width: 76, alignment: .leading)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(barTrackFill)
                            Capsule()
                                .fill(barForegroundFill(for: item))
                                .frame(width: proxy.size.width * CGFloat(item.minutes) / CGFloat(totalMinutes))
                        }
                    }
                    .frame(height: 10)

                    Text(String(format: Localized.string("format.minutes_suffix", locale: locale), item.minutes))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(glassSidebarStyle && dark ? Color.white.opacity(0.46) : Color.primary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }

#if !targetEnvironment(macCatalyst)
    @ViewBuilder
    private func usageTrackedAppIcon(for item: UsageItem) -> some View {
        let corner: CGFloat = 8
        if let img = AppUsageAuditor.resolvedWorkspaceIcon(for: item) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(iconOutlineOpacity, lineWidth: 1)
                }
        } else {
            Image(systemName: item.symbolName)
                .font(.headline)
                .foregroundStyle(glassSidebarStyle && dark ? Color.white.opacity(0.88) : Color.white)
                .frame(width: 30, height: 30)
                .background(
                    glassSidebarStyle && dark ? item.color.opacity(0.72) : item.color,
                    in: RoundedRectangle(cornerRadius: corner)
                )
        }
    }

    private var iconOutlineOpacity: Color {
        if glassSidebarStyle && dark {
            return Color.white.opacity(0.14)
        }
        return dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
#endif

    private var barTrackFill: Color {
        if glassSidebarStyle && dark {
            return Color.white.opacity(0.065)
        }
        return dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private func barForegroundFill(for item: UsageItem) -> some ShapeStyle {
        if glassSidebarStyle && dark {
            return AnyShapeStyle(disguiseBarGradient)
        }
        return AnyShapeStyle(item.color)
    }
}

#if os(macOS) && !targetEnvironment(macCatalyst)

/// 跨 SwiftUI 更新周期定位并聚焦某一行的 AppKit 编辑器（回车新建下一行后需要）。
fileprivate final class TodoChecklistFieldBridge {
    static let shared = TodoChecklistFieldBridge()
    private var fields: [UUID: WeakField] = [:]

    private struct WeakField {
        weak var view: TodoChecklistLayoutTextView?
    }

    /// 将 `NSTextView` 滚入外层 AppKit 滚动视图可视区（SwiftUI `ScrollView` 底层为 `NSScrollView`）。
    private func scrollFieldIntoVisibleArea(_ tv: NSTextView) {
        tv.layoutSubtreeIfNeeded()
        tv.superview?.layoutSubtreeIfNeeded()
        guard let scroll = tv.enclosingScrollView else { return }
        let clip = scroll.contentView
        let rect = tv.convert(tv.bounds, to: clip)
        let padded = rect.insetBy(dx: -12, dy: -40)
        clip.scrollToVisible(padded)
    }

    func register(rowId: UUID, view: TodoChecklistLayoutTextView) {
        fields[rowId] = WeakField(view: view)
    }

    func unregister(rowId: UUID, view: TodoChecklistLayoutTextView) {
        if fields[rowId]?.view === view {
            fields.removeValue(forKey: rowId)
        }
    }

    func focus(rowId: UUID, placeCaretAtEnd: Bool = true, caretUTF16: Int? = nil, attempt: Int = 0) {
        guard let tv = fields[rowId]?.view, tv.window != nil else {
            // 新建行后 NSTextView 可能晚一拍才挂载；稍后重试，避免静默失败导致无法接续输入。
            guard attempt < 16 else { return }
            DispatchQueue.main.async {
                self.focus(rowId: rowId, placeCaretAtEnd: placeCaretAtEnd, caretUTF16: caretUTF16, attempt: attempt + 1)
            }
            return
        }
        tv.window?.makeKeyAndOrderFront(nil)
        let becameFirst = tv.window?.makeFirstResponder(tv) == true
        let len = (tv.string as NSString).length
        if let c = caretUTF16 {
            tv.setSelectedRange(NSRange(location: min(max(0, c), len), length: 0))
        } else if placeCaretAtEnd {
            tv.setSelectedRange(NSRange(location: len, length: 0))
        } else {
            tv.setSelectedRange(NSRange(location: 0, length: 0))
        }
        scrollFieldIntoVisibleArea(tv)
        let frOK = becameFirst && tv.window?.firstResponder === tv
        if !frOK {
            guard attempt < 16 else { return }
            DispatchQueue.main.async {
                self.focus(rowId: rowId, placeCaretAtEnd: placeCaretAtEnd, caretUTF16: caretUTF16, attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.fields[rowId]?.view === tv else { return }
            self.scrollFieldIntoVisibleArea(tv)
        }
    }

    /// 行中回车后本条在短时间内仍是第一响应者：`updateNSView` 在 editing 时不会用 Binding 覆盖 string，需手动对齐。
    func syncPlainWhileFirstResponder(rowId: UUID, plain: String) {
        guard let tv = fields[rowId]?.view else { return }
        guard tv.window?.firstResponder === tv else { return }
        let normalized = plain
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard tv.string != normalized else { return }
        tv.string = normalized
        tv.syncTypingAppearance()
        tv.invalidateIntrinsicContentSize()
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: tv)
    }
}

private protocol TodoChecklistFieldKeyDelegate: AnyObject {
    func editorInteractionBegan()
    func submitReturn(collapsedPlain: String, caretUTF16: Int)
    func cancelEditing()
    func tab(_ shiftDown: Bool)
    func backspaceWhenEmpty()
    /// - Returns: 是否已切换到上一行（未切换则交由系统默认处理光标/按键）。
    func focusPreviousTodoRow() -> Bool
    /// - Returns: 是否已切换到下一行。
    func focusNextTodoRow() -> Bool
    /// 行首退格：当前行非空时并入前方同级子任务、父任务或上一条一级。
    func mergeTodoBackward(fullPlain: String) -> Bool
}

/// 备忘录 checklist 式多行输入：自动换行、系统插入点与 ⌘C/⌘V/⌘Z。
private final class TodoChecklistLayoutTextView: NSTextView {
    weak var keyDelegate: TodoChecklistFieldKeyDelegate?
    var showsStrikethrough = false
    /// 全屏休息界面等：`ScrollView` 会先吃掉方向键与部分编辑快捷键，需在本地监视器里拦截并交给 `interpretKeyEvents`。
    var useLocalKeyMonitor = false
    var titleColor: NSColor = .labelColor {
        didSet {
            if window?.firstResponder === self {
                syncTypingAppearance()
            } else {
                applyDisplayedString()
            }
        }
    }

    private var editKeyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    deinit {
        removeEditKeyMonitor()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleEditCommand(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 菜单栏弹窗：`⌘` 仍走监视器兜底；其它键走常规 `keyDown`。全屏遮罩：`useLocalKeyMonitor` 时在监视器内完整路由。
    private func installEditKeyMonitor() {
        guard editKeyMonitor == nil else { return }
        editKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.firstResponder === self, self.keyDelegate != nil else { return event }
            if self.processTodoFieldKeyDown(event) {
                return nil
            }
            if self.useLocalKeyMonitor {
                self.interpretKeyEvents([event])
                return nil
            }
            return event
        }
    }

    private func removeEditKeyMonitor() {
        if let editKeyMonitor {
            NSEvent.removeMonitor(editKeyMonitor)
            self.editKeyMonitor = nil
        }
    }

    @discardableResult
    private func handleEditCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
            return false
        }
        switch key {
        case "c":
            copy(self)
            return true
        case "v":
            paste(self)
            return true
        case "x":
            cut(self)
            return true
        case "a":
            selectAll(self)
            return true
        case "z":
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            notifyTextChanged()
            return true
        default:
            return false
        }
    }

    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0 else { return }
        let fragment = (string as NSString).substring(with: range)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fragment, forType: .string)
    }

    override func paste(_ sender: Any?) {
        guard let incoming = NSPasteboard.general.string(forType: .string) else { return }
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        replaceSelection(with: incoming)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        replaceSelection(with: "")
    }

    /// 在**当前选区/光标**处替换；切勿 `self.string = …`（会把插入点打回开头）。
    private func replaceSelection(with replacement: String) {
        let normalized = replacement
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: normalized) else { return }
        textStorage?.replaceCharacters(in: range, with: normalized)
        let newCaret = range.location + (normalized as NSString).length
        setSelectedRange(NSRange(location: newCaret, length: 0))
        notifyTextChanged()
    }

    private func notifyTextChanged() {
        invalidateIntrinsicContentSize()
        NotificationCenter.default.post(name: NSText.didChangeNotification, object: self)
    }

    override func mouseDown(with event: NSEvent) {
        keyDelegate?.editorInteractionBegan()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            keyDelegate?.editorInteractionBegan()
            installEditKeyMonitor()
            syncTypingAppearance()
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        removeEditKeyMonitor()
        return super.resignFirstResponder()
    }

    func applyDisplayedString(from plain: String? = nil) {
        guard window?.firstResponder !== self else { return }
        let raw = plain ?? string
        let attr = NSMutableAttributedString(
            string: raw,
            attributes: [
                .font: font ?? NSFont.preferredFont(forTextStyle: .body),
                .foregroundColor: titleColor
            ]
        )
        if showsStrikethrough, attr.length > 0 {
            attr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: attr.length))
        }
        let sel = selectedRange()
        textStorage?.setAttributedString(attr)
        let safeLocation = min(sel.location, max(attr.length, 0))
        let safeLength = min(sel.length, max(attr.length - safeLocation, 0))
        setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    }

    /// 编辑态统一字体与前景色，并与列表展示一致；去掉删除线（已完成项失焦态才显示）。
    func syncTypingAppearance() {
        let f = font ?? NSFont.preferredFont(forTextStyle: .body)
        typingAttributes = [
            .font: f,
            .foregroundColor: titleColor
        ]
        guard let ts = textStorage else { return }
        let len = ts.length
        guard len > 0 else { return }
        let full = NSRange(location: 0, length: len)
        ts.beginEditing()
        ts.removeAttribute(.strikethroughStyle, range: full)
        ts.addAttribute(.foregroundColor, value: titleColor, range: full)
        ts.addAttribute(.font, value: f, range: full)
        ts.endEditing()
    }

    override func layout() {
        super.layout()
        syncContainerWidthToBounds()
        invalidateIntrinsicContentSize()
    }

    private func syncContainerWidthToBounds() {
        guard let tc = textContainer else { return }
        let horizontalInset = textContainerInset.width * 2 + tc.lineFragmentPadding * 2
        let w = max(bounds.width - horizontalInset, 32)
        tc.containerSize = NSSize(width: w, height: CGFloat.greatestFiniteMagnitude)
    }

    private func fallbackOneLineHeight() -> CGFloat {
        guard let font else { return 22 }
        return ceil(font.ascender - font.descender + font.leading)
    }

    override var intrinsicContentSize: NSSize {
        syncContainerWidthToBounds()
        guard bounds.width > 4, let tc = textContainer, let lm = layoutManager else {
            return NSSize(width: NSView.noIntrinsicMetric, height: fallbackOneLineHeight())
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let body = max(ceil(used.height + textContainerInset.height * 2), fallbackOneLineHeight())
        return NSSize(width: NSView.noIntrinsicMetric, height: body)
    }

    /// - Returns: `true` 表示事件已处理完毕（含自定义逻辑），无需再走默认 `keyDown` / `interpretKeyEvents`。
    private func processTodoFieldKeyDown(_ event: NSEvent) -> Bool {
        guard let keyDelegate else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.command) {
            if handleEditCommand(event) || performKeyEquivalent(with: event) {
                return true
            }
            return false
        }
        if mods.contains(.control) || mods.contains(.option) {
            return false
        }
        let code = event.keyCode
        let sel = selectedRange()
        let nsLen = (string as NSString).length

        if string.isEmpty, code == 51 || code == 117 {
            keyDelegate.backspaceWhenEmpty()
            return true
        }

        if !hasMarkedText() {
            let collapsedAtStart = sel.length == 0 && sel.location == 0
            let collapsedAtEnd = sel.length == 0 && sel.location == nsLen

            if code == 126 || code == 123 {
                if collapsedAtStart, keyDelegate.focusPreviousTodoRow() {
                    return true
                }
            } else if code == 125 || code == 124 {
                if collapsedAtEnd, keyDelegate.focusNextTodoRow() {
                    return true
                }
            } else if code == 117 {
                if collapsedAtEnd, keyDelegate.focusNextTodoRow() {
                    return true
                }
            } else if code == 51 {
                if collapsedAtStart {
                    if !string.isEmpty, keyDelegate.mergeTodoBackward(fullPlain: string) {
                        return true
                    }
                }
            }
        }

        if code == 36 || code == 76 {
            if mods.contains(.shift) {
                insertNewline(nil)
                return true
            }
            if hasMarkedText() {
                return false
            }
            let r = selectedRange()
            let nsFull = string as NSString
            let collapsed = nsFull.replacingCharacters(in: r, with: "") as String
            let clen = (collapsed as NSString).length
            var caret = r.location
            if caret > clen { caret = clen }
            keyDelegate.submitReturn(collapsedPlain: collapsed, caretUTF16: caret)
            return true
        }
        if code == 48 {
            keyDelegate.tab(mods.contains(.shift))
            return true
        }
        if code == 53 {
            keyDelegate.cancelEditing()
            return true
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        guard keyDelegate != nil else {
            super.keyDown(with: event)
            return
        }
        if processTodoFieldKeyDown(event) {
            return
        }
        super.keyDown(with: event)
    }
}

private struct TodoChecklistField: NSViewRepresentable {
    let rowId: UUID
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var showsStrikethrough: Bool
    var isFocused: Bool
    var onBeginEditing: () -> Void
    var onReturn: (String, Int) -> Void
    var onExitCommand: () -> Void
    var onTab: (Bool) -> Void
    var onBackspaceEmpty: () -> Void
    var onFocusPreviousRow: () -> Bool
    var onFocusNextRow: () -> Bool
    var onMergeBackward: (String) -> Bool
    var useLocalKeyMonitor: Bool = false
    var onNativeFocusChanged: ((Bool) -> Void)?

    final class Coordinator: NSObject, NSTextViewDelegate, TodoChecklistFieldKeyDelegate {
        var rowId: UUID
        var text: Binding<String>
        var onBeginEditing: () -> Void
        var onReturn: (String, Int) -> Void
        var onExitCommand: () -> Void
        var onTab: (Bool) -> Void
        var onBackspaceEmpty: () -> Void
        var onFocusPreviousRow: () -> Bool
        var onFocusNextRow: () -> Bool
        var onMergeBackward: (String) -> Bool
        var onNativeFocusChanged: ((Bool) -> Void)?
        weak var textView: TodoChecklistLayoutTextView?

        init(
            rowId: UUID,
            text: Binding<String>,
            onBeginEditing: @escaping () -> Void,
            onReturn: @escaping (String, Int) -> Void,
            onExitCommand: @escaping () -> Void,
            onTab: @escaping (Bool) -> Void,
            onBackspaceEmpty: @escaping () -> Void,
            onFocusPreviousRow: @escaping () -> Bool,
            onFocusNextRow: @escaping () -> Bool,
            onMergeBackward: @escaping (String) -> Bool,
            onNativeFocusChanged: ((Bool) -> Void)?
        ) {
            self.rowId = rowId
            self.text = text
            self.onBeginEditing = onBeginEditing
            self.onReturn = onReturn
            self.onExitCommand = onExitCommand
            self.onTab = onTab
            self.onBackspaceEmpty = onBackspaceEmpty
            self.onFocusPreviousRow = onFocusPreviousRow
            self.onFocusNextRow = onFocusNextRow
            self.onMergeBackward = onMergeBackward
            self.onNativeFocusChanged = onNativeFocusChanged
        }

        func textDidBeginEditing(_ notification: Notification) {
            onBeginEditing()
            onNativeFocusChanged?(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            onNativeFocusChanged?(false)
        }

        func editorInteractionBegan() {
            onBeginEditing()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            text.wrappedValue = tv.string
            tv.invalidateIntrinsicContentSize()
        }

        func submitReturn(collapsedPlain: String, caretUTF16: Int) {
            onReturn(collapsedPlain, caretUTF16)
        }

        func cancelEditing() { onExitCommand() }
        func tab(_ shiftDown: Bool) { onTab(shiftDown) }
        func backspaceWhenEmpty() { onBackspaceEmpty() }
        func focusPreviousTodoRow() -> Bool { onFocusPreviousRow() }
        func focusNextTodoRow() -> Bool { onFocusNextRow() }
        func mergeTodoBackward(fullPlain: String) -> Bool { onMergeBackward(fullPlain) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            rowId: rowId,
            text: $text,
            onBeginEditing: onBeginEditing,
            onReturn: onReturn,
            onExitCommand: onExitCommand,
            onTab: onTab,
            onBackspaceEmpty: onBackspaceEmpty,
            onFocusPreviousRow: onFocusPreviousRow,
            onFocusNextRow: onFocusNextRow,
            onMergeBackward: onMergeBackward,
            onNativeFocusChanged: onNativeFocusChanged
        )
    }

    func makeNSView(context: Context) -> TodoChecklistLayoutTextView {
        let tv = TodoChecklistLayoutTextView()
        tv.useLocalKeyMonitor = useLocalKeyMonitor
        tv.keyDelegate = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.drawsBackground = false
        tv.importsGraphics = false
        tv.font = font
        tv.titleColor = textColor
        tv.showsStrikethrough = showsStrikethrough
        tv.insertionPointColor = NSColor.controlAccentColor
        tv.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.selectedTextColor
        ]
        tv.focusRingType = .default
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 2
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.string = text
        tv.applyDisplayedString(from: text)
        context.coordinator.textView = tv
        TodoChecklistFieldBridge.shared.register(rowId: rowId, view: tv)
        return tv
    }

    static func dismantleNSView(_ nsView: TodoChecklistLayoutTextView, coordinator: Coordinator) {
        TodoChecklistFieldBridge.shared.unregister(rowId: coordinator.rowId, view: nsView)
    }

    func updateNSView(_ textView: TodoChecklistLayoutTextView, context: Context) {
        let c = context.coordinator
        c.text = $text
        c.onBeginEditing = onBeginEditing
        c.onReturn = onReturn
        c.onExitCommand = onExitCommand
        c.onTab = onTab
        c.onBackspaceEmpty = onBackspaceEmpty
        c.onFocusPreviousRow = onFocusPreviousRow
        c.onFocusNextRow = onFocusNextRow
        c.onMergeBackward = onMergeBackward
        c.onNativeFocusChanged = onNativeFocusChanged

        textView.useLocalKeyMonitor = useLocalKeyMonitor
        textView.font = font
        textView.titleColor = textColor

        let editing = textView.window?.firstResponder === textView
        textView.showsStrikethrough = showsStrikethrough && !editing

        if editing {
            textView.syncTypingAppearance()
        } else if textView.string != text {
            textView.string = text
            textView.applyDisplayedString(from: text)
        } else {
            textView.applyDisplayedString(from: textView.string)
        }

        textView.needsLayout = true
        textView.invalidateIntrinsicContentSize()

        if isFocused, !editing {
            DispatchQueue.main.async {
                TodoChecklistFieldBridge.shared.focus(rowId: rowId, placeCaretAtEnd: false)
            }
        }
    }
}

#endif

struct ProgressRingView: View {
    let progress: Double
    let timeText: String
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(
                    AngularGradient(colors: [.blue, .cyan, .blue], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(timeText)
                .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: progress)
    }
}
