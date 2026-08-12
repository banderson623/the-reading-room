import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Change detection")
struct TreeDiffTests {
    @Test("A new file is reported as added")
    func added() throws {
        let folder = try TestFolder(["a.md": "# A"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        try folder.write("# B", to: "b.md")
        let after = FileTree.scan(folder.root)

        let changes = TreeDiff.changes(from: before, to: after)
        #expect(changes.count == 1)
        #expect(changes[0].kind == .added)
        #expect(changes[0].label == "b.md")
        #expect(changes[0].isOpenable)
    }

    @Test("An edited file is reported as changed")
    func modified() throws {
        let folder = try TestFolder(["a.md": "# A", "b.md": "# B"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("# A edited", to: "a.md")
        let after = FileTree.scan(folder.root)

        let changes = TreeDiff.changes(from: before, to: after)
        #expect(changes.map(\.label) == ["a.md"])
        #expect(changes[0].kind == .modified)
    }

    @Test("A deleted file is reported, and can't be opened")
    func removed() throws {
        let folder = try TestFolder(["a.md": "# A", "b.md": "# B"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        try FileManager.default.removeItem(at: folder.url("a.md"))
        let after = FileTree.scan(folder.root)

        let changes = TreeDiff.changes(from: before, to: after)
        #expect(changes.count == 1)
        #expect(changes[0].kind == .removed)
        #expect(changes[0].label == "a.md")
        #expect(!changes[0].isOpenable)
    }

    @Test("A retitled file reports its new title")
    func retitled() throws {
        let folder = try TestFolder(["index.md": "# Old Title"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("# New Title", to: "index.md")
        let after = FileTree.scan(folder.root)

        let changes = TreeDiff.changes(from: before, to: after)
        #expect(changes.map(\.label) == ["New Title"])
    }

    @Test("Nested files are reported with the folder left out")
    func nested() throws {
        let folder = try TestFolder(["guides/deep/a.md": "# A"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)
        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("# A edited", to: "guides/deep/a.md")
        let after = FileTree.scan(folder.root)

        // Only the file; the folders' dates just mirror it.
        let changes = TreeDiff.changes(from: before, to: after)
        #expect(changes.count == 1)
        #expect(changes[0].url == folder.url("guides/deep/a.md"))
    }

    @Test("Nothing changed means nothing reported")
    func quiet() throws {
        let folder = try TestFolder(["a.md": "# A"])
        defer { folder.remove() }

        let tree = FileTree.scan(folder.root)
        #expect(TreeDiff.changes(from: tree, to: FileTree.scan(folder.root)).isEmpty)
    }

    @Test("Several changes come back newest first")
    func ordering() throws {
        let folder = try TestFolder(["a.md": "# A", "b.md": "# B", "c.md": "# C"])
        defer { folder.remove() }

        let before = FileTree.scan(folder.root)

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-30)],
            ofItemAtPath: folder.url("a.md").path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: folder.url("c.md").path
        )
        let after = FileTree.scan(folder.root)

        let changes = TreeDiff.changes(from: before, to: after)
        #expect(changes.map(\.label) == ["c.md", "a.md"])
    }

    @Test("The verbs read naturally in the toast")
    func verbs() {
        #expect(TreeChange.Kind.added.verb == "added")
        #expect(TreeChange.Kind.modified.verb == "changed")
        #expect(TreeChange.Kind.removed.verb == "removed")
    }
}
