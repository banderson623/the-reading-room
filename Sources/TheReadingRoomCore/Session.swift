import Foundation

/// One window, as it was when the app last quit.
public struct WindowSession: Codable, Equatable, Sendable {
    public var root: String
    public var selection: String?
    public var scroll: Double

    public init(root: String, selection: String? = nil, scroll: Double = 0) {
        self.root = root
        self.selection = selection
        self.scroll = scroll
    }

    public init(root: URL, selection: URL? = nil, scroll: Double = 0) {
        self.init(root: root.path, selection: selection?.path, scroll: scroll)
    }

    public var rootURL: URL { URL(fileURLWithPath: root) }
    public var selectionURL: URL? { selection.map { URL(fileURLWithPath: $0) } }
}

/// Everything that was on screen at quit, so relaunching picks up where you
/// left off: the same folders, in the same windows, on the same files, scrolled
/// to the same place.
public struct Session: Codable, Equatable, Sendable {
    public var windows: [WindowSession]

    public static let empty = Session(windows: [])

    /// A runaway session shouldn't open fifty windows at launch.
    public static let maximumWindows = 8

    public init(windows: [WindowSession]) {
        self.windows = windows
    }

    /// Drops folders that are gone, collapses duplicates (one window per
    /// directory), and caps the count. Restoring is best-effort: a folder that
    /// moved or was deleted since last launch is quietly skipped.
    public func sanitized(
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Session {
        var seen: Set<String> = []
        var kept: [WindowSession] = []

        for var window in windows {
            guard exists(window.root), !seen.contains(window.root) else { continue }
            seen.insert(window.root)
            if let selection = window.selection, !exists(selection) {
                // The folder is still there; just not that file.
                window.selection = nil
                window.scroll = 0
            }
            kept.append(window)
            if kept.count == Self.maximumWindows { break }
        }
        return Session(windows: kept)
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Anything unreadable becomes an empty session — a corrupt record should
    /// cost you your window layout, not your launch.
    public static func decoded(from data: Data?) -> Session {
        guard let data, let session = try? JSONDecoder().decode(Session.self, from: data) else {
            return .empty
        }
        return session
    }
}
