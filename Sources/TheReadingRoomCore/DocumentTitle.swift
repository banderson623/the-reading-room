import Foundation

/// Works out what to call a file in the sidebar.
///
/// Some filenames say nothing about their contents — `index.md` in twenty
/// folders is twenty rows that all read "index.md". For those, the document's
/// own title (front matter `title:`, else its first heading) is used instead.
/// The real filename stays available as the row's tooltip.
public enum DocumentTitle {
    /// Filenames (without extension, lowercased) that get titled from content.
    /// Extendable per user via `~/.config/the-reading-room/config.json`.
    public static let defaultGenericNames: Set<String> = [
        "index", "_index", "readme", "home", "overview",
        "introduction", "intro", "about", "start", "main",
    ]

    /// Only the head of a file is read — a title this far down isn't a title.
    static let headBytes = 8 * 1024
    static let headLines = 60

    /// The label to show for `url`, or nil to use the filename.
    public static func displayTitle(for url: URL, genericNames: Set<String>) -> String? {
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        guard genericNames.contains(base) else { return nil }
        guard let head = head(of: url) else { return nil }
        return title(inMarkdown: head)
    }

    /// Front matter `title:` if present, otherwise the first heading.
    public static func title(inMarkdown text: String) -> String? {
        let (body, frontMatter) = MarkdownRenderer.stripFrontMatter(text)
        if let frontMatter, let title = frontMatterTitle(frontMatter) { return title }

        var previous: String?
        for (index, rawLine) in body.components(separatedBy: "\n").enumerated() {
            if index >= headLines { break }
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // ATX heading: `# Title`
            if line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }
                guard hashes.count <= 6 else { continue }
                let text = line.dropFirst(hashes.count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t#"))
                if !text.isEmpty { return clean(text) }
                continue
            }

            // Setext heading: a line of === or --- under the title.
            if let previous, !previous.isEmpty, line.count >= 2 {
                if line.allSatisfy({ $0 == "=" }) || line.allSatisfy({ $0 == "-" }) {
                    return clean(previous)
                }
            }

            previous = line
        }
        return nil
    }

    private static func frontMatterTitle(_ frontMatter: String) -> String? {
        for line in frontMatter.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "title" else { continue }
            var value = parts[1].trimmingCharacters(in: .whitespaces)
            for quote in ["\"", "'"] where value.hasPrefix(quote) && value.hasSuffix(quote) && value.count > 1 {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { return clean(value) }
        }
        return nil
    }

    /// Strips the markdown a heading might contain, so the sidebar shows text.
    private static func clean(_ text: String) -> String {
        var out = text
        // Links: [label](target) -> label
        while let open = out.firstIndex(of: "["),
              let close = out[open...].firstIndex(of: "]"),
              out.index(after: close) < out.endIndex,
              out[out.index(after: close)] == "(",
              let end = out[close...].firstIndex(of: ")") {
            let label = String(out[out.index(after: open)..<close])
            out.replaceSubrange(open...end, with: label)
        }
        out = out.replacingOccurrences(of: "`", with: "")
        for marker in ["***", "___", "**", "__", "*", "_"] {
            out = out.replacingOccurrences(of: marker, with: "")
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func head(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: headBytes), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}
