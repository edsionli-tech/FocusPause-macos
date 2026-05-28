import Combine
import Foundation
#if !targetEnvironment(macCatalyst)
import AppKit
import UniformTypeIdentifiers
#endif

extension Notification.Name {
    static let focusPauseForceCloseBreakOverlay = Notification.Name("FocusPauseForceCloseBreakOverlay")
}

@MainActor
final class FocusPauseStore: ObservableObject {
    @Published var status: FocusStatus = .focusing
    @Published var focusSecondsRemaining = 45 * 60
    @Published var breakSecondsRemaining = 10 * 60
    @Published var settings = FocusPauseSettings()
    @Published var todos: [TodoItem] = [
        TodoItem(title: "Ship FocusPause design review", isDone: false, priority: .high),
        TodoItem(title: "Triage user feedback", isDone: false, priority: .normal),
        TodoItem(title: "Implement statistics charts", isDone: false, priority: .normal),
        TodoItem(title: "Read Deep Work chapter 3", isDone: false, priority: .low)
    ]
    @Published var usageItems: [UsageItem] = []
    @Published var usageScope: UsageScope = .currentFocus
    @Published var restTipIndex = 0
    @Published var panicMessage: String?
    @Published var popoverMessage: String?
    @Published var showReturnConfirmation = false
    @Published var settingsMessage: String?
    /// 伪装休息侧边栏是否收起（仅本次休息有效，不写入偏好）。
    @Published var breakOverlaySidebarCollapsed = false
    /// 「整理桌面」：暂时收起全屏休息窗口以便操作桌面；休息时仍为 true，约 10 秒后复位。
    @Published private(set) var breakDesktopRevealActive = false

    let restTipCount = 4

    private var timer: AnyCancellable?
    private let storage = LocalStorageService()
    private let auditor = AppUsageAuditor()
    private var statusBeforeDoNotDisturb: FocusStatus = .idle
    private var breakDesktopRevealRestoreTask: DispatchWorkItem?
    /// 上一秒自定义勿扰是否处于「冻结倒计时」状态（用于结束时收起顶部 Toast）。
    private var lastCustomDNDTickFrozen = false

    enum DNDFeedbackChannel {
        case silent
        case settingsAlert
        case popoverToast
    }

    init() {
        load()
        status = .focusing
        focusSecondsRemaining = settings.minWorkMinutes * 60
        breakSecondsRemaining = settings.breakMinutes * 60
        auditor.resetCurrentCycle()
        refreshUsageAudit()
        reconcileDoNotDisturbAfterLoad()
        startTicker()
    }

    deinit {
        breakDesktopRevealRestoreTask?.cancel()
    }

    var currentTimeText: String {
        formatDuration(status == .resting ? breakSecondsRemaining : focusSecondsRemaining)
    }

    var dndStatusTitle: String {
        let loc = settings.resolvedLocale
        if settings.dndPeriod == .custom {
            switch Self.evaluateCustomDND(settings: settings, now: Date()) {
            case .activeUntil(let end):
                return String(format: Localized.string("dnd.status.custom_active_until", locale: loc), Self.formatShortTime(end, locale: loc))
            case .scheduled(let start, let end):
                return String(
                    format: Localized.string("dnd.status.custom_scheduled", locale: loc),
                    Self.formatShortTime(start, locale: loc),
                    Self.formatShortTime(end, locale: loc)
                )
            default:
                return DoNotDisturbPeriod.custom.localizedStatusTitle(locale: loc)
            }
        }
        return settings.dndPeriod.localizedStatusTitle(locale: loc)
    }

    /// 已选择勿扰模式（含「预约中的自定义时段」）。
    var isDoNotDisturbModeSelected: Bool {
        settings.dndPeriod != .off
    }

    /// 勿扰是否正在冻结专注/休息计时（不含仅预约未到时段的情况）。
    var isDoNotDisturbPausingTimer: Bool {
        settings.dndPeriod != .off && status == .paused
    }

    /// 菜单栏弹窗专用：倒计时上方的勿扰徽章、勿扰菜单是否高亮。
    /// 仅在「正在勿扰冻结计时」或「自定义模式且仍有即将到来的一段」时为 true。
    var isDoNotDisturbPopoverProminent: Bool {
        if isDoNotDisturbPausingTimer { return true }
        if settings.dndPeriod == .custom {
            switch Self.evaluateCustomDND(settings: settings, now: Date()) {
            case .scheduled:
                return true
            default:
                return false
            }
        }
        return false
    }

    var isDoNotDisturbEnabled: Bool {
        isDoNotDisturbModeSelected
    }

    var timerRuleSummary: String {
        String(
            format: Localized.string("format.timer_rule", locale: settings.resolvedLocale),
            settings.minWorkMinutes,
            settings.breakMinutes
        )
    }

    var completedTodoCount: Int {
        todos.filter(\.isDone).count
    }

    /// 待办面板当前查看的自然日（本地零点）。`settings.todoListSelectedDay == nil` 时等同「今天」。
    var todoListSelectedNormalizedDay: Date {
        TodoDueDayFormatting.normalize(settings.todoListSelectedDay ?? Date())
    }

    func setTodoListSelectedDay(_ day: Date) {
        let today = TodoDueDayFormatting.normalize(Date())
        let n = TodoDueDayFormatting.normalize(day)
        var s = settings
        if n == today {
            s.todoListSelectedDay = nil
        } else {
            s.todoListSelectedDay = n
        }
        settings = s
        save()
    }

