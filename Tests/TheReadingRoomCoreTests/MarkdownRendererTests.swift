import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Markdown rendering")
struct MarkdownRendererTests {
    @Test("Headings get GitHub-style slugs and hover anchors")
    func headingSlugs() {
        let html = MarkdownRenderer.render(markdown: "# Hello, World!\n\n## Hello, World!")
        #expect(html.contains("<h1 id=\"hello-world\">"))
        #expect(html.contains("<h2 id=\"hello-world-1\">"))
        #expect(html.contains("<a class=\"anchor\" href=\"#hello-world\""))
    }

    @Test("Slugs keep consecutive hyphens, exactly as GitHub does")
    func gitHubCompatibleSlugs() {
        // GitHub slugs "a - b" to "a---b" (spaces become hyphens, the literal
        // hyphen stays); a link written against GitHub must resolve here.
        let html = MarkdownRenderer.render(markdown: "# a - b\n\n## C++ API")
        #expect(html.contains("<h1 id=\"a---b\">"))
        #expect(html.contains("<h2 id=\"c-api\">"))
    }

    @Test("Front matter is metadata, not content")
    func frontMatter() {
        let markdown = "---\ntitle: Secret\n---\n\n# Body\n"
        let html = MarkdownRenderer.render(markdown: markdown)
        #expect(!html.contains("Secret"))
        #expect(html.contains("<h1 id=\"body\">"))
    }

    @Test("A document that merely starts with a rule keeps its content")
    func thematicBreakIsNotFrontMatter() {
        let (body, frontMatter) = MarkdownRenderer.stripFrontMatter("---\n\n# Title\n")
        // No closing delimiter, so nothing is stripped.
        #expect(frontMatter == nil)
        #expect(body.contains("# Title"))
    }

    @Test("Fenced code carries a language class for the highlighter")
    func codeBlocks() {
        let html = MarkdownRenderer.render(markdown: "```swift\nlet x = 1\n```")
        #expect(html.contains("<pre><code class=\"language-swift\">let x = 1"))

        let plain = MarkdownRenderer.render(markdown: "```\nplain\n```")
        #expect(plain.contains("<pre><code>plain"))
    }

