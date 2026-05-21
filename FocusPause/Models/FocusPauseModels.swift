import Foundation
import SwiftUI

/// 应用界面语言；默认跟随系统。手动语种使用固定 Locale。
enum AppLanguage: String, Codable, Identifiable {
    case system
    case english
    case chineseSimplified
    case spanish
    case englishIndia
    case french
    case japanese
    case russian
    case korean

    var id: String { rawValue }

    /// 设置里可选的语言列表（首项为跟随系统）。
    static let selectableCases: [AppLanguage] = [
        .system,
        .english,
        .chineseSimplified,
        .spanish,
        .japanese,
        .russian,
        .korean,
        .englishIndia,
        .french,
    ]

    var localizationKey: String {
        switch self {
        case .system: "lang.system"
        case .english: "lang.english"
        case .chineseSimplified: "lang.chinese_simplified"
        case .spanish: "lang.spanish"
        case .englishIndia: "lang.english_india"
        case .french: "lang.french"
        case .japanese: "lang.japanese"
        case .russian: "lang.russian"
        case .korean: "lang.korean"
        }
    }

    /// 非 `.system` 时由 `FocusPauseSettings.resolvedLocale` 使用；`.system` 分支仅为穷尽匹配占位。
    var manualLocaleIdentifier: String {
        switch self {
        case .system, .english:
            return "en"
        case .chineseSimplified:
            return "zh-Hans"
        case .spanish:
            return "es"
        case .englishIndia:
            return "en-IN"
        case .french:
            return "fr"
        case .japanese:
            return "ja"
        case .russian:
            return "ru"
        case .korean:
            return "ko"
        }
    }
}

enum FocusStatus: String, CaseIterable, Codable {
    case idle
    case focusing
    case resting
    case paused

    var color: Color {
        switch self {
        case .idle: .secondary
        case .focusing: .green
        case .resting: .blue
        case .paused: .orange
        }
    }
}

enum TodoPriority: String, CaseIterable, Codable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .low: .gray
        case .normal: .blue
        case .high: .red
        }
    }
}

/// 待办事件分类（右侧胶囊）；可在设置中增删改，默认包含常见生活维度。
struct TodoCategoryDefinition: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    /// `#RRGGBB`，用于胶囊浅色底。
    var tintHex: String

    /// 稳定 id，便于偏好与待办关联持久化。
    static let systemDefaults: [TodoCategoryDefinition] = [
        TodoCategoryDefinition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111101")!, title: "Work", tintHex: "#2563EB"),
        TodoCategoryDefinition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111102")!, title: "Life", tintHex: "#059669"),
        TodoCategoryDefinition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111103")!, title: "Study", tintHex: "#7C3AED"),
        TodoCategoryDefinition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111104")!, title: "Health", tintHex: "#DC2626"),
        TodoCategoryDefinition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111105")!, title: "Leisure", tintHex: "#EA580C"),
        TodoCategoryDefinition(id: UUID(uuidString: "11111111-1111-4111-8111-111111111106")!, title: "Other", tintHex: "#64748B")
    ]

    /// 六项内置分类的稳定 id（界面文案随语言来自 `localizedTitle`）。
    static let presetBuiltinIds: Set<UUID> = Set(systemDefaults.map(\.id))

    static func isPresetBuiltin(id: UUID) -> Bool {
        presetBuiltinIds.contains(id)
    }

    static var presetTintHexes: [String] {
        ["#2563EB", "#059669", "#7C3AED", "#DC2626", "#EA580C", "#64748B", "#CA8A04", "#DB2777", "#0891B2", "#4F46E5"]
    }

    /// 新建待办默认归入「工作」（与 `systemDefaults` 首项 id 一致）。
    static var defaultAssignedCategoryId: UUID { systemDefaults[0].id }
}

