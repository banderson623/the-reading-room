import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Deep links")
struct DeepLinkTests {
    @Test("A link carries the file and the folder it was read in")
    func roundTrip() throws {
        let file = URL(fileURLWithPath: "/Users/me/notes/api/auth.md")
        let root = URL(fileURLWithPath: "/Users/me/notes")

        let link = DeepLink.string(file: file, root: root)
        #expect(link == "reading-room://open?path=/Users/me/notes/api/auth.md&root=/Users/me/notes")

        let target = try #require(DeepLink.target(of: URL(string: link)!))
        #expect(target.file == file)
        #expect(target.root == root)
    }

    @Test("Spaces and punctuation survive the round trip")
    func encoding() throws {
        let file = URL(fileURLWithPath: "/Users/me/My Notes/a & b + c #1.md")
        let link = DeepLink.string(file: file)
        #expect(!link.contains(" "))
        #expect(!link.contains("#"))
        #expect(!link.contains("&"))

        let target = try #require(DeepLink.target(of: URL(string: link)!))
        #expect(target.file == file)
        #expect(target.root == nil)
    }

    @Test("A folder on its own opens that folder")
    func rootOnly() throws {
        let target = try #require(
            DeepLink.target(of: URL(string: "reading-room://open?root=/Users/me/notes")!)
        )
        #expect(target.file == nil)
        #expect(target.root == URL(fileURLWithPath: "/Users/me/notes"))
    }

    @Test("The URL's own path is taken as the file")
    func pathForm() throws {
        let target = try #require(
            DeepLink.target(of: URL(string: "reading-room:///Users/me/notes/api.md")!)
        )
        #expect(target.file == URL(fileURLWithPath: "/Users/me/notes/api.md"))
        #expect(target.root == nil)
    }

    @Test("A relative path is resolved against the folder")
    func relativePath() throws {
        let target = try #require(
            DeepLink.target(of: URL(string: "reading-room://open?path=api/auth.md&root=/Users/me/notes")!)
        )
        #expect(target.file == URL(fileURLWithPath: "/Users/me/notes/api/auth.md"))
    }

    @Test("Dot-dot segments are flattened")
    func standardizing() throws {
        let target = try #require(
            DeepLink.target(of: URL(string: "reading-room://open?path=/Users/me/notes/../notes/api.md")!)
        )
        #expect(target.file == URL(fileURLWithPath: "/Users/me/notes/api.md"))
    }

    @Test("Other schemes and hosts are not ours")
    func rejected() {
        #expect(DeepLink.target(of: URL(string: "mdv://doc/Users/me/notes/api.md")!) == nil)
        #expect(DeepLink.target(of: URL(string: "https://example.com/api.md")!) == nil)
        #expect(DeepLink.target(of: URL(string: "reading-room://elsewhere/api.md")!) == nil)
    }

    @Test("A link naming nothing openable is refused")
    func empty() {
        #expect(DeepLink.target(of: URL(string: "reading-room://open")!) == nil)
        #expect(DeepLink.target(of: URL(string: "reading-room://open?path=")!) == nil)
        // Relative with no folder to resolve against.
        #expect(DeepLink.target(of: URL(string: "reading-room://open?path=api/auth.md")!) == nil)
    }

    @Test("The scheme is matched regardless of case")
    func caseInsensitive() throws {
        let target = try #require(
            DeepLink.target(of: URL(string: "READING-ROOM://open?path=/Users/me/a.md")!)
        )
        #expect(target.file == URL(fileURLWithPath: "/Users/me/a.md"))
    }
}