    @Test("Tables render with per-column alignment")
    func tables() {
        let markdown = """
        | A | B | C |
        | - | :-: | --: |
        | 1 | 2 | 3 |
        """
        let html = MarkdownRenderer.render(markdown: markdown)
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th align=\"center\">B</th>"))
        #expect(html.contains("<td align=\"right\">3</td>"))
        #expect(!html.contains("<th align=\"left\">A</th>"))
    }

    @Test("Task list items become disabled checkboxes")
    func taskLists() {
        let html = MarkdownRenderer.render(markdown: "- [x] done\n- [ ] todo")
        #expect(html.contains("class=\"contains-task-list\""))
        #expect(html.contains("<input type=\"checkbox\" data-line=\"1\" disabled checked> done"))
        #expect(html.contains("<input type=\"checkbox\" data-line=\"2\" disabled> todo"))
    }

    @Test("A loose task list keeps the checkbox inside the first paragraph")
    func looseTaskLists() {
        let markdown = """
        - [ ] first item

        - [x] second item
        """
        let html = MarkdownRenderer.render(markdown: markdown)
        #expect(html.contains(
            "<li class=\"task-list-item\"><p><input type=\"checkbox\" data-line=\"1\" disabled> first item</p>"))
        #expect(html.contains(
            "<li class=\"task-list-item\"><p><input type=\"checkbox\" data-line=\"3\" disabled checked> "
                + "second item</p>"))
        #expect(!html.contains("disabled> <p>"))
    }

    @Test("Task checkboxes carry the source line, counting front matter")
    func taskCheckboxLines() {
        let markdown = """
        ---
        title: Notes
        ---
        # Notes

        - [ ] first
        - [x] second
        """
        let html = MarkdownRenderer.render(markdown: markdown)
        #expect(html.contains("data-line=\"6\" disabled> first"))
        #expect(html.contains("data-line=\"7\" disabled checked> second"))
    }

    @Test("A list with a nested sublist and no blank lines stays tight")
    func tightList() {
        let html = MarkdownRenderer.render(markdown: "- one\n- two\n  - nested\n")
        #expect(html.contains("<li>one</li>"))
        #expect(!html.contains("<li><p>"))
    }

    @Test("Blank lines between items make a list loose")
    func looseList() {
        let html = MarkdownRenderer.render(markdown: "- one\n\n- two\n")
        #expect(html.contains("<li><p>one</p>"))
    }

    @Test("Ordered lists keep a non-default start")
    func orderedListStart() {
        #expect(MarkdownRenderer.render(markdown: "7. seven\n8. eight").contains("<ol start=\"7\">"))
        #expect(MarkdownRenderer.render(markdown: "1. one").contains("<ol>"))
    }

    @Test("GitHub alerts become styled callouts with the marker removed")
    func alerts() {
        let html = MarkdownRenderer.render(markdown: "> [!WARNING]\n> Be careful.")
        #expect(html.contains("markdown-alert markdown-alert-warning"))
        #expect(html.contains(">Warning</p>"))
        #expect(html.contains("<p>Be careful.</p>"))
        #expect(!html.contains("[!WARNING]"))
    }

    @Test("An unrecognized marker is left as an ordinary blockquote")
    func nonAlertBlockquote() {
        let html = MarkdownRenderer.render(markdown: "> [!SOMETHING]\n> text")
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("[!SOMETHING]"))
    }

    @Test("Inline formatting maps to the expected tags")
    func inlineFormatting() {
        let html = MarkdownRenderer.render(markdown: "**b** *i* `c` ~~s~~")
        #expect(html.contains("<strong>b</strong>"))
        #expect(html.contains("<em>i</em>"))
        #expect(html.contains("<code>c</code>"))
        #expect(html.contains("<del>s</del>"))
    }

    @Test("Links are tagged external so the app can route them to the browser")
    func links() {
        let html = MarkdownRenderer.render(
            markdown: "[out](https://example.com) and [in](./other.md)"
        )
        #expect(html.contains("<a href=\"https://example.com\" data-external=\"1\">out</a>"))
        #expect(html.contains("<a href=\"./other.md\">in</a>"))
    }

    @Test("Text is escaped; only real HTML blocks pass through")
    func escaping() {
        let html = MarkdownRenderer.render(markdown: "A < B & C > D\n\n`<script>`")
        #expect(html.contains("A &lt; B &amp; C &gt; D"))
        #expect(html.contains("<code>&lt;script&gt;</code>"))
    }

    @Test("Images render with alt text and lazy loading")
    func images() {
        let html = MarkdownRenderer.render(markdown: "![a \"quoted\" alt](img/x.png)")
        #expect(html.contains("src=\"img/x.png\""))
        #expect(html.contains("alt=\"a &quot;quoted&quot; alt\""))
        #expect(html.contains("loading=\"lazy\""))
    }

    @Test("A lone tilde means \"approximately\", not strikethrough")
    func singleTildeIsNotStrikethrough() {
        // cmark-gfm pairs single tildes, which turned a sentence full of
        // approximate dollar amounts into one long struck-out run.
        let markdown = "but ~$230/mo still bills — two connectors (~$200), "
            + "a rule (~$17), storage (~$23)."
        let html = MarkdownRenderer.render(markdown: markdown)
        #expect(!html.contains("<del>"))
        #expect(html.contains("~$230/mo"))
        #expect(html.contains("(~$200)"))
        #expect(html.contains("(~$23)"))
    }

    @Test("Double tildes still strike through")
    func doubleTildeStrikesThrough() {
        let html = MarkdownRenderer.render(markdown: "a ~~struck~~ word and ~approx~ values")
        #expect(html.contains("<del>struck</del>"))
        #expect(html.contains("~approx~"))
    }

    @Test("Tildes survive alongside multi-byte characters")
    func tildesAfterMultibyte() {
        // Source positions are byte offsets, so an em dash before the tilde
        // shifts them; getting this wrong strikes out the wrong span.
        let html = MarkdownRenderer.render(markdown: "cost — ~$5 versus ~$9 monthly")
        #expect(!html.contains("<del>"))
        #expect(html.contains("~$5"))
        #expect(html.contains("~$9"))

        let struck = MarkdownRenderer.render(markdown: "cost — ~~gone~~ now")
        #expect(struck.contains("<del>gone</del>"))
    }

    @Test("A home directory path in prose is left alone")
    func homeDirectoryPaths() {
        let html = MarkdownRenderer.render(markdown: "put it in ~/Documents or ~/Desktop")
        #expect(!html.contains("<del>"))
        #expect(html.contains("~/Documents"))
        #expect(html.contains("~/Desktop"))
    }

    @Test("Quotes and dashes are left as typed, like GitHub")
    func noSmartPunctuation() {
        let html = MarkdownRenderer.render(markdown: "He said \"hi\" -- really.")
        #expect(html.contains("\"hi\""))
        #expect(html.contains("--"))
    }

    @Test("Rendering a large document stays fast")
    func performance() {
        let section = """
        ## Section

        Some **text** with a [link](x.md) and `code`.

        | a | b |
        | - | - |
        | 1 | 2 |

        ```swift
        let x = 1
        ```

        - one
        - two

        """
        let markdown = String(repeating: section, count: 400)
        let started = Date()
        let html = MarkdownRenderer.render(markdown: markdown)
        let elapsed = Date().timeIntervalSince(started)
        #expect(html.count > 10_000)
        #expect(elapsed < 2.0, "rendering ~400 sections took \(elapsed)s")
    }
}