struct TodoItem: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var isDone: Bool
    var priority: TodoPriority
    /// `nil` 为一级待办；非 `nil` 为二级（直属该父 id）。
    var parentId: UUID?
    /// 旧版与系统提醒绑定的标识；已不再同步，仅用于解码旧数据。
    var reminderCalendarItemIdentifier: String?
    /// 归属自然日（本地日历零点）；列表顶部「长期待办 / 今天 / 明天」与日历共用。长期待办使用锚点日 `TodoDueDayFormatting.longTermDueDay`（9999-12-31），与时间轴无关。
    var dueDay: Date
    /// 事件分类（右侧胶囊）；`nil` 表示未分类。
    var categoryId: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool,
        priority: TodoPriority,
        parentId: UUID? = nil,
        reminderCalendarItemIdentifier: String? = nil,
        dueDay: Date = TodoDueDayFormatting.normalize(Date()),
        categoryId: UUID? = TodoCategoryDefinition.defaultAssignedCategoryId
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.priority = priority
        self.parentId = parentId
        self.reminderCalendarItemIdentifier = reminderCalendarItemIdentifier
        self.dueDay = TodoDueDayFormatting.normalize(dueDay)
        self.categoryId = categoryId
    }

    enum CodingKeys: String, CodingKey {
        case id, title, isDone, priority, parentId, reminderCalendarItemIdentifier, dueDay, categoryId
    }
}

extension TodoItem: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decode(Bool.self, forKey: .isDone)
        priority = try c.decode(TodoPriority.self, forKey: .priority)
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        reminderCalendarItemIdentifier = try c.decodeIfPresent(String.self, forKey: .reminderCalendarItemIdentifier)
        categoryId = try c.decodeIfPresent(UUID.self, forKey: .categoryId)
        if let d = try c.decodeIfPresent(Date.self, forKey: .dueDay) {
            dueDay = TodoDueDayFormatting.normalize(d)
        } else {
            dueDay = TodoDueDayFormatting.normalize(Date())
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(isDone, forKey: .isDone)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(parentId, forKey: .parentId)
        try c.encodeIfPresent(reminderCalendarItemIdentifier, forKey: .reminderCalendarItemIdentifier)
        try c.encode(dueDay, forKey: .dueDay)
        try c.encodeIfPresent(categoryId, forKey: .categoryId)
    }
}

enum TodoDueDayFormatting {
    static func normalize(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    /// 长期待办锚点：导出列显示为 9999-12-31，且任意导出日期范围均包含此类条目。
    static let longTermDueDay: Date = {
        let cal = Calendar.current
        var dc = DateComponents()
        dc.calendar = cal
        dc.year = 9999
        dc.month = 12
        dc.day = 31
        guard let d = dc.date else {
            return normalize(Date(timeIntervalSince1970: 0))
        }
        return normalize(d)
    }()

    static func isLongTermDueDay(_ date: Date) -> Bool {
        let cal = Calendar.current
        let n = normalize(date)
        return cal.component(.year, from: n) == 9999
            && cal.component(.month, from: n) == 12
            && cal.component(.day, from: n) == 31
    }

    /// 相对「参考时刻」所在自然日的文案：长期待办 / 今天 / 昨天 / 明天 / 具体日期。
    static func relativeLabel(for dueDay: Date, reference: Date = Date(), locale: Locale = Locale.autoupdatingCurrent) -> String {
        if isLongTermDueDay(dueDay) {
            return Localized.string("day.long_term", locale: locale)
        }
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: dueDay)
        let r0 = cal.startOfDay(for: reference)
        let days = cal.dateComponents([.day], from: r0, to: d0).day ?? 0
        switch days {
        case 0: return Localized.string("day.today", locale: locale)
        case -1: return Localized.string("day.yesterday", locale: locale)
        case 1: return Localized.string("day.tomorrow", locale: locale)
        default:
            let fmt = DateFormatter()
            fmt.locale = locale
            let yNow = cal.component(.year, from: r0)
            let y = cal.component(.year, from: d0)
            fmt.dateFormat = y == yNow ? Localized.string("date.format.month_day", locale: locale) : Localized.string("date.format.full", locale: locale)
            return fmt.string(from: d0)
        }
    }

