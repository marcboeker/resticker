import Foundation

enum Formatting {
    /// Absolute times only. "2 days ago" hides whether a backup ran this morning
    /// or last night, which is exactly what you want to know.
    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "never" }
        let formatter: DateFormatter
        if Calendar.current.isDateInToday(date) {
            formatter = todayFormatter
        } else if Calendar.current.isDateInYesterday(date) {
            formatter = yesterdayFormatter
        } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter = thisYearFormatter
        } else {
            // Dates from another year need the year.
            formatter = otherYearFormatter
        }
        return formatter.string(from: date)
    }

    // The Restore window formats every snapshot's date, so the formatters are made once.
    private static let todayFormatter = dateFormatter("'today' HH:mm")
    private static let yesterdayFormatter = dateFormatter("'yesterday' HH:mm")
    private static let thisYearFormatter = dateFormatter("d MMM HH:mm")
    private static let otherYearFormatter = dateFormatter("d MMM yyyy HH:mm")

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        // The formatters live as long as the app, which can outlast a time zone change.
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = format
        return formatter
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    /// GB with two decimals above 1 GB, otherwise whole MB. Menu bar space is tight,
    /// so this stays shorter than ByteCountFormatter's output.
    static func remainingBytes(_ value: Int64) -> String {
        let gb = Double(value) / 1_000_000_000
        if gb > 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(value) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        let rest = total % 60
        if minutes < 60 { return "\(minutes)m \(rest)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
