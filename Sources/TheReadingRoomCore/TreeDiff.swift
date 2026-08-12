import Foundation

/// Something that happened to one file in the open folder.
public struct TreeChange: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case added, modified, removed

        public var verb: String {
            switch self {
            case .added: return "added"
            case .modified: return "changed"
            case .removed: return "removed"
            }
        }
    }

    public let url: URL
    /// The label as the sidebar shows it — a document title, or the filename.
    public let label: String
    public let kind: Kind
    public let modified: Date?

    public var id: URL { url }

    /// Removed files can be reported but not opened.
    public var isOpenable: Bool { kind != .removed }
}

/// Works out what changed between two scans.
///
/// Diffing the trees rather than reading FSEvents paths keeps the noise out:
/// editors write lock files, swap files, and temporary copies that never appear
/// in the tree, and a single save can produce a handful of events for one file.
public enum TreeDiff {
    public static func changes(from old: [FileNode], to new: [FileNode]) -> [TreeChange] {
        let before = index(of: old)
        let after = index(of: new)

        var changes: [TreeChange] = []

        for (url, node) in after {
            guard let previous = before[url] else {
                changes.append(
                    TreeChange(url: url, label: node.label, kind: .added, modified: node.modified)
                )
                continue
            }
            if previous.modified != node.modified || previous.label != node.label {
                changes.append(
                    TreeChange(url: url, label: node.label, kind: .modified, modified: node.modified)
                )
            }
        }

        for (url, node) in before where after[url] == nil {
            changes.append(
                TreeChange(url: url, label: node.label, kind: .removed, modified: node.modified)
            )
        }

        // Most recent first, so a single-line summary names the newest change.
        return changes.sorted { a, b in
            let aDate = a.modified ?? .distantPast
            let bDate = b.modified ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.label.localizedStandardCompare(b.label) == .orderedAscending
        }
    }

    /// Files only — a folder's date is just a reflection of its contents, so
    /// reporting it as well would double-count every change.
    private static func index(of nodes: [FileNode]) -> [URL: FileNode] {
        var result: [URL: FileNode] = [:]
        for node in nodes {
            if node.isDirectory {
                result.merge(index(of: node.children ?? [])) { current, _ in current }
            } else {
                result[node.url] = node
            }
        }
        return result
    }
}
