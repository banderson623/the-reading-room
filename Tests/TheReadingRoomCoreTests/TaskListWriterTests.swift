import Foundation
import Testing

@testable import TheReadingRoomCore

@Suite("Ticking task boxes")
struct TaskListWriterTests {
    private let document = """
    # Notes

    - [ ] first
    - [x] second
      with a wrapped line
    * [ ] star bullet
    1. [ ] numbered

    Not a list: [ ] nothing to tick.
    """

    @Test("Ticking a box rewrites only that marker")
    func ticksABox() throws {
        let updated = try TaskListWriter.toggling(line: 3, from: false, to: true, in: document)
        #expect(updated.components(separatedBy: "\n")[2] == "- [x] first")
        // Every other line is untouched, trailing newline included.
        let before = document.components(separatedBy: "\n")
        let after = updated.components(separatedBy: "\n")
        #expect(before.count == after.count)
        #expect(zip(before, after).enumerated().allSatisfy { $0.offset == 2 || $0.element.0 == $0.element.1 })
    }

    @Test("Un-ticking works, on any bullet style")
    func unticks() throws {
        #expect(try TaskListWriter.toggling(line: 4, from: true, to: false, in: document)
            .contains("- [ ] second"))
        #expect(try TaskListWriter.toggling(line: 6, from: false, to: true, in: document)
            .contains("* [x] star bullet"))
        #expect(try TaskListWriter.toggling(line: 7, from: false, to: true, in: document)
            .contains("1. [x] numbered"))
    }

    @Test("An uppercase X counts as checked")
    func uppercaseX() throws {
        let updated = try TaskListWriter.toggling(line: 1, from: true, to: false, in: "- [X] done")
        #expect(updated == "- [ ] done")
    }

    @Test("A line that isn't a task item is refused")
    func refusesNonTaskLines() {
        #expect(throws: TaskListWriter.Failure.notATaskItem) {
            try TaskListWriter.toggling(line: 9, from: false, to: true, in: document)
        }
        #expect(throws: TaskListWriter.Failure.notATaskItem) {
            try TaskListWriter.toggling(line: 1, from: false, to: true, in: document)
        }
        #expect(throws: TaskListWriter.Failure.notATaskItem) {
            try TaskListWriter.toggling(line: 5, from: false, to: true, in: document)
        }
    }

    @Test("A file that moved on underneath the page is refused")
    func refusesStaleState() {
        #expect(throws: TaskListWriter.Failure.staleState) {
            try TaskListWriter.toggling(line: 4, from: false, to: true, in: document)
        }
        #expect(throws: TaskListWriter.Failure.lineOutOfRange) {
            try TaskListWriter.toggling(line: 99, from: false, to: true, in: document)
        }
    }

    @Test("Rendered line numbers point at the right markers")
    func lineNumbersMatchTheRenderedPage() throws {
        let markdown = """
        ---
        title: Notes
        ---
        # Notes

        - [ ] first

        - [ ] second
        """
        let html = MarkdownRenderer.render(markdown: markdown)
        let lines = html.components(separatedBy: "data-line=\"").dropFirst()
            .compactMap { Int($0.prefix { $0.isNumber }) }
        #expect(lines == [6, 8])
        for line in lines {
            // Each reported line really is the marker for that item.
            #expect(try TaskListWriter.toggling(line: line, from: false, to: true, in: markdown)
                .components(separatedBy: "\n")[line - 1].contains("[x]"))
        }
    }

    @Test("The file on disk is updated in place")
    func writesTheFile() throws {
        let folder = try TestFolder(["notes.md": document])
        defer { folder.remove() }
        let path = folder.url("notes.md").path

        try TaskListWriter.toggle(line: 3, from: false, to: true, atPath: path)
        let updated = try String(contentsOf: folder.url("notes.md"), encoding: .utf8)
        #expect(updated.contains("- [x] first"))
        #expect(updated.contains("- [x] second"))

        // A refused write leaves the file exactly as it was.
        #expect(throws: TaskListWriter.Failure.staleState) {
            try TaskListWriter.toggle(line: 3, from: false, to: true, atPath: path)
        }
        #expect(try String(contentsOf: folder.url("notes.md"), encoding: .utf8) == updated)
    }

    @Test("A document reached through a symlink edits the real file")
    func followsSymlinks() throws {
        let folder = try TestFolder(["notes.md": "- [ ] first\n"])
        defer { folder.remove() }
        let link = folder.url("link.md")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.url("notes.md"))

        try TaskListWriter.toggle(line: 1, from: false, to: true, atPath: link.path)
        #expect(try String(contentsOf: folder.url("notes.md"), encoding: .utf8) == "- [x] first\n")
        // The link is still a link — the atomic write replaced its target.
        let isSymlink = try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
        #expect(isSymlink == true)
    }
}
