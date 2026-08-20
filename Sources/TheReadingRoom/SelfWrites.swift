import Foundation

/// Remembers files this app just wrote, so the watcher doesn't re-render a
/// document in response to the app's own edit. Ticking a checkbox already
/// updated the page; reloading on top of it only makes the page flicker.
@MainActor
final class SelfWrites {
    static let shared = SelfWrites()

    /// How long after a write an event still counts as ours. FSEvents coalesces
    /// on a quarter-second timer, so this only has to outlast that.
    private let window: TimeInterval = 3

    private var recent: [String: Date] = [:]

    /// Called just before writing, so the event can't arrive first.
    func record(path: String) {
        recent[path] = Date()
        prune()
    }

    /// True if this path's change is one we made — and forgets it, so the next
    /// change to the same file is treated as somebody else's.
    func claim(path: String) -> Bool {
        guard let written = recent[path], Date().timeIntervalSince(written) < window else {
            return false
        }
        recent[path] = nil
        return true
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-window)
        recent = recent.filter { $0.value > cutoff }
    }
}
