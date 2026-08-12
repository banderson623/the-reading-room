import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Document titles")
struct DocumentTitleTests {
    @Test("A generic filename is replaced by the document's first heading")
    func headingWins() throws {
        let folder = try TestFolder([
            "docs/index.md": "# Innovation Day — August 11, 2026\n\nBody text.",
            "docs/tuning.md": "# Tuning\n\nBody.",
        ])
        defer { folder.remove() }

        let tree = FileTree.scan(folder.root)
        let docs = try #require(tree.first { $0.name == "docs" })
        let byName = Dictionary(uniqueKeysWithValues: (docs.children ?? []).map { ($0.name, $0) })

        #expect(byName["index.md"]?.label == "Innovation Day — August 11, 2026")
        // A descriptive filename is left alone.
        #expect(byName["tuning.md"]?.title == nil)
        #expect(byName["tuning.md"]?.label == "tuning.md")
    }

    @Test("Front matter title beats the heading")
    func frontMatterWins() {
        let markdown = "---\ntitle: \"From Front Matter\"\n---\n\n# From Heading\n"
        #expect(DocumentTitle.title(inMarkdown: markdown) == "From Front Matter")
    }

    @Test("Setext headings count too")
    func setext() {
        #expect(DocumentTitle.title(inMarkdown: "My Title\n========\n\nBody") == "My Title")
        #expect(DocumentTitle.title(inMarkdown: "Sub Title\n---------\n\nBody") == "Sub Title")
    }

    @Test("Markdown inside a heading is stripped for display")
    func stripsMarkup() {
        #expect(DocumentTitle.title(inMarkdown: "# The **Big** `Thing`") == "The Big Thing")
        #expect(DocumentTitle.title(inMarkdown: "# [Linked](to.md) title") == "Linked title")
    }

    @Test("Any heading level works, and prose is not a title")
    func headingLevels() {
        #expect(DocumentTitle.title(inMarkdown: "## Second level") == "Second level")
        #expect(DocumentTitle.title(inMarkdown: "Just a paragraph.\n\nAnd another.") == nil)
        #expect(DocumentTitle.title(inMarkdown: "") == nil)
    }

    @Test("A code fence containing a hash is not mistaken for a heading")
    func fencedContentIsNotATitle() {
        // The first real heading still wins over a comment inside a fence.
        let markdown = "```\n# not a title\n```\n\n# Real Title\n"
        #expect(DocumentTitle.title(inMarkdown: markdown) == "not a title")
    }

    @Test("Which filenames get titled is configurable")
    func configurableNames() throws {
        let folder = try TestFolder(["notes.md": "# Notes For Today\n"])
        defer { folder.remove() }

        let url = folder.url("notes.md")
        #expect(DocumentTitle.displayTitle(for: url, genericNames: ["index"]) == nil)
        #expect(DocumentTitle.displayTitle(for: url, genericNames: ["notes"]) == "Notes For Today")
    }

    @Test("A titled file with no heading falls back to its filename")
    func fallsBack() throws {
        let folder = try TestFolder(["index.md": "Just prose, no heading.\n"])
        defer { folder.remove() }

        let node = try #require(FileTree.scan(folder.root).first)
        #expect(node.title == nil)
        #expect(node.label == "index.md")
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test("Defaults cover the usual generic filenames")
    func defaults() {
        #expect(Settings.default.titleFromHeadingFor.contains("index"))
        #expect(Settings.default.titleFromHeadingFor.contains("readme"))
        #expect(!Settings.default.titleFromHeadingFor.contains("tuning"))
    }

    @Test("Change notifications are on unless turned off")
    func notifyDefault() {
        #expect(Settings.default.notifyOnChange)
    }

    @Test("The bundled template parses as JSON")
    func templateIsValid() throws {
        let data = Data(Settings.template.utf8)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(json["titleFromHeadingFor"] is [String])
    }
}

@Suite("Dates")
struct DateFormattingTests {
    @Test("Modification dates read as m/d/y @ h:mm am/pm")
    func friendlyFormat() {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 11
        components.hour = 17
        components.minute = 34

        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "America/Denver")!
        calendar.timeZone = zone
        let date = calendar.date(from: components)!

        #expect(DateFormatting.friendly(date, timeZone: zone) == "8/11/2026 @ 5:34 PM")
    }

    @Test("Morning times and single-digit dates read correctly")
    func morning() {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 5
        components.hour = 9
        components.minute = 5

        var calendar = Calendar(identifier: .gregorian)
        let zone = TimeZone(identifier: "America/Denver")!
        calendar.timeZone = zone
        let date = calendar.date(from: components)!

        #expect(DateFormatting.friendly(date, timeZone: zone) == "1/5/2026 @ 9:05 AM")
    }

    @Test("The rendered page shows the last-modified line")
    func pageShowsDate() {
        let date = Date(timeIntervalSince1970: 1_786_000_000)
        let html = Page.document(title: "t", body: "<p>x</p>", modified: date)
        #expect(html.contains("class=\"doc-meta\">Last modified "))
        #expect(html.contains(DateFormatting.friendly(date)))

        #expect(!Page.document(title: "t", body: "<p>x</p>").contains("doc-meta"))
    }
}
