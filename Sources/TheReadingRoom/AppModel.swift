import AppKit
import Combine
import SwiftUI
import TheReadingRoomCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var tree: [FileNode] = []
    @Published private(set) var isScanning = false
    @Published var selection: URL?
    @Published var searchText = ""
    @Published var expanded: Set<URL> = []
    @Published private(set) var recentFolders: [URL] = []
    @Published var findBarVisible = false
    @Published var findText = ""
    /// Toggled to move keyboard focus into the sidebar search field.
    @Published var focusSearch = false

    /// Sidebar order. Shared across windows, and remembered between launches.
    @Published var sortOrder: FileTree.SortOrder = .alphabetical {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }

    /// Full-text search state. `searchText` is the query; results are files whose
    /// *contents* matched.
    @Published private(set) var searchResults: [SearchHit] = [] {
        // Every visible row asks for its count and snippet on every render;
        // answering from a dictionary keeps that O(1) instead of a scan.
        didSet {
            searchHitsByURL = Dictionary(
                searchResults.map { ($0.url, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
    private var searchHitsByURL: [URL: SearchHit] = [:]
    @Published private(set) var isSearching = false

    /// Queries shorter than this match too much to be useful.
    static let minimumQueryLength = 2

    let webViewController = WebViewController()

    /// Identifies this window to the router.
    var windowID: UUID?

    private var watcher: DirectoryWatcher?
    private var searchTask: Task<Void, Never>?
    private var searchCancellable: AnyCancellable?
    private var webViewCancellable: AnyCancellable?
    private var settings = Settings.default
    private let recentsKey = "recentFolders"
    private let lastFolderKey = "lastFolder"
    private static let sortOrderKey = "sortOrder"

    private static func storedSortOrder() -> FileTree.SortOrder {
        guard let raw = UserDefaults.standard.string(forKey: sortOrderKey) else {
            return .alphabetical
        }
        return FileTree.SortOrder(rawValue: raw) ?? .alphabetical
    }

    func focusSearchField() {
        focusSearch = true
    }

    init() {
        sortOrder = Self.storedSortOrder()
        recentFolders = (UserDefaults.standard.array(forKey: recentsKey) as? [String] ?? [])
            .map { URL(fileURLWithPath: $0) }

        searchCancellable = $searchText
            .removeDuplicates()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] query in self?.runSearch(query) }

        // The toolbar and menus watch this model, but back/forward and zoom live
        // on the web view controller — forward its changes so their enabled
        // states and labels keep up.
        webViewCancellable = webViewController.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    var isSearchActive: Bool {
        searchText.trimmingCharacters(in: .whitespaces).count >= Self.minimumQueryLength
    }

    /// What the sidebar shows: the whole tree, or just the search results,
    /// in the chosen order.
    var visibleTree: [FileNode] {
        let nodes = isSearchActive
            ? FileTree.restrict(tree, to: Set(searchResults.map(\.url)))
            : tree
        return FileTree.sort(nodes, by: sortOrder)
    }

    func matchCount(for url: URL) -> Int? {
        searchHitsByURL[url]?.matchCount
    }

    func snippet(for url: URL) -> String? {
        searchHitsByURL[url]?.snippet
    }

    /// What to call the open file in the window title — its document title when
    /// the filename is a generic one, otherwise the filename.
    var titleOfSelection: String? {
        guard let selection else { return nil }
        return FileTree.node(for: selection, in: tree)?.label ?? selection.lastPathComponent
    }

    /// A file's path relative to the opened folder, e.g. `guides/setup.md`.
    /// Falls back to the absolute path for anything outside the folder.
    func relativePath(of url: URL) -> String {
        guard let root else { return url.path }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return url.path }
        return String(url.path.dropFirst(rootPath.count))
    }

    /// Path of the selected file relative to the root folder.
    var relativePathOfSelection: String? {
        selection.map { relativePath(of: $0) }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Window subtitle: the folder holding the selected file, rooted at the
    /// opened folder's name.
    var subtitle: String {
        guard let root else { return "" }
        guard let relative = relativePathOfSelection else { return root.lastPathComponent }
        let directory = (relative as NSString).deletingLastPathComponent
        return directory.isEmpty
            ? root.lastPathComponent
            : "\(root.lastPathComponent)/\(directory)"
    }

    // MARK: - Opening folders

    /// Reopens a window as it was: same folder, same file, same scroll position.
    func restore(_ window: WindowSession) {
        if let selection = window.selection, window.scroll > 0 {
            // Seed the store so the first render of this file comes back to
            // where the reader left off, using the same path as a live reload.
            ScrollStore.shared.record(path: selection, offset: window.scroll)
            ScrollStore.shared.requestRestore(path: selection)
        }
        open(folder: window.rootURL, select: window.selectionURL)
    }

    /// Falls back to the single remembered folder — for anyone upgrading from a
    /// version that didn't record a whole session.
    func restoreLastFolder() {
        guard root == nil,
              let path = UserDefaults.standard.string(forKey: lastFolderKey) else { return }
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        // Never end up with two windows on one folder.
        guard !WindowRouter.shared.isOpenAnywhere(url.canonicalFileURL) else { return }
        open(folder: url)
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder of markdown files, or a single markdown file."
        panel.directoryURL = root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openPreferringNewWindow(url)
    }

    /// Hands a folder to the router, which decides whether it belongs in this
    /// window, one that already has it open, or a new one.
    func openPreferringNewWindow(_ url: URL) {
        WindowRouter.shared.route(url, from: windowID)
    }

    /// Accepts either a folder or a markdown file (opening its parent folder).
    func open(_ url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            open(folder: url)
        } else {
            open(folder: url.deletingLastPathComponent(), select: url)
        }
    }

    func open(folder url: URL, select fileToSelect: URL? = nil) {
        let folder = url.canonicalFileURL
        root = folder
        searchText = ""
        expanded = []
        isScanning = true
        UserDefaults.standard.set(folder.path, forKey: lastFolderKey)
        noteRecentFolder(folder)

        // Settings are re-read here, so edits apply on the next folder open.
        settings = Settings.load()
        let settings = settings

        Task.detached(priority: .userInitiated) {
            let nodes = FileTree.scan(folder, settings: settings)
            await MainActor.run { [weak self] in
                guard let self, self.root == folder else { return }
                self.tree = nodes
                self.isScanning = false
                self.expanded = Self.initialExpansion(nodes)
                // A query typed while the scan was still running had nothing to
                // search; now there is.
                self.refreshSearchIfActive()
                if let fileToSelect {
                    self.select(fileToSelect)
                } else if let first = FileTree.defaultSelection(in: nodes) {
                    self.select(first.url)
                } else {
                    self.selection = nil
                }
            }
        }

        watcher = DirectoryWatcher(url: folder) { [weak self] paths in
            self?.handleFileSystemChanges(paths)
        }
    }

    func closeFolder() {
        watcher = nil
        root = nil
        tree = []
        selection = nil
        searchText = ""
        UserDefaults.standard.removeObject(forKey: lastFolderKey)
        // Deliberately emptying a window should stick, so this save is allowed
        // to record an empty session.
        WindowRouter.shared.saveSession(allowingEmpty: true)
    }

    /// Expand top-level directories, but only when the tree is small enough that
    /// doing so stays readable.
    private static func initialExpansion(_ nodes: [FileNode]) -> Set<URL> {
        let directories = nodes.filter(\.isDirectory)
        guard directories.count <= 12 else { return [] }
        return Set(directories.map(\.url))
    }

    private func noteRecentFolder(_ url: URL) {
        var recents = recentFolders.filter { $0.path != url.path }
        recents.insert(url, at: 0)
        recentFolders = Array(recents.prefix(8))
        UserDefaults.standard.set(recentFolders.map(\.path), forKey: recentsKey)
    }

    func clearRecentFolders() {
        recentFolders = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    // MARK: - Content search

    private func runSearch(_ rawQuery: String) {
        searchTask?.cancel()
        let query = rawQuery.trimmingCharacters(in: .whitespaces)

        guard query.count >= Self.minimumQueryLength else {
            searchResults = []
            isSearching = false
            return
        }

        let files = FileTree.allFiles(tree)
        isSearching = true
        searchTask = Task.detached(priority: .userInitiated) {
            let hits = ContentSearch.shared.search(
                query: query,
                in: files,
                isCancelled: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.searchText.trimmingCharacters(in: .whitespaces) == query else { return }
                self.searchResults = hits
                self.isSearching = false
            }
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
        searchTask?.cancel()
    }

    /// Re-run the current search, e.g. after files changed on disk.
    private func refreshSearchIfActive() {
        guard isSearchActive else { return }
        runSearch(searchText)
    }

    // MARK: - Sidebar expansion

    /// While searching, everything is expanded so matches are visible.
    func expansionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return false }
                return isSearchActive || expanded.contains(url)
            },
            set: { [weak self] isExpanded in
                guard let self, !isSearchActive else { return }
                if isExpanded {
                    expanded.insert(url)
                } else {
                    expanded.remove(url)
                }
            }
        )
    }

    func toggleExpansion(_ url: URL) {
        guard !isSearchActive else { return }
        if expanded.contains(url) {
            expanded.remove(url)
        } else {
            expanded.insert(url)
        }
    }

    // MARK: - Selection

    func select(_ url: URL) {
        selection = url
        // Reveal the file in the sidebar if it lives in a collapsed folder.
        if let ancestors = FileTree.ancestors(of: url, in: tree) {
            expanded.formUnion(ancestors)
        }
        // Opening a search result jumps to the first match in the page.
        webViewController.pendingFind = isSearchActive ? searchText : nil
        webViewController.show(path: url.path)
    }

    /// Called when the page itself navigated (a markdown link was followed).
    func pageNavigated(to path: String) {
        let url = URL(fileURLWithPath: path)
        guard url != selection else { return }
        selection = url
        if let ancestors = FileTree.ancestors(of: url, in: tree) {
            expanded.formUnion(ancestors)
        }
    }

    func revealInFinder() {
        guard let selection else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selection])
    }

    func openInDefaultEditor() {
        guard let selection else { return }
        NSWorkspace.shared.open(selection)
    }

    // MARK: - File system changes

    private func handleFileSystemChanges(_ paths: [String]) {
        guard let root else { return }

        // Anything that changed is stale in the search cache.
        for path in paths { ContentSearch.shared.invalidate(path: path) }

        // The open document changed on disk — re-render it where the reader is.
        if let selection, FileTree.changeAffects(path: selection.path, changedPaths: paths) {
            webViewController.reload()
        }

        guard FileTree.changesAffectTree(paths) else { return }

        let settings = settings
        Task.detached(priority: .utility) {
            let nodes = FileTree.scan(root, settings: settings)
            await MainActor.run { [weak self] in
                guard let self, self.root == root else { return }
                if nodes != self.tree {
                    let changes = TreeDiff.changes(from: self.tree, to: nodes)
                    // The open file may have been deleted; leave it on screen
                    // rather than yanking the reader somewhere unexpected.
                    self.tree = nodes
                    self.announce(changes)
                }
                self.refreshSearchIfActive()
            }
        }
    }

    // MARK: - Change notices

    /// Reports changes worth telling the reader about.
    private func announce(_ changes: [TreeChange]) {
        guard let root, settings.notifyOnChange else { return }
        // The file on screen re-renders in place; saying so as well is noise.
        let worthShowing = changes.filter { $0.url != selection }
        guard !worthShowing.isEmpty else { return }
        ChangeNotifier.shared.notify(worthShowing, in: root)
    }
}
