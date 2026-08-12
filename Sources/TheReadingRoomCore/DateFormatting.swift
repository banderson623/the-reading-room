import Foundation

public enum DateFormatting {
    /// `8/11/2026 @ 5:34 PM`, in the viewer's local time zone.
    public static func friendly(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        // A fixed pattern, so the format doesn't shift with system settings —
        // but rendered with the user's own locale symbols for AM/PM.
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d/yyyy '@' h:mm a"
        return formatter.string(from: date)
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
