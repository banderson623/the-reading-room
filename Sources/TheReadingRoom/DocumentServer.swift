import Foundation
import UniformTypeIdentifiers
import WebKit
import TheReadingRoomCore

/// Serves rendered markdown, local images, and the bundled CSS/JS.
final class DocumentServer: NSObject, WKURLSchemeHandler {
    private let queue = DispatchQueue(label: "the-reading-room.render", qos: .userInitiated)
    private var cancelled: Set<ObjectIdentifier> = []
    private let cancelLock = NSLock()

    /// Files larger than this are shown as a notice instead of rendered; keeps a
    /// stray multi-megabyte log file from freezing the window.
    private let maxDocumentBytes = 8 * 1024 * 1024

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let url = task.request.url
        let identifier = ObjectIdentifier(task)

        guard let url, url.scheme == Scheme.name else {
            finish(task, identifier: identifier, url: nil, data: Data(), mimeType: "text/plain", cache: false)
            return
        }

        if url.host == Scheme.assetHost {
            serveAsset(named: url.lastPathComponent, task: task, identifier: identifier, url: url)
            return
        }

        guard let path = Scheme.path(of: url) else {
            let html = Page.message(title: "Not found", detail: url.absoluteString)
            finish(task, identifier: identifier, url: url, data: Data(html.utf8), mimeType: "text/html", cache: false)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            let (data, mimeType) = self.body(forPath: path)
            DispatchQueue.main.async {
                self.finish(task, identifier: identifier, url: url, data: data, mimeType: mimeType, cache: false)
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        cancelLock.lock()
        cancelled.insert(ObjectIdentifier(task))
        cancelLock.unlock()
    }

    // MARK: - Content

    private func body(forPath path: String) -> (Data, String) {
        let fileURL = URL(fileURLWithPath: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)

        guard attributes != nil else {
            let html = Page.message(
                title: "File not found",
                detail: path
            )
            return (Data(html.utf8), "text/html")
        }

        guard FileTree.isMarkdown(fileURL) else {
            // Images and other assets referenced by the document.
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let data = (try? Data(contentsOf: fileURL, options: .mappedIfSafe)) ?? Data()
            return (data, mimeType)
        }

        let size = (attributes?[.size] as? Int) ?? 0
        if size > maxDocumentBytes {
            let html = Page.message(
                title: fileURL.lastPathComponent,
                detail: "This file is \(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) — too large to render."
            )
            return (Data(html.utf8), "text/html")
        }

        guard let text = readText(fileURL) else {
            let html = Page.message(
                title: fileURL.lastPathComponent,
                detail: "Could not read this file as text."
            )
            return (Data(html.utf8), "text/html")
        }

        let rendered = MarkdownRenderer.render(markdown: text)
        let html = Page.document(
            title: fileURL.deletingPathExtension().lastPathComponent,
            body: rendered,
            modified: attributes?[.modificationDate] as? Date,
            restoreScroll: ScrollStore.shared.takeRestore(path: path)
        )
        return (Data(html.utf8), "text/html")
    }

    /// UTF-8 first, then a couple of fallbacks so a latin-1 file still renders.
    private func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .utf16) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    private func serveAsset(
        named name: String,
        task: WKURLSchemeTask,
        identifier: ObjectIdentifier,
        url: URL
    ) {
        let content: String
        let mimeType: String
        switch name {
        case "style.css":
            content = Resources.markdownCSS + "\n" + Resources.userCSS
            mimeType = "text/css"
        case "app.js":
            content = Resources.appJS
            mimeType = "text/javascript"
        case "highlight.js":
            content = Resources.highlightJS
            mimeType = "text/javascript"
        default:
            content = ""
            mimeType = "text/plain"
        }
        finish(task, identifier: identifier, url: url, data: Data(content.utf8), mimeType: mimeType, cache: name != "style.css")
    }

    // MARK: - Task plumbing

    private func finish(
        _ task: WKURLSchemeTask,
        identifier: ObjectIdentifier,
        url: URL?,
        data: Data,
        mimeType: String,
        cache: Bool
    ) {
        cancelLock.lock()
        let isCancelled = cancelled.remove(identifier) != nil
        cancelLock.unlock()
        guard !isCancelled else { return }

        let response = HTTPURLResponse(
            url: url ?? URL(string: "\(Scheme.name)://\(Scheme.documentHost)/")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": String(data.count),
                "Cache-Control": cache ? "max-age=86400" : "no-store",
            ]
        )!

        // WebKit raises if a stopped task is fed more data; the `cancelled`
        // check above is what keeps that from happening.
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
