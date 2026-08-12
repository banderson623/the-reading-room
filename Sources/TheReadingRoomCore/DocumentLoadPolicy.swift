import Foundation

/// Decides whether the viewer should load a document right now.
///
/// This looks trivial, and it shipped broken: the selection is set before
/// SwiftUI has built the web view, so the first request arrives with nowhere to
/// put it. Recording the path anyway marked it loaded, and the call that came
/// back moments later — this time with a view — was skipped as redundant. The
/// result was a window that never rendered anything.
public enum DocumentLoadPolicy {
    /// - Parameters:
    ///   - requested: the path the app wants on screen.
    ///   - loaded: the path currently loaded, if any.
    ///   - hasWebView: whether there is a web view to load into yet.
    public static func shouldLoad(
        requested: String?,
        loaded: String?,
        hasWebView: Bool
    ) -> Bool {
        guard let requested, !requested.isEmpty else { return false }
        guard hasWebView else { return false }
        return requested != loaded
    }
}
