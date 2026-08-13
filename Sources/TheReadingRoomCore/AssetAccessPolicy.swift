import Foundation

/// Decides whether a non-markdown file may be served to the page.
///
/// Markdown navigations are user actions — a click on a link — but asset
/// requests (images, mostly) are made by the document on its own authority.
/// An untrusted document could reference `/Users/…` paths it has no business
/// showing, so assets are only served from inside folders the reader opened:
/// the window's root, and the folder of the document being read (which can sit
/// outside the root after following a `../` link).
public enum AssetAccessPolicy {
    public static func allows(path: String, withinAny roots: [URL]) -> Bool {
        guard !roots.isEmpty else { return false }
        let requested = URL(fileURLWithPath: path).canonicalFileURL.path
        return roots.contains { root in
            let base = root.canonicalFileURL.path
            return requested == base || requested.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        }
    }
}
