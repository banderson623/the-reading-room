import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Content search")
struct ContentSearchTests {
    static func makeFolder() throws -> TestFolder {
        try TestFolder([
            "alpha.md": """
            # Alpha

            The quick brown fox jumps over the lazy dog.
            Another line mentioning the fox again.
            """,
            "beta.md": """
            # Beta

            Nothing to see here.
            """,
            "nested/gamma.md": """
            # Gamma

            A FOX in capitals, plus a fox in lower case, plus one more fox.
            """,
        ])
    }

    @Test("Finds files by their contents, not their names")
    func findsByContents() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let files = FileTree.allFiles(FileTree.scan(folder.root))

        let hits = ContentSearch().search(query: "fox", in: files)
        let names = hits.map(\.url.lastPathComponent)

        #expect(names.sorted() == ["alpha.md", "gamma.md"])
        // A filename-only match finds nothing, since names aren't searched.
        #expect(ContentSearch().search(query: "beta", in: files).map(\.url.lastPathComponent) == ["beta.md"])
        #expect(ContentSearch().search(query: "gamma.md", in: files).isEmpty)
    }

    @Test("Counts every match, case-insensitively")
    func countsMatches() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let files = FileTree.allFiles(FileTree.scan(folder.root))

        let hits = ContentSearch().search(query: "fox", in: files)
        let byName = Dictionary(uniqueKeysWithValues: hits.map { ($0.url.lastPathComponent, $0) })

        #expect(byName["alpha.md"]?.matchCount == 2)
        #expect(byName["gamma.md"]?.matchCount == 3)
    }

    @Test("Each hit carries the matching line as a snippet")
    func snippets() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let files = FileTree.allFiles(FileTree.scan(folder.root))

        let hit = try #require(
            ContentSearch().search(query: "lazy", in: files).first
        )
        #expect(hit.snippet == "The quick brown fox jumps over the lazy dog.")
        #expect(hit.lineNumber == 3)
    }

    @Test("A long line is windowed around the match")
    func longLineSnippet() throws {
        let filler = String(repeating: "padding ", count: 60)
        let folder = try TestFolder(["long.md": filler + "NEEDLE " + filler])
        defer { folder.remove() }

        let hit = try #require(
            ContentSearch().search(query: "needle", in: [folder.url("long.md")]).first
        )
        #expect(hit.snippet.contains("NEEDLE"))
        #expect(hit.snippet.count < 200)
        #expect(hit.snippet.hasPrefix("…"))
        #expect(hit.snippet.hasSuffix("…"))
    }

    @Test("An empty query matches nothing")
    func emptyQuery() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let files = FileTree.allFiles(FileTree.scan(folder.root))
        #expect(ContentSearch().search(query: "   ", in: files).isEmpty)
    }

    @Test("Results follow the order the files were given in")
    func preservesOrder() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let files = [folder.url("nested/gamma.md"), folder.url("alpha.md")]
        let hits = ContentSearch().search(query: "fox", in: files)
        #expect(hits.map(\.url.lastPathComponent) == ["gamma.md", "alpha.md"])
    }

    @Test("A cancelled search returns nothing")
    func cancellation() throws {
        let folder = try Self.makeFolder()
        defer { folder.remove() }
        let files = FileTree.allFiles(FileTree.scan(folder.root))
        #expect(ContentSearch().search(query: "fox", in: files, isCancelled: { true }).isEmpty)
    }

    @Test("Edited files are re-read, not served from cache")
    func cacheInvalidation() throws {
        let folder = try TestFolder(["a.md": "before"])
        defer { folder.remove() }
        let search = ContentSearch()
        let files = [folder.url("a.md")]

        #expect(search.search(query: "before", in: files).count == 1)

        // A same-second rewrite would keep the same mtime, so wait a moment.
        Thread.sleep(forTimeInterval: 1.1)
        try folder.write("after", to: "a.md")
        search.invalidate(path: folder.url("a.md").path)

        #expect(search.search(query: "before", in: files).isEmpty)
        #expect(search.search(query: "after", in: files).count == 1)
    }

    @Test("Searching a large folder stays quick")
    func performance() throws {
        var files: [String: String] = [:]
        for index in 0..<400 {
            files["doc-\(index).md"] = String(repeating: "lorem ipsum dolor sit amet\n", count: 80)
                + (index % 7 == 0 ? "the needle is here\n" : "")
        }
        let folder = try TestFolder(files)
        defer { folder.remove() }
        let urls = FileTree.allFiles(FileTree.scan(folder.root))
        let search = ContentSearch()

        let started = Date()
        let hits = search.search(query: "needle", in: urls)
        let cold = Date().timeIntervalSince(started)

        #expect(hits.count == 58)
        #expect(cold < 5.0, "cold search over 400 files took \(cold)s")

        // The second pass reads from the cache.
        let warmStart = Date()
        _ = search.search(query: "ipsum", in: urls)
        let warm = Date().timeIntervalSince(warmStart)
        #expect(warm < cold + 1.0)
    }
}
