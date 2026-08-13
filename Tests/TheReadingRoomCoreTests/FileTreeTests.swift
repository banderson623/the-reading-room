import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("File tree")
struct FileTreeTests {
    /// Builds a throwaway folder tree.
    static func makeFixture() throws -> TestFolder {
        try TestFolder([
            "README.md": "# Read me",
            "changelog.md": "# Changes",
            "notes.txt": "not markdown",
            "img/diagram.png": "png",
            "guides/setup.md": "# Setup",
            "guides/advanced/tuning.md": "# Tuning",
            "empty-folder/photo.png": "png",
            "node_modules/pkg/readme.md": "# Ignored",
            ".hidden/secret.md": "# Ignored",
        ])
    }

    @Test("Scanning finds markdown and skips noise")
    func scan() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root

        let tree = FileTree.scan(root)
        let names = tree.map(\.name)

        #expect(!names.contains("node_modules"))
        #expect(!names.contains(".hidden"))
        // A folder with no markdown anywhere beneath it is pruned.
        #expect(!names.contains("empty-folder"))
        #expect(!names.contains("img"))
        #expect(!names.contains("notes.txt"))
        #expect(names.contains("guides"))
    }

    @Test("README sorts first, directories before files")
    func ordering() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root

        let names = FileTree.scan(root).map(\.name)
        #expect(names == ["guides", "README.md", "changelog.md"])
    }

    @Test("Nested directories are scanned recursively")
    func nesting() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root

        let guides = try #require(FileTree.scan(root).first { $0.name == "guides" })
        #expect(guides.isDirectory)
        let children = try #require(guides.children).map(\.name)
        #expect(children == ["advanced", "setup.md"])
    }

    @Test("The default selection is the top-level README")
    func defaultSelection() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root

        let selected = FileTree.defaultSelection(in: FileTree.scan(root))
        #expect(selected?.name == "README.md")
    }

    @Test("Restricting the tree keeps the parents of the kept files")
    func restricting() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root
        let tree = FileTree.scan(root)

        let deep = root.appendingPathComponent("guides/advanced/tuning.md")
        let restricted = FileTree.restrict(tree, to: [deep])
        #expect(restricted.count == 1)
        #expect(restricted[0].name == "guides")
        #expect(restricted[0].children?.count == 1)
        #expect(restricted[0].children?.first?.name == "advanced")
        #expect(restricted[0].children?.first?.children?.first?.name == "tuning.md")

        #expect(FileTree.restrict(tree, to: []).isEmpty)
    }

    @Test("Every markdown file is listed in sidebar order")
    func allFiles() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root

        let names = FileTree.allFiles(FileTree.scan(root)).map(\.lastPathComponent)
        #expect(names == ["tuning.md", "setup.md", "README.md", "changelog.md"])
    }

    @Test("Ancestors of a nested file are reported for sidebar reveal")
    func ancestors() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root
        let tree = FileTree.scan(root)

        let target = root.appendingPathComponent("guides/advanced/tuning.md")
        let found = try #require(FileTree.ancestors(of: target, in: tree))
        #expect(found == [
            root.appendingPathComponent("guides"),
            root.appendingPathComponent("guides/advanced"),
        ])

        #expect(FileTree.ancestors(of: root.appendingPathComponent("nope.md"), in: tree) == nil)
        #expect(FileTree.contains(root.appendingPathComponent("README.md"), in: tree))
    }

    @Test("Files can be found by name or title, anywhere in the tree")
    func nameMatching() throws {
        let folder = try Self.makeFixture()
        defer { folder.remove() }
        let root = folder.root
        let tree = FileTree.scan(root)

        // By filename, case-insensitively, nested included.
        #expect(FileTree.matchingNames("SETUP", in: tree)
            == [root.appendingPathComponent("guides/setup.md")])
        // By the label the sidebar shows (README's title is "Read me").
        #expect(FileTree.matchingNames("read me", in: tree)
            == [root.appendingPathComponent("README.md")])
        // Directories themselves never match; a miss is empty, not nil.
        #expect(FileTree.matchingNames("guides", in: tree).isEmpty)
        #expect(FileTree.matchingNames("   ", in: tree).isEmpty)
    }

    @Test("Markdown is recognized by extension, case-insensitively")
    func markdownDetection() {
        #expect(FileTree.isMarkdown(URL(fileURLWithPath: "/a/b.MD")))
        #expect(FileTree.isMarkdown(URL(fileURLWithPath: "/a/b.markdown")))
        #expect(!FileTree.isMarkdown(URL(fileURLWithPath: "/a/b.png")))
        #expect(!FileTree.isMarkdown(URL(fileURLWithPath: "/a/b")))
    }
}

@Suite("Document URLs")
struct SchemeTests {
    @Test("A file path round-trips through a document URL")
    func roundTrip() {
        let path = "/Users/me/notes/api guide.md"
        let url = Scheme.documentURL(for: path)
        #expect(url.scheme == "mdv")
        #expect(url.host == "doc")
        #expect(Scheme.path(of: url) == path)
    }

    @Test("Relative links resolve against the document URL")
    func relativeResolution() {
        let page = Scheme.documentURL(for: "/docs/guides/setup.md")

        let sibling = URL(string: "other.md", relativeTo: page)!.absoluteURL
        #expect(Scheme.path(of: sibling) == "/docs/guides/other.md")

        let parent = URL(string: "../index.md", relativeTo: page)!.absoluteURL
        #expect(Scheme.path(of: parent) == "/docs/index.md")

        let image = URL(string: "img/x.png", relativeTo: page)!.absoluteURL
        #expect(Scheme.path(of: image) == "/docs/guides/img/x.png")
    }

    @Test("Asset URLs are not mistaken for documents")
    func assets() {
        let asset = URL(string: Scheme.assetURL("style.css"))!
        #expect(asset.host == "asset")
        #expect(Scheme.path(of: asset) == nil)
    }
}
