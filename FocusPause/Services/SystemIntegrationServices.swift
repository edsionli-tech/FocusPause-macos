#if !targetEnvironment(macCatalyst)
import AppKit
import ApplicationServices
import ServiceManagement
#endif
import Foundation

struct AccessibilityPermissionService {
    static var isTrusted: Bool {
#if targetEnvironment(macCatalyst)
        false
#else
        AXIsProcessTrusted()
#endif
    }

    static func requestPermissionPrompt() {
#if !targetEnvironment(macCatalyst)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
#endif
    }
}

final class AppUsageAuditor {
    private let defaults = UserDefaults.standard
    private let dailyPrefix = "focuspause.usage.daily."
    private var dailySeconds: [String: Int] = [:]
    private var currentCycleSeconds: [String: Int] = [:]
    private var activeDayKey: String

#if !targetEnvironment(macCatalyst)
    private static let legacyLookupLock = NSLock()
    /// 小写显示名 → bundle id（首次快照或写入前填充）。
    private static var legacyDisplayNameToBundleID: [String: String]?
#endif

    init() {
        activeDayKey = Self.dayKey(for: Date())
        dailySeconds = Self.loadNormalizedDailySeconds(defaults: defaults, dailyPrefix: dailyPrefix, dayKey: activeDayKey)
    }

    func resetCurrentCycle() {
        currentCycleSeconds = [:]
    }

    func recordActiveSecond(countForCurrentCycle: Bool) {
        rotateDayIfNeeded()
        guard let storageKey = Self.storageKeyForFrontmostApp(),
              !Self.isSelf(storageKey: storageKey) else {
            return
        }

        dailySeconds[storageKey, default: 0] += 1
        if countForCurrentCycle {
            currentCycleSeconds[storageKey, default: 0] += 1
        }
        defaults.set(dailySeconds, forKey: dailyPrefix + activeDayKey)
    }

    func snapshot(for scope: UsageScope) -> [UsageItem] {
#if !targetEnvironment(macCatalyst)
        Self.populateLegacyLookupCacheIfNeeded()
#endif
        let source = scope == .today ? dailySeconds : currentCycleSeconds
        let filtered = source.filter { !Self.shouldExcludeUsageStorageKey($0.key) }
        return Self.usageItems(from: filtered, limit: 8)
    }

