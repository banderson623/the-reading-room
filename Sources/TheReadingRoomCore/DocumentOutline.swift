import Foundation
import Markdown

/// One heading in a document, with the anchor the renderer gave it.
public struct OutlineItem: Hashable, Sendable, Identifiable {
    public let level: Int
    public let text: String
    /// Matches the `id` the renderer put on the heading, so jumping to
    /// `#slug` lands on it.
    public let slug: String

    public var id: String { slug }

    public init(level: Int, text: String, slug: String) {
        self.level = level
        self.text = text
        self.slug = slug
    }
}

/// The document's headings, in reading order — the table of contents.
///
/// Parses the same way the renderer does and assigns slugs with the same
/// `Slugger`, so every item's anchor agrees with the rendered page.
public enum DocumentOutline {
    public static func headings(inMarkdown text: String) -> [OutlineItem] {
        let (body, _) = MarkdownRenderer.stripFrontMatter(text)
        let document = Document(parsing: body, options: [.disableSmartOpts])
        var collector = HeadingCollector()
        collector.visit(document)
        return collector.items
    }
}

private struct HeadingCollector: MarkupWalker {
    var items: [OutlineItem] = []
    private var slugger = Slugger()

    mutating func visitHeading(_ heading: Heading) {
        let text = heading.plainText
        items.append(
            OutlineItem(
                level: min(max(heading.level, 1), 6),
                text: text,
                slug: slugger.slug(for: text)
            )
        )
    }
}
