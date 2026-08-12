import Foundation

/// Scroll offsets per file, so reloads (⌘R, a file changing on disk, or picking
/// up where you left off after a relaunch) don't throw you back to the top.
/// Shared between the web view and the scheme handler, hence the lock.
public final class ScrollStore: @unchecked Sendable {
    public static let shared = ScrollStore()

    private let lock = NSLock()
    private var offsets: [String: Double] = [:]
    /// A set rather than one slot: several windows can be restoring at once.
    private var pendingRestores: Set<String> = []

    public func record(path: String, offset: Double) {
        lock.lock()
        offsets[path] = offset
        lock.unlock()
    }

    public func offset(for path: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return offsets[path] ?? 0
    }

    /// Ask that the next load of `path` come back to where we left off.
    public func requestRestore(path: String) {
        lock.lock()
        pendingRestores.insert(path)
        lock.unlock()
    }

    /// Consumes the pending request, if there is one for this path.
    public func takeRestore(path: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard pendingRestores.remove(path) != nil else { return nil }
        guard let offset = offsets[path], offset > 0 else { return nil }
        return offset
    }

    public func forget(path: String) {
        lock.lock()
        offsets[path] = nil
        pendingRestores.remove(path)
        lock.unlock()
    }
}
