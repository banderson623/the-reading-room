import AppKit
import SwiftUI
import WebKit
import TheReadingRoomCore

/// Holds the live web view so menu commands (back, forward, reload, find, zoom)
/// can drive it without SwiftUI having to own WebKit state.
@MainActor
final class WebViewController: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    /// Set by link navigation so the sidebar can follow along.
    @Published var currentPath: String?

    /// Text to look for once the next page finishes loading — set when opening a
    /// search result, so the view lands on the match.
    var pendingFind: String?

    fileprivate weak var webView: WKWebView?
    /// Selection changes come from the sidebar; link clicks come from the page.
    /// This distinguishes them so we don't fight over navigation.
    fileprivate var loadedPath: String?

    private static let zoomKey = "zoom"

    @Published private(set) var zoom: Double = {
        let stored = UserDefaults.standard.double(forKey: zoomKey)
        return stored > 0 ? ZoomLadder.clamp(stored) : 1.0
    }()

    var zoomPercent: String { ZoomLadder.percent(zoom) }
    var canZoomIn: Bool { zoom < ZoomLadder.maximum }
    var canZoomOut: Bool { zoom > ZoomLadder.minimum }

    /// Shows a file, if there's somewhere to show it — see `DocumentLoadPolicy`
    /// for why the "is there a web view yet" part matters.
    func show(path: String?) {
        guard DocumentLoadPolicy.shouldLoad(
            requested: path,
            loaded: loadedPath,
            hasWebView: webView != nil
        ), let path, let webView else { return }

        loadedPath = path
        currentPath = path
        webView.load(URLRequest(url: Scheme.documentURL(for: path)))
    }

    /// Re-renders the current file. Scroll position is restored by the page
    /// itself (see `ScrollStore`), so a file changing on disk doesn't yank the
    /// reader back to the top.
    func reload(preservingScroll: Bool = true) {
        guard let path = loadedPath, let webView else { return }
        if preservingScroll { ScrollStore.shared.requestRestore(path: path) }

        // Reloading rather than re-loading the URL keeps the back/forward list
        // (and any #fragment) intact.
        if let current = webView.url, Scheme.path(of: current) == path {
            webView.reload()
        } else {
            webView.load(URLRequest(url: Scheme.documentURL(for: path)))
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func zoomIn() { apply(ZoomLadder.next(above: zoom)) }
    func zoomOut() { apply(ZoomLadder.next(below: zoom)) }

    func resetZoom() { apply(1.0) }

    private func apply(_ level: Double) {
        zoom = level
        webView?.pageZoom = level
        // Undo any trackpad pinch, so "Actual Size" really is actual size.
        webView?.magnification = 1
        UserDefaults.standard.set(level, forKey: Self.zoomKey)
    }

    /// Re-asserts the zoom after a navigation.
    fileprivate func reapplyZoom() {
        guard let webView, webView.pageZoom != zoom else { return }
        webView.pageZoom = zoom
    }

    func find(_ text: String, backwards: Bool = false) {
        guard !text.isEmpty else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        configuration.caseSensitive = false
        webView?.find(text, configuration: configuration, completionHandler: { _ in })
    }

    func clearFind() {
        // Dismisses the highlight by searching for nothing findable.
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    func printDocument() {
        guard let webView else { return }
        let info = NSPrintInfo.shared
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 40
        info.rightMargin = 40
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        if let window = webView.window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var controller: WebViewController
    /// Absolute path of the file to display.
    var path: String?
    /// Called when the page navigates itself (a markdown link was followed).
    var onNavigate: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(DocumentServer(), forURLScheme: Scheme.name)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "app")
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.pageZoom = controller.zoom
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        controller.webView = webView
        if let path { controller.show(path: path) }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        controller.webView = webView
        controller.show(path: path)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView

        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            // Links out to the web (and mailto:, etc.) go to the default app.
            if let scheme = url.scheme?.lowercased(), scheme != Scheme.name {
                if navigationAction.navigationType == .linkActivated {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            guard let path = Scheme.path(of: url) else {
                decisionHandler(.allow)
                return
            }

            let fileURL = URL(fileURLWithPath: path)
            let isMarkdown = FileTree.isMarkdown(fileURL)
            let exists = FileManager.default.fileExists(atPath: path)

            // A link to something we can't render — hand it to the system.
            if navigationAction.navigationType == .linkActivated, !isMarkdown, exists {
                NSWorkspace.shared.open(fileURL)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame?.isMainFrame != false {
                parent.controller.loadedPath = path
                parent.controller.currentPath = path
                parent.onNavigate(path)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateNavigationState(webView)
            parent.controller.reapplyZoom()

            if let query = parent.controller.pendingFind {
                parent.controller.pendingFind = nil
                parent.controller.find(query)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            updateNavigationState(webView)
        }

        private func updateNavigationState(_ webView: WKWebView) {
            parent.controller.canGoBack = webView.canGoBack
            parent.controller.canGoForward = webView.canGoForward
        }

        /// Target="_blank" style links.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url, url.scheme != Scheme.name {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any],
                  let kind = payload["kind"] as? String else { return }
            switch kind {
            case "scroll":
                guard let offset = payload["y"] as? Double,
                      let path = parent.controller.loadedPath else { return }
                ScrollStore.shared.record(path: path, offset: offset)
            case "copy":
                guard let text = payload["text"] as? String else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            default:
                break
            }
        }
    }
}
