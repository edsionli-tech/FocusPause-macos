import Foundation
import SwiftUI

enum Localized {
    /// 英文 `.lproj`，供缺失键回退（避免界面显示裸 key）。
    private static let englishLprojBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        return bundle
    }()

    /// 按给定 `Locale` 解析 `Localizable.strings`（用于 SwiftUI `.environment(\.locale)` 与 AppKit 菜单等）。
    static func string(_ key: String, locale: Locale) -> String {
        for bundle in bundles(for: locale) {
            let table = NSLocalizedString(key, tableName: nil, bundle: bundle, value: "\u{FFFD}", comment: "")
            if table != "\u{FFFD}" { return table }
        }
        if let en = englishLprojBundle {
            let fallback = NSLocalizedString(key, tableName: nil, bundle: en, value: "\u{FFFD}", comment: "")
            if fallback != "\u{FFFD}" { return fallback }
        }
        return key
    }

    private static func bundles(for locale: Locale) -> [Bundle] {
        var ordered: [Bundle] = []
        var seen = Set<ObjectIdentifier>()

        func append(_ bundle: Bundle) {
            let o = ObjectIdentifier(bundle)
            guard !seen.contains(o) else { return }
            seen.insert(o)
            ordered.append(bundle)
        }

        for code in lprojCandidateCodes(for: locale) {
            if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
               let b = Bundle(path: path) {
                append(b)
            }
        }
        append(.main)
        return ordered
    }

    /// 是否存在与该 `Locale` 匹配的 `.lproj`（用于「跟随系统」时判断是否回落到英语）。
    static func appBundleSupports(locale: Locale) -> Bool {
        for code in lprojCandidateCodes(for: locale) {
            if Bundle.main.path(forResource: code, ofType: "lproj") != nil {
                return true
            }
        }
        return false
    }

    private static func lprojCandidateCodes(for locale: Locale) -> [String] {
        var codes: [String] = []
        let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
        codes.append(id)

        let langCode =
            locale.language.languageCode?.identifier
            ?? id.split(separator: "-").first.map(String.init)
            ?? id

        if langCode != id, !codes.contains(langCode) {
            codes.append(langCode)
        }

        if langCode.hasPrefix("zh") {
            if !codes.contains("zh-Hans") { codes.append("zh-Hans") }
        }

        if langCode == "en" {
            if id.contains("-IN") {
                if !codes.contains("en-IN") { codes.append("en-IN") }
            }
            if !codes.contains("en") { codes.append("en") }
        }

        switch langCode {
        case "es":
            if !codes.contains("es") { codes.append("es") }
        case "fr":
            if !codes.contains("fr") { codes.append("fr") }
        case "ja":
            if !codes.contains("ja") { codes.append("ja") }
        case "ru":
            if !codes.contains("ru") { codes.append("ru") }
        case "ko":
            if !codes.contains("ko") { codes.append("ko") }
        default:
            break
        }

        return codes
    }
}

extension FocusPauseSettings {
    var resolvedLocale: Locale {
        if preferredLanguage == .system {
            let auto = Locale.autoupdatingCurrent
            return Localized.appBundleSupports(locale: auto) ? auto : Locale(identifier: "en")
        }
        return Locale(identifier: preferredLanguage.manualLocaleIdentifier)
    }
}

// MARK: - 根视图包装（语言切换后刷新子树）

struct FocusPauseLocalizedRoot<Content: View>: View {
    @ObservedObject var store: FocusPauseStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.locale, store.settings.resolvedLocale)
            .id(languageRefreshToken)
    }

    private var languageRefreshToken: String {
        let sysId = store.settings.preferredLanguage == .system
            ? Locale.autoupdatingCurrent.identifier
            : ""
        return "\(store.settings.preferredLanguage.rawValue)|\(sysId)|\(store.settings.resolvedLocale.identifier)"
    }
}

// MARK: - 枚举与格式化文案

