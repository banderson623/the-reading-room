import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Document outline")
struct DocumentOutlineTests {
    @Test("Headings are listed in reading order with their levels")
    func order() {
        let markdown = """
        # Title

        ## First

        Some text.

        ### Nested

        ## Second
        """
        let outline = DocumentOutline.headings(inMarkdown: markdown)
        #expect(outline.map(\.text) == ["Title", "First", "Nested", "Second"])
        #expect(outline.map(\.level) == [1, 2, 3, 2])
    }

    @Test("Outline slugs agree with the anchors the renderer emits")
    func slugsMatchRenderedIDs() {
        let markdown = """
        # Hello, World!

        ## Hello, World!

        ## Configuração
        """
        let html = MarkdownRenderer.render(markdown: markdown)
        let outline = DocumentOutline.headings(inMarkdown: markdown)

        #expect(outline.count == 3)
        for item in outline {
            #expect(html.contains("id=\"\(item.slug)\""), "no anchor for \(item.slug)")
        }
        // Duplicates are disambiguated the same way on both sides.
        #expect(outline.map(\.slug) == ["hello-world", "hello-world-1", "configuração"])
    }

    @Test("Front matter contributes nothing to the outline")
    func frontMatter() {
        let markdown = "---\ntitle: Secret\n---\n\n# Body\n"
        let outline = DocumentOutline.headings(inMarkdown: markdown)
        #expect(outline.map(\.text) == ["Body"])
    }

    @Test("A document with no headings has an empty outline")
    func empty() {
        #expect(DocumentOutline.headings(inMarkdown: "Just prose.").isEmpty)
    }
}
