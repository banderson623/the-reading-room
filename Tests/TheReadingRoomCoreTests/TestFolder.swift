import Foundation

@testable import TheReadingRoomCore

/// A throwaway folder tree for tests.
///
/// The root is resolved *after* creation on purpose: `resolvingSymlinksInPath()`
/// can't resolve a path that doesn't exist yet, and `/var` → `/private/var` on
/// macOS — so resolving too early leaves URLs that don't compare equal to the
/// ones `FileManager` hands back when scanning.
struct TestFolder {
    let root: URL

    init(_ files: [String: String]) throws {
        let created = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mdv-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        root = created.canonicalFileURL

        for (path, contents) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    func write(_ contents: String, to path: String) throws {
        try Data(contents.utf8).write(to: url(path))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
