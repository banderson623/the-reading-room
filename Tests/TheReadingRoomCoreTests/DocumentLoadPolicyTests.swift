import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Loading a document")
struct DocumentLoadPolicyTests {
    @Test("A file selected before the web view exists is still loaded afterwards")
    func loadsOncePossible() {
        // The bug this guards: opening a folder set the selection while the web
        // view was still being built. Marking it loaded then meant the request
        // that arrived with a real view was dropped, and nothing ever rendered.
        #expect(!DocumentLoadPolicy.shouldLoad(requested: "/a.md", loaded: nil, hasWebView: false))
        // Crucially, nothing was recorded, so the next attempt still loads.
        #expect(DocumentLoadPolicy.shouldLoad(requested: "/a.md", loaded: nil, hasWebView: true))
    }

    @Test("The same file isn't reloaded on every SwiftUI update")
    func skipsRedundantLoads() {
        #expect(!DocumentLoadPolicy.shouldLoad(requested: "/a.md", loaded: "/a.md", hasWebView: true))
    }

    @Test("Switching files loads the new one")
    func loadsOnChange() {
        #expect(DocumentLoadPolicy.shouldLoad(requested: "/b.md", loaded: "/a.md", hasWebView: true))
    }

    @Test("Nothing selected loads nothing")
    func nothingToLoad() {
        #expect(!DocumentLoadPolicy.shouldLoad(requested: nil, loaded: nil, hasWebView: true))
        #expect(!DocumentLoadPolicy.shouldLoad(requested: "", loaded: nil, hasWebView: true))
        #expect(!DocumentLoadPolicy.shouldLoad(requested: nil, loaded: "/a.md", hasWebView: true))
    }
}