    /// 读取多日归档并按自然日聚合（仅含当日有记录的日期）；组内按耗时降序，`items` 含当日全部应用。
    func storedDailyBreakdown(from startInclusive: Date, through endInclusive: Date) -> [(Date, [UsageItem])] {
#if targetEnvironment(macCatalyst)
        _ = startInclusive
        _ = endInclusive
        return []
#else
        rotateDayIfNeeded()
        let cal = Calendar.current
        let start = cal.startOfDay(for: startInclusive)
        let end = cal.startOfDay(for: endInclusive)
        guard start <= end else { return [] }
        var out: [(Date, [UsageItem])] = []
        var day = start
        while true {
            let key = Self.dayKey(for: day)
            let dict = readNormalizedDailyDict(dayKey: key)
            let items = Self.usageItems(from: dict, limit: nil)
            if !items.isEmpty {
                out.append((day, items))
            }
            guard day < end else { break }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out.sorted { $0.0 > $1.0 }
#endif
    }

    /// `yyyy-MM-dd` 至 `yyyy-MM-dd`（含）的 CSV，`Date,App,Seconds,Minutes`。
    func usageCSVString(from startInclusive: Date, through endInclusive: Date) -> String {
#if targetEnvironment(macCatalyst)
        _ = startInclusive
        _ = endInclusive
        return "Date,App,Seconds,Minutes\n"
#else
        rotateDayIfNeeded()
        Self.populateLegacyLookupCacheIfNeeded()
        let cal = Calendar.current
        let start = cal.startOfDay(for: startInclusive)
        let end = cal.startOfDay(for: endInclusive)
        guard start <= end else {
            return "Date,App,Seconds,Minutes\n"
        }
        var lines = ["Date,App,Seconds,Minutes"]
        var day = start
        while true {
            let dayStr = Self.dayKey(for: day)
            let dict = readNormalizedDailyDict(dayKey: dayStr)
            let sorted = dict.sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            for (storageKey, seconds) in sorted {
                let identity = Self.resolveIdentity(storageKey: storageKey)
                let label = identity.displayName.replacingOccurrences(of: "\"", with: "\"\"")
                let minutes = String(format: "%.2f", Double(seconds) / 60.0)
                lines.append("\(dayStr),\"\(label)\",\(seconds),\(minutes)")
            }
            guard day < end else { break }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return lines.joined(separator: "\r\n") + "\r\n"
#endif
    }

    /// 删除「归属自然日」早于 `cutoffDay`（不含当日零点）的每日归档。
    @discardableResult
    func removeDailyUsageEntries(beforeCutoffDay cutoffDay: Date) -> Int {
#if targetEnvironment(macCatalyst)
        _ = cutoffDay
        return 0
#else
        rotateDayIfNeeded()
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cutoffDay)
        let keys = Self.allStoredDailyDayKeys(defaults: defaults, dailyPrefix: dailyPrefix)
        var removed = 0
        for dayKey in keys {
            guard let d = Self.date(fromDayKey: dayKey) else { continue }
            if cal.startOfDay(for: d) < cutoff {
                defaults.removeObject(forKey: dailyPrefix + dayKey)
                removed += 1
            }
        }
        reloadDailySecondsAfterMutation()
        return removed
#endif
    }

    func removeAllDailyUsageEntriesAndCycle() {
#if targetEnvironment(macCatalyst)
        currentCycleSeconds = [:]
        dailySeconds = [:]
#else
        rotateDayIfNeeded()
        for dayKey in Self.allStoredDailyDayKeys(defaults: defaults, dailyPrefix: dailyPrefix) {
            defaults.removeObject(forKey: dailyPrefix + dayKey)
        }
        currentCycleSeconds = [:]
        dailySeconds = [:]
        activeDayKey = Self.dayKey(for: Date())
        dailySeconds = Self.loadNormalizedDailySeconds(defaults: defaults, dailyPrefix: dailyPrefix, dayKey: activeDayKey)
#endif
    }

    private func reloadDailySecondsAfterMutation() {
#if !targetEnvironment(macCatalyst)
        rotateDayIfNeeded()
        dailySeconds = Self.loadNormalizedDailySeconds(defaults: defaults, dailyPrefix: dailyPrefix, dayKey: activeDayKey)
#endif
    }

#if !targetEnvironment(macCatalyst)
    private func readNormalizedDailyDict(dayKey: String) -> [String: Int] {
        Self.populateLegacyLookupCacheIfNeeded()
        let raw = defaults.dictionary(forKey: dailyPrefix + dayKey) as? [String: Int] ?? [:]
        let merged = Self.mergedStorageKeys(raw)
        return merged.filter { !Self.shouldExcludeUsageStorageKey($0.key) }
    }

    private static func usageItems(from dict: [String: Int], limit: Int?) -> [UsageItem] {
        Self.populateLegacyLookupCacheIfNeeded()
        let sorted = dict.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value > rhs.value
        }
        let slice: [(String, Int)]
        if let limit {
            slice = Array(sorted.prefix(limit))
        } else {
            slice = sorted
        }
        return slice.map { storageKey, seconds in
            let identity = Self.resolveIdentity(storageKey: storageKey)
            return UsageItem(
                appName: identity.displayName,
                minutes: max(1, Int(ceil(Double(seconds) / 60.0))),
                tintHex: Self.colorHex(for: identity.displayName),
                symbolName: Self.symbolName(for: identity.displayName),
                bundleIdentifier: identity.bundleIdentifier
            )
        }
    }

    private static func allStoredDailyDayKeys(defaults: UserDefaults, dailyPrefix: String) -> [String] {
        defaults.dictionaryRepresentation().keys.compactMap { fullKey in
            guard fullKey.hasPrefix(dailyPrefix) else { return nil }
            return String(fullKey.dropFirst(dailyPrefix.count))
        }
    }

    private static func date(fromDayKey dayKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }
#else
    private static func usageItems(from dict: [String: Int], limit: Int?) -> [UsageItem] {
        let sorted = dict.sorted { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }
        let slice: [(String, Int)]
        if let limit {
            slice = Array(sorted.prefix(limit))
        } else {
            slice = sorted
        }
        return slice.map { storageKey, seconds in
            let identity = Self.resolveIdentity(storageKey: storageKey)
            return UsageItem(
                appName: identity.displayName,
                minutes: max(1, Int(ceil(Double(seconds) / 60.0))),
                tintHex: Self.colorHex(for: identity.displayName),
                symbolName: Self.symbolName(for: identity.displayName),
                bundleIdentifier: identity.bundleIdentifier
            )
        }
    }
#endif

