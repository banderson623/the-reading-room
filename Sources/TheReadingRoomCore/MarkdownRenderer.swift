import Foundation
import Markdown

/// Renders a markdown document to GitHub-flavored HTML.
///
/// Link rewriting happens here rather than in JavaScript: relative links stay
/// relative (the page's own `mdv://` URL resolves them), so following a link to
/// another markdown file is an ordinary navigation and the web view's
/// back/forward history works for free.
public enum MarkdownRenderer {
    /// Markdown in, HTML fragment out (no surrounding page shell).
    public static func render(markdown: String) -> String {
        let (body, dropped) = bodyAfterFrontMatter(markdown)
        // No smart punctuation: GitHub leaves quotes and dashes as typed.
        let document = Document(parsing: body, options: [.disableSmartOpts])
        // Task checkboxes carry the line they came from, and the reader edits
        // the file on disk — so the count has to include the front matter that
        // parsing never saw.
        var formatter = HTMLFormatter(source: body, lineOffset: dropped)
        return formatter.visit(document)
    }

    /// Strips a leading YAML front matter block, returning the body and the raw
    /// front matter (if any). Front matter is metadata, not content.
    public static func stripFrontMatter(_ text: String) -> (body: String, frontMatter: String?) {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else {
            return (text, nil)
        }
        for index in 1..<lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                let frontMatter = lines[1..<index].joined(separator: "\n")
                let body = lines[(index + 1)...].joined(separator: "\n")
                return (body, frontMatter)
            }
        }
        return (text, nil)
    }

    /// The body, plus how many lines the front matter took — the offset that
    /// turns a parsed line number back into a line of the file on disk.
    static func bodyAfterFrontMatter(_ text: String) -> (body: String, droppedLines: Int) {
        let (body, frontMatter) = stripFrontMatter(text)
        guard frontMatter != nil else { return (body, 0) }
        let bodyLines = body.components(separatedBy: "\n").count
        return (body, text.components(separatedBy: "\n").count - bodyLines)
    }
}

// MARK: - HTML formatter

private struct HTMLFormatter: MarkupVisitor {
    typealias Result = String

    private var slugger = Slugger()
    /// The document's source, by line, as UTF-8 — source positions are byte
    /// offsets, and these files are full of em dashes.
    private let sourceLines: [[UInt8]]

    /// Added to every source line number this renderer reports, so the numbers
    /// name lines of the original file rather than of the parsed body.
    private let lineOffset: Int

    init(source: String, lineOffset: Int = 0) {
        sourceLines = source.components(separatedBy: "\n").map { Array($0.utf8) }
        self.lineOffset = lineOffset
    }

    mutating func defaultVisit(_ markup: Markup) -> String {
        visitChildren(of: markup)
    }

    private mutating func visitChildren(of markup: Markup) -> String {
        var out = ""
        for child in markup.children { out += visit(child) }
        return out
    }

    // MARK: Blocks

