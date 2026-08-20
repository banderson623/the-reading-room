import Foundation

/// The one edit this app makes to a document: ticking a task-list checkbox.
///
/// It rewrites exactly two characters — the `[ ]` / `[x]` marker on one line —
/// and only after confirming the line still holds a task item in the state the
/// page was showing. If the file has moved on underneath the reader, the write
/// is refused rather than guessed at.
public enum TaskListWriter {
    public enum Failure: Error, Equatable {
        /// The file has fewer lines than the page thought.
        case lineOutOfRange
        /// That line isn't a task-list item any more.
        case notATaskItem
        /// The marker is there, but not in the state the page was showing.
        case staleState
        /// The file isn't UTF-8 text.
        case unreadable
    }

    /// Flips the marker on `line` (1-based) of `text`. `was` is the state the
    /// page was showing, and must match what the file says.
    public static func toggling(
        line: Int,
        from was: Bool,
        to now: Bool,
        in text: String
    ) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count else { throw Failure.lineOutOfRange }

        let source = lines[line - 1]
        guard let marker = markerIndex(in: source) else { throw Failure.notATaskItem }
        guard isChecked(source[marker]) == was else { throw Failure.staleState }

        var updated = source
        updated.replaceSubrange(marker...marker, with: now ? "x" : " ")
        lines[line - 1] = updated
        return lines.joined(separator: "\n")
    }

    /// Applies the toggle to the file at `path`, in place.
    public static func toggle(
        line: Int,
        from was: Bool,
        to now: Bool,
        atPath path: String
    ) throws {
        // Follow symlinks first: an atomic write replaces the file it names, and
        // a document reached through a symlink should still edit the real file.
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw Failure.unreadable }
        let updated = try toggling(line: line, from: was, to: now, in: text)
        guard updated != text else { return }
        try Data(updated.utf8).write(to: url, options: .atomic)
    }

    /// The offset of the character between the brackets, for a line that reads
    /// as a task item: an unordered or ordered list marker, then `[ ]`/`[x]`,
    /// then a space or the end of the line.
    private static func markerIndex(in line: String) -> String.Index? {
        var index = line.startIndex
        func skipSpaces() {
            while index < line.endIndex, line[index] == " " || line[index] == "\t" {
                index = line.index(after: index)
            }
        }

        skipSpaces()
        guard index < line.endIndex else { return nil }

        if "-*+".contains(line[index]) {
            index = line.index(after: index)
        } else if line[index].isNumber {
            while index < line.endIndex, line[index].isNumber {
                index = line.index(after: index)
            }
            guard index < line.endIndex, line[index] == "." || line[index] == ")" else { return nil }
            index = line.index(after: index)
        } else {
            return nil
        }

        // A list marker has to be followed by whitespace to open an item.
        guard index < line.endIndex, line[index] == " " || line[index] == "\t" else { return nil }
        skipSpaces()

        guard index < line.endIndex, line[index] == "[" else { return nil }
        let box = line.index(after: index)
        guard box < line.endIndex, isChecked(line[box]) || line[box] == " " else { return nil }
        let close = line.index(after: box)
        guard close < line.endIndex, line[close] == "]" else { return nil }

        // GitHub wants whitespace (or nothing) after the box.
        let after = line.index(after: close)
        guard after == line.endIndex || line[after] == " " || line[after] == "\t" else { return nil }
        return box
    }

    private static func isChecked(_ character: Character) -> Bool {
        character == "x" || character == "X"
    }
}
