import SwiftUI
#if canImport(Charts) && !targetEnvironment(macCatalyst)
import Charts
#endif

enum SettingsSection: String, CaseIterable, Identifiable {
    /// 原「通用」「提醒」合并为一页。
    case general
    case dnd
    case tasks
    case data
    case about

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .dnd: "moon.fill"
        case .tasks: "checkmark.square.fill"
        case .data: "externaldrive.fill"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale
    @State private var selection: SettingsSection = .general
    @State private var resetSettingsConfirm = false
    /// 勿扰「自定义」：展开后开始/结束时间选择器。
    @State private var showCustomDNDTimePickers = false

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 16) {
                brand
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Label(section.localizedTitle(locale: locale), systemImage: section.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(selection == section ? Color.blue.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            // 整行（含图标左侧留白）均可点击，避免只能点到文字
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(selection == section ? .blue : .primary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .frame(minWidth: 220)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .padding(44)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .onChange(of: store.settings) { _ in store.save() }
        .alert("FocusPause", isPresented: Binding(
            get: { store.settingsMessage != nil },
            set: { if !$0 { store.settingsMessage = nil } }
        )) {
            Button(Localized.string("common.ok", locale: locale), role: .cancel) {
                store.settingsMessage = nil
            }
        } message: {
            Text(store.settingsMessage ?? "")
        }
        .alert(
            Localized.string("settings.data.confirm.title", locale: locale),
            isPresented: $resetSettingsConfirm
        ) {
            Button(Localized.string("common.cancel", locale: locale), role: .cancel) {}
            Button(Localized.string("settings.general.reset.confirm", locale: locale), role: .destructive) {
                store.resetAllSettings()
            }
        } message: {
            Text(Localized.string("settings.data.confirm.reset_settings", locale: locale))
        }
        .onChange(of: store.settings.dndPeriod) { _ in
            if store.settings.dndPeriod != .custom {
                showCustomDNDTimePickers = false
            }
        }
        .onChange(of: selection) { _ in
            if selection != .dnd {
                showCustomDNDTimePickers = false
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 12) {
            FocusPauseBrandMark(size: 42)
            Text("FocusPause")
                .font(.system(.headline, design: .rounded).weight(.semibold))
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            SettingsPanel(title: nil) {
                Picker(selection: Binding(
                    get: { store.settings.preferredLanguage },
                    set: { store.setPreferredLanguage($0) }
                )) {
                    ForEach(AppLanguage.selectableCases, id: \.self) { lang in
                        Text(Localized.string(lang.localizationKey, locale: locale)).tag(lang)
                    }
                } label: {
                    Text(Localized.string("settings.language", locale: locale))
                }
                .pickerStyle(.menu)

                Divider()
                    .padding(.vertical, 10)

                Toggle(Localized.string("settings.launch_at_login", locale: locale), isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.setLaunchAtLogin($0) }
                ))
                Toggle(Localized.string("settings.show_menubar", locale: locale), isOn: $store.settings.showMenuBarIcon)

                Divider()
                    .padding(.vertical, 10)

                SliderRow(
                    title: Localized.string("settings.work_duration", locale: locale),
                    value: Binding(
                        get: { store.settings.minWorkMinutes },
                        set: { store.updateReminderDurations(minWork: $0) }
                    ),
                    range: 15...60
                )
                SliderRow(
                    title: Localized.string("settings.break_duration", locale: locale),
                    value: Binding(
                        get: { store.settings.breakMinutes },
                        set: { store.updateReminderDurations(breakMinutes: $0) }
                    ),
                    range: 5...20
                )
                Picker(Localized.string("settings.break_overlay_style", locale: locale), selection: Binding(
                    get: { store.settings.breakOverlayDisplayMode ?? .disguise },
                    set: { store.setBreakOverlayDisplayMode($0) }
                )) {
                    ForEach(BreakOverlayDisplayMode.allCases) { mode in
                        Text(mode.localizedTitle(locale: locale)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Text(Localized.string("settings.break_overlay_hint", locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker(Localized.string("settings.reminder_sound", locale: locale), selection: $store.settings.reminderSound) {
                    Text(Localized.string("reminder.sound.system", locale: locale)).tag("system")
                    Text(Localized.string("reminder.sound.gentle", locale: locale)).tag("gentle")
                    Text(Localized.string("reminder.sound.none", locale: locale)).tag("none")
                }

                Divider()
                    .padding(.vertical, 10)

                VStack(alignment: .leading, spacing: 8) {
                    Button(Localized.string("settings.data.reset", locale: locale), role: .destructive) {
                        resetSettingsConfirm = true
                    }
                    Text(Localized.string("settings.data.reset.footer", locale: locale))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        case .dnd:
            SettingsPanel(title: Localized.string("settings.section.dnd", locale: locale)) {
                Picker(Localized.string("settings.dnd.mode", locale: locale), selection: Binding(
                    get: { store.settings.dndPeriod },
                    set: { newPeriod in
                        guard newPeriod != store.settings.dndPeriod else { return }
                        if newPeriod == .custom {
                            store.selectDoNotDisturbCustomSegmentForSettings()
                        } else {
                            store.setDoNotDisturb(newPeriod, feedback: .settingsAlert)
                        }
                    }
                )) {
                    ForEach(DoNotDisturbPeriod.settingsPickerCases, id: \.self) { period in
                        Text(period.localizedPickerTitle(locale: locale)).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                if store.settings.dndPeriod == .custom {
                    if !showCustomDNDTimePickers {
                        Text(String(format: Localized.string("settings.dnd.saved_range_format", locale: locale), store.settings.dndTimeRanges))
                            .font(.subheadline)
                    .foregroundStyle(.secondary)
                    }
                    SettingsCustomDNDTimeRangeSection(
                        store: store,
                        locale: locale,
                        showTimePickers: $showCustomDNDTimePickers
                    )
                }
            }
        case .tasks:
            SettingsPanel(title: Localized.string("settings.section.tasks", locale: locale)) {
                SettingsTasksMainPanel(store: store)
            }
        case .data:
            SettingsPanel(title: Localized.string("settings.section.data", locale: locale)) {
                SettingsDataMainPanel(store: store)
            }
        case .about:
            SettingsPanel(title: Localized.string("settings.about.title", locale: locale)) {
                Text(Localized.string("settings.about.body", locale: locale))
                    .lineSpacing(4)
                Text(Localized.string("settings.about.version", locale: locale))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text(Localized.string("settings.about.feedback.intro", locale: locale))
                        .font(.subheadline)
                    if let mailURL = URL(string: "mailto:edsionli99@gmail.com?subject=FocusPause%20Feedback") {
                        Link(destination: mailURL) {
                            Text(Localized.string("settings.about.feedback.email_link", locale: locale))
                                .font(.body.weight(.medium))
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

// MARK: - 设置 · 勿扰自定义时段

/// `HH:mm` 文本输入 + 下拉菜单选时/分。
private struct SettingsDNDHMField: View {
    @Binding var hhmmText: String
    let locale: Locale

    var body: some View {
        HStack(spacing: 6) {
            TextField(Localized.string("settings.dnd.time_placeholder", locale: locale), text: $hhmmText)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 82)
                .textFieldStyle(.roundedBorder)

            Menu {
                Section {
                    ForEach(0 ..< 24, id: \.self) { h in
                        Button("\(String(format: "%02d", h))") {
                            applyHour(h)
                        }
                    }
                } header: {
                    Text(Localized.string("settings.dnd.pick_hour", locale: locale))
                }

                Section {
                    ForEach(0 ..< 60, id: \.self) { mi in
                        Button("\(String(format: "%02d", mi))") {
                            applyMinute(mi)
                        }
                    }
                } header: {
                    Text(Localized.string("settings.dnd.pick_minute", locale: locale))
                }
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .font(.title3)
                    .accessibilityLabel(Localized.string("settings.dnd.time_picker_menu_a11y", locale: locale))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
        }
    }

    private func applyHour(_ h: Int) {
        let mi = (Self.parseHM(hhmmText).map { $0 % 60 }) ?? 0
        hhmmText = String(format: "%02d:%02d", h, mi)
    }

    private func applyMinute(_ mi: Int) {
        guard let total = Self.parseHM(hhmmText) else {
            hhmmText = String(format: "%02d:%02d", 0, mi)
            return
        }
        let h = total / 60
        hhmmText = String(format: "%02d:%02d", h, mi)
    }

    /// - Returns: 从午夜起的分钟数；非法返回 `nil`。
    static func parseHM(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let mi = Int(parts[1].trimmingCharacters(in: .whitespaces)),
              (0 ..< 24).contains(h),
              (0 ..< 60).contains(mi) else { return nil }
        return h * 60 + mi
    }

    static func hhmm(fromMinutes minutes: Int) -> String {
        let cl = max(0, min(minutes, 24 * 60 - 1))
        return String(format: "%02d:%02d", cl / 60, cl % 60)
    }
}

private struct DNDDraftWindowRow: Identifiable {
    let id: UUID
    var startHHMM: String
    var endHHMM: String
}

private struct SettingsCustomDNDTimeRangeSection: View {
    @ObservedObject var store: FocusPauseStore
    let locale: Locale
    @Binding var showTimePickers: Bool

    @State private var draftRows: [DNDDraftWindowRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !showTimePickers {
                Button {
                    syncTextsFromStore()
                    showTimePickers = true
                } label: {
                    Text(Localized.string("settings.dnd.choose_range_button", locale: locale))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(draftRows.enumerated()), id: \.element.id) { index, element in
                        HStack(spacing: 10) {
                            SettingsDNDHMField(hhmmText: $draftRows[index].startHHMM, locale: locale)
                            Text("–")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)
                            SettingsDNDHMField(hhmmText: $draftRows[index].endHHMM, locale: locale)
                            if draftRows.count > 1 {
                                Button {
                                    draftRows.removeAll { $0.id == element.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .symbolRenderingMode(.hierarchical)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(Localized.string("settings.dnd.remove_segment_a11y", locale: locale))
                            }
                        }
                    }

                    Button {
                        draftRows.append(DNDDraftWindowRow(id: UUID(), startHHMM: "00:00", endHHMM: "00:00"))
                    } label: {
                        Label(Localized.string("settings.dnd.add_segment", locale: locale), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    HStack(spacing: 12) {
                        Button(Localized.string("settings.dnd.apply_times", locale: locale)) {
                            applyDraft()
                        }
                        .buttonStyle(.borderedProminent)
                        Button(Localized.string("common.cancel", locale: locale)) {
                            showTimePickers = false
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(Localized.string("settings.dnd.times_hint", locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            }
        }
        .padding(.top, 6)
    }

    private func syncTextsFromStore() {
        draftRows = store.settings.dndCustomDayWindows.map {
            DNDDraftWindowRow(
                id: UUID(),
                startHHMM: SettingsDNDHMField.hhmm(fromMinutes: $0.startMinute),
                endHHMM: SettingsDNDHMField.hhmm(fromMinutes: $0.endMinute)
            )
        }
        if draftRows.isEmpty {
            draftRows = [DNDDraftWindowRow(id: UUID(), startHHMM: "00:00", endHHMM: "00:00")]
        }
    }

    private func applyDraft() {
        var wins: [DNDCustomDayWindow] = []
        for row in draftRows {
            guard let sm = SettingsDNDHMField.parseHM(row.startHHMM),
                  let em = SettingsDNDHMField.parseHM(row.endHHMM) else {
                store.settingsMessage = Localized.string("message.dnd_custom_invalid", locale: locale)
                return
            }
            guard sm < em else {
                store.settingsMessage = Localized.string("message.dnd_custom_invalid_order", locale: locale)
                return
            }
            wins.append(DNDCustomDayWindow(startMinute: sm, endMinute: em))
        }
        store.applyCommittedCustomDNDWindows(wins, feedback: .settingsAlert)
        showTimePickers = false
    }
}

// MARK: - 设置 · 顶部分段 + 下方子页容器

/// 任务管理 / 数据管理等二级 Tab：上方分段控件，下方卡片式页面区域切换。
private struct SettingsSubpageContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

private struct SettingsInsightCard: View {
    let icon: String
    let iconTint: Color
    let title: String
    let value: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconTint)
                .frame(width: 38, height: 38)
                .background(iconTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 设置 · 任务（导出 + 分类）

private enum TasksSettingsInnerTab: String, CaseIterable, Identifiable {
    case details
    case categories

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .details: "settings.tasks.tab.details"
        case .categories: "settings.tasks.tab.categories"
        }
    }
}

private struct SettingsTasksMainPanel: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale
    @State private var innerTab: TasksSettingsInnerTab = .details

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsTasksInsightBlock(store: store)

            Picker(Localized.string("settings.tasks.tab.picker_a11y", locale: locale), selection: $innerTab) {
                ForEach(TasksSettingsInnerTab.allCases) { tab in
                    Text(Localized.string(tab.localizationKey, locale: locale)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            SettingsSubpageContainer {
                Group {
                    switch innerTab {
                    case .details:
                        SettingsTodoManagementBlock(store: store)
                    case .categories:
                        VStack(alignment: .leading, spacing: 12) {
                            Text(Localized.string("settings.tasks.categories_title", locale: locale))
                                .font(.headline)
                            Text(Localized.string("settings.tasks.categories_hint", locale: locale))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            SettingsTodoCategoriesEditor(store: store)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: innerTab)
            }
        }
    }
}

private struct SettingsTasksInsightBlock: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale

    private var doneCount: Int {
        store.todos.filter(\.isDone).count
    }

    private var totalCount: Int {
        store.todos.count
    }

    private var completionPercent: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(doneCount) / Double(totalCount) * 100).rounded())
    }

    private var categoryRows: [(label: String, color: Color, count: Int)] {
        let defs = store.settings.effectiveTodoCategories
        var raw: [UUID?: Int] = [:]
        for todo in store.todos {
            raw[todo.categoryId, default: 0] += 1
        }
        return raw.compactMap { key, count in
            guard count > 0 else { return nil }
            switch key {
            case nil:
                return (Localized.string("todo.uncategorized", locale: locale), Color.secondary.opacity(0.66), count)
            case let id?:
                if let def = defs.first(where: { $0.id == id }) {
                    return (def.localizedTitle(locale: locale), Color(hex: def.tintHex), count)
                }
                return (Localized.string("todo.uncategorized", locale: locale), Color.secondary.opacity(0.72), count)
            }
        }
        .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SettingsInsightCard(
                    icon: "checklist",
                    iconTint: .blue,
                    title: Localized.string("settings.tasks.insight.total", locale: locale),
                    value: "\(totalCount)"
                )
                SettingsInsightCard(
                    icon: "checkmark.circle.fill",
                    iconTint: .green,
                    title: Localized.string("settings.tasks.insight.done", locale: locale),
                    value: "\(doneCount)",
                    subtitle: "\(completionPercent)%"
                )
                SettingsInsightCard(
                    icon: "tag.fill",
                    iconTint: .purple,
                    title: Localized.string("settings.tasks.insight.categories", locale: locale),
                    value: "\(store.settings.effectiveTodoCategories.count)"
                )
            }

            if !categoryRows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(Localized.string("settings.tasks.insight.category_distribution", locale: locale), systemImage: "chart.bar.xaxis")
                        .font(.subheadline.weight(.semibold))
                    SettingsCategoryDistributionBar(rows: categoryRows)
                        .frame(height: 12)
                    HStack(spacing: 12) {
                        ForEach(Array(categoryRows.prefix(4).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 8, height: 8)
                                Text(row.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
            }
        }
    }
}

private struct SettingsCategoryDistributionBar: View {
    let rows: [(label: String, color: Color, count: Int)]

    var body: some View {
        GeometryReader { proxy in
            let total = max(rows.reduce(0) { $0 + $1.count }, 1)
            HStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(row.color)
                        .frame(width: max(3, proxy.size.width * CGFloat(row.count) / CGFloat(total)))
                        .accessibilityLabel("\(row.label) \(row.count)")
                }
            }
        }
    }
}

private enum TodoPeriodChoice: String, CaseIterable, Identifiable {
    case week
    case month
    case custom

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .week: "settings.tasks.period.week"
        case .month: "settings.tasks.period.month"
        case .custom: "settings.tasks.period.custom"
        }
    }
}

private struct SettingsTodoManagementBlock: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale

    @State private var period: TodoPeriodChoice = .week
    @State private var customStart = TodoExportDateBounds.defaultExportStart()
    @State private var customEnd = TodoExportDateBounds.defaultExportEnd()
    @State private var selectedTodoIds = Set<UUID>()
    @State private var exportFormat: TodoExportFormat = .csvExcel

    private var bounds: (min: Date, max: Date) {
        TodoExportDateBounds.bounds()
    }

    private func currentExportRange() -> (start: Date, end: Date) {
        switch period {
        case .week:
            return TodoExportDateBounds.thisWeekNormalizedRange()
        case .month:
            return TodoExportDateBounds.thisMonthNormalizedRange()
        case .custom:
            return TodoExportDateBounds.normalizedExportRange(start: customStart, end: customEnd)
        }
    }

    private var listedTodos: [TodoItem] {
        let r = currentExportRange()
        let raw = store.todosInExportWindow(startInclusive: r.start, endInclusive: r.end)
        // 归属日越晚越靠前；同一天内保持与原列表一致的相对顺序。
        return raw.enumerated().sorted { lhs, rhs in
            let dl = TodoDueDayFormatting.normalize(lhs.element.dueDay)
            let dr = TodoDueDayFormatting.normalize(rhs.element.dueDay)
            if dl != dr {
                return dl > dr
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// 按列表顺序、按「归属自然日」切分的分组（连续同一天的条目在同一组）。
    private var listedTodoSections: [(day: Date, items: [TodoItem])] {
        groupedSections(items: listedTodos)
    }

    private func groupedSections(items: [TodoItem]) -> [(day: Date, items: [TodoItem])] {
        guard !items.isEmpty else { return [] }
        var sections: [(day: Date, items: [TodoItem])] = []
        var currentDay = TodoDueDayFormatting.normalize(items[0].dueDay)
        var bucket: [TodoItem] = []
        for item in items {
            let d = TodoDueDayFormatting.normalize(item.dueDay)
            if d == currentDay {
                bucket.append(item)
            } else {
                sections.append((currentDay, bucket))
                currentDay = d
                bucket = [item]
            }
        }
        sections.append((currentDay, bucket))
        return sections
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Localized.string("settings.tasks.export_title", locale: locale))
                .font(.headline)

            Text(Localized.string("settings.tasks.export_selection_hint", locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker(Localized.string("settings.tasks.period.picker_a11y", locale: locale), selection: $period) {
                ForEach(TodoPeriodChoice.allCases) { p in
                    Text(Localized.string(p.localizationKey, locale: locale)).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if period == .custom {
                DatePicker(
                    Localized.string("settings.tasks.export.start_date", locale: locale),
                    selection: $customStart,
                    in: bounds.min ... bounds.max,
                    displayedComponents: [.date]
                )
                DatePicker(
                    Localized.string("settings.tasks.export.end_date", locale: locale),
                    selection: $customEnd,
                    in: bounds.min ... bounds.max,
                    displayedComponents: [.date]
                )
            }

            HStack(alignment: .firstTextBaseline) {
                Text(Localized.string("settings.tasks.list_title", locale: locale))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(Localized.string("settings.tasks.select_all", locale: locale)) {
                    selectedTodoIds = Set(listedTodos.map(\.id))
                }
                .disabled(listedTodos.isEmpty)
                Button(Localized.string("settings.tasks.select_none", locale: locale)) {
                    selectedTodoIds.removeAll()
                }
                .disabled(selectedTodoIds.isEmpty)
            }

            Group {
                if listedTodos.isEmpty {
                    Text(Localized.string("settings.tasks.list_empty", locale: locale))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(listedTodoSections, id: \.day) { section in
                                SettingsTodoDueDaySectionTab(day: section.day, locale: locale)
                                ForEach(section.items) { item in
                                    SettingsTodoExportSelectableRow(
                                        item: item,
                                        categories: store.settings.effectiveTodoCategories,
                                        locale: locale,
                                        isSelected: selectedTodoIds.contains(item.id),
                                        toggle: { toggleSelection(item.id) }
                                    )
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 380)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }

            Picker(Localized.string("settings.tasks.export.format", locale: locale), selection: $exportFormat) {
                ForEach(TodoExportFormat.allCases) { format in
                    Text(format.localizedTitle(locale: locale)).tag(format)
                }
            }
            .pickerStyle(.menu)

            Button(Localized.string("settings.tasks.export.button", locale: locale)) {
                let r = currentExportRange()
                let normalizedCustom = TodoExportDateBounds.normalizedExportRange(start: r.start, end: r.end)
                let limited = selectedTodoIds.isEmpty ? nil : selectedTodoIds
                store.exportTodos(
                    startDay: normalizedCustom.start,
                    endDay: normalizedCustom.end,
                    format: exportFormat,
                    limitedToTodoIds: limited
                )
                if period == .custom {
                    customStart = normalizedCustom.start
                    customEnd = normalizedCustom.end
                }
            }
        }
        .onChange(of: period) { _ in selectedTodoIds.removeAll() }
        .onChange(of: customStart) { _ in
            guard period == .custom else { return }
            selectedTodoIds.removeAll()
        }
        .onChange(of: customEnd) { _ in
            guard period == .custom else { return }
            selectedTodoIds.removeAll()
        }
        .onChange(of: store.todos) { _ in pruneSelection() }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedTodoIds.contains(id) {
            selectedTodoIds.remove(id)
        } else {
            selectedTodoIds.insert(id)
        }
    }

    private func pruneSelection() {
        let r = currentExportRange()
        let ids = Set(store.todosInExportWindow(startInclusive: r.start, endInclusive: r.end).map(\.id))
        selectedTodoIds = selectedTodoIds.intersection(ids)
    }
}

private struct SettingsTodoDueDaySectionTab: View {
    let day: Date
    let locale: Locale

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(TodoDueDayFormatting.calendarDateLabel(for: day, locale: locale))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("·")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TodoDueDayFormatting.relativeLabel(for: day, locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SettingsTodoExportSelectableRow: View {
    let item: TodoItem
    let categories: [TodoCategoryDefinition]
    let locale: Locale
    let isSelected: Bool
    let toggle: () -> Void

    private var categoryLabel: String {
        guard let cid = item.categoryId,
              let def = categories.first(where: { $0.id == cid }) else {
            return Localized.string("todo.uncategorized", locale: locale)
        }
        return def.localizedTitle(locale: locale)
    }

    private var titleText: String {
        let t = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? Localized.string("todo.placeholder", locale: locale) : t
    }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .font(.body)

                    HStack(spacing: 10) {
                        Text(item.priority.localizedTitle(locale: locale))
                        Text(categoryLabel)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, item.parentId == nil ? 0 : 14)
        .accessibilityLabel(Text(titleText))
        .accessibilityValue(Text(isSelected ? Localized.string("common.selected", locale: locale) : Localized.string("common.not_selected", locale: locale)))
    }
}

// MARK: - 设置 · 数据管理

private enum DataSettingsInnerTab: String, CaseIterable, Identifiable {
    case overview
    case usage
    case lifecycle

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .overview: "settings.data.tab.overview"
        case .usage: "settings.data.tab.usage"
        case .lifecycle: "settings.data.tab.lifecycle"
        }
    }
}

private struct SettingsDataMainPanel: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale
    @State private var innerTab: DataSettingsInnerTab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(Localized.string("settings.data.tab.picker_a11y", locale: locale), selection: $innerTab) {
                ForEach(DataSettingsInnerTab.allCases) { tab in
                    Text(Localized.string(tab.localizationKey, locale: locale)).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            SettingsSubpageContainer {
                Group {
                    switch innerTab {
                    case .overview:
                        SettingsDataOverviewBlock(store: store)
                    case .usage:
                        SettingsUsageManagementBlock(store: store)
                    case .lifecycle:
                        SettingsDataSettingsBlock(store: store)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: innerTab)
            }
        }
    }
}

private struct SettingsDataOverviewBlock: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale

    private var weekRange: (start: Date, end: Date) {
        let r = TodoExportDateBounds.thisWeekNormalizedRange()
        return TodoExportDateBounds.normalizedExportRange(start: r.start, end: r.end)
    }

    private var weekTodos: [TodoItem] {
        let r = weekRange
        return store.todosInExportWindow(startInclusive: r.start, endInclusive: r.end)
    }

    private var weekUsageMinutes: Int {
        let r = weekRange
        return store.usageManagementDailySections(startDay: r.start, endDay: r.end)
            .reduce(0) { partial, section in
                partial + section.1.reduce(0) { $0 + $1.minutes }
            }
    }

    private var categoryRows: [(label: String, color: Color, count: Int)] {
        let defs = store.settings.effectiveTodoCategories
        var raw: [UUID?: Int] = [:]
        for todo in store.todos {
            raw[todo.categoryId, default: 0] += 1
        }
        return raw.compactMap { key, count in
            guard count > 0 else { return nil }
            switch key {
            case nil:
                return (Localized.string("todo.uncategorized", locale: locale), Color.secondary.opacity(0.66), count)
            case let id?:
                if let def = defs.first(where: { $0.id == id }) {
                    return (def.localizedTitle(locale: locale), Color(hex: def.tintHex), count)
                }
                return (Localized.string("todo.uncategorized", locale: locale), Color.secondary.opacity(0.72), count)
            }
        }
        .sorted { $0.count > $1.count }
    }

    private var totalTasksCount: Int {
        store.todos.count
    }

    private func formatUsageMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else {
            return Localized.string("settings.data.overview.usage_none", locale: locale)
        }
        if minutes < 60 {
            return String(format: Localized.string("format.minutes_suffix", locale: locale), minutes)
        }
        let hours = minutes / 60
        let rest = minutes % 60
        if rest == 0 {
            return String(format: Localized.string("settings.data.overview.usage_hours_only", locale: locale), hours)
        }
        return String(format: Localized.string("settings.data.overview.usage_hours_minutes", locale: locale), hours, rest)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Localized.string("settings.data.overview.intro", locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                SettingsInsightCard(
                    icon: "list.bullet.rectangle.fill",
                    iconTint: .blue,
                    title: Localized.string("settings.data.overview.card.week_tasks", locale: locale),
                    value: "\(weekTodos.count)"
                )
                SettingsInsightCard(
                    icon: "checkmark.circle.fill",
                    iconTint: .green,
                    title: Localized.string("settings.data.overview.card.done_week", locale: locale),
                    value: "\(weekTodos.filter(\.isDone).count)"
                )
                SettingsInsightCard(
                    icon: "hourglass.circle.fill",
                    iconTint: .orange,
                    title: Localized.string("settings.data.overview.card.usage_week", locale: locale),
                    value: formatUsageMinutes(weekUsageMinutes)
                )
            }

            categoryDistributionSection
            weeklyUsageTrendSection
        }
    }

    @ViewBuilder
    private var categoryDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(Localized.string("settings.data.overview.categories_title", locale: locale), systemImage: "chart.pie.fill")
                .font(.subheadline.weight(.semibold))

            if categoryRows.isEmpty {
                Text(Localized.string("settings.data.overview.categories_empty", locale: locale))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        SettingsTodoCategoryDonutCanvas(slices: categoryRows.map { SettingsTodoCategorySlice(color: $0.color, count: $0.count) })
                            .frame(width: 164, height: 164)

                        VStack(spacing: 2) {
                            Text("\(totalTasksCount)")
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                            Text(Localized.string("settings.data.overview.categories_center", locale: locale))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .allowsHitTesting(false)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        let sum = Double(categoryRows.reduce(0) { $0 + $1.count })
                        ForEach(Array(categoryRows.enumerated()), id: \.offset) { _, row in
                            let pct = sum > 0 ? Int((Double(row.count) / sum * 100).rounded()) : 0
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 10, height: 10)
                                Text(row.label)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(pct)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("\(row.label), \(pct) percent")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(chartCardBackdrop)
            }
        }
    }

    @ViewBuilder
    private var weeklyUsageTrendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Localized.string("settings.data.overview.week_usage_spark_title", locale: locale), systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))

            let points = weeklySparkPoints
            Group {
                if points.allSatisfy({ $0.minutes == 0 }) {
                    Text(Localized.string("settings.data.usage.empty", locale: locale))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 28)
                } else {
#if canImport(Charts) && !targetEnvironment(macCatalyst)
                    let yLabel = Localized.string("settings.data.usage.chart.axis_minutes", locale: locale)
                    Chart(points) { point in
                        AreaMark(
                            x: .value("", point.date, unit: .day),
                            y: .value(yLabel, point.minutes)
                        )
                        .interpolationMethod(.catmullRom(alpha: 0.62))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("", point.date, unit: .day),
                            y: .value(yLabel, point.minutes)
                        )
                        .interpolationMethod(.catmullRom(alpha: 0.62))
                        .foregroundStyle(Color.accentColor)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7))
                    }
                    .frame(height: 160)
#else
                    Text(Localized.string("settings.data.overview.chart_unavailable_catalyst", locale: locale))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 28)
#endif
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(chartCardBackdrop)
        }
    }

    private var chartCardBackdrop: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
    }

    private struct WeeklyUsageSparkPoint: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    private var weeklySparkPoints: [WeeklyUsageSparkPoint] {
        let raw = TodoExportDateBounds.thisWeekNormalizedRange()
        let range = TodoExportDateBounds.normalizedExportRange(start: raw.start, end: raw.end)
        let sections = store.usageManagementDailySections(startDay: range.start, endDay: range.end)
        var byDay: [Date: Int] = [:]
        let calendar = Calendar.current

        for (day, items) in sections {
            let normalized = calendar.startOfDay(for: day)
            byDay[normalized, default: 0] += items.reduce(0) { $0 + $1.minutes }
        }

        var output: [WeeklyUsageSparkPoint] = []
        var cursor = range.start
        while cursor <= range.end {
            let day = calendar.startOfDay(for: cursor)
            output.append(WeeklyUsageSparkPoint(date: day, minutes: Double(byDay[day] ?? 0)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }
}

private struct SettingsTodoCategorySlice {
    var color: Color
    var count: Int
}

private struct SettingsTodoCategoryDonutCanvas: View {
    var slices: [SettingsTodoCategorySlice]

    var body: some View {
        Canvas { context, size in
            let total = slices.reduce(0) { $0 + $1.count }
            guard total > 0, size.width > 2, size.height > 2 else { return }

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - 1
            let innerRadius = outerRadius * 0.58
            var start = -CGFloat.pi / 2

            for slice in slices {
                let sweep = CGFloat(slice.count) / CGFloat(total) * 2 * CGFloat.pi
                let end = start + sweep

                var path = Path()
                path.move(to: CGPoint(x: center.x + outerRadius * cos(start), y: center.y + outerRadius * sin(start)))
                path.addArc(
                    center: center,
                    radius: outerRadius,
                    startAngle: Angle(radians: Double(start)),
                    endAngle: Angle(radians: Double(end)),
                    clockwise: false
                )
                path.addLine(to: CGPoint(x: center.x + innerRadius * cos(end), y: center.y + innerRadius * sin(end)))
                path.addArc(
                    center: center,
                    radius: innerRadius,
                    startAngle: Angle(radians: Double(end)),
                    endAngle: Angle(radians: Double(start)),
                    clockwise: true
                )
                path.closeSubpath()

                context.fill(path, with: .color(slice.color))
                context.stroke(path, with: .color(Color(nsColor: .textBackgroundColor).opacity(0.35)), lineWidth: 1)
                start = end
            }
        }
    }
}

private struct SettingsUsageManagementBlock: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale

    @State private var period: TodoPeriodChoice = .week
    @State private var customStart = TodoExportDateBounds.defaultExportStart()
    @State private var customEnd = TodoExportDateBounds.defaultExportEnd()

    private var bounds: (min: Date, max: Date) {
        TodoExportDateBounds.bounds()
    }

    private func currentExportRange() -> (start: Date, end: Date) {
        switch period {
        case .week:
            return TodoExportDateBounds.thisWeekNormalizedRange()
        case .month:
            return TodoExportDateBounds.thisMonthNormalizedRange()
        case .custom:
            return TodoExportDateBounds.normalizedExportRange(start: customStart, end: customEnd)
        }
    }

    private var usageSections: [(Date, [UsageItem])] {
        let r = currentExportRange()
        return store.usageManagementDailySections(startDay: r.start, endDay: r.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Localized.string("settings.data.usage.title", locale: locale))
                .font(.headline)

            Text(Localized.string("settings.data.usage.hint", locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker(Localized.string("settings.data.usage.period.a11y", locale: locale), selection: $period) {
                ForEach(TodoPeriodChoice.allCases) { p in
                    Text(Localized.string(p.localizationKey, locale: locale)).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if period == .custom {
                DatePicker(
                    Localized.string("settings.tasks.export.start_date", locale: locale),
                    selection: $customStart,
                    in: bounds.min ... bounds.max,
                    displayedComponents: [.date]
                )
                DatePicker(
                    Localized.string("settings.tasks.export.end_date", locale: locale),
                    selection: $customEnd,
                    in: bounds.min ... bounds.max,
                    displayedComponents: [.date]
                )
            }

#if canImport(Charts) && !targetEnvironment(macCatalyst)
            if !usageSections.isEmpty {
                usageTrendChartSection
            }
#endif

            Text(Localized.string("settings.data.usage.list_title", locale: locale))
                .font(.subheadline.weight(.semibold))

            Group {
                if usageSections.isEmpty {
                    Text(Localized.string("settings.data.usage.empty", locale: locale))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(usageSections, id: \.0) { section in
                                SettingsTodoDueDaySectionTab(day: section.0, locale: locale)
                                ForEach(section.1) { item in
                                    SettingsUsageManagementRow(item: item, locale: locale)
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 380)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }

            Button(Localized.string("settings.data.usage.export", locale: locale)) {
                let r = currentExportRange()
                let normalized = TodoExportDateBounds.normalizedExportRange(start: r.start, end: r.end)
                store.exportUsageCSV(startDay: normalized.start, endDay: normalized.end)
                if period == .custom {
                    customStart = normalized.start
                    customEnd = normalized.end
                }
            }
        }
    }

#if canImport(Charts) && !targetEnvironment(macCatalyst)
    private struct UsageTrendPoint: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
    }

    private var usageTrendPoints: [UsageTrendPoint] {
        usageSections
            .map { day, items in
                UsageTrendPoint(date: day, minutes: Double(items.reduce(0) { $0 + $1.minutes }))
            }
            .sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private var usageTrendChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Localized.string("settings.data.usage.chart.title", locale: locale), systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))

            let yLabel = Localized.string("settings.data.usage.chart.axis_minutes", locale: locale)
            Chart(usageTrendPoints) { point in
                BarMark(
                    x: .value("", point.date, unit: .day),
                    y: .value(yLabel, point.minutes)
                )
                .foregroundStyle(Color.accentColor.opacity(0.22))

                LineMark(
                    x: .value("", point.date, unit: .day),
                    y: .value(yLabel, point.minutes)
                )
                .interpolationMethod(.catmullRom(alpha: 0.62))
                .foregroundStyle(Color.accentColor)

                PointMark(
                    x: .value("", point.date, unit: .day),
                    y: .value(yLabel, point.minutes)
                )
                .foregroundStyle(Color.accentColor)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7))
            }
            .frame(height: 180)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
#endif
}

private struct SettingsUsageManagementRow: View {
    let item: UsageItem
    let locale: Locale

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(item.appName)
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(String(format: Localized.string("format.minutes_suffix", locale: locale), item.minutes))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private enum DataRetentionAgeBracket: String, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case year

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .week: "settings.data.age.week"
        case .month: "settings.data.age.month"
        case .threeMonths: "settings.data.age.three_months"
        case .year: "settings.data.age.year"
        }
    }

    func cutoffDate(referenceNow: Date = Date()) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceNow)
        switch self {
        case .week:
            return cal.date(byAdding: .day, value: -7, to: today) ?? today
        case .month:
            return cal.date(byAdding: .month, value: -1, to: today) ?? today
        case .threeMonths:
            return cal.date(byAdding: .month, value: -3, to: today) ?? today
        case .year:
            return cal.date(byAdding: .year, value: -1, to: today) ?? today
        }
    }
}

private enum DataCleanupConfirmKind: Identifiable, Hashable {
    case clearTodos(DataRetentionAgeBracket)
    case clearUsage(DataRetentionAgeBracket)
    case clearAllTodosAndUsage

    var id: String {
        switch self {
        case .clearTodos(let b): return "todos-\(b.rawValue)"
        case .clearUsage(let b): return "usage-\(b.rawValue)"
        case .clearAllTodosAndUsage: return "all-data"
        }
    }

    func message(locale: Locale) -> String {
        switch self {
        case .clearTodos(let b):
            return String(format: Localized.string("settings.data.confirm.todos", locale: locale), Localized.string(b.labelKey, locale: locale))
        case .clearUsage(let b):
            return String(format: Localized.string("settings.data.confirm.usage", locale: locale), Localized.string(b.labelKey, locale: locale))
        case .clearAllTodosAndUsage:
            return Localized.string("settings.data.confirm.all_data", locale: locale)
        }
    }
}

private struct SettingsDataSettingsBlock: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale
    @State private var cleanupConfirm: DataCleanupConfirmKind?
    @State private var todoRetentionBracket: DataRetentionAgeBracket = .month
    @State private var usageRetentionBracket: DataRetentionAgeBracket = .month

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(Localized.string("settings.data.local_only", locale: locale), isOn: $store.settings.keepUsageLocalOnly)
                Text(Localized.string("settings.data.lifecycle.local_only_hint", locale: locale))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Label(Localized.string("settings.data.lifecycle.cleanup_header", locale: locale), systemImage: "clock.badge.exclamationmark.fill")
                .font(.headline)
            Text(Localized.string("settings.data.lifecycle.cleanup_hint", locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)

            dataRetentionRow(
                icon: "checklist.checked",
                titleKey: "settings.data.row.todos.title",
                bracket: $todoRetentionBracket,
                onCommit: { cleanupConfirm = .clearTodos(todoRetentionBracket) }
            )

            Divider()

            dataRetentionRow(
                icon: "chart.bar.doc.horizontal",
                titleKey: "settings.data.row.usage.title",
                bracket: $usageRetentionBracket,
                onCommit: { cleanupConfirm = .clearUsage(usageRetentionBracket) }
            )

            Divider()

            Button(Localized.string("settings.data.cleanup.all.button", locale: locale), role: .destructive) {
                cleanupConfirm = .clearAllTodosAndUsage
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Localized.string("settings.data.cleanup.all.footer", locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .alert(
            Localized.string("settings.data.confirm.title", locale: locale),
            isPresented: Binding(
                get: { cleanupConfirm != nil },
                set: { newValue in
                    if !newValue { cleanupConfirm = nil }
                }
            )
        ) {
            Button(Localized.string("common.cancel", locale: locale), role: .cancel) {
                cleanupConfirm = nil
            }
            Button(Localized.string("settings.data.confirm.delete", locale: locale), role: .destructive) {
                guard let kind = cleanupConfirm else { return }
                executeCleanup(kind)
                cleanupConfirm = nil
            }
        } message: {
            Text(cleanupConfirm.map { $0.message(locale: locale) } ?? "")
        }
    }

    private func executeCleanup(_ kind: DataCleanupConfirmKind) {
        switch kind {
        case .clearTodos(let age):
            store.removeTodosWithDueDayBefore(age.cutoffDate())
        case .clearUsage(let age):
            store.removeUsageDailyBefore(age.cutoffDate())
        case .clearAllTodosAndUsage:
            store.clearAllTodosAndUsageData()
        }
    }

    @ViewBuilder
    private func dataRetentionRow(icon: String, titleKey: String, bracket: Binding<DataRetentionAgeBracket>, onCommit: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Label {
                Text(Localized.string(titleKey, locale: locale))
                    .font(.body)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(Localized.string("settings.data.retention.picker.a11y", locale: locale), selection: bracket) {
                ForEach(DataRetentionAgeBracket.allCases) { b in
                    Text(Localized.string(b.labelKey, locale: locale)).tag(b)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Button(Localized.string("settings.data.row.action", locale: locale)) {
                onCommit()
            }
            .buttonStyle(.bordered)
        }
        .accessibilityElement(children: .contain)
    }
}

struct SettingsPanel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: title == nil ? 18 : 22) {
            if let title {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            }
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(String(format: Localized.string("format.minutes_suffix", locale: locale), value))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            HStack {
                Text("\(range.lowerBound)")
                Spacer()
                Text("\((range.lowerBound + range.upperBound) / 2)")
                Spacer()
                Text(String(format: Localized.string("format.slider.max_minutes", locale: locale), range.upperBound))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 待办事件分类编辑

private struct SettingsTodoCategoriesEditor: View {
    @ObservedObject var store: FocusPauseStore
    @Environment(\.locale) private var locale
    @State private var draft: [TodoCategoryDefinition] = []
    @State private var acceptDraftPersistence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(draft) { category in
                HStack(alignment: .center, spacing: 12) {
                    Circle()
                        .fill(Color(hex: category.tintHex))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        .accessibilityHidden(true)

                    TextField(Localized.string("todo.cat.name_placeholder", locale: locale), text: titleBinding(for: category.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)

                    Button {
                        removeCategory(id: category.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.count <= 1)
                    .help(draft.count <= 1 ? Localized.string("todo.cat.delete_help_single", locale: locale) : Localized.string("todo.cat.delete_help", locale: locale))
                }
            }

            Button {
                let presets = TodoCategoryDefinition.presetTintHexes
                let hex = presets[draft.count % presets.count]
                draft.append(TodoCategoryDefinition(id: UUID(), title: Localized.string("todo.cat.new", locale: locale), tintHex: hex))
            } label: {
                Label(Localized.string("todo.cat.add", locale: locale), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .onAppear {
            acceptDraftPersistence = false
            store.ensureTodoCategoriesMaterializedFromDefaults()
            draft = store.settings.effectiveTodoCategories
            applyPresetBuiltinLocalizedTitles()
            acceptDraftPersistence = true
        }
        .onChange(of: locale.identifier) { _ in
            guard acceptDraftPersistence else { return }
            acceptDraftPersistence = false
            applyPresetBuiltinLocalizedTitles()
            acceptDraftPersistence = true
        }
        .onChange(of: draft) { _ in
            guard acceptDraftPersistence else { return }
            guard !draft.isEmpty else { return }
            store.updateTodoCategoryDefinitions(draft)
        }
    }

    /// 内置六项：若标题仍是某种语言的默认译名（含英文占位），则同步为当前界面语言；用户改过名的不覆盖。
    private func applyPresetBuiltinLocalizedTitles() {
        draft = draft.map { cat in
            guard TodoCategoryDefinition.isPresetBuiltin(id: cat.id) else { return cat }
            guard matchesKnownPresetDefaultTitle(cat) else { return cat }
            var c = cat
            c.title = cat.localizedTitle(locale: locale)
            return c
        }
    }

    private func matchesKnownPresetDefaultTitle(_ cat: TodoCategoryDefinition) -> Bool {
        var known: Set<String> = []
        for id in Self.presetTitleLocaleIdentifiers {
            known.insert(cat.localizedTitle(locale: Locale(identifier: id)))
        }
        if let def = TodoCategoryDefinition.systemDefaults.first(where: { $0.id == cat.id }) {
            known.insert(def.title)
        }
        return known.contains(cat.title)
    }

    private static let presetTitleLocaleIdentifiers = ["en", "zh-Hans", "es", "fr", "en-IN", "ja", "ru", "ko"]

    private func titleBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { draft.first(where: { $0.id == id })?.title ?? "" },
            set: { new in
                guard let i = draft.firstIndex(where: { $0.id == id }) else { return }
                draft[i].title = new
            }
        )
    }

    private func removeCategory(id: UUID) {
        guard draft.count > 1, let idx = draft.firstIndex(where: { $0.id == id }) else { return }
        draft.remove(at: idx)
    }
}
