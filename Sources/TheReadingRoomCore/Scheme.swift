import Foundation

/// The custom URL scheme the web view loads everything through.
///
/// Using a scheme instead of `file://` means relative links and images resolve
/// with ordinary URL rules — a link to `../guide.md` from
/// `mdv://doc/Users/me/docs/api.md` becomes `mdv://doc/Users/me/guide.md` — so
/// following markdown links is a normal navigation with working back/forward
/// history, and no `file://` read-access restrictions get in the way.
public enum Scheme {
    public static let name = "mdv"
    public static let documentHost = "doc"
    public static let assetHost = "asset"

    public static func documentURL(for path: String) -> URL {
        var components = URLComponents()
        components.scheme = name
        components.host = documentHost
        components.path = path.hasPrefix("/") ? path : "/" + path
        return components.url ?? URL(string: "\(name)://\(documentHost)/")!
    }

    public static func assetURL(_ name: String) -> String {
        "\(Self.name)://\(assetHost)/\(name)"
    }

    /// The file path a document URL refers to, or nil if it isn't one.
    public static func path(of url: URL) -> String? {
        guard url.scheme == name, url.host == documentHost, !url.path.isEmpty else { return nil }
        return url.path
    }
}
