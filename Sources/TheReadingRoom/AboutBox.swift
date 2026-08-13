import AppKit
import SwiftUI

/// A small branded About window: the app icon, name, version, and the pitch.
/// Opened from the "About The Reading Room" menu item (see ViewerCommands).
@MainActor
enum AboutWindow {
    private static var controller: NSWindowController?

    static func show() {
        // Reuse the window if it's already up rather than stacking copies.
        if let window = controller?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "About The Reading Room"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.setContentSize(hosting.view.fittingSize)
        window.center()

        // Build a fresh window next time this one is closed. The observation is
        // one-shot: remove it as it fires, or every open leaks an observer.
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { controller = nil }
            if let token { NotificationCenter.default.removeObserver(token) }
        }

        controller = NSWindowController(window: window)
        controller?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct AboutView: View {
    private static let pitch = """
        The Reading Room is a calm, native macOS space for reading your \
        markdown. Open the door, settle in, and everything you need is within \
        reach — a full folder of docs, rendered beautifully, no distractions. \
        Sessions are private and restored exactly where you left off, so you \
        can always pick up right where you… finished. However long it takes.
        """

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                // The icon master is a full-bleed square (macOS rounds it in the
                // Dock); round it here too so the About box matches.
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityHidden(true)

            Text("The Reading Room")
                .font(.title2.weight(.semibold))

            Text(version)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(Self.pitch)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // The name is a markdown link; SwiftUI renders it and opens it in
            // the default browser.
            Text("Your seat was pre-warmed by [Brian Anderson](https://github.com/banderson623)")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text("MIT-licensed")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 44)
        .padding(.top, 46)
        .padding(.bottom, 30)
        .frame(width: 460)
    }
}
