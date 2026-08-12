import Foundation

/// One file that matched a search, with a preview of the first match.
public struct SearchHit: Identifiable, Hashable, Sendable {
    public let url: URL
    public let matchCount: Int
    public let lineNumber: Int
    public let snippet: String

    public var id: URL { url }
}

/// Full-text search across a folder of markdown files.
///
/// File contents are cached by modification date, so typing into the search
/// field re-scans from memory instead of re-reading the disk. Searches run on a
/// background queue and check `isCancelled` between files, so a search in
/// progress is abandoned as soon as the query changes.
public final class ContentSearch: @unchecked Sendable {
    public static let shared = ContentSearch()

    /// Files bigger than this are skipped — they aren't documents anyone reads.
    private let maxFileBytes: Int
    /// Total cached text; the cache is dropped wholesale past this.
    private let maxCacheBytes: Int
    /// Matches counted per file before we stop counting.
    private let maxMatchesPerFile = 500
    private let snippetWidth = 140

    private struct Entry {
        let modified: Date
        let size: Int
        let text: String
    }

    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var cachedBytes = 0

    public init(maxFileBytes: Int = 4 * 1024 * 1024, maxCacheBytes: Int = 64 * 1024 * 1024) {
        self.maxFileBytes = maxFileBytes
        self.maxCacheBytes = maxCacheBytes
    }

    /// Searches `files` for `query`, preserving the order they were given in.
    public func search(
        query: String,
        in files: [URL],
        isCancelled: () -> Bool = { false }
    ) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        var hits: [SearchHit] = []
        for url in files {
            if isCancelled() { return [] }
            guard let text = text(for: url) else { continue }
            if let hit = match(needle: needle, in: text, url: url) {
                hits.append(hit)
            }
        }
        return hits
    }

    /// Forget a file's cached contents — call this when it changes on disk.
    public func invalidate(path: String) {
        lock.lock()
        if let entry = cache.removeValue(forKey: path) {
            cachedBytes -= entry.text.utf8.count
        }
        lock.unlock()
    }

    public func invalidateAll() {
        lock.lock()
        cache.removeAll()
        cachedBytes = 0
        lock.unlock()
    }

    // MARK: - Matching

    private func match(needle: String, in text: String, url: URL) -> SearchHit? {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let first = text.range(of: needle, options: options) else { return nil }

        var count = 1
        var searchStart = first.upperBound
        while count < maxMatchesPerFile,
              let next = text.range(of: needle, options: options, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = next.upperBound
        }

        return SearchHit(
            url: url,
            matchCount: count,
            lineNumber: lineNumber(of: first.lowerBound, in: text),
            snippet: snippet(around: first, in: text)
        )
    }

    private func lineNumber(of index: String.Index, in text: String) -> Int {
        var line = 1
        var cursor = text.startIndex
        while cursor < index {
            if text[cursor] == "\n" { line += 1 }
            cursor = text.index(after: cursor)
        }
        return line
    }

    /// The matching line, trimmed and windowed so the match itself is visible.
    private func snippet(around range: Range<String.Index>, in text: String) -> String {
        var lineStart = range.lowerBound
        while lineStart > text.startIndex {
            let previous = text.index(before: lineStart)
            if text[previous] == "\n" { break }
            lineStart = previous
        }
        var lineEnd = range.upperBound
        while lineEnd < text.endIndex, text[lineEnd] != "\n" {
            lineEnd = text.index(after: lineEnd)
        }

        let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)
        guard line.count > snippetWidth else { return line }

        // Keep the match in view by windowing around it.
        let matchOffset = text.distance(from: lineStart, to: range.lowerBound)
        let leading = max(0, matchOffset - snippetWidth / 3)
        let start = line.index(line.startIndex, offsetBy: min(leading, line.count))
        let end = line.index(start, offsetBy: min(snippetWidth, line.distance(from: start, to: line.endIndex)))
        var windowed = String(line[start..<end])
        if leading > 0 { windowed = "…" + windowed }
        if end < line.endIndex { windowed += "…" }
        return windowed
    }

    // MARK: - Cache

    private func text(for url: URL) -> String? {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
        let size = (attributes?[.size] as? Int) ?? 0
        guard size > 0, size <= maxFileBytes else { return nil }

        lock.lock()
        if let entry = cache[path], entry.modified == modified, entry.size == size {
            lock.unlock()
            return entry.text
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }

        lock.lock()
        if cachedBytes > maxCacheBytes {
            cache.removeAll()
            cachedBytes = 0
        }
        cache[path] = Entry(modified: modified, size: size, text: text)
        cachedBytes += text.utf8.count
        lock.unlock()

        return text
    }
}
