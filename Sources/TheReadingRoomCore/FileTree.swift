import Foundation

/// A node in the sidebar file tree. Directories that contain no markdown
/// (at any depth) are pruned during the scan, so the sidebar only ever shows
/// paths that lead somewhere useful.
public struct FileNode: Identifiable, Hashable {
    public let url: URL
    /// The filename, or a directory's name.
    public let name: String
    /// A title read from the document, for files whose name says nothing (see
    /// `DocumentTitle`). Nil means "show the filename".
    public var title: String?
    public let isDirectory: Bool
    /// A file's modification date; for a directory, its newest descendant's.
    public var modified: Date?
    public var children: [FileNode]?

    public var id: URL { url }

    /// What the sidebar shows.
    public var label: String { title ?? name }

    public init(
        url: URL,
        name: String,
        title: String? = nil,
        isDirectory: Bool,
        modified: Date? = nil,
        children: [FileNode]? = nil
    ) {
        self.url = url
        self.name = name
        self.title = title
        self.isDirectory = isDirectory
        self.modified = modified
        self.children = children
    }

    /// Compares everything, not just the URL: a rescan after an edit finds the
    /// same paths, and the sidebar has to notice that a title or a modification
    /// date changed underneath them.
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.url == rhs.url
            && lhs.name == rhs.name
            && lhs.title == rhs.title
            && lhs.isDirectory == rhs.isDirectory
            && lhs.modified == rhs.modified
            && lhs.children == rhs.children
    }

    /// Hashing on identity alone is coarser than equality, which is allowed —
    /// and it keeps hashing a deep tree cheap.
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