    /// 菜单栏弹出面板打开时，或每次开始进入休息时复位：待办分段默认落在「今天」。不在休息界面生命周期内重复调用，以免打断用户在遮罩内的日期切换。
    func resetTodoListDayToTodayOnPanelOpen() {
        guard settings.todoListSelectedDay != nil else { return }
        var s = settings
        s.todoListSelectedDay = nil
        settings = s
        save()
    }

    /// 某一列表日内要展示的待办（含：归属日匹配的根任务及其直属子项）。
    func todosForListDay(_ day: Date) -> [TodoItem] {
        let d0 = TodoDueDayFormatting.normalize(day)
        let ordered = todosOrderedForDisplay
        var out: [TodoItem] = []
        var takingChildren = false
        for t in ordered {
            if t.parentId == nil {
                takingChildren = TodoDueDayFormatting.normalize(t.dueDay) == d0
                if takingChildren {
                    out.append(t)
                }
            } else if takingChildren {
                out.append(t)
            }
        }
        return out
    }

    func completedCount(forListDay day: Date) -> Int {
        todosForListDay(day).filter(\.isDone).count
    }

    func totalCount(forListDay day: Date) -> Int {
        todosForListDay(day).count
    }

    /// 展示顺序中某一行的上一行 id（用于删除空行后回落焦点）。
    func orderedPredecessorId(of id: TodoItem.ID, listDay: Date) -> TodoItem.ID? {
        let ordered = todosForListDay(listDay)
        guard let idx = ordered.firstIndex(where: { $0.id == id }), idx > 0 else { return nil }
        return ordered[idx - 1].id
    }

    /// 在某条展示项之后插入同级新待办（跟在「该项及其子项」之后）；不写提醒事项，仅本地。
    @discardableResult
    func addTodoAfter(_ afterId: TodoItem.ID, title: String = "") -> TodoItem.ID? {
        guard let refIdx = todos.firstIndex(where: { $0.id == afterId }) else { return nil }
        let parentId = todos[refIdx].parentId
        var insertAt = refIdx + 1
        if todos[refIdx].parentId == nil {
            while insertAt < todos.count, todos[insertAt].parentId == todos[refIdx].id {
                insertAt += 1
            }
        }
        let refDue = todos[refIdx].dueDay
        let item = TodoItem(
            title: title,
            isDone: false,
            priority: .normal,
            parentId: parentId,
            reminderCalendarItemIdentifier: nil,
            dueDay: refDue
        )
        todos.insert(item, at: insertAt)
        save()
        return item.id
    }

    /// 紧贴在指定同级条目**之前**插入一条待办（与该项同一 parent、同一归属日）。
    @discardableResult
    func insertTodoBefore(_ siblingId: TodoItem.ID, title: String = "") -> TodoItem.ID? {
        guard let idx = todos.firstIndex(where: { $0.id == siblingId }) else { return nil }
        let ref = todos[idx]
        let item = TodoItem(
            title: title,
            isDone: false,
            priority: .normal,
            parentId: ref.parentId,
            reminderCalendarItemIdentifier: nil,
            dueDay: ref.dueDay
        )
        todos.insert(item, at: idx)
        save()
        return item.id
    }

    /// 为当前列表日插入一条空白一级待办（用于点击空白直接进入行内编辑）；不写提醒事项。
    @discardableResult
    func addBlankRootTodoForSelectedListDay() -> TodoItem.ID? {
        let dueDay = todoListSelectedNormalizedDay
        let item = TodoItem(
            title: "",
            isDone: false,
            priority: .normal,
            parentId: nil,
            reminderCalendarItemIdentifier: nil,
            dueDay: dueDay
        )
        insertTodoInList(item)
        save()
        return item.id
    }

    /// 在某一级待办块末尾插入空白子待办（备忘录式「添加子项」）。
    @discardableResult
    func addBlankChildTodo(under parentId: UUID) -> TodoItem.ID? {
        guard let parent = todos.first(where: { $0.id == parentId }), parent.parentId == nil else { return nil }
        guard let pIdx = todos.firstIndex(where: { $0.id == parentId }) else { return nil }
        var insertAt = pIdx + 1
        while insertAt < todos.count, todos[insertAt].parentId == parentId {
            insertAt += 1
        }
        let item = TodoItem(
            title: "",
            isDone: false,
            priority: .normal,
            parentId: parentId,
            reminderCalendarItemIdentifier: nil,
            dueDay: parent.dueDay
        )
        todos.insert(item, at: insertAt)
        save()
        return item.id
    }

    /// 将「当前列表日」下的某一一级待办（及其子项整块）拖到另一一级之前；`anchorRootId == nil` 表示移到末尾。
    func moveTodoRootBlockBeforeAnchor(draggedItemId: UUID, anchorRootId: UUID?, listDay: Date) {
        let d0 = TodoDueDayFormatting.normalize(listDay)
        guard let dragRoot = canonicalRootId(forItemId: draggedItemId),
              let draggedTodo = todos.first(where: { $0.id == dragRoot }),
              TodoDueDayFormatting.normalize(draggedTodo.dueDay) == d0,
              let dragRange = contiguousBlockRange(forRootId: dragRoot)
        else { return }

        if let anchorRootId, anchorRootId == dragRoot { return }

        let block = Array(todos[dragRange])
        todos.removeSubrange(dragRange)

        let insertAt: Int
        if let anchorRoot = anchorRootId {
            guard let anchorTodo = todos.first(where: { $0.id == anchorRoot }),
                  TodoDueDayFormatting.normalize(anchorTodo.dueDay) == d0,
                  let anchorRange = contiguousBlockRange(forRootId: anchorRoot)
            else {
                todos.insert(contentsOf: block, at: todos.count)
                save()
                return
            }
            insertAt = anchorRange.lowerBound
        } else {
            insertAt = todos.count
        }

        todos.insert(contentsOf: block, at: min(insertAt, todos.count))
        save()
    }

