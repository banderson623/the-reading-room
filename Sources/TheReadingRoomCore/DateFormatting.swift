import Foundation

public enum DateFormatting {
    /// `8/11/2026 @ 5:34 PM` in a US locale, `11/08/2026 @ 17:34` in a British
    /// one — numeric date and minutes, joined with "@", with the order, the
    /// separators, and the clock (12h vs 24h) following the reader's locale.
    public static func friendly(
        _ date: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        // Templates rather than fixed patterns: the fields are pinned (numeric
        // month/day, full year, hour and minute) but their arrangement is the
        // locale's own.
        dateFormatter.setLocalizedDateFormatFromTemplate("Mdyyyy")

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jmm")

        return dateFormatter.string(from: date) + " @ " + timeFormatter.string(from: date)
    }

    public static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
