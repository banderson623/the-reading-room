import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Sidebar sorting")
struct SortingTests {
    /// Files with known, distinct modification times.
    static func makeFolder() throws -> TestFolder {
        let folder = try TestFolder([
            "README.md": "# Read me",
            "apple.md": "# Apple",
            "zebra.md": "# Zebra",
            "guides/old.md": "# Old",
            "guides/new.md": "# New",
        ])

        let times: [(String, TimeInterval)] = [
            ("README.md", -5000),
            ("apple.md", -400),
            ("zebra.md", -100),
            ("guides/old.md", -9000),
            ("guides/new.md", -50),
        ]
        for (path, offset) in times {
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(offset)],
                ofItemAtPath: folder.url(path).path
            )
        }
        return folder
    }

    @Test("Alphabetical puts folders first and the README on top")
    func alphabetical() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }

        let sorted = FileTree.sort(FileTree.scan(folder.root), by: .alphabetical)
        #expect(sorted.map(\.name) == ["guides", "README.md", "apple.md", "zebra.md"])

        let guides = try #require(sorted.first { $0.name == "guides" })
        #expect(guides.children?.map(\.name) == ["new.md", "old.md"])
    }

    @Test("Most-recent-first orders by modification date, newest at the top")
    func recentFirst() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }

        let sorted = FileTree.sort(FileTree.scan(folder.root), by: .recentFirst)
        // guides is newest because guides/new.md is the newest file in it.
        #expect(sorted.map(\.name) == ["guides", "zebra.md", "apple.md", "README.md"])

        let guides = try #require(sorted.first { $0.name == "guides" })
        #expect(guides.children?.map(\.name) == ["new.md", "old.md"])
    }

    @Test("A folder is as recent as its newest document")
    func folderDates() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }

        let tree = FileTree.scan(folder.root)
        let guides = try #require(tree.first { $0.name == "guides" })
        let newest = try #require(guides.children?.compactMap(\.modified).max())
        #expect(guides.modified == newest)
    }

    @Test("Sorting is reversible without re-reading the disk")
    func stableRoundTrip() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let tree = FileTree.scan(folder.root)

        let there = FileTree.sort(tree, by: .recentFirst)
        let back = FileTree.sort(there, by: .alphabetical)
        #expect(back.map(\.name) == FileTree.sort(tree, by: .alphabetical).map(\.name))
    }

    @Test("Titled files sort under their displayed title")
    func sortsByLabel() throws {
        let folder = try TestFolder([
            "aaa.md": "# Zebra Document",
            "zzz.md": "# Aardvark",
            "index.md": "# Middle",
        ])
        defer { folder.remove() }

        let sorted = FileTree.sort(FileTree.scan(folder.root), by: .alphabetical)
        // index.md is the entry point, so it leads; the rest go by filename,
        // since neither aaa.md nor zzz.md is a generic name.
        #expect(sorted.map(\.label) == ["Middle", "aaa.md", "zzz.md"])
    }
}