    func exportTodayCSV() throws -> URL {
        rotateDayIfNeeded()
#if !targetEnvironment(macCatalyst)
        Self.populateLegacyLookupCacheIfNeeded()
#endif
        let rows = dailySeconds
            .filter { !Self.shouldExcludeUsageStorageKey($0.key) }
            .sorted { $0.value > $1.value }
            .map { storageKey, seconds in
                let identity = Self.resolveIdentity(storageKey: storageKey)
                let minutes = Double(seconds) / 60.0
                let label = identity.displayName
                return "\"\(label.replacingOccurrences(of: "\"", with: "\"\""))\",\(seconds),\(String(format: "%.2f", minutes))"
            }

        let csv = (["App,Seconds,Minutes"] + rows).joined(separator: "\n")
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = downloads.appendingPathComponent("focuspause-usage-\(activeDayKey).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func resetUsageData() {
        removeAllDailyUsageEntriesAndCycle()
    }

    private func rotateDayIfNeeded() {
        let today = Self.dayKey(for: Date())
        guard today != activeDayKey else { return }
        activeDayKey = today
        dailySeconds = Self.loadNormalizedDailySeconds(defaults: defaults, dailyPrefix: dailyPrefix, dayKey: activeDayKey)
    }

#if !targetEnvironment(macCatalyst)
    /// 应用图标（与系统一致的 `.app` 图标）；找不到时 UI 回退 SF Symbol。
    static func resolvedWorkspaceIcon(for item: UsageItem) -> NSImage? {
        Self.populateLegacyLookupCacheIfNeeded()
        if let bid = item.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let bid = bundleIdentifier(forLegacyDisplayName: item.appName),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return nil
    }

    /// 不应计入「应用耗时」的前台进程（登录界面、屏保等），避免与普通 App 混在一起。
    private static let excludedUsageBundleIdentifiers: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine"
    ]

    private static func shouldExcludeUsageTracking(bundleIdentifier: String?, localizedName: String?) -> Bool {
        if let bid = bundleIdentifier, !bid.isEmpty, excludedUsageBundleIdentifiers.contains(bid) {
            return true
        }
        let trimmed = localizedName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if trimmed == "loginwindow" {
            return true
        }
        return false
    }

    /// 按存储键判断是否排除（支持 bundle id 与旧版「显示名称」存档）。
    private static func shouldExcludeUsageStorageKey(_ storageKey: String) -> Bool {
        if isLikelyBundleIdentifier(storageKey), excludedUsageBundleIdentifiers.contains(storageKey) {
            return true
        }
        let identity = resolveIdentity(storageKey: storageKey)
        if let bid = identity.bundleIdentifier, !bid.isEmpty, excludedUsageBundleIdentifiers.contains(bid) {
            return true
        }
        return shouldExcludeUsageTracking(bundleIdentifier: nil, localizedName: identity.displayName)
    }

    private static func storageKeyForFrontmostApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        guard let name = app.localizedName else { return nil }
        if isSelfRunning(app) { return nil }
        if shouldExcludeUsageTracking(bundleIdentifier: app.bundleIdentifier, localizedName: name) {
            return nil
        }
        if let bid = app.bundleIdentifier, !bid.isEmpty {
            return bid
        }
        return name
    }

    private static func isSelfRunning(_ app: NSRunningApplication) -> Bool {
        if let bid = app.bundleIdentifier, bid == Bundle.main.bundleIdentifier {
            return true
        }
        if let name = app.localizedName {
            return name == "FocusPause" || name == ProcessInfo.processInfo.processName
        }
        return false
    }

    private static func isSelf(storageKey: String) -> Bool {
        if storageKey == Bundle.main.bundleIdentifier {
            return true
        }
        let identity = resolveIdentity(storageKey: storageKey)
        let name = identity.displayName
        return name == "FocusPause" || name == ProcessInfo.processInfo.processName
    }

    private static func loadNormalizedDailySeconds(defaults: UserDefaults, dailyPrefix: String, dayKey: String) -> [String: Int] {
        Self.populateLegacyLookupCacheIfNeeded()
        let raw = defaults.dictionary(forKey: dailyPrefix + dayKey) as? [String: Int] ?? [:]
        let merged = mergedStorageKeys(raw)
        let filtered = merged.filter { !shouldExcludeUsageStorageKey($0.key) }
        if merged != raw || filtered.count != merged.count {
            defaults.set(filtered, forKey: dailyPrefix + dayKey)
        }
        return filtered
    }

    private static func mergedStorageKeys(_ raw: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (key, secs) in raw {
            let canonical = canonicalStorageKey(key)
            result[canonical, default: 0] += secs
        }
        return result
    }

    private static func canonicalStorageKey(_ key: String) -> String {
        if isLikelyBundleIdentifier(key) {
            return key
        }
        if let bid = bundleIdentifier(forLegacyDisplayName: key) {
            return bid
        }
        return key
    }

    /// Bundle ID 通常形如 `com.apple.Safari`，旧版仅存本地化名称。
    private static func isLikelyBundleIdentifier(_ string: String) -> Bool {
        guard string.contains(".") else { return false }
        guard !string.contains(" "), !string.contains("/") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return string.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func bundleIdentifier(forLegacyDisplayName displayName: String) -> String? {
        Self.populateLegacyLookupCacheIfNeeded()
        let key = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return legacyDisplayNameToBundleID?[key]
    }

    static func populateLegacyLookupCacheIfNeeded() {
        legacyLookupLock.lock()
        defer { legacyLookupLock.unlock() }
        if legacyDisplayNameToBundleID != nil {
            return
        }
        var map: [String: String] = [:]
        let workspace = NSWorkspace.shared
        for app in workspace.runningApplications {
            guard let bid = app.bundleIdentifier, !bid.isEmpty,
                  let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                continue
            }
            map[name.lowercased()] = bid
        }

        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            URL(fileURLWithPath: NSHomeDirectory() + "/Applications")
        ]
        for root in roots {
            guard let urls = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let bid = bundle.bundleIdentifier ?? ""
                guard !bid.isEmpty else { continue }
                let candidates: [String] = [
                    bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
                    bundle.localizedInfoDictionary?["CFBundleName"] as? String,
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                    bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
                    url.deletingPathExtension().lastPathComponent
                ]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

                for cand in candidates {
                    map[cand.lowercased()] = bid
                }
            }
        }
        legacyDisplayNameToBundleID = map
    }

    private static func resolveIdentity(storageKey: String) -> (displayName: String, bundleIdentifier: String?) {
        if isLikelyBundleIdentifier(storageKey) {
            let bundleId = storageKey
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
                let shortName = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
                return (shortName, bundleId)
            }
            let bundle = Bundle(url: url)
            let display = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            return (display, bundleId)
        }

        if let bid = bundleIdentifier(forLegacyDisplayName: storageKey),
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let bundle = Bundle(url: url)
            let display = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
                ?? storageKey
            return (display, bid)
        }

        return (storageKey, bundleIdentifier(forLegacyDisplayName: storageKey))
    }

