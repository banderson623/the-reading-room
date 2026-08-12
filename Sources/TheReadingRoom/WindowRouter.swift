import AppKit
import SwiftUI
import TheReadingRoomCore

/// Decides which window a folder belongs in, and remembers the whole set across
/// launches.
///
/// Every way of opening something — ⌘O, Open Recent, a drop, Finder's "Open
/// With", the Dock icon — comes through `route(_:from:)`, so the rules live in
/// one place:
///
/// 1. A window already showing that folder is brought to the front. There is
///    never a second window on the same directory.
/// 2. Otherwise, if the window that asked is empty, it opens there.
/// 3. Otherwise the folder is queued and a new window is asked for.
///
/// Each window takes at most one queued entry as it appears, so a queued folder
/// is never opened twice. At launch there are no windows yet, so the first one
/// to appear picks up the first entry — which is how the saved session, queued
/// during launch, comes back.
@MainActor
final class WindowRouter: ObservableObject {
    static let shared = WindowRouter()

    /// Bumped when a queued folder needs a window; a live window watches this and
    /// creates one.
    @Published private(set) var spawnRequests = 0

    private struct Registration {
        weak var model: AppModel?
        weak var window: NSWindow?
    }

    private var windows: [UUID: Registration] = [:]
    private var pending: [WindowSession] = []
    private var openerWindow: UUID?
    private var hasQueuedSession = false
    private var hasClaimedFirstWindow = false

    private let sessionKey = "session"

    // MARK: - Routing

    func route(_ url: URL, from origin: UUID? = nil) {
        let (folder, file) = Self.folderAndFile(for: url)

        // 1. Already open somewhere — go there instead of opening it twice.
        if let (id, existing) = windows.first(where: { $0.value.model?.root == folder }) {
            focus(existing, selecting: file)
            // An empty window used only to pick this folder has no purpose now.
            if let origin, origin != id, let asked = windows[origin], asked.model?.root == nil {
                asked.window?.close()
            }
            return
        }

        // 2. The window that asked, if it has nothing open.
        if let origin, let asked = windows[origin], asked.model?.root == nil {
            asked.model?.open(url)
            return
        }

        // 3. A window of its own.
        enqueue(WindowSession(root: folder, selection: file))
    }

    private func enqueue(_ window: WindowSession) {
        pending.append(window)
        // No window yet (launch): the first one to appear takes it, and asks for
        // the next via `spawnWindowIfPending`.
        guard NSApp.windows.contains(where: \.isVisible) else { return }
        spawnRequests += 1
    }

    /// Asks for another window while a queued folder is still waiting.
    ///
    /// Every window calls this as it appears, so a saved session unfolds one
    /// window at a time: each new window takes an entry, then asks for the next.
    /// Bumping the counter once per remaining entry wouldn't work — the opener
    /// sees a single change no matter how much it went up by.
    func spawnWindowIfPending() {
        guard !pending.isEmpty else { return }
        spawnRequests += 1
    }

    private func focus(_ registration: Registration, selecting file: URL?) {
        NSApp.activate()
        registration.window?.makeKeyAndOrderFront(nil)
        if let file { registration.model?.select(file) }
    }

