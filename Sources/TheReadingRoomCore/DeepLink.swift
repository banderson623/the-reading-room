import Foundation

/// The `reading-room://` URL scheme — links that bring a document back up in
/// the app.
///
/// A link carries both halves of what a window shows: the file to read, and the
/// folder to show around it, so following one lands you on the same sidebar you
/// copied it from rather than on the file's immediate parent.
///
///     reading-room://open?path=/Users/me/notes/api/auth.md&root=/Users/me/notes
///
/// Written by hand, three shorter spellings also work: `path` alone (the folder
/// is inferred), a `path` relative to `root`, and the whole thing as the URL's
/// own path — `reading-room:///Users/me/notes/api/auth.md`.
///
/// Nothing here touches the file system: `target(of:)` reports what a link
/// points at, and the app decides whether it's still there.
public enum DeepLink {
    public static let scheme = "reading-room"
    /// The only host; `open` reads well in a link and leaves room for others.
    public static let openHost = "open"

    private enum Key {
        static let path = "path"
        static let root = "root"
    }

    /// Where a link points: the folder to open, and the file to select in it.
    /// Either can be absent — a link may name only a folder.
    public struct Target: Equatable, Sendable {
        public var file: URL?
        public var root: URL?

        public init(file: URL?, root: URL?) {
            self.file = file
            self.root = root
        }
    }

    // MARK: - Writing

    /// A link to `file`, read inside `root`.
    public static func url(file: URL, root: URL? = nil) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = openHost
        var query = "\(Key.path)=\(encode(file.path))"
        if let root {
            query += "&\(Key.root)=\(encode(root.path))"
        }
        components.percentEncodedQuery = query
        return components.url ?? URL(string: "\(scheme)://\(openHost)")!
    }

    public static func string(file: URL, root: URL? = nil) -> String {
        url(file: file, root: root).absoluteString
    }

    /// Everything a path may keep literal. Spaces, `#`, `&`, `+` and the rest
    /// are escaped, so a link survives being pasted anywhere a URL is expected.
    private static let literal = CharacterSet(
        charactersIn: "/-._~ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    )

    private static func encode(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: literal) ?? path
    }

    // MARK: - Reading

    /// What a link points at, or nil if the URL isn't one of ours or names
    /// nothing openable.
    public static func target(of url: URL) -> Target? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        // An unrecognized host is somebody else's URL shape, not a stray path.
        let host = components?.host ?? ""
        guard host.isEmpty || host == openHost else { return nil }

        let items = components?.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let found = items.first(where: { $0.name == name })?.value,
                  !found.isEmpty else { return nil }
            return found
        }

        let root = value(Key.root).flatMap(absolute)
        // With no `path` item, the URL's own path is the file — the hand-written
        // `reading-room:///Users/me/notes/api.md` form.
        let requested = value(Key.path) ?? (url.path.isEmpty ? nil : url.path)

        guard let requested else {
            // A folder on its own is still worth opening.
            return root.map { Target(file: nil, root: $0) }
        }

        // A relative path belongs to the folder the link names.
        let file: URL?
        if let absolute = absolute(requested) {
            file = absolute
        } else if let root {
            file = URL(fileURLWithPath: root.path + "/" + requested).standardizedFileURL
        } else {
            file = nil
        }

        guard let file else { return nil }
        return Target(file: file, root: root)
    }

    /// A path a link may refer to: absolute, or home-relative for anyone typing
    /// one by hand. `standardizingPath` also flattens `.` and `..`.
    private static func absolute(_ path: String) -> URL? {
        guard path.hasPrefix("/") || path.hasPrefix("~") else { return nil }
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: standardized)
    }
}