#else

    private static func shouldExcludeUsageStorageKey(_ storageKey: String) -> Bool {
        false
    }

    private static func storageKeyForFrontmostApp() -> String? {
        nil
    }

    private static func isSelf(storageKey: String) -> Bool {
        storageKey == "FocusPause"
    }

    private static func resolveIdentity(storageKey: String) -> (displayName: String, bundleIdentifier: String?) {
        (storageKey, nil)
    }

    private static func loadNormalizedDailySeconds(defaults: UserDefaults, dailyPrefix: String, dayKey: String) -> [String: Int] {
        defaults.dictionary(forKey: dailyPrefix + dayKey) as? [String: Int] ?? [:]
    }

#endif

    private static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func colorHex(for appName: String) -> String {
        let palette = ["#2F7AF8", "#35A7FF", "#7A5CFF", "#34C759", "#FF9F0A", "#FF375F", "#64D2FF", "#BF5AF2"]
        let index = abs(appName.hashValue) % palette.count
        return palette[index]
    }

    private static func symbolName(for appName: String) -> String {
        let lowercased = appName.lowercased()
        if lowercased.contains("safari") { return "safari.fill" }
        if lowercased.contains("xcode") { return "hammer.fill" }
        if lowercased.contains("slack") { return "number" }
        if lowercased.contains("terminal") { return "terminal.fill" }
        if lowercased.contains("cursor") { return "cursorarrow.click.2" }
        if lowercased.contains("wechat") || appName.contains("微信") { return "message.fill" }
        return "app.fill"
    }
}

struct LaunchAtLoginService {
    static func setEnabled(_ isEnabled: Bool) -> String? {
#if targetEnvironment(macCatalyst)
        return "Mac Catalyst 目标暂不支持登录项配置。"
#else
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "开机自启动设置失败：\(error.localizedDescription)"
        }
#endif
    }
}

final class GlobalHotkeyController {
#if !targetEnvironment(macCatalyst)
    private var globalMonitor: Any?
    private var localMonitor: Any?
#endif
    private let onPanic: () -> Void

    init(onPanic: @escaping () -> Void) {
        self.onPanic = onPanic
    }

    func start() {
#if !targetEnvironment(macCatalyst)
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handle(event) == true {
                return nil
            }
            return event
        }
#endif
    }

    func stop() {
#if !targetEnvironment(macCatalyst)
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
#endif
    }

#if !targetEnvironment(macCatalyst)
    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains([.command, .option]),
              event.charactersIgnoringModifiers?.lowercased() == "w" else {
            return false
        }
        DispatchQueue.main.async { [onPanic] in
            onPanic()
        }
        return true
    }
#endif

    deinit {
        stop()
    }
}
