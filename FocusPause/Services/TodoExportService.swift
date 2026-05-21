import Foundation
#if !targetEnvironment(macCatalyst)
import AppKit
import UniformTypeIdentifiers
#endif

enum TodoExportDateBounds {
    /// 相对「今天」前后各一年的可选归属日范围（自然日零点）。
    static func bounds(referenceNow: Date = Date()) -> (min: Date, max: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceNow)
        let minD = cal.date(byAdding: .year, value: -1, to: today) ?? today
        let maxD = cal.date(byAdding: .year, value: 1, to: today) ?? today
        return (TodoDueDayFormatting.normalize(minD), TodoDueDayFormatting.normalize(maxD))
    }

    static func clamp(_ day: Date, to bounds: (min: Date, max: Date)) -> Date {
        let n = TodoDueDayFormatting.normalize(day)
        return min(max(n, bounds.min), bounds.max)
    }

    static func defaultExportStart(referenceNow: Date = Date()) -> Date {
        let cal = Calendar.current
        let (minB, _) = bounds(referenceNow: referenceNow)
        let today = TodoDueDayFormatting.normalize(referenceNow)
        let proposed = cal.date(byAdding: .day, value: -30, to: today) ?? today
        return max(minB, proposed)
    }

    static func defaultExportEnd(referenceNow: Date = Date()) -> Date {
        TodoDueDayFormatting.normalize(referenceNow)
    }

    /// 将用户选择的起止日期钳到允许区间，并保证开始日 ≤ 结束日。
    static func normalizedExportRange(start: Date, end: Date, referenceNow: Date = Date()) -> (start: Date, end: Date) {
        let b = bounds(referenceNow: referenceNow)
        var s = clamp(start, to: b)
        var e = clamp(end, to: b)
        if s > e {
            swap(&s, &e)
        }
        return (s, e)
    }

    /// 当前日历周（周起始依系统 `Calendar`），归一化后的首尾自然日。
    static func thisWeekNormalizedRange(referenceNow: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceNow)
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
            let n = TodoDueDayFormatting.normalize(today)
            return (n, n)
        }
        let start = TodoDueDayFormatting.normalize(interval.start)
        let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        let end = TodoDueDayFormatting.normalize(lastDay)
        return (start, end)
    }

    /// 当前月首个自然日至最后一个自然日（归一化）。
    static func thisMonthNormalizedRange(referenceNow: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: referenceNow)
        guard let interval = cal.dateInterval(of: .month, for: today) else {
            let n = TodoDueDayFormatting.normalize(today)
            return (n, n)
        }
        let start = TodoDueDayFormatting.normalize(interval.start)
        let lastDay = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        let end = TodoDueDayFormatting.normalize(lastDay)
        return (start, end)
    }
}

struct TodoExportRow: Equatable {
    let dueISO: String
    let titleDisplay: String
    let doneLabel: String
    let categoryLabel: String
    let priorityLabel: String
    let levelLabel: String
}

enum TodoExportBuilder {
    /// 按列表展示顺序导出；`dueDay` 落在 `[startInclusive, endInclusive]`（均为归一化自然日）内的条目。
    static func makeRows(
        orderedTodos: [TodoItem],
        categories: [TodoCategoryDefinition],
        locale: Locale,
        startInclusive: Date,
        endInclusive: Date,
        limitedToTodoIds: Set<UUID>? = nil
    ) -> [TodoExportRow] {
        // 避免 duplicate category id 触发 Dictionary(uniqueKeysWithValues:) 运行时崩溃
        var catMap: [UUID: TodoCategoryDefinition] = [:]
        for c in categories {
            catMap[c.id] = c
        }
        let uncategorized = Localized.string("todo.uncategorized", locale: locale)

        func categoryLabel(for item: TodoItem) -> String {
            guard let cid = item.categoryId, let def = catMap[cid] else {
                return uncategorized
            }
            return def.localizedTitle(locale: locale)
        }

        let isoFormatter = DateFormatter()
        isoFormatter.calendar = Calendar(identifier: .gregorian)
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        isoFormatter.dateFormat = "yyyy-MM-dd"

        let start = TodoDueDayFormatting.normalize(startInclusive)
        let end = TodoDueDayFormatting.normalize(endInclusive)

        var rows: [TodoExportRow] = []
        for item in orderedTodos {
            if let lim = limitedToTodoIds, !lim.contains(item.id) {
                continue
            }
            let day = TodoDueDayFormatting.normalize(item.dueDay)
            if !TodoDueDayFormatting.isLongTermDueDay(day) {
                guard day >= start, day <= end else { continue }
            }

            let indent = item.parentId == nil ? "" : "    "
            let titleDisplay = indent + item.title
            let doneLabel = item.isDone
                ? Localized.string("todo.export.done.yes", locale: locale)
                : Localized.string("todo.export.done.no", locale: locale)
            let priorityLabel = item.priority.localizedTitle(locale: locale)
            let levelLabel = item.parentId == nil
                ? Localized.string("todo.export.level.root", locale: locale)
                : Localized.string("todo.export.level.subtask", locale: locale)

            rows.append(
                TodoExportRow(
                    dueISO: isoFormatter.string(from: day),
                    titleDisplay: titleDisplay,
                    doneLabel: doneLabel,
                    categoryLabel: categoryLabel(for: item),
                    priorityLabel: priorityLabel,
                    levelLabel: levelLabel
                )
            )
        }
        return rows
    }
}

enum TodoExportFilename {
    static func `default`(start: Date, end: Date, format: TodoExportFormat) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let a = fmt.string(from: TodoDueDayFormatting.normalize(start))
        let b = fmt.string(from: TodoDueDayFormatting.normalize(end))
        return "FocusPause-todos-\(a)-to-\(b).\(format.fileExtension)"
    }
}

