import Foundation

extension URL {
    /// The canonical file URL, with every symlink in the path resolved.
    ///
    /// `resolvingSymlinksInPath()` is not enough: it *strips* a leading
    /// `/private`, while `FileManager` hands back paths that include it — so a
    /// folder opened as `/var/…` would never compare equal to the files found
    /// inside it. `realpath` gives the one spelling both sides agree on, which
    /// matters because file URLs are the identity of everything here: sidebar
    /// selection, expansion state, and search results.
    public var canonicalFileURL: URL {
        guard isFileURL else { return self }
        guard let resolved = path.withCString({ pointer -> String? in
            guard let result = realpath(pointer, nil) else { return nil }
            defer { free(result) }
            return String(cString: result)
        }) else {
            return standardizedFileURL
        }
        return URL(fileURLWithPath: resolved)
    }
}