public enum FileTree {
    public static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdx", "qmd", "rmd", "text",
    ]

    /// Directories we never descend into. Keeps scanning fast in real repos.
    public static let skippedDirectories: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", ".build", "build", "dist",
        "vendor", "Pods", ".venv", "venv", "__pycache__", ".next", ".nuxt",
        "target", "DerivedData", ".terraform", ".gradle", ".idea", ".cache",
    ]

    public static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    /// Recursively scan `root`, returning markdown files and the directories
    /// leading to them. Depth-capped so a mistakenly opened `/` can't hang.
    public static func scan(
        _ root: URL,
        settings: Settings = .default,
        depth: Int = 0
    ) -> [FileNode] {
        guard depth < 16 else { return [] }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey,
        ]
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )) ?? []

        var directories: [FileNode] = []
        var files: [FileNode] = []

        for entry in contents {
            let values = try? entry.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }

            // `contentsOfDirectory` gives directories a trailing slash; drop it so
            // node URLs compare equal to ones built from path components.
            let url = URL(fileURLWithPath: entry.path)

            if values?.isDirectory == true {
                let name = url.lastPathComponent
                if skippedDirectories.contains(name) { continue }
                let children = scan(url, settings: settings, depth: depth + 1)
                if children.isEmpty { continue }
                directories.append(
                    FileNode(
                        url: url,
                        name: name,
                        isDirectory: true,
                        // A folder is as recent as its newest document.
                        modified: children.compactMap(\.modified).max(),
                        children: children
                    )
                )
            } else if isMarkdown(url) {
                files.append(
                    FileNode(
                        url: url,
                        name: url.lastPathComponent,
                        title: DocumentTitle.displayTitle(
                            for: url,
                            genericNames: settings.titleFromHeadingFor
                        ),
                        isDirectory: false,
                        modified: values?.contentModificationDate
                    )
                )
            }
        }

        return sort(directories, files, by: .alphabetical)
    }

    // MARK: - Sorting

    public enum SortOrder: String, CaseIterable, Sendable {
        /// A–Z by what the sidebar shows, entry points (README/index) pinned up.
        case alphabetical
        /// Most recently modified first.
        case recentFirst

        public var label: String {
            switch self {
            case .alphabetical: return "Name"
            case .recentFirst: return "Date Modified"
            }
        }
    }

    /// Re-sorts a tree in place — cheap enough to do at display time, so
    /// switching order never re-reads the disk.
    public static func sort(_ nodes: [FileNode], by order: SortOrder) -> [FileNode] {
        var directories: [FileNode] = []
        var files: [FileNode] = []
        for node in nodes {
            if node.isDirectory {
                var copy = node
                copy.children = sort(node.children ?? [], by: order)
                directories.append(copy)
            } else {
                files.append(node)
            }
        }
        return sort(directories, files, by: order)
    }

    private static func sort(
        _ directories: [FileNode],
        _ files: [FileNode],
        by order: SortOrder
    ) -> [FileNode] {
        switch order {
        case .alphabetical:
            return directories.sorted(by: byName) + files.sorted(by: byLabel)
        case .recentFirst:
            // Newest first, with folders and files interleaved — when you sort by
            // date, grouping by kind hides what you're looking for.
            return (directories + files).sorted(by: byDate)
        }
    }

    private static func byName(_ a: FileNode, _ b: FileNode) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Sorts by the shown label, with a folder's entry point pinned to the top.
    private static func byLabel(_ a: FileNode, _ b: FileNode) -> Bool {
        let aEntry = isEntryPoint(a)
        let bEntry = isEntryPoint(b)
        if aEntry != bEntry { return aEntry }
        return a.label.localizedStandardCompare(b.label) == .orderedAscending
    }

    private static func byDate(_ a: FileNode, _ b: FileNode) -> Bool {
        let aDate = a.modified ?? .distantPast
        let bDate = b.modified ?? .distantPast
        if aDate != bDate { return aDate > bDate }
        return byLabel(a, b)
    }

    /// A folder's obvious starting point: its README or index.
    static func isEntryPoint(_ node: FileNode) -> Bool {
        let base = node.url.deletingPathExtension().lastPathComponent.lowercased()
        return base.hasPrefix("readme") || base == "index" || base == "_index"
    }

    /// The file to show when a folder is first opened: the top-level README or
    /// index if there is one, otherwise the first markdown file in the tree.
    public static func defaultSelection(in nodes: [FileNode]) -> FileNode? {
        if let entry = nodes.first(where: { !$0.isDirectory && isEntryPoint($0) }) {
            return entry
        }
        if let file = nodes.first(where: { !$0.isDirectory }) { return file }
        for node in nodes where node.isDirectory {
            if let found = defaultSelection(in: node.children ?? []) { return found }
        }
        return nil
    }

    /// Every markdown file in the tree, in sidebar order.
    public static func allFiles(_ nodes: [FileNode]) -> [URL] {
        var urls: [URL] = []
        for node in nodes {
            if node.isDirectory {
                urls.append(contentsOf: allFiles(node.children ?? []))
            } else {
                urls.append(node.url)
            }
        }
        return urls
    }

    /// Files whose filename or shown label contains `query` — so a search can
    /// find a document by what the sidebar calls it, not only by its contents.
    public static func matchingNames(_ query: String, in nodes: [FileNode]) -> Set<URL> {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        var result: Set<URL> = []
        for node in nodes {
            if node.isDirectory {
                result.formUnion(matchingNames(needle, in: node.children ?? []))
            } else if node.name.range(of: needle, options: options) != nil
                || node.label.range(of: needle, options: options) != nil {
                result.insert(node.url)
            }
        }
        return result
    }

    /// Narrow the tree to `keep`, retaining the directories that lead to them.
    public static func restrict(_ nodes: [FileNode], to keep: Set<URL>) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            if node.isDirectory {
                let children = restrict(node.children ?? [], to: keep)
                if !children.isEmpty {
                    result.append(
                        FileNode(url: node.url, name: node.name, isDirectory: true, children: children)
                    )
                }
            } else if keep.contains(node.url) {
                result.append(node)
            }
        }
        return result
    }

    /// Every directory URL in the tree — used to expand everything while filtering.
    public static func directoryURLs(_ nodes: [FileNode]) -> Set<URL> {
        var urls: Set<URL> = []
        for node in nodes where node.isDirectory {
            urls.insert(node.url)
            urls.formUnion(directoryURLs(node.children ?? []))
        }
        return urls
    }

    /// The chain of ancestor directories of `url` within the tree, so the
    /// sidebar can reveal a file opened by following a link.
    public static func ancestors(of url: URL, in nodes: [FileNode]) -> Set<URL>? {
        for node in nodes {
            if node.url == url { return [] }
            if node.isDirectory, let children = node.children,
               let deeper = ancestors(of: url, in: children) {
                return deeper.union([node.url])
            }
        }
        return nil
    }

    public static func contains(_ url: URL, in nodes: [FileNode]) -> Bool {
        ancestors(of: url, in: nodes) != nil
    }

    /// Finds a node anywhere in the tree.
    public static func node(for url: URL, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.url == url { return node }
            if node.isDirectory, let found = self.node(for: url, in: node.children ?? []) {
                return found
            }
        }
        return nil
    }

    // MARK: - Reacting to file-system events

    /// Whether a batch of changed paths means `path` should be re-rendered.
    ///
    /// Editors save in a variety of ways — write in place, or write a temp file
    /// and rename over the original — and FSEvents sometimes reports only the
    /// containing directory. Treating a change to the parent directory as a hit
    /// makes live reload reliable across editors; a redundant re-render is
    /// invisible, since scroll position is preserved.
    public static func changeAffects(path: String, changedPaths: [String]) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        for changed in changedPaths {
            if changed == path { return true }
            if changed == parent { return true }
        }
        return false
    }

    /// Whether a batch of changed paths could have altered the tree — its shape,
    /// or the titles and dates shown in it.
    public static func changesAffectTree(_ paths: [String]) -> Bool {
        paths.contains { path in
            let name = (path as NSString).lastPathComponent
            // Hidden files (.DS_Store and friends) are never in the tree.
            if name.hasPrefix(".") { return false }
            let url = URL(fileURLWithPath: path)
            if isMarkdown(url) { return true }
            // No extension: most likely a directory appearing or disappearing.
            if url.pathExtension.isEmpty { return true }
            // A directory's name can contain a dot ("v1.2"), so ask the disk.
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        }
    }
}
