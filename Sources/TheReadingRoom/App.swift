import AppKit
import SwiftUI
import TheReadingRoomCore

@main
struct TheReadingRoomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        CommandLineMode.runIfRequested()
    }

    var body: some Scene {
        // Keyed by a UUID rather than being a plain WindowGroup: `openWindow`
        // only creates an additional window when it's given a value it hasn't
        // seen: without one it just activates the window that already exists,
        // and a saved session of several folders could never unfold.
        //
        // Each window owns its own folder, selection, and history. ⌘N starts
        // empty — reopening the last folder there would duplicate a window that
        // already has it.
        WindowGroup(id: Self.windowGroupID, for: UUID.self) { $key in
            RootView(windowID: key ?? UUID())
                .frame(minWidth: 620, minHeight: 400)
        }
        .defaultSize(width: 1100, height: 780)
        .commands { ViewerCommands() }
    }

    static let windowGroupID = "viewer"
}

/// One window's worth of state.
private struct RootView: View {
    /// Identity for this window, from the scene's value.
    let windowID: UUID

    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var router = WindowRouter.shared
    /// `onAppear` can fire more than once for one window; without this, a
    /// window would take a second queued folder and replace its own.
    @State private var hasTakenQueuedWindow = false

    var body: some View {
        ContentView()
            .environmentObject(model)
            // Lets menu commands act on whichever window is focused.
            .focusedSceneObject(model)
            .background(WindowAccessor { router.attach(windowID, window: $0) })
            .onAppear {
                guard !hasTakenQueuedWindow else { return }
                hasTakenQueuedWindow = true

                model.windowID = windowID
                router.register(windowID, model: model)
                // Puts last run's windows in the queue behind anything Finder
                // asked for; does nothing after the first window.
                router.queueSavedSession()
                if let window = router.take() {
                    model.restore(window)
                } else if router.claimFirstWindow() {
                    model.restoreLastFolder()
                }
                router.spawnWindowIfPending()
            }
            .onDisappear { router.unregister(windowID) }
            .onChange(of: router.spawnRequests) {
                // A folder is waiting for a window; one window creates it, with a
                // fresh key so SwiftUI makes a window instead of reusing this one.
                if router.isOpener(windowID) {
                    openWindow(id: TheReadingRoomApp.windowGroupID, value: UUID())
                }
            }
    }
}

private struct ViewerCommands: Commands {
    @FocusedObject private var model: AppModel?

    var body: some Commands {
        // Left after .newItem so SwiftUI keeps its own "New Window" item.
        CommandGroup(after: .newItem) {
            Button("Open…") { model?.presentOpenPanel() }
                .keyboardShortcut("o")

            Menu("Open Recent") {
                ForEach(model?.recentFolders ?? [], id: \.self) { url in
                    Button(url.lastPathComponent) { model?.openPreferringNewWindow(url) }
                }
                if !(model?.recentFolders.isEmpty ?? true) {
                    Divider()
                    Button("Clear Menu") { model?.clearRecentFolders() }
                }
            }
            .disabled(model?.recentFolders.isEmpty ?? true)

            Divider()

            Button("Close Folder") { model?.closeFolder() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(model?.root == nil)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") { model?.webViewController.printDocument() }
                .keyboardShortcut("p")
                .disabled(model?.selection == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Relative Path") {
                guard let model, let selection = model.selection else { return }
                model.copyToClipboard(model.relativePath(of: selection))
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model?.selection == nil)

            Button("Copy Path") {
                guard let model, let selection = model.selection else { return }
                model.copyToClipboard(selection.path)
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            .disabled(model?.selection == nil)

            Divider()
            Button("Find in Page…") { model?.findBarVisible = true }
                .keyboardShortcut("f")
                .disabled(model?.selection == nil)
            Button("Search Folder Contents…") { model?.focusSearchField() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(model?.root == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            Picker("Sort Files By", selection: sortBinding) {
                ForEach(FileTree.SortOrder.allCases, id: \.self) { order in
                    Text(order.label).tag(order)
                }
            }
            .disabled(model == nil)

            Divider()

            Button("Back") { model?.webViewController.goBack() }
                .keyboardShortcut("[")
                .disabled(!(model?.webViewController.canGoBack ?? false))

            Button("Forward") { model?.webViewController.goForward() }
                .keyboardShortcut("]")
                .disabled(!(model?.webViewController.canGoForward ?? false))

            Divider()

            Button("Reload") { model?.webViewController.reload() }
                .keyboardShortcut("r")
                .disabled(model?.selection == nil)

            Divider()

            Button("Zoom In") { model?.webViewController.zoomIn() }
                .keyboardShortcut("+")
                .disabled(!(model?.webViewController.canZoomIn ?? false))
            Button("Zoom Out") { model?.webViewController.zoomOut() }
                .keyboardShortcut("-")
                .disabled(!(model?.webViewController.canZoomOut ?? false))
            Button("Actual Size (\(model?.webViewController.zoomPercent ?? "100%"))") {
                model?.webViewController.resetZoom()
            }
            .keyboardShortcut("0")
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button("Reveal in Finder") { model?.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(model?.selection == nil)
            Button("Open in Default App") { model?.openInDefaultEditor() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(model?.selection == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Edit Settings…") { reveal(Settings.configURL, template: Settings.template) }
            Button("Edit Custom Stylesheet…") {
                reveal(
                    Resources.userCSSPath,
                    template: "/* Overrides for The Reading Room. Reload with ⌘R. */\n"
                )
            }
        }
    }

    private var sortBinding: Binding<FileTree.SortOrder> {
        Binding(
            get: { model?.sortOrder ?? .alphabetical },
            set: { model?.sortOrder = $0 }
        )
    }

    /// Creates the file with a starter template if it's missing, then shows it.
    private func reveal(_ url: URL, template: String) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            try? template.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Windows are still up at this point, so this is the reliable place to
    /// capture the layout for next launch.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { WindowRouter.shared.saveSession() }
    }

    /// Also save when you switch away, so an unexpected exit still leaves a
    /// recent record rather than nothing.
    func applicationDidResignActive(_ notification: Notification) {
        MainActor.assumeIsolated { WindowRouter.shared.saveSession() }
    }

    /// The notification delegate has to be in place before launching finishes,
    /// or a click on a banner that launched the app is dropped.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { ChangeNotifier.shared.start() }
    }

    /// Folders and files opened from Finder or dropped on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls { WindowRouter.shared.route(url) }
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        MainActor.assumeIsolated { WindowRouter.shared.route(URL(fileURLWithPath: filename)) }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        MainActor.assumeIsolated {
            for name in filenames { WindowRouter.shared.route(URL(fileURLWithPath: name)) }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        return !hasVisibleWindows
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