    /// 列表中展示「哪一天」的待办：具体日历日期（通常含星期）；长期待办返回本地化「长期待办」。
    static func calendarDateLabel(for dueDay: Date, locale: Locale) -> String {
        if isLongTermDueDay(dueDay) {
            return Localized.string("day.long_term", locale: locale)
        }
        let d0 = normalize(dueDay)
        let fmt = DateFormatter()
        fmt.locale = locale
        fmt.calendar = Calendar.current
        if let template = DateFormatter.dateFormat(fromTemplate: "yMMMdEEEE", options: 0, locale: locale) {
            fmt.dateFormat = template
        } else {
            fmt.dateStyle = .long
            fmt.timeStyle = .none
        }
        return fmt.string(from: d0)
    }

    /// 紧凑展示：20260512（用于日期分段右侧）。
    static func digitsYyyyMmDd(for day: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: day)
        let m = cal.component(.month, from: day)
        let d = cal.component(.day, from: day)
        return String(format: "%04d%02d%02d", y, m, d)
    }
}

struct UsageItem: Identifiable, Equatable {
    /// 稳定标识：列表与导出行一致（优先 bundle id）。
    var id: String { bundleIdentifier ?? appName }
    var appName: String
    var minutes: Int
    var tintHex: String
    var symbolName: String
    /// 用于加载「设置」里同款应用图标；旧版本仅存显示名称时可能为 nil。
    var bundleIdentifier: String?

    var color: Color {
        Color(hex: tintHex)
    }
}

enum UsageScope: String, CaseIterable, Identifiable {
    case currentFocus
    case today

    var id: String { rawValue }
}

/// 设置中导出本地待办所选格式。
enum TodoExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case pdf
    case csvExcel

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .pdf: return "pdf"
        case .csvExcel: return "csv"
        }
    }
}

/// 当天内一段勿扰窗口（从午夜起的分钟数，`endMinute` 须大于 `startMinute`）。
struct DNDCustomDayWindow: Codable, Equatable, Hashable {
    var startMinute: Int
    var endMinute: Int
}

enum DoNotDisturbPeriod: String, CaseIterable, Codable, Identifiable {
    case off
    case morning
    case afternoon
    case allDay
    case custom

    var id: String { rawValue }

    var isEnabled: Bool {
        self != .off
    }

    /// 设置页展示顺序：关闭 → 上午 → 下午 → 全天 → 自定义多时段（弹窗菜单不含此项）。
    static var settingsPickerCases: [DoNotDisturbPeriod] {
        [.off, .morning, .afternoon, .allDay, .custom]
    }
}

/// 休息阶段全屏遮罩的呈现方式（可选以实现旧版偏好解码兼容）。
enum BreakOverlayDisplayMode: String, Codable, CaseIterable, Identifiable, Hashable {
    /// 深色沉浸式全屏（默认）。
    case standard
    /// 桌面可见，右侧半透明悬浮卡片。
    case disguise

    var id: String { rawValue }
}

struct FocusPauseSettings: Equatable {
    /// 自定义勿扰默认：09:30–10:30（当天）。
    static let defaultDNDCustomStartMinutes = 9 * 60 + 30
    static let defaultDNDCustomEndMinutes = 10 * 60 + 30