    mutating func visitDocument(_ document: Document) -> String {
        visitChildren(of: document)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(visitChildren(of: paragraph))</p>\n"
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let inner = visitChildren(of: heading)
        let text = heading.plainText
        let slug = uniqueSlug(for: text)
        let level = min(max(heading.level, 1), 6)
        return "<h\(level) id=\"\(escapeAttribute(slug))\">"
            + "<a class=\"anchor\" href=\"#\(escapeAttribute(slug))\" aria-hidden=\"true\"></a>"
            + "\(inner)</h\(level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let language = codeBlock.language?
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet(charactersIn: " \t{,:"))
            .first?
            .lowercased() ?? ""
        let classAttribute = language.isEmpty ? "" : " class=\"language-\(escapeAttribute(language))\""
        return "<pre><code\(classAttribute)>\(escapeHTML(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        html.rawHTML
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        if let alert = Alert(blockQuote) {
            var stripped = ""
            for (index, child) in blockQuote.children.enumerated() {
                if index == 0, let paragraph = child as? Paragraph {
                    stripped += renderAlertLead(paragraph)
                } else {
                    stripped += visit(child)
                }
            }
            return "<div class=\"markdown-alert markdown-alert-\(alert.kind)\">\n"
                + "<p class=\"markdown-alert-title\">\(alert.icon)\(alert.title)</p>\n"
                + stripped
                + "</div>\n"
        }
        return "<blockquote>\n\(visitChildren(of: blockQuote))</blockquote>\n"
    }

    /// Renders an alert's first paragraph with the `[!NOTE]` marker line removed.
    private mutating func renderAlertLead(_ paragraph: Paragraph) -> String {
        var inner = ""
        var skippingLead = true
        for child in paragraph.children {
            if skippingLead {
                // The marker is the first Text node; content resumes after the
                // line break that follows it.
                if child is Text { continue }
                if child is SoftBreak || child is LineBreak {
                    skippingLead = false
                    continue
                }
                skippingLead = false
            }
            inner += visit(child)
        }
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "<p>\(trimmed)</p>\n"
    }

    mutating func visitUnorderedList(_ list: UnorderedList) -> String {
        let isTaskList = list.listItems.contains { $0.checkbox != nil }
        let classAttribute = isTaskList ? " class=\"contains-task-list\"" : ""
        return "<ul\(classAttribute)>\n\(renderItems(of: list))</ul>\n"
    }

    mutating func visitOrderedList(_ list: OrderedList) -> String {
        let start = list.startIndex == 1 ? "" : " start=\"\(list.startIndex)\""
        return "<ol\(start)>\n\(renderItems(of: list))</ol>\n"
    }

    private mutating func renderItems(of list: ListItemContainer) -> String {
        let items = Array(list.listItems)
        let loose = isLoose(items)
        var out = ""
        for item in items {
            out += renderItem(item, loose: loose)
        }
        return out
    }

    private mutating func renderItem(_ item: ListItem, loose: Bool) -> String {
        // The checkbox goes inside the item's first paragraph. In a loose list
        // that paragraph is a block, so a checkbox placed before it would sit
        // stranded on a line of its own above the text.
        var pendingCheckbox = item.checkbox.map { checkbox -> String in
            let checked = checkbox == .checked ? " checked" : ""
            // The line the marker sits on: what the app rewrites when the
            // reader ticks the box. Rendered disabled — only the app enables it.
            let line = item.range.map { " data-line=\"\($0.lowerBound.line + lineOffset)\"" } ?? ""
            return "<input type=\"checkbox\"\(line) disabled\(checked)> "
        }
        var inner = ""
        for child in item.children {
            var rendered: String
            if !loose, let paragraph = child as? Paragraph {
                rendered = visitChildren(of: paragraph)
                if let checkbox = pendingCheckbox {
                    rendered = checkbox + rendered
                    pendingCheckbox = nil
                }
            } else {
                rendered = visit(child)
                if let checkbox = pendingCheckbox, child is Paragraph,
                   rendered.hasPrefix("<p>") {
                    rendered = "<p>" + checkbox + rendered.dropFirst("<p>".count)
                    pendingCheckbox = nil
                }
            }
            inner += rendered
        }
        guard item.checkbox != nil else {
            return "<li>\(inner)</li>\n"
        }
        // An item that opens with something other than a paragraph still needs
        // its checkbox somewhere: fall back to the front of the item.
        return "<li class=\"task-list-item\">\(pendingCheckbox ?? "")\(inner)</li>\n"
    }

    /// CommonMark looseness: a blank line between items, or between blocks
    /// inside an item, makes the whole list loose (its items wrap in `<p>`).
    /// Blank lines aren't in the tree, so this reads them off source ranges.
    private func isLoose(_ items: [ListItem]) -> Bool {
        for (previous, next) in zip(items, items.dropFirst()) {
            // An item's own range can swallow the blank line that follows it, so
            // measure from where its last child ends.
            guard let end = contentEndLine(of: previous),
                  let start = next.range?.lowerBound.line else { continue }
            if start > end + 1 { return true }
        }
        return items.contains { hasBlankLineBetween(Array($0.children)) }
    }

    private func contentEndLine(of item: ListItem) -> Int? {
        item.children.reversed().lazy
            .compactMap { $0.range?.upperBound.line }
            .first ?? item.range?.upperBound.line
    }

    private func hasBlankLineBetween(_ blocks: [Markup]) -> Bool {
        for (previous, next) in zip(blocks, blocks.dropFirst()) {
            guard let end = previous.range?.upperBound.line,
                  let start = next.range?.lowerBound.line else { continue }
            if start > end + 1 { return true }
        }
        return false
    }

    // MARK: Tables

    mutating func visitTable(_ table: Table) -> String {
        let alignments = table.columnAlignments
        var out = "<table>\n"
        out += renderRow(table.head, cellTag: "th", alignments: alignments, wrapper: "thead")
        let bodyRows = Array(table.body.rows)
        if !bodyRows.isEmpty {
            out += "<tbody>\n"
            for row in bodyRows {
                out += renderRow(row, cellTag: "td", alignments: alignments, wrapper: nil)
            }
            out += "</tbody>\n"
        }
        out += "</table>\n"
        return out
    }

    private mutating func renderRow(
        _ container: Markup,
        cellTag: String,
        alignments: [Table.ColumnAlignment?],
        wrapper: String?
    ) -> String {
        var cells = ""
        var column = 0
        for child in container.children {
            guard let cell = child as? Table.Cell else { continue }
            if cell.colspan == 0 || cell.rowspan == 0 { continue }
            var attributes = ""
            if column < alignments.count, let alignment = alignments[column] {
                attributes += " align=\"\(alignmentName(alignment))\""
            }
            if cell.colspan > 1 { attributes += " colspan=\"\(cell.colspan)\"" }
            if cell.rowspan > 1 { attributes += " rowspan=\"\(cell.rowspan)\"" }
            cells += "<\(cellTag)\(attributes)>\(visitChildren(of: cell))</\(cellTag)>"
            column += Int(cell.colspan)
        }
        let row = "<tr>\(cells)</tr>\n"
        guard let wrapper else { return row }
        return "<\(wrapper)>\n\(row)</\(wrapper)>\n"
    }

    private func alignmentName(_ alignment: Table.ColumnAlignment) -> String {
        switch alignment {
        case .left: return "left"
        case .center: return "center"
        case .right: return "right"
        }
    }

    // MARK: Inlines

    mutating func visitText(_ text: Text) -> String {
        escapeHTML(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(visitChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(visitChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        let inner = visitChildren(of: strikethrough)
        guard isDoubleTilde(strikethrough) else {
            // cmark-gfm also strikes through single-tilde pairs, which turns
            // prose like "~$230/mo … (~$200)" into one long struck-out run. The
            // GFM spec asks for two tildes, and in practice a lone tilde means
            // "approximately" or a home directory — so put it back as typed.
            return "~\(inner)~"
        }
        return "<del>\(inner)</del>"
    }

    private func isDoubleTilde(_ node: Strikethrough) -> Bool {
        guard let start = node.range?.lowerBound else { return true }
        let line = start.line - 1
        let column = start.column - 1
        guard sourceLines.indices.contains(line) else { return true }
        let bytes = sourceLines[line]
        guard column >= 0, column + 1 < bytes.count else { return true }
        let tilde = UInt8(ascii: "~")
        return bytes[column] == tilde && bytes[column + 1] == tilde
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(escapeHTML(inlineCode.code))</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        inlineHTML.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }

    mutating func visitLink(_ link: Link) -> String {
        let inner = visitChildren(of: link)
        guard let destination = link.destination, !destination.isEmpty else {
            return inner
        }
        let external = isExternal(destination)
        let target = external ? " data-external=\"1\"" : ""
        return "<a href=\"\(escapeAttribute(destination))\"\(target)>\(inner)</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        guard let source = image.source, !source.isEmpty else { return "" }
        let alt = image.plainText
        var attributes = " src=\"\(escapeAttribute(source))\" alt=\"\(escapeAttribute(alt))\""
        if let title = image.title, !title.isEmpty {
            attributes += " title=\"\(escapeAttribute(title))\""
        }
        return "<img\(attributes) loading=\"lazy\">"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> String {
        "<code>\(escapeHTML(symbolLink.destination ?? ""))</code>"
    }

    // MARK: Helpers

    private func isExternal(_ destination: String) -> Bool {
        guard let scheme = URL(string: destination)?.scheme?.lowercased() else { return false }
        return scheme != "file"
    }

    /// GitHub-compatible heading slug, de-duplicated with a numeric suffix.
    private mutating func uniqueSlug(for text: String) -> String {
        slugger.slug(for: text)
    }
}

/// GitHub-compatible heading slugs, de-duplicated with a numeric suffix.
///
/// Shared between the renderer (heading ids) and the document outline (jump
/// targets) — the two have to agree on every slug, so there is one algorithm.
struct Slugger {
    private var usedSlugs: [String: Int] = [:]

    mutating func slug(for text: String) -> String {
        var base = text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        base = String(base.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return character == " " ? "-" : " "
        })
        base = base.replacingOccurrences(of: " ", with: "")
        // No collapsing or trimming of hyphens: GitHub keeps them ("a - b"
        // slugs to "a---b"), and anchors written against GitHub's slugger
        // should resolve here too.
        if base.isEmpty { base = "section" }

        let count = usedSlugs[base, default: 0]
        usedSlugs[base] = count + 1
        return count == 0 ? base : "\(base)-\(count)"
    }
}

// MARK: - GitHub alerts

private struct Alert {
    let kind: String
    let title: String

    init?(_ blockQuote: BlockQuote) {
        guard let paragraph = blockQuote.child(at: 0) as? Paragraph,
              let text = paragraph.child(at: 0) as? Text else { return nil }
        let marker = text.string.trimmingCharacters(in: .whitespaces)
        guard marker.hasPrefix("[!"), marker.hasSuffix("]") else { return nil }
        let name = String(marker.dropFirst(2).dropLast()).uppercased()
        guard ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"].contains(name) else { return nil }
        kind = name.lowercased()
        title = name.prefix(1) + name.dropFirst().lowercased()
    }

    /// Inline SVG, so alerts render without any network or font dependency.
    var icon: String {
        let path: String
        switch kind {
        case "note":
            path = "M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"
        case "tip":
            path = "M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z"
        case "important":
            path = "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"
        case "warning":
            path = "M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"
        default:
            path = "M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"
        }
        return "<svg class=\"octicon\" viewBox=\"0 0 16 16\" width=\"16\" height=\"16\" "
            + "aria-hidden=\"true\"><path d=\"\(path)\"></path></svg>"
    }
}

// MARK: - Escaping

public func escapeHTML(_ string: String) -> String {
    var out = ""
    out.reserveCapacity(string.count)
    for character in string {
        switch character {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        default: out.append(character)
        }
    }
    return out
}

public func escapeAttribute(_ string: String) -> String {
    escapeHTML(string)
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
