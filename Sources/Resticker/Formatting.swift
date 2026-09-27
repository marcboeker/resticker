import Foundation

enum Formatting {
    /// Absolute times only. "2 days ago" hides whether a backup ran this morning
    /// or last night, which is exactly what you want to know.
    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "never" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "'today' HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'yesterday' HH:mm"
        } else {
            formatter.dateFormat = "d MMM HH:mm"
        }
        return formatter.string(from: date)
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
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