    var launchAtLogin = true
    var showMenuBarIcon = true
    var theme = "system"
    var minWorkMinutes = 45
    var maxWorkMinutes = 90
    var breakMinutes = 10
    /// `system` / `gentle` / `none`（兼容旧版中文存盘值，见 Store 迁移）。
    var reminderSound = "system"
    /// 界面语言；默认跟随系统。JSON 缺字段或 `preferredLanguage: null` 时亦为跟随系统。
    var preferredLanguage: AppLanguage = .system
    var notificationsEnabled = true
    var syncSystemFocus = true
    var autoPauseInMeetings = true
    var dndApps = "Keynote, Zoom, Microsoft Teams"
    /// 兼容旧版存档可读摘要；以 `dndCustomDayWindows` 为准。
    var dndTimeRanges = "09:30 - 10:30"
    /// 当天多段勿扰窗口（按开始时间排序存储）。
    var dndCustomDayWindows: [DNDCustomDayWindow] = [
        DNDCustomDayWindow(startMinute: Self.defaultDNDCustomStartMinutes, endMinute: Self.defaultDNDCustomEndMinutes),
    ]
    var dndPeriod: DoNotDisturbPeriod = .off
    var dndUntil: Date?
    var keepUsageLocalOnly = true
    /// `nil` 表示使用默认休息遮罩样式（伪装侧边卡片）；兼容旧存储未写入该字段。
    var breakOverlayDisplayMode: BreakOverlayDisplayMode?
    /// 待办列表顶部当前查看的自然日（本地零点）；`nil` 表示「今天」。选择「长期待办」时为锚点日（9999-12-31）。
    var todoListSelectedDay: Date?
    /// 待办事件分类列表；`nil` 表示尚未写入偏好，界面使用 `TodoCategoryDefinition.systemDefaults`。
    var todoCategories: [TodoCategoryDefinition]?

    var resolvedBreakOverlayMode: BreakOverlayDisplayMode {
        breakOverlayDisplayMode ?? .disguise
    }

    /// 列表与编辑器使用的分类（至少一项）。
    var effectiveTodoCategories: [TodoCategoryDefinition] {
        if let list = todoCategories, !list.isEmpty {
            return list
        }
        return TodoCategoryDefinition.systemDefaults
    }
}

extension FocusPauseSettings {
    mutating func syncDNDTimeRangesCaptionFromWindows() {
        if dndCustomDayWindows.isEmpty {
            dndTimeRanges = ""
            return
        }
        dndTimeRanges = dndCustomDayWindows
            .map { Self.formatDNDRangeCaption(startMinutes: $0.startMinute, endMinutes: $0.endMinute) }
            .joined(separator: ", ")
    }

    static func formatDNDRangeCaption(startMinutes: Int, endMinutes: Int) -> String {
        String(format: "%02d:%02d - %02d:%02d", startMinutes / 60, startMinutes % 60, endMinutes / 60, endMinutes % 60)
    }

    /// 滤掉非法段，按开始时间排序；若为空则返回默认一段。
    static func normalizedDNDCustomWindows(_ raw: [DNDCustomDayWindow]) -> [DNDCustomDayWindow] {
        let lastMinuteOfDay = 24 * 60 - 1
        let valid = raw.filter { w in
            w.startMinute >= 0 && w.startMinute < lastMinuteOfDay
                && w.endMinute > w.startMinute && w.endMinute <= lastMinuteOfDay
        }
        if valid.isEmpty {
            return [
                DNDCustomDayWindow(startMinute: defaultDNDCustomStartMinutes, endMinute: defaultDNDCustomEndMinutes),
            ]
        }
        return valid.sorted { $0.startMinute < $1.startMinute }
    }

    /// 解析逗号分隔的每一段 `HH:mm … HH:mm`，返回多段窗口。
    static func migratedWindowsFromLegacyDNDString(_ raw: String) -> [DNDCustomDayWindow]? {
        let normalized = raw.replacingOccurrences(of: "，", with: ",")
        let chunks = normalized.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var wins: [DNDCustomDayWindow] = []
        for segment in chunks {
            guard let pair = parseLegacySegmentToMinutePair(segment) else { continue }
            wins.append(DNDCustomDayWindow(startMinute: pair.start, endMinute: pair.end))
        }
        return wins.isEmpty ? nil : wins
    }

