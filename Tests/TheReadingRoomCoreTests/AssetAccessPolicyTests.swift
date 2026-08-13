import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Asset access")
struct AssetAccessPolicyTests {
    @Test("Assets inside an allowed folder are served")
    func insideRoot() throws {
        let folder = try TestFolder(["docs/guide.md": "# G", "docs/img/pic.png": "png"])
        defer { folder.remove() }
        let root = folder.root.appendingPathComponent("docs")

        #expect(AssetAccessPolicy.allows(
            path: folder.url("docs/img/pic.png").path, withinAny: [root]
        ))
    }

    @Test("Paths outside every allowed folder are refused")
    func outsideRoot() throws {
        let folder = try TestFolder(["docs/guide.md": "# G", "elsewhere/secret.png": "png"])
        defer { folder.remove() }
        let root = folder.root.appendingPathComponent("docs")

        #expect(!AssetAccessPolicy.allows(
            path: folder.url("elsewhere/secret.png").path, withinAny: [root]
        ))
        #expect(!AssetAccessPolicy.allows(path: "/etc/hosts", withinAny: [root]))
    }

    @Test("A sibling folder whose name shares a prefix is not inside")
    func prefixConfusion() throws {
        let folder = try TestFolder(["docs/a.md": "# A", "docs-private/b.png": "png"])
        defer { folder.remove() }
        let root = folder.root.appendingPathComponent("docs")

        #expect(!AssetAccessPolicy.allows(
            path: folder.url("docs-private/b.png").path, withinAny: [root]
        ))
    }

    @Test("With nothing open, nothing is served")
    func noRoots() {
        #expect(!AssetAccessPolicy.allows(path: "/tmp/x.png", withinAny: []))
    }

    @Test("Dot-dot segments cannot escape the folder")
    func traversal() throws {
        let folder = try TestFolder(["docs/a.md": "# A"])
        defer { folder.remove() }
        let root = folder.root.appendingPathComponent("docs")

        #expect(!AssetAccessPolicy.allows(
            path: root.path + "/../../../etc/hosts", withinAny: [root]
        ))
    }
}
