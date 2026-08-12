import Foundation

/// Bundled CSS/JS. Loaded from `Contents/Resources` in the built app, or from
/// the source tree when running via `swift run` during development.
public enum Resources {
    public static let markdownCSS = load("github-markdown.css")
    public static let appJS = load("app.js")
    public static let highlightJS = load("highlight.min.js")

    /// Optional user stylesheet, appended after the built-in CSS. Read fresh on
    /// every render so edits show up on reload.
    public static var userCSS: String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/the-reading-room/custom.css")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    public static var userCSSPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/the-reading-room/custom.css")
    }

    private static func load(_ name: String) -> String {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent("Resources/\(name)"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name)"),
        ].compactMap { $0 }

        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        }
        return ""
    }
}
