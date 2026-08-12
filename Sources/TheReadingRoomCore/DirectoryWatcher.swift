import Foundation

/// Watches a folder tree with FSEvents and reports changed paths, debounced.
/// Used for two things: refreshing the sidebar when files appear or disappear,
/// and re-rendering the open document when it changes on disk.
public final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "the-reading-room.fsevents")
    private let onChange: ([String]) -> Void
    private var pending: Set<String> = []
    private var debounce: DispatchWorkItem?

    public init(url: URL, onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = paths.assumingMemoryBound(to: UnsafeMutableRawPointer?.self)
                as UnsafeMutablePointer<UnsafeMutableRawPointer?>? else { return }
            var changed: [String] = []
            for index in 0..<count {
                if let pointer = paths[index] {
                    changed.append(String(cString: pointer.assumingMemoryBound(to: CChar.self)))
                }
            }
            watcher.enqueue(changed)
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
            )
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    /// Coalesce bursts (editors write several times per save) into one callback.
    private func enqueue(_ paths: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            pending.formUnion(paths)
            debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let batch = Array(pending)
                pending.removeAll()
                DispatchQueue.main.async { self.onChange(batch) }
            }
            debounce = work
            queue.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
    }
}
