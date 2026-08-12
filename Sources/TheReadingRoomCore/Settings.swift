import Foundation

/// Optional user settings from `~/.config/the-reading-room/config.json`.
///
/// Everything has a working default, so the file is only needed to change
/// something. It is re-read when a folder is opened.
public struct Settings: Sendable {
    /// Filenames (without extension) shown by their document title rather than
    /// their name. Add your own here.
    public var titleFromHeadingFor: Set<String>

    /// Whether to post a notification when files change in the open folder.
    public var notifyOnChange: Bool

    public static let `default` = Settings(
        titleFromHeadingFor: DocumentTitle.defaultGenericNames,
        notifyOnChange: true
    )

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/the-reading-room/config.json")
    }

    /// Reads the config file, falling back to defaults for anything missing or
    /// malformed — a typo in the config should never stop the app from opening.
    public static func load() -> Settings {
        var settings = Settings.default
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return settings
        }

        if let names = json["titleFromHeadingFor"] as? [String] {
            settings.titleFromHeadingFor = Set(
                names.map { $0.lowercased() }.filter { !$0.isEmpty }
            )
        }
        if let extra = json["alsoTitleFromHeadingFor"] as? [String] {
            settings.titleFromHeadingFor.formUnion(extra.map { $0.lowercased() })
        }
        if let notify = json["notifyOnChange"] as? Bool {
            settings.notifyOnChange = notify
        }
        return settings
    }

    /// The file written when the user asks to edit their settings.
    public static let template = """
    {
      "//": "The Reading Room settings. Reopen the folder to apply.",

      "//titleFromHeadingFor": "Files shown by their heading instead of their filename (no extension, lowercase). Replaces the defaults.",
      "titleFromHeadingFor": [
        "index", "_index", "readme", "home", "overview",
        "introduction", "intro", "about", "start", "main"
      ],

      "//alsoTitleFromHeadingFor": "Names to add to the list above instead of replacing it.",
      "alsoTitleFromHeadingFor": [],

      "//notifyOnChange": "Post a notification when a file in the open folder changes.",
      "notifyOnChange": true
    }

    """
}