extension FocusStatus {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .idle: Localized.string("focus.status.idle", locale: locale)
        case .focusing: Localized.string("focus.status.focusing", locale: locale)
        case .resting: Localized.string("focus.status.resting", locale: locale)
        case .paused: Localized.string("focus.status.paused", locale: locale)
        }
    }
}

extension TodoPriority {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .low: Localized.string("priority.low", locale: locale)
        case .normal: Localized.string("priority.normal", locale: locale)
        case .high: Localized.string("priority.high", locale: locale)
        }
    }
}

extension DoNotDisturbPeriod {
    func localizedPickerTitle(locale: Locale) -> String {
        switch self {
        case .morning: Localized.string("dnd.picker.morning", locale: locale)
        case .afternoon: Localized.string("dnd.picker.afternoon", locale: locale)
        case .allDay: Localized.string("dnd.picker.all_day", locale: locale)
        case .off: Localized.string("dnd.picker.off", locale: locale)
        case .custom: Localized.string("dnd.picker.custom", locale: locale)
        }
    }

    func localizedStatusTitle(locale: Locale) -> String {
        switch self {
        case .off: Localized.string("dnd.status.off", locale: locale)
        case .morning: Localized.string("dnd.status.morning", locale: locale)
        case .afternoon: Localized.string("dnd.status.afternoon", locale: locale)
        case .allDay: Localized.string("dnd.status.all_day", locale: locale)
        case .custom: Localized.string("dnd.status.custom", locale: locale)
        }
    }
}

extension BreakOverlayDisplayMode {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .standard: Localized.string("break.mode.standard", locale: locale)
        case .disguise: Localized.string("break.mode.disguise", locale: locale)
        }
    }
}

extension TodoExportFormat {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .markdown:
            return Localized.string("settings.tasks.export.format.markdown", locale: locale)
        case .pdf:
            return Localized.string("settings.tasks.export.format.pdf", locale: locale)
        case .csvExcel:
            return Localized.string("settings.tasks.export.format.csv_excel", locale: locale)
        }
    }
}

extension UsageScope {
    func localizedShortTitle(locale: Locale) -> String {
        switch self {
        case .currentFocus: Localized.string("usage.scope.cycle", locale: locale)
        case .today: Localized.string("usage.scope.today", locale: locale)
        }
    }

    func localizedPanelTitle(locale: Locale) -> String {
        switch self {
        case .currentFocus: Localized.string("usage.scope.cycle.panel", locale: locale)
        case .today: Localized.string("usage.scope.today.panel", locale: locale)
        }
    }

    func localizedPickerDescription(locale: Locale) -> String {
        switch self {
        case .currentFocus: Localized.string("usage.scope.cycle.desc", locale: locale)
        case .today: Localized.string("usage.scope.today.desc", locale: locale)
        }
    }
}

extension SettingsSection {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .general: Localized.string("settings.section.general", locale: locale)
        case .dnd: Localized.string("settings.section.dnd", locale: locale)
        case .tasks: Localized.string("settings.section.tasks", locale: locale)
        case .data: Localized.string("settings.section.data", locale: locale)
        case .about: Localized.string("settings.section.about", locale: locale)
        }
    }
}

extension TodoCategoryDefinition {
    func localizedTitle(locale: Locale) -> String {
        switch id.uuidString {
        case "11111111-1111-4111-8111-111111111101":
            return Localized.string("todo.cat.work", locale: locale)
        case "11111111-1111-4111-8111-111111111102":
            return Localized.string("todo.cat.life", locale: locale)
        case "11111111-1111-4111-8111-111111111103":
            return Localized.string("todo.cat.study", locale: locale)
        case "11111111-1111-4111-8111-111111111104":
            return Localized.string("todo.cat.health", locale: locale)
        case "11111111-1111-4111-8111-111111111105":
            return Localized.string("todo.cat.leisure", locale: locale)
        case "11111111-1111-4111-8111-111111111106":
            return Localized.string("todo.cat.other", locale: locale)
        default:
            return title
        }
    }
}