enum TodoExportWriter {
    static func write(rows: [TodoExportRow], format: TodoExportFormat, to url: URL, locale: Locale) throws {
#if targetEnvironment(macCatalyst)
        _ = rows
        _ = format
        _ = url
        _ = locale
        throw NSError(domain: "FocusPause", code: 1)
#else
        switch format {
        case .markdown:
            try markdownString(rows: rows, locale: locale).write(to: url, atomically: true, encoding: .utf8)
        case .csvExcel:
            let data = Data(csvExcelBytes(rows: rows, locale: locale))
            try data.write(to: url, options: .atomic)
        case .pdf:
            let data = pdfData(rows: rows, locale: locale)
            try data.write(to: url, options: .atomic)
        }
#endif
    }

    private static func escapeMarkdownCell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
    }

    private static func markdownString(rows: [TodoExportRow], locale: Locale) -> String {
        let docTitle = Localized.string("todo.export.doc_title", locale: locale)
        let hDate = Localized.string("todo.export.header.date", locale: locale)
        let hTitle = Localized.string("todo.export.header.title", locale: locale)
        let hDone = Localized.string("todo.export.header.done", locale: locale)
        let hCat = Localized.string("todo.export.header.category", locale: locale)
        let hPri = Localized.string("todo.export.header.priority", locale: locale)
        let hLevel = Localized.string("todo.export.header.level", locale: locale)

        var lines: [String] = []
        lines.append("# \(docTitle)")
        lines.append("")
        lines.append("| \(hDate) | \(hTitle) | \(hDone) | \(hCat) | \(hPri) | \(hLevel) |")
        lines.append("| --- | --- | --- | --- | --- | --- |")
        for r in rows {
            lines.append(
                "| \(escapeMarkdownCell(r.dueISO)) | \(escapeMarkdownCell(r.titleDisplay)) | \(escapeMarkdownCell(r.doneLabel)) | \(escapeMarkdownCell(r.categoryLabel)) | \(escapeMarkdownCell(r.priorityLabel)) | \(escapeMarkdownCell(r.levelLabel)) |"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ field: String) -> String {
        let needsQuotes =
            field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
            || field.contains("\t")
        if needsQuotes {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    private static func csvExcelBytes(rows: [TodoExportRow], locale: Locale) -> [UInt8] {
        let hDate = Localized.string("todo.export.header.date", locale: locale)
        let hTitle = Localized.string("todo.export.header.title", locale: locale)
        let hDone = Localized.string("todo.export.header.done", locale: locale)
        let hCat = Localized.string("todo.export.header.category", locale: locale)
        let hPri = Localized.string("todo.export.header.priority", locale: locale)
        let hLevel = Localized.string("todo.export.header.level", locale: locale)

        let nl = "\r\n"
        var text = "\u{FEFF}"
        text += [hDate, hTitle, hDone, hCat, hPri, hLevel].map(csvEscape).joined(separator: ",")
        text += nl
        for r in rows {
            let cols = [r.dueISO, r.titleDisplay, r.doneLabel, r.categoryLabel, r.priorityLabel, r.levelLabel]
            text += cols.map(csvEscape).joined(separator: ",")
            text += nl
        }
        return Array(text.utf8)
    }

#if !targetEnvironment(macCatalyst)
    private static func pdfData(rows: [TodoExportRow], locale: Locale) -> Data {
        let hDate = Localized.string("todo.export.header.date", locale: locale)
        let hTitle = Localized.string("todo.export.header.title", locale: locale)
        let hDone = Localized.string("todo.export.header.done", locale: locale)
        let hCat = Localized.string("todo.export.header.category", locale: locale)
        let hPri = Localized.string("todo.export.header.priority", locale: locale)
        let hLevel = Localized.string("todo.export.header.level", locale: locale)
        let headerLine = [hDate, hTitle, hDone, hCat, hPri, hLevel].joined(separator: "\t")

        var bodyLines: [String] = [headerLine]
        for r in rows {
            let cols = [r.dueISO, r.titleDisplay, r.doneLabel, r.categoryLabel, r.priorityLabel, r.levelLabel]
            bodyLines.append(cols.map { $0.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\t"))
        }
        let body = bodyLines.joined(separator: "\n")

        let font = NSFont.systemFont(ofSize: 10)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let attributed = NSAttributedString(string: body, attributes: attrs)

        let tv = NSTextView(frame: .zero)
        tv.isEditable = false
        tv.isSelectable = false
        tv.drawsBackground = false
        tv.textStorage?.setAttributedString(attributed)
        tv.textContainerInset = NSSize(width: 24, height: 24)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)

        let layoutWidth: CGFloat = 520
        tv.frame = NSRect(x: 0, y: 0, width: layoutWidth, height: 400)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let used = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
        let height = max(ceil(used.height + tv.textContainerInset.height * 2 + 40), 600)
        tv.frame = NSRect(x: 0, y: 0, width: layoutWidth, height: height)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        return tv.dataWithPDF(inside: tv.bounds)
    }
#endif
}

#if !targetEnvironment(macCatalyst)
extension TodoExportFormat {
    var savePanelContentTypes: [UTType] {
        switch self {
        case .markdown:
            if let md = UTType(filenameExtension: "md") {
                return [md, .plainText]
            }
            return [.plainText]
        case .pdf:
            return [.pdf]
        case .csvExcel:
            // 部分系统上仅 commaSeparatedText 会导致保存面板异常，附带 plainText 更稳妥
            return [.commaSeparatedText, .plainText]
        }
    }
}
#endif
