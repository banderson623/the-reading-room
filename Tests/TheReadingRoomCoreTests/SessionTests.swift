import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Session restore")
struct SessionTests {
    @Test("A session survives a round trip through storage")
    func roundTrip() throws {
        let session = Session(windows: [
            WindowSession(root: "/docs", selection: "/docs/guides/setup.md", scroll: 1840),
            WindowSession(root: "/notes", selection: nil, scroll: 0),
        ])

        let restored = Session.decoded(from: session.encoded())
        #expect(restored == session)
        #expect(restored.windows[0].scroll == 1840)
        #expect(restored.windows[0].selectionURL?.lastPathComponent == "setup.md")
    }

    @Test("A missing or corrupt record launches with no windows, not a crash")
    func corruptRecord() {
        #expect(Session.decoded(from: nil) == .empty)
        #expect(Session.decoded(from: Data("not json".utf8)) == .empty)
        #expect(Session.decoded(from: Data()) == .empty)
    }

    @Test("Folders that have gone away are dropped")
    func dropsMissingFolders() throws {
        let folder = try TestFolder(["a.md": "# A"])
        defer { folder.remove() }

        let session = Session(windows: [
            WindowSession(root: folder.root.path, selection: folder.url("a.md").path),
            WindowSession(root: "/nowhere/at/all"),
        ])

        let kept = session.sanitized()
        #expect(kept.windows.count == 1)
        #expect(kept.windows[0].root == folder.root.path)
    }

    @Test("A folder that survived a deleted file still reopens")
    func dropsMissingSelection() throws {
        let folder = try TestFolder(["a.md": "# A"])
        defer { folder.remove() }

        let session = Session(windows: [
            WindowSession(root: folder.root.path, selection: folder.url("gone.md").path, scroll: 900),
        ])

        let kept = session.sanitized()
        #expect(kept.windows.count == 1)
        #expect(kept.windows[0].selection == nil)
        #expect(kept.windows[0].scroll == 0)
    }

    @Test("One window per directory, even in a stale record")
    func dedupesFolders() {
        let session = Session(windows: [
            WindowSession(root: "/docs", selection: "/docs/a.md"),
            WindowSession(root: "/docs", selection: "/docs/b.md"),
            WindowSession(root: "/notes"),
        ])

        let kept = session.sanitized { _ in true }
        #expect(kept.windows.map(\.root) == ["/docs", "/notes"])
        // The first entry wins, so the frontmost window's file is the one kept.
        #expect(kept.windows[0].selection == "/docs/a.md")
    }

    @Test("A runaway record can't open dozens of windows")
    func capsWindowCount() {
        let session = Session(
            windows: (0..<50).map { WindowSession(root: "/folder-\($0)") }
        )
        #expect(session.sanitized { _ in true }.windows.count == Session.maximumWindows)
    }

    @Test("An empty session restores nothing")
    func empty() {
        #expect(Session.empty.sanitized { _ in true }.windows.isEmpty)
    }
}

@Suite("Scroll restore across windows")
struct ScrollStoreMultiWindowTests {
    @Test("Several windows can each restore their own position")
    func independentRestores() {
        // With a single pending slot, the last window to ask would have stolen
        // the restore from the others.
        let store = ScrollStore()
        store.record(path: "/a.md", offset: 100)
        store.record(path: "/b.md", offset: 200)
        store.record(path: "/c.md", offset: 300)

        store.requestRestore(path: "/a.md")
        store.requestRestore(path: "/b.md")
        store.requestRestore(path: "/c.md")

        #expect(store.takeRestore(path: "/b.md") == 200)
        #expect(store.takeRestore(path: "/a.md") == 100)
        #expect(store.takeRestore(path: "/c.md") == 300)
        // Each request is still one-shot.
        #expect(store.takeRestore(path: "/a.md") == nil)
    }

    @Test("Offsets can be read back for saving the session")
    func readsBackOffsets() {
        let store = ScrollStore()
        store.record(path: "/a.md", offset: 512)
        #expect(store.offset(for: "/a.md") == 512)
        #expect(store.offset(for: "/never-seen.md") == 0)
    }

    @Test("Forgetting a file drops its pending restore too")
    func forgetting() {
        let store = ScrollStore()
        store.record(path: "/a.md", offset: 512)
        store.requestRestore(path: "/a.md")
        store.forget(path: "/a.md")
        #expect(store.offset(for: "/a.md") == 0)
        #expect(store.takeRestore(path: "/a.md") == nil)
    }
}