    private func canonicalRootId(forItemId id: UUID) -> UUID? {
        guard let t = todos.first(where: { $0.id == id }) else { return nil }
        return t.parentId ?? t.id
    }

    /// `id` 须为一级待办；返回 `[root, …children]` 在 `todos` 中的连续区间。
    private func contiguousBlockRange(forRootId id: UUID) -> Range<Int>? {
        guard let start = todos.firstIndex(where: { $0.id == id }) else { return nil }
        var end = start + 1
        while end < todos.count, todos[end].parentId == id {
            end += 1
        }
        return start..<end
    }

    /// 一级在前、紧随其二级子项（顺序与 `todos` 中兄弟顺序一致）。
    var todosOrderedForDisplay: [TodoItem] {
        func children(of pid: UUID) -> [TodoItem] {
            todos.filter { $0.parentId == pid }
        }

        var roots: [TodoItem] = []
        var seen = Set<UUID>()
        for t in todos where t.parentId == nil {
            if !seen.contains(t.id) {
                roots.append(t)
                seen.insert(t.id)
            }
        }
        /// 先按归属日，其次按在 `todos` 中的物理顺序（便于拖拽调整同级排序）。
        roots.sort { a, b in
            let da = TodoDueDayFormatting.normalize(a.dueDay)
            let db = TodoDueDayFormatting.normalize(b.dueDay)
            if da != db { return da < db }
            let ia = todos.firstIndex(where: { $0.id == a.id }) ?? 0
            let ib = todos.firstIndex(where: { $0.id == b.id }) ?? 0
            return ia < ib
        }

        var out: [TodoItem] = []
        for r in roots {
            out.append(r)
            out.append(contentsOf: children(of: r.id))
        }

        let placedIds = Set(out.map(\.id))
        for t in todos where !placedIds.contains(t.id) {
            out.append(t)
        }
        return out
    }

    var pendingTodos: [TodoItem] {
        todos.filter { !$0.isDone }
    }

    var currentRestTip: String {
        let idx = restTipIndex % restTipCount
        return Localized.string("rest.tip.\(idx + 1)", locale: settings.resolvedLocale)
    }

    var breakProgress: Double {
        let total = max(settings.breakMinutes * 60, 1)
        return 1 - Double(breakSecondsRemaining) / Double(total)
    }

    var totalUsageMinutes: Int {
        max(usageItems.reduce(0) { $0 + $1.minutes }, 1)
    }

    func startFocus() {
        settings.dndPeriod = .off
        settings.dndUntil = nil
        enterFocusCycle(resetUsageCycle: true, forceCurrentFocusScope: true)
        save()
    }

    func pauseReminders() {
        setDoNotDisturb(.allDay, feedback: .silent)
    }

    func startBreakNow() {
        resetTodoListDayToTodayOnPanelOpen()
        refreshUsageAudit()
        status = .resting
        breakSecondsRemaining = settings.breakMinutes * 60
    }

    func skipBreak() {
        if breakSecondsRemaining <= 5 * 60 {
            returnToWork()
        } else {
            breakSecondsRemaining -= 5 * 60
        }
    }

    func snoozeBreak(minutes: Int) {
        status = .focusing
        focusSecondsRemaining = max(minutes, 1) * 60
        breakSecondsRemaining = settings.breakMinutes * 60
        cancelBreakDesktopRevealScheduling()
        requestBreakOverlayClose()
    }

    func extendBreak() {
        breakSecondsRemaining += 5 * 60
    }

    func returnToWork() {
        // 非勿扰模式下，结束休息后直接进入下一轮专注，不停留在 idle。
        enterFocusCycle(resetUsageCycle: true, forceCurrentFocusScope: false)
    }

    func returnToFocusFromOverlay() {
        guard status == .resting else { return }
        enterFocusCycle(resetUsageCycle: true, forceCurrentFocusScope: false)
    }