    /// Splits an opened URL into the folder to show and the file to select.
    private static func folderAndFile(for url: URL) -> (folder: URL, file: URL?) {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            return (url.canonicalFileURL, nil)
        }
        return (url.deletingLastPathComponent().canonicalFileURL, url.canonicalFileURL)
    }

    /// Consumes one queued window, if any.
    func take() -> WindowSession? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Whether some window is already showing this folder.
    func isOpenAnywhere(_ folder: URL) -> Bool {
        windows.values.contains { $0.model?.root == folder }
    }

    /// Brings a file on screen — used when a change notification is clicked.
    ///
    /// Unlike `route`, this looks for a window whose folder *contains* the file,
    /// since the file is usually nested somewhere below the opened folder.
    func reveal(file: URL, preferringRoot root: URL? = nil) {
        let file = file.canonicalFileURL

        if let root = root?.canonicalFileURL,
           let match = windows.values.first(where: { $0.model?.root == root }) {
            focus(match, selecting: file)
            return
        }

        let containing = windows.values.first { registration in
            guard let folder = registration.model?.root else { return false }
            return file.path.hasPrefix(folder.path + "/")
        }
        if let containing {
            focus(containing, selecting: file)
            return
        }

        // Nothing has it open any more; fall back to opening its folder.
        route(file)
    }

    // MARK: - Session

    /// Queues the windows from the last run. Called once, as the first window
    /// appears; anything opened from Finder is already ahead of it in the queue.
    func queueSavedSession() {
        guard !hasQueuedSession else { return }
        hasQueuedSession = true

        let saved = Session.decoded(from: UserDefaults.standard.data(forKey: sessionKey))
            .sanitized()
        // Appended rather than enqueued: `enqueue` asks for a new window, and
        // the window running this will take the first entry itself. The rest are
        // picked up by `spawnWindowIfPending`, one window at a time.
        for window in saved.windows where !isQueuedOrOpen(window.rootURL) {
            pending.append(window)
        }
    }

    private func isQueuedOrOpen(_ folder: URL) -> Bool {
        isOpenAnywhere(folder) || pending.contains { $0.rootURL == folder }
    }

    /// True once, for the first window of the launch.
    func claimFirstWindow() -> Bool {
        guard !hasClaimedFirstWindow else { return false }
        hasClaimedFirstWindow = true
        return true
    }

    /// Records what's on screen now, so the next launch can put it back.
    ///
    /// `allowingEmpty` is off by default: quitting tears windows down one by
    /// one, and the last teardown would otherwise overwrite a good record with
    /// nothing. Closing a folder on purpose passes true.
    func saveSession(allowingEmpty: Bool = false) {
        // Ordered by window position on screen, so windows come back in a stable
        // order rather than whatever the dictionary happens to hold.
        let ordered = windows.values
            .filter { $0.model?.root != nil }
            .sorted { ($0.window?.orderedIndex ?? 0) > ($1.window?.orderedIndex ?? 0) }

        let session = Session(
            windows: ordered.compactMap { registration in
                guard let model = registration.model, let root = model.root else { return nil }
                let selection = model.selection
                return WindowSession(
                    root: root,
                    selection: selection,
                    scroll: selection.map { ScrollStore.shared.offset(for: $0.path) } ?? 0
                )
            }
        )

        guard allowingEmpty || !session.windows.isEmpty else { return }
        UserDefaults.standard.set(session.encoded(), forKey: sessionKey)
    }

    /// Closing every folder deliberately should not be undone at next launch.
    func clearSession() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    // MARK: - Live windows

    func register(_ id: UUID, model: AppModel) {
        if openerWindow == nil { openerWindow = id }
        windows[id] = Registration(model: model, window: windows[id]?.window)
    }

    /// The `NSWindow` isn't available until the view is in a window, so it
    /// arrives separately from `register`.
    func attach(_ id: UUID, window: NSWindow?) {
        guard var registration = windows[id], window != nil else { return }
        registration.window = window
        windows[id] = registration
    }

    func unregister(_ id: UUID) {
        // Capture the layout before the window goes, so quitting keeps it.
        saveSession()
        windows[id] = nil
        if openerWindow == id { openerWindow = nil }
    }

    /// The first live window creates windows for queued folders; if it closes,
    /// the next one to check in takes over.
    func isOpener(_ id: UUID) -> Bool {
        if openerWindow == nil { openerWindow = id }
        return openerWindow == id
    }
}

/// Hands the enclosing `NSWindow` back to SwiftUI, so the router can bring a
/// particular window to the front.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(view.window) }
    }
}