    /// 单段 `09:30 - 10:30` → 分钟对。
    private static func parseLegacySegmentToMinutePair(_ segment: String) -> (start: Int, end: Int)? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let separators = [" - ", " – ", " — ", "－", "-"]
        var lhs: String?
        var rhs: String?
        for sep in separators {
            if segment.contains(sep) {
                let halves = segment.components(separatedBy: sep)
                if halves.count == 2 {
                    lhs = halves[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    rhs = halves[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
        }
        guard let a = lhs, let b = rhs else { return nil }
        func hm(_ token: String) -> (Int, Int)? {
            let parts = token.split(separator: ":")
            guard parts.count == 2,
                  let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let m = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  (0 ..< 24).contains(h), (0 ..< 60).contains(m) else { return nil }
            return (h, m)
        }
        guard let hm1 = hm(a), let hm2 = hm(b) else { return nil }
        var dc = cal.dateComponents([.year, .month, .day], from: dayStart)
        dc.hour = hm1.0
        dc.minute = hm1.1
        dc.second = 0
        guard let d1 = cal.date(from: dc) else { return nil }
        dc.hour = hm2.0
        dc.minute = hm2.1
        guard let d2 = cal.date(from: dc), d2 > d1 else { return nil }
        let c1 = cal.dateComponents([.hour, .minute], from: d1)
        let c2 = cal.dateComponents([.hour, .minute], from: d2)
        let sm = (c1.hour ?? 0) * 60 + (c1.minute ?? 0)
        let em = (c2.hour ?? 0) * 60 + (c2.minute ?? 0)
        guard em > sm else { return nil }
        return (sm, em)
    }

    /// 将一对分钟数约束在合法区间内；若结束不晚于开始则回落到默认时段。
    static func normalizedDNDCustomMinutePair(start: Int, end: Int) -> (start: Int, end: Int) {
        let lastMinuteOfDay = 24 * 60 - 1
        let s = min(max(start, 0), lastMinuteOfDay - 1)
        let e = min(max(end, 0), lastMinuteOfDay)
        if e <= s {
            return (defaultDNDCustomStartMinutes, defaultDNDCustomEndMinutes)
        }
        return (s, e)
    }
}

extension FocusPauseSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case showMenuBarIcon
        case theme
        case minWorkMinutes
        case maxWorkMinutes
        case breakMinutes
        case reminderSound
        case preferredLanguage
        case notificationsEnabled
        case syncSystemFocus
        case autoPauseInMeetings
        case dndApps
        case dndTimeRanges
        case dndCustomDayWindows
        case dndCustomStartMinutes
        case dndCustomEndMinutes
        case dndPeriod
        case dndUntil
        case keepUsageLocalOnly
        case breakOverlayDisplayMode
        case todoListSelectedDay
        case todoCategories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "system"
        minWorkMinutes = try c.decodeIfPresent(Int.self, forKey: .minWorkMinutes) ?? 45
        maxWorkMinutes = try c.decodeIfPresent(Int.self, forKey: .maxWorkMinutes) ?? 90
        breakMinutes = try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 10
        reminderSound = try c.decodeIfPresent(String.self, forKey: .reminderSound) ?? "system"

        preferredLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .preferredLanguage) ?? .system

        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        syncSystemFocus = try c.decodeIfPresent(Bool.self, forKey: .syncSystemFocus) ?? true
        autoPauseInMeetings = try c.decodeIfPresent(Bool.self, forKey: .autoPauseInMeetings) ?? true
        dndApps = try c.decodeIfPresent(String.self, forKey: .dndApps) ?? "Keynote, Zoom, Microsoft Teams"

        if let arr = try c.decodeIfPresent([DNDCustomDayWindow].self, forKey: .dndCustomDayWindows), !arr.isEmpty {
            dndCustomDayWindows = FocusPauseSettings.normalizedDNDCustomWindows(arr)
        } else {
            let decStart = try c.decodeIfPresent(Int.self, forKey: .dndCustomStartMinutes)
            let decEnd = try c.decodeIfPresent(Int.self, forKey: .dndCustomEndMinutes)
            let legacy = try c.decodeIfPresent(String.self, forKey: .dndTimeRanges) ?? "09:30 - 10:30"
            if let ds = decStart, let de = decEnd {
                let pair = FocusPauseSettings.normalizedDNDCustomMinutePair(start: ds, end: de)
                dndCustomDayWindows = [
                    DNDCustomDayWindow(startMinute: pair.start, endMinute: pair.end),
                ]
            } else if let multi = FocusPauseSettings.migratedWindowsFromLegacyDNDString(legacy) {
                dndCustomDayWindows = FocusPauseSettings.normalizedDNDCustomWindows(multi)
            } else {
                dndCustomDayWindows = [
                    DNDCustomDayWindow(
                        startMinute: FocusPauseSettings.defaultDNDCustomStartMinutes,
                        endMinute: FocusPauseSettings.defaultDNDCustomEndMinutes
                    ),
                ]
            }
        }
        dndTimeRanges = dndCustomDayWindows
            .map { FocusPauseSettings.formatDNDRangeCaption(startMinutes: $0.startMinute, endMinutes: $0.endMinute) }
            .joined(separator: ", ")

        dndPeriod = try c.decodeIfPresent(DoNotDisturbPeriod.self, forKey: .dndPeriod) ?? .off
        dndUntil = try c.decodeIfPresent(Date.self, forKey: .dndUntil)
        keepUsageLocalOnly = try c.decodeIfPresent(Bool.self, forKey: .keepUsageLocalOnly) ?? true
        breakOverlayDisplayMode = try c.decodeIfPresent(BreakOverlayDisplayMode.self, forKey: .breakOverlayDisplayMode)
        todoListSelectedDay = try c.decodeIfPresent(Date.self, forKey: .todoListSelectedDay)
        todoCategories = try c.decodeIfPresent([TodoCategoryDefinition].self, forKey: .todoCategories)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try c.encode(theme, forKey: .theme)
        try c.encode(minWorkMinutes, forKey: .minWorkMinutes)
        try c.encode(maxWorkMinutes, forKey: .maxWorkMinutes)
        try c.encode(breakMinutes, forKey: .breakMinutes)
        try c.encode(reminderSound, forKey: .reminderSound)
        try c.encode(preferredLanguage, forKey: .preferredLanguage)
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encode(syncSystemFocus, forKey: .syncSystemFocus)
        try c.encode(autoPauseInMeetings, forKey: .autoPauseInMeetings)
        try c.encode(dndApps, forKey: .dndApps)
        try c.encode(dndCustomDayWindows, forKey: .dndCustomDayWindows)
        let syncedCaption = dndCustomDayWindows
            .map { FocusPauseSettings.formatDNDRangeCaption(startMinutes: $0.startMinute, endMinutes: $0.endMinute) }
            .joined(separator: ", ")
        try c.encode(syncedCaption, forKey: .dndTimeRanges)
        let first = dndCustomDayWindows.first
        try c.encode(first?.startMinute ?? FocusPauseSettings.defaultDNDCustomStartMinutes, forKey: .dndCustomStartMinutes)
        try c.encode(first?.endMinute ?? FocusPauseSettings.defaultDNDCustomEndMinutes, forKey: .dndCustomEndMinutes)
        try c.encode(dndPeriod, forKey: .dndPeriod)
        try c.encodeIfPresent(dndUntil, forKey: .dndUntil)
        try c.encode(keepUsageLocalOnly, forKey: .keepUsageLocalOnly)
        try c.encodeIfPresent(breakOverlayDisplayMode, forKey: .breakOverlayDisplayMode)
        try c.encodeIfPresent(todoListSelectedDay, forKey: .todoListSelectedDay)
        try c.encodeIfPresent(todoCategories, forKey: .todoCategories)
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")))
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

func formatDuration(_ seconds: Int) -> String {
    let safeSeconds = max(seconds, 0)
    let minutes = safeSeconds / 60
    let remainingSeconds = safeSeconds % 60
    return String(format: "%02d:%02d", minutes, remainingSeconds)
}