    func panicReturnToWork() {
        status = .paused
        panicMessage = Localized.string("message.break_paused_hint", locale: settings.resolvedLocale)
        cancelBreakDesktopRevealScheduling()
        requestBreakOverlayClose()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.panicMessage = nil
        }
    }

    @discardableResult
    func addTodo(_ title: String, parentId: UUID? = nil) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let pid = parentId {
            guard let parent = todos.first(where: { $0.id == pid }), parent.parentId == nil else {
                return false
            }
        }

        let dueDay: Date
        if let pid = parentId, let parent = todos.first(where: { $0.id == pid }) {
            dueDay = parent.dueDay
        } else {
            dueDay = todoListSelectedNormalizedDay
        }

        let item = TodoItem(
            title: trimmed,
            isDone: false,
            priority: .normal,
            parentId: parentId,
            reminderCalendarItemIdentifier: nil,
            dueDay: dueDay
        )
        insertTodoInList(item)
        save()
        return true
    }

    /// 一级插在末尾；二级紧贴父项及其已有子项之后。
    private func insertTodoInList(_ item: TodoItem) {
        guard let pid = item.parentId else {
            todos.append(item)
            return
        }
        guard let pIdx = todos.firstIndex(where: { $0.id == pid }) else {
            todos.append(item)
            return
        }
        var insertAt = pIdx + 1
        while insertAt < todos.count, todos[insertAt].parentId == pid {
            insertAt += 1
        }
        todos.insert(item, at: insertAt)
    }

    func toggleTodo(_ id: TodoItem.ID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].isDone.toggle()
        save()
    }

    func deleteTodo(_ id: TodoItem.ID) {
        let childIds = todos.filter { $0.parentId == id }.map(\.id)
        // 优化默认删除策略：删父任务时保留子任务并提升为一级，减少误删。
        if !childIds.isEmpty {
            for childId in childIds {
                if let childIndex = todos.firstIndex(where: { $0.id == childId }) {
                    todos[childIndex].parentId = nil
                }
            }
        }

        let remove = Set([id])
        todos.removeAll { remove.contains($0.id) }
        save()
    }

    /// 将直属子任务从某一一级父任务迁移到另一一级父任务下（用于合并父任务时保留子树）。
    func moveChildren(fromParentId oldParentId: TodoItem.ID, toParentId newParentId: TodoItem.ID) {
        guard oldParentId != newParentId else { return }
        guard let newParent = todos.first(where: { $0.id == newParentId && $0.parentId == nil }) else { return }

        let indices = todos.indices.filter { todos[$0].parentId == oldParentId }
        guard !indices.isEmpty else { return }

        let children = indices.map { todos[$0] }
        for i in indices.reversed() {
            todos.remove(at: i)
        }

        guard let pIdx = todos.firstIndex(where: { $0.id == newParentId }) else { return }
        var insertAt = pIdx + 1
        while insertAt < todos.count, todos[insertAt].parentId == newParentId {
            insertAt += 1
        }
        for var child in children {
            child.parentId = newParentId
            child.dueDay = newParent.dueDay
            todos.insert(child, at: insertAt)
            insertAt += 1
        }
        save()
    }

    /// 级联删除：删除父任务及其直属子任务。
    func deleteTodoIncludingChildren(_ id: TodoItem.ID) {
        let childIds = todos.filter { $0.parentId == id }.map(\.id)
        let remove = Set([id] + childIds)
        todos.removeAll { remove.contains($0.id) }
        save()
    }

    func cyclePriority(_ id: TodoItem.ID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let order: [TodoPriority] = [.normal, .high, .low]
        let currentIndex = order.firstIndex(of: todos[index].priority) ?? 0
        todos[index].priority = order[(currentIndex + 1) % order.count]
        save()
    }

    /// 一级待办缩进为二级：挂到它前一个一级待办下面。
    @discardableResult
    func indentTodo(_ id: TodoItem.ID) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return false }
        guard todos[index].parentId == nil else { return false }

        var parentIndex: Int?
        var cursor = index - 1
        while cursor >= 0 {
            if todos[cursor].parentId == nil {
                parentIndex = cursor
                break
            }
            cursor -= 1
        }
        guard let pIdx = parentIndex else { return false }

        let parentId = todos[pIdx].id
        var moved = todos[index]
        moved.parentId = parentId
        moved.dueDay = todos[pIdx].dueDay
        todos.remove(at: index)

        guard let parentCurrentIndex = todos.firstIndex(where: { $0.id == parentId }) else {
            todos.append(moved)
            save()
            return true
        }
        var insertAt = parentCurrentIndex + 1
        while insertAt < todos.count, todos[insertAt].parentId == parentId {
            insertAt += 1
        }
        todos.insert(moved, at: insertAt)
        save()
        return true
    }

    /// 二级待办提升为一级：移到其父项和同级子项之后。
    @discardableResult
    func outdentTodo(_ id: TodoItem.ID) -> Bool {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return false }
        guard let parentId = todos[index].parentId else { return false }

        var moved = todos[index]
        moved.parentId = nil
        todos.remove(at: index)

        guard let parentIndex = todos.firstIndex(where: { $0.id == parentId }) else {
            todos.append(moved)
            save()
            return true
        }
        var insertAt = parentIndex + 1
        while insertAt < todos.count, todos[insertAt].parentId == parentId {
            insertAt += 1
        }
        todos.insert(moved, at: insertAt)
        save()
        return true
    }

    func renameTodo(id: TodoItem.ID, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].title = trimmed
        save()
    }

    func setTodoDueDayLongTerm(id: TodoItem.ID) {
        applyTodoDueDay(id: id, normalizedDay: TodoDueDayFormatting.longTermDueDay)
    }

    /// 将归属日设为「今天」起算的偏移天数（0 = 今天，1 = 明天，-1 = 日历上的前一天）。
    func setTodoDueDayRelativeToToday(id: TodoItem.ID, daysFromToday: Int) {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        guard let target = cal.date(byAdding: .day, value: daysFromToday, to: base) else { return }
        applyTodoDueDay(id: id, normalizedDay: cal.startOfDay(for: target))
    }

    /// 在当前归属日上增减天数。
    func shiftTodoDueDay(id: TodoItem.ID, by days: Int) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let cal = Calendar.current
        guard let target = cal.date(byAdding: .day, value: days, to: todos[index].dueDay) else { return }
        applyTodoDueDay(id: id, normalizedDay: cal.startOfDay(for: target))
    }

    private func applyTodoDueDay(id: TodoItem.ID, normalizedDay: Date) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].dueDay = normalizedDay
        save()
    }

    func setTodoCategory(id: TodoItem.ID, categoryId: UUID?) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].categoryId = categoryId
        save()
    }

    /// 设置自定义分类列表；删除的分类会从相关待办上自动摘掉。
    func updateTodoCategoryDefinitions(_ definitions: [TodoCategoryDefinition]) {
        guard !definitions.isEmpty else { return }
        var next = settings
        next.todoCategories = definitions
        settings = next
        let valid = Set(definitions.map(\.id))
        for i in todos.indices {
            if let cid = todos[i].categoryId, !valid.contains(cid) {
                todos[i].categoryId = nil
            }
        }
        save()
    }

    /// 首次编辑分类时，把内置默认写入偏好。
    func ensureTodoCategoriesMaterializedFromDefaults() {
        guard settings.todoCategories == nil else { return }
        var next = settings
        next.todoCategories = TodoCategoryDefinition.systemDefaults
        settings = next
        save()
    }

    /// 与导出相同的日期窗口规则：`dueDay` 在区间内，或长期待办锚点日。
    func todosInExportWindow(startInclusive: Date, endInclusive: Date) -> [TodoItem] {
        let start = TodoDueDayFormatting.normalize(startInclusive)
        let end = TodoDueDayFormatting.normalize(endInclusive)
        return todosOrderedForDisplay.filter { item in
            let day = TodoDueDayFormatting.normalize(item.dueDay)
            if TodoDueDayFormatting.isLongTermDueDay(day) {
                return true
            }
            return day >= start && day <= end
        }
    }

    /// 设置 · 数据管理：按自然日分段的应用耗时（自本地归档聚合）；每日组内按时长降序。
    func usageManagementDailySections(startDay: Date, endDay: Date) -> [(Date, [UsageItem])] {
        let cal = Calendar.current
        let s = cal.startOfDay(for: TodoDueDayFormatting.normalize(startDay))
        let e = cal.startOfDay(for: TodoDueDayFormatting.normalize(endDay))
        guard s <= e else { return [] }
        return auditor.storedDailyBreakdown(from: s, through: e).map { day, items in
            (day, Self.sortedUsageItemsByMinutesDescending(items))
        }
    }

    private static func sortedUsageItemsByMinutesDescending(_ items: [UsageItem]) -> [UsageItem] {
        items.sorted { lhs, rhs in
            if lhs.minutes != rhs.minutes {
                return lhs.minutes > rhs.minutes
            }
            return lhs.appName.localizedStandardCompare(rhs.appName) == .orderedAscending
        }
    }

    func setPreferredLanguage(_ language: AppLanguage) {
        guard settings.preferredLanguage != language else { return }
        var next = settings
        next.preferredLanguage = language
        settings = next
        save()
    }

    func exportTodos(startDay: Date, endDay: Date, format: TodoExportFormat, limitedToTodoIds: Set<UUID>? = nil) {
#if targetEnvironment(macCatalyst)
        _ = startDay
        _ = endDay
        _ = format
        _ = limitedToTodoIds
        settingsMessage = Localized.string("message.todo_export_unsupported", locale: settings.resolvedLocale)
#else
        let locale = settings.resolvedLocale
        let start = TodoDueDayFormatting.normalize(startDay)
        let end = TodoDueDayFormatting.normalize(endDay)
        guard start <= end else {
            settingsMessage = Localized.string("message.todo_export_bad_range", locale: locale)
            return
        }

        let rows = TodoExportBuilder.makeRows(
            orderedTodos: todosOrderedForDisplay,
            categories: settings.effectiveTodoCategories,
            locale: locale,
            startInclusive: start,
            endInclusive: end,
            limitedToTodoIds: limitedToTodoIds
        )

        if rows.isEmpty {
            settingsMessage = Localized.string("message.todo_export_empty", locale: locale)
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = Localized.string("settings.tasks.export.panel.title", locale: locale)
        panel.message = Localized.string("settings.tasks.export.panel.message", locale: locale)
        panel.nameFieldStringValue = TodoExportFilename.default(start: start, end: end, format: format)
        panel.allowedContentTypes = format.savePanelContentTypes
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try TodoExportWriter.write(rows: rows, format: format, to: url, locale: locale)
            settingsMessage = String(format: Localized.string("message.todo_export_ok", locale: locale), url.path)
        } catch {
            settingsMessage = String(format: Localized.string("message.todo_export_fail", locale: locale), error.localizedDescription)
        }
#endif
    }

    func save() {
        storage.save(todos: todos, settings: settings)
    }

    func setBreakOverlayDisplayMode(_ mode: BreakOverlayDisplayMode) {
        var next = settings
        next.breakOverlayDisplayMode = mode
        settings = next
        save()
    }

    func setBreakOverlaySidebarCollapsed(_ collapsed: Bool) {
        guard breakOverlaySidebarCollapsed != collapsed else { return }
        breakOverlaySidebarCollapsed = collapsed
    }

    /// 暂时隐藏全屏休息遮盖约 10 秒（标准 / 伪装模式均可用），便于整理桌面；休息倒计时不停。
    func beginBreakDesktopOrganizeGracePeriodIfResting() {
        guard status == .resting else { return }

        breakDesktopRevealRestoreTask?.cancel()
        breakDesktopRevealActive = true

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            breakDesktopRevealActive = false
            breakDesktopRevealRestoreTask = nil
        }
        breakDesktopRevealRestoreTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        settings.launchAtLogin = isEnabled
        settingsMessage = LaunchAtLoginService.setEnabled(isEnabled)
        save()
    }

    func updateReminderDurations(minWork: Int? = nil, maxWork: Int? = nil, breakMinutes: Int? = nil) {
        if let minWork {
            settings.minWorkMinutes = minWork
        }
        if let maxWork {
            settings.maxWorkMinutes = max(maxWork, settings.minWorkMinutes)
        }
        if let breakMinutes {
            settings.breakMinutes = breakMinutes
            if status == .resting {
                breakSecondsRemaining = min(breakSecondsRemaining, breakMinutes * 60)
            }
        }
        settings.maxWorkMinutes = max(settings.maxWorkMinutes, settings.minWorkMinutes)
        save()
    }

    func resetAllSettings() {
        settings = FocusPauseSettings()
        focusSecondsRemaining = settings.minWorkMinutes * 60
        breakSecondsRemaining = settings.breakMinutes * 60
        save()
    }

    func exportUsageCSV(startDay: Date, endDay: Date) {
#if targetEnvironment(macCatalyst)
        _ = startDay
        _ = endDay
        settingsMessage = Localized.string("message.todo_export_unsupported", locale: settings.resolvedLocale)
#else
        let locale = settings.resolvedLocale
        let cal = Calendar.current
        let rawStart = cal.startOfDay(for: TodoDueDayFormatting.normalize(startDay))
        let rawEnd = cal.startOfDay(for: TodoDueDayFormatting.normalize(endDay))
        guard rawStart <= rawEnd else {
            settingsMessage = Localized.string("message.todo_export_bad_range", locale: locale)
            return
        }

        let csvBody = auditor.usageCSVString(from: rawStart, through: rawEnd)
        let nonEmptyRows = csvBody.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        guard nonEmptyRows.count > 1 else {
            settingsMessage = Localized.string("message.usage_export_empty", locale: locale)
            return
        }

        let utf8 = "\u{FEFF}" + csvBody
        guard let data = utf8.data(using: .utf8) else {
            settingsMessage = String(format: Localized.string("message.export_csv_fail", locale: locale), "")
            return
        }

        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let a = fmt.string(from: rawStart)
        let b = fmt.string(from: rawEnd)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = Localized.string("settings.data.usage.export.panel.title", locale: locale)
        panel.message = Localized.string("settings.data.usage.export.panel.message", locale: locale)
        panel.nameFieldStringValue = "focuspause-usage-\(a)-to-\(b).csv"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
            settingsMessage = String(format: Localized.string("message.export_csv_ok", locale: locale), url.path)
        } catch {
            settingsMessage = String(format: Localized.string("message.export_csv_fail", locale: locale), error.localizedDescription)
        }
