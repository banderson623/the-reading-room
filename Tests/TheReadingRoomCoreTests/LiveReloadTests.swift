import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Live reload")
struct LiveReloadTests {
    @Test("The watcher reports a file being edited")
    func watcherFiresOnEdit() async throws {
        let folder = try TestFolder(["doc.md": "# one"])
        defer { folder.remove() }
        let root = folder.root
        let file = folder.url("doc.md")

        let reported = Reported()
        let watcher = DirectoryWatcher(url: root) { paths in
            reported.add(paths)
        }
        defer { _ = watcher }

        // FSEvents needs a moment to arm before it will report anything.
        try await Task.sleep(for: .milliseconds(400))
        try Data("# two".utf8).write(to: file)

        try await reported.wait(forPathContaining: "doc.md", timeout: .seconds(5))
        #expect(FileTree.changeAffects(path: file.path, changedPaths: reported.paths))
    }

    @Test("A nested file's edit is reported too")
    func watcherIsRecursive() async throws {
        let folder = try TestFolder(["a/b/deep.md": "# one"])
        defer { folder.remove() }
        let root = folder.root
        let file = folder.url("a/b/deep.md")

        let reported = Reported()
        let watcher = DirectoryWatcher(url: root) { paths in
            reported.add(paths)
        }
        defer { _ = watcher }

        try await Task.sleep(for: .milliseconds(400))
        try Data("# two".utf8).write(to: file)

        try await reported.wait(forPathContaining: "deep.md", timeout: .seconds(5))
    }

    @Test("An atomic save that only reports the directory still counts as a hit")
    func changeDetectionTolerates() {
        let file = "/docs/guides/api.md"
        #expect(FileTree.changeAffects(path: file, changedPaths: [file]))
        #expect(FileTree.changeAffects(path: file, changedPaths: ["/docs/guides"]))
        #expect(!FileTree.changeAffects(path: file, changedPaths: ["/docs"]))
        #expect(!FileTree.changeAffects(path: file, changedPaths: ["/docs/guides/other.md"]))
    }

    @Test("Only markdown and directory changes trigger a rescan")
    func rescanTriggers() {
        #expect(FileTree.changesAffectTree(["/docs/new.md"]))
        #expect(FileTree.changesAffectTree(["/docs/newfolder"]))
        #expect(!FileTree.changesAffectTree(["/docs/.DS_Store", "/docs/image.png"]))
    }

    @Test("A directory whose name contains a dot still triggers a rescan")
    func rescanForDottedDirectory() throws {
        let folder = try TestFolder(["v1.2/notes.md": "# Notes"])
        defer { folder.remove() }
        #expect(FileTree.changesAffectTree([folder.url("v1.2").path]))
    }

    // MARK: - The sidebar noticing changes

    @Test("A rescan after an edit differs from the tree it replaces")
    func rescanSeesEdits() throws {
        let folder = try TestFolder([
            "index.md": "# First Title",
            "other.md": "# Other",
        ])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        #expect(before.first { $0.name == "index.md" }?.label == "First Title")

        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("# Second Title", to: "index.md")

        let after = FileTree.scan(folder.root)
        #expect(after.first { $0.name == "index.md" }?.label == "Second Title")
        // The sidebar only refreshes when the trees compare unequal, so this is
        // the assertion that keeps stale titles off the screen.
        #expect(before != after)
    }

    @Test("An edit that changes nothing visible still updates the date")
    func rescanSeesModificationDates() throws {
        let folder = try TestFolder(["notes.md": "# Notes\n\nbefore"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("# Notes\n\nafter", to: "notes.md")
        let after = FileTree.scan(folder.root)

        #expect(before.first?.modified != after.first?.modified)
        #expect(before != after)
    }

    @Test("Added, removed, and renamed files change the tree")
    func rescanSeesStructuralChanges() throws {
        let folder = try TestFolder(["a.md": "# A"])
        defer { folder.remove() }

        let start = FileTree.scan(folder.root)
        #expect(start.map(\.name) == ["a.md"])

        try folder.write("# B", to: "b.md")
        let added = FileTree.scan(folder.root)
        #expect(added.map(\.name) == ["a.md", "b.md"])
        #expect(added != start)

        try FileManager.default.removeItem(at: folder.url("a.md"))
        let removed = FileTree.scan(folder.root)
        #expect(removed.map(\.name) == ["b.md"])
        #expect(removed != added)
    }

    @Test("A change deep in the tree is visible at the top")
    func rescanSeesNestedChanges() throws {
        let folder = try TestFolder(["a/b/c/index.md": "# Deep One"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("# Deep Two", to: "a/b/c/index.md")
        let after = FileTree.scan(folder.root)

        #expect(before != after)
        #expect(before.first?.name == after.first?.name)
    }

    @Test("Scroll position survives a reload of the same file, once")
    func scrollRestore() {
        let store = ScrollStore()
        let path = "/docs/long.md"

        store.record(path: path, offset: 1234)
        // Nothing is restored unless a reload asked for it — following a link to
        // a file should start at the top.
        #expect(store.takeRestore(path: path) == nil)

        store.requestRestore(path: path)
        #expect(store.takeRestore(path: path) == 1234)
        // The request is one-shot.
        #expect(store.takeRestore(path: path) == nil)
    }

    @Test("A restore request for one file doesn't apply to another")
    func scrollRestoreIsPerFile() {
        let store = ScrollStore()
        store.record(path: "/a.md", offset: 500)
        store.record(path: "/b.md", offset: 900)

        store.requestRestore(path: "/a.md")
        #expect(store.takeRestore(path: "/b.md") == nil)
        #expect(store.takeRestore(path: "/a.md") == 500)
    }

    @Test("A document scrolled to the top needs no restore")
    func scrollRestoreAtTop() {
        let store = ScrollStore()
        store.record(path: "/a.md", offset: 0)
        store.requestRestore(path: "/a.md")
        #expect(store.takeRestore(path: "/a.md") == nil)
    }

    @Test("The page shell carries the restore offset to the browser")
    func restoreReachesThePage() {
        let withRestore = Page.document(title: "t", body: "<p>x</p>", restoreScroll: 820)
        #expect(withRestore.contains("window.__restoreScroll = 820.0;"))

        let without = Page.document(title: "t", body: "<p>x</p>", restoreScroll: nil)
        #expect(!without.contains("__restoreScroll"))
    }
}

/// Collects watcher callbacks from whatever thread they arrive on.
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func add(_ paths: [String]) {
        lock.lock()
        storage.append(contentsOf: paths)
        lock.unlock()
    }

    func wait(forPathContaining needle: String, timeout: Duration) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if paths.contains(where: { $0.contains(needle) }) { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("watcher never reported a path containing \(needle); saw \(paths)")
    }
}