#endif
    }

    func removeTodosWithDueDayBefore(_ cutoffDay: Date) {
        let c = Calendar.current.startOfDay(for: TodoDueDayFormatting.normalize(cutoffDay))
        let beforeCount = todos.count
        todos.removeAll { TodoDueDayFormatting.normalize($0.dueDay) < c }
        guard todos.count != beforeCount else {
            settingsMessage = Localized.string("message.data_prune_todos_none", locale: settings.resolvedLocale)
            return
        }
        save()
        settingsMessage = Localized.string("message.data_prune_todos_ok", locale: settings.resolvedLocale)
    }

    func removeUsageDailyBefore(_ cutoffDay: Date) {
        let c = Calendar.current.startOfDay(for: TodoDueDayFormatting.normalize(cutoffDay))
        let n = auditor.removeDailyUsageEntries(beforeCutoffDay: c)
        refreshUsageAudit(force: true)
        if n == 0 {
            settingsMessage = Localized.string("message.data_prune_usage_none", locale: settings.resolvedLocale)
        } else {
            settingsMessage = String(format: Localized.string("message.data_prune_usage_ok", locale: settings.resolvedLocale), n)
        }
    }

    func clearAllTodosAndUsageData() {
        todos.removeAll()
        auditor.removeAllDailyUsageEntriesAndCycle()
        refreshUsageAudit(force: true)
        save()
        settingsMessage = Localized.string("message.data_clear_all_ok", locale: settings.resolvedLocale)
    }

    func resetUsageData() {
        auditor.resetUsageData()
        refreshUsageAudit(force: true)
        settingsMessage = Localized.string("message.usage_reset_ok", locale: settings.resolvedLocale)
    }

    func requestAccessibilityPermission() {
        AccessibilityPermissionService.requestPermissionPrompt()
    }

    func setUsageScope(_ scope: UsageScope) {
        usageScope = scope
        refreshUsageAudit(force: true)
    }

    func setDoNotDisturb(_ period: DoNotDisturbPeriod, feedback: DNDFeedbackChannel = .popoverToast) {
        if period == .custom {
            commitCustomDoNotDisturb(feedback: feedback)
            return
        }

        if period == .off {
            popoverMessage = nil
        }

        let wasEnabled = settings.dndPeriod.isEnabled
        let dndUntil = Self.dndEndDate(for: period)

        guard period == .off || dndUntil != nil else {
            popoverMessage = nil
            settings.dndPeriod = .off
            settings.dndUntil = nil
            let fmt = Localized.string("message.dnd_outside_period", locale: settings.resolvedLocale)
            deliverDNDFeedback(String(format: fmt, period.localizedPickerTitle(locale: settings.resolvedLocale)), channel: feedback)
            save()
            return
        }

        settings.dndPeriod = period
        settings.dndUntil = dndUntil

        if period.isEnabled {
            if !wasEnabled {
                statusBeforeDoNotDisturb = status == .paused ? .focusing : status
            }
            status = .paused
        } else if status == .paused {
            resumeFromDNDPauseIfNeeded()
            settings.dndUntil = nil
        }
        save()
    }

    /// 设置页选中「自定义时段」分段：只切换选项，不解除勿扰计时逻辑（由下一秒 tick 按已保存时段重新评估）。
    func selectDoNotDisturbCustomSegmentForSettings() {
        switch settings.dndPeriod {
        case .morning, .afternoon, .allDay:
            settings.dndUntil = nil
        default:
            break
        }
        settings.dndPeriod = .custom
        save()
    }

    /// 由设置页写入多段勿扰窗口后应用（校验每段且规范化排序）。
    func applyCommittedCustomDNDWindows(_ windows: [DNDCustomDayWindow], feedback: DNDFeedbackChannel) {
        let loc = settings.resolvedLocale
        guard !windows.isEmpty else {
            deliverDNDFeedback(Localized.string("message.dnd_custom_invalid", locale: loc), channel: feedback)
            return
        }
        for w in windows {
            guard w.startMinute >= 0,
                  w.endMinute <= 24 * 60 - 1,
                  w.startMinute < w.endMinute else {
                deliverDNDFeedback(
                    Localized.string("message.dnd_custom_invalid_order", locale: loc),
                    channel: feedback
                )
                return
            }
        }
        settings.dndCustomDayWindows = FocusPauseSettings.normalizedDNDCustomWindows(windows)
        settings.syncDNDTimeRangesCaptionFromWindows()
        commitCustomDoNotDisturb(feedback: feedback)
    }

    /// 应用当前已存储的自定义时段（当天多段）。
    func commitCustomDoNotDisturb(feedback: DNDFeedbackChannel) {
        let loc = settings.resolvedLocale
        let now = Date()
        switch Self.evaluateCustomDND(settings: settings, now: now) {
        case .parseFailed, .noWindows:
            settings.dndPeriod = .off
            settings.dndUntil = nil
            if status == .paused { resumeFromDNDPauseIfNeeded() }
            deliverDNDFeedback(Localized.string("message.dnd_custom_invalid", locale: loc), channel: feedback)
            save()
        case .allEnded:
            settings.dndPeriod = .custom
            settings.dndUntil = nil
            if status == .paused { resumeFromDNDPauseIfNeeded() }
            deliverDNDFeedback(Localized.string("message.dnd_custom_failed_past", locale: loc), channel: feedback)
            save()
        case .activeUntil(let end):
            settings.dndPeriod = .custom
            settings.dndUntil = end
            if status != .paused {
                statusBeforeDoNotDisturb = status == .paused ? .focusing : status
                status = .paused
            }
            deliverDNDFeedback(Localized.string("message.dnd_custom_success_active", locale: loc), channel: feedback)
            save()
        case .scheduled(let start, let end):
            settings.dndPeriod = .custom
            settings.dndUntil = nil
            if status == .paused { resumeFromDNDPauseIfNeeded() }
            let s = Self.formatShortTime(start, locale: loc)
            let e = Self.formatShortTime(end, locale: loc)
            deliverDNDFeedback(
                String(format: Localized.string("message.dnd_custom_success_scheduled", locale: loc), s, e),
                channel: feedback
            )
            save()
        }
    }

    private func deliverDNDFeedback(_ text: String, channel: DNDFeedbackChannel) {
        switch channel {
        case .silent:
            break
        case .settingsAlert:
            settingsMessage = text
        case .popoverToast:
            showPopoverMessage(text)
        }
    }

    private func resumeFromDNDPauseIfNeeded() {
        guard status == .paused else { return }
        status = statusBeforeDoNotDisturb == .resting ? .focusing : statusBeforeDoNotDisturb
    }

    private func reconcileDoNotDisturbAfterLoad() {
        let now = Date()
        if settings.dndPeriod == .custom {
            switch Self.evaluateCustomDND(settings: settings, now: now) {
            case .parseFailed, .noWindows:
                settings.dndPeriod = .off
                settings.dndUntil = nil
                save()
            case .allEnded:
                settings.dndUntil = nil
                save()
            case .activeUntil(let end):
                settings.dndUntil = end
                statusBeforeDoNotDisturb = .focusing
                status = .paused
                save()
            case .scheduled:
                settings.dndUntil = nil
                save()
            }
            return
        }
        guard settings.dndPeriod.isEnabled else { return }
        guard let until = settings.dndUntil, until > now else {
            settings.dndPeriod = .off
            settings.dndUntil = nil
            save()
            return
        }
        statusBeforeDoNotDisturb = .focusing
        status = .paused
        save()
    }

    private static let todoCategoryNilToWorkMigrationKey = "focuspause.todoCategory.nilToWorkMigration.v1"

    private func load() {
        let snapshot = storage.load()
        todos = snapshot.todos ?? todos
        settings = snapshot.settings ?? settings
        migrateLegacyReminderSoundIfNeeded()
        migrateTodoCategoryNilToWorkIfNeeded()
    }

    private func migrateLegacyReminderSoundIfNeeded() {
        let legacy = settings.reminderSound
        let mapped: String?
        switch legacy {
        case "系统默认": mapped = "system"
        case "轻柔提示音": mapped = "gentle"
        case "关闭音效": mapped = "none"
        default: mapped = nil
        }
        guard let mapped else { return }
        settings.reminderSound = mapped
        save()
    }

    /// 历史存档里没有 `categoryId` 的条目一次性归为默认「工作」，避免界面始终像「没改过默认值」。
    private func migrateTodoCategoryNilToWorkIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.todoCategoryNilToWorkMigrationKey) else { return }
        let defaultId = TodoCategoryDefinition.defaultAssignedCategoryId
        var changed = false
        for i in todos.indices where todos[i].categoryId == nil {
            todos[i].categoryId = defaultId
            changed = true
        }
        UserDefaults.standard.set(true, forKey: Self.todoCategoryNilToWorkMigrationKey)
        if changed {
            save()
        }
    }

    private func startTicker() {
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        let now = Date()

        if settings.dndPeriod == .custom {
            let freezing = tickCustomDoNotDisturb(now: now)
            if lastCustomDNDTickFrozen && !freezing {
                popoverMessage = nil
            }
            lastCustomDNDTickFrozen = freezing
            if freezing { return }
        } else {
            lastCustomDNDTickFrozen = false
            if settings.dndPeriod.isEnabled {
                if let until = settings.dndUntil {
                    if until <= now {
                        setDoNotDisturb(.off, feedback: .silent)
                    } else if status == .paused {
                        auditor.recordActiveSecond(countForCurrentCycle: false)
                        refreshUsageAudit(force: true)
                        return
                    }
                } else {
                    settings.dndPeriod = .off
                    settings.dndUntil = nil
                    save()
                }
            }
        }

        auditor.recordActiveSecond(countForCurrentCycle: status == .focusing)
        refreshUsageAudit()

        switch status {
        case .focusing:
            if focusSecondsRemaining <= 1 {
                startBreakNow()
            } else {
                focusSecondsRemaining -= 1
            }
        case .resting:
            if breakSecondsRemaining <= 1 {
                returnToWork()
            } else {
                breakSecondsRemaining -= 1
                if breakSecondsRemaining % 5 == 0 {
                    restTipIndex = (restTipIndex + 1) % restTipCount
                }
            }
        case .idle:
            // 兜底：只要不是勿扰，就持续在专注/休息循环。
            enterFocusCycle(resetUsageCycle: true, forceCurrentFocusScope: false)
        case .paused:
            break
        }
    }

    private func cancelBreakDesktopRevealScheduling() {
        breakDesktopRevealRestoreTask?.cancel()
        breakDesktopRevealRestoreTask = nil
        breakDesktopRevealActive = false
    }

    private func enterFocusCycle(resetUsageCycle: Bool, forceCurrentFocusScope: Bool) {
        if resetUsageCycle {
            auditor.resetCurrentCycle()
        }
        if forceCurrentFocusScope {
            usageScope = .currentFocus
        }
        status = .focusing
        focusSecondsRemaining = settings.minWorkMinutes * 60
        breakSecondsRemaining = settings.breakMinutes * 60
        refreshUsageAudit(force: true)
        cancelBreakDesktopRevealScheduling()
        requestBreakOverlayClose()
    }

    private func requestBreakOverlayClose() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .focusPauseForceCloseBreakOverlay, object: nil)
        }
    }

    /// - Parameter force: 为 true 时立即刷新（切换统计口径、设置变更等）；休息时默认同 tick 节流，避免侧边栏 ScrollView 每秒随用量条重建而跳回顶部。
    private func refreshUsageAudit(force: Bool = false) {
        if !force, status == .resting {
            guard breakSecondsRemaining % 5 == 0 else { return }
        }
        let next = auditor.snapshot(for: usageScope)
        guard next != usageItems else { return }
        usageItems = next
    }

    /// - Returns: `true` 时本轮应冻结专注/休息倒计时（处于自定义勿扰生效窗口内）。
    private func tickCustomDoNotDisturb(now: Date) -> Bool {
        switch Self.evaluateCustomDND(settings: settings, now: now) {
        case .parseFailed, .noWindows:
            clearBrokenCustomDND()
            return false
        case .allEnded:
            settings.dndUntil = nil
            if status == .paused {
                resumeFromDNDPauseIfNeeded()
            }
            save()
            return false
        case .activeUntil(let end):
            settings.dndUntil = end
            if status != .paused {
                statusBeforeDoNotDisturb = status
                status = .paused
            }
            auditor.recordActiveSecond(countForCurrentCycle: false)
            refreshUsageAudit(force: true)
            return true
        case .scheduled:
            settings.dndUntil = nil
            if status == .paused {
                resumeFromDNDPauseIfNeeded()
            }
            save()
            return false
        }
    }

    private func clearBrokenCustomDND() {
        guard settings.dndPeriod == .custom else { return }
        settings.dndPeriod = .off
        settings.dndUntil = nil
        if status == .paused { resumeFromDNDPauseIfNeeded() }
        save()
    }

    private enum CustomDNDEvaluation {
        case parseFailed
        case noWindows
        case allEnded
        case activeUntil(Date)
        case scheduled(start: Date, end: Date)
    }

    private static func evaluateCustomDND(settings: FocusPauseSettings, now: Date, calendar: Calendar = .current) -> CustomDNDEvaluation {
        let dayStart = calendar.startOfDay(for: now)
        var intervals: [(Date, Date)] = []
        for w in settings.dndCustomDayWindows {
            guard w.startMinute >= 0,
                  w.endMinute <= 24 * 60 - 1,
                  w.endMinute > w.startMinute else {
                continue
            }
            guard let d1 = calendar.date(byAdding: .minute, value: w.startMinute, to: dayStart),
                  let d2 = calendar.date(byAdding: .minute, value: w.endMinute, to: dayStart) else {
                continue
            }
            intervals.append((d1, d2))
        }
        intervals.sort { $0.0 < $1.0 }
        if intervals.isEmpty {
            return .parseFailed
        }
        return classifyWindows(intervals, now: now)
    }

    private static func classifyWindows(_ sorted: [(Date, Date)], now: Date) -> CustomDNDEvaluation {
        guard let last = sorted.last else { return .noWindows }
        if last.1 <= now { return .allEnded }
        for (s, e) in sorted {
            if now >= s && now < e { return .activeUntil(e) }
            if now < s { return .scheduled(start: s, end: e) }
        }
        return .allEnded
    }

    private static func formatShortTime(_ date: Date, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    private func showPopoverMessage(_ message: String) {
        popoverMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            guard self?.popoverMessage == message else { return }
            self?.popoverMessage = nil
        }
    }

    private static func dndEndDate(for period: DoNotDisturbPeriod) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)

        switch period {
        case .morning:
            guard hour < 12 else { return nil }
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
            return noon > now ? noon : nil
        case .afternoon:
            guard hour >= 12, hour < 18 else { return nil }
            let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now) ?? now
            return evening > now ? evening : nil
        case .allDay:
            return calendar.dateInterval(of: .day, for: now)?.end
        case .off, .custom:
            return nil
        }
    }
}
