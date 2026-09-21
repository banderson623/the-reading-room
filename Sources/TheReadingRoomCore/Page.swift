import Foundation

/// Wraps rendered markdown in the HTML page shell.
public enum Page {
    public static func document(
        title: String,
        body: String,
        modified: Date? = nil,
        restoreScroll: Double? = nil
    ) -> String {
        let restore = restoreScroll.map {
            "<script>window.__restoreScroll = \($0);</script>\n"
        } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <link rel="stylesheet" href="\(Scheme.assetURL("style.css"))">
        </head>
        <body>
        <article class="page">
        \(meta(modified: modified))\(body)
        </article>
        \(restore)<script src="\(Scheme.assetURL("highlight.js"))"></script>
        \(mermaidScript(for: body))<script src="\(Scheme.assetURL("app.js"))"></script>
        </body>
        </html>
        """
    }

    /// A self-contained page with the CSS and scripts inlined — used by the
    /// `--render` flag, so the output opens anywhere.
    public static func standalone(
        title: String,
        body: String,
        modified: Date? = nil,
        baseURL: URL?
    ) -> String {
        let base = baseURL.map { "<base href=\"\($0.absoluteString)\">\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        \(base)<style>
        \(Resources.markdownCSS)
        \(Resources.userCSS)
        </style>
        </head>
        <body>
        <article class="page">
        \(meta(modified: modified))\(body)
        </article>
        <script>\(Resources.highlightJS)</script>
        \(inlineMermaidScript(for: body))<script>\(Resources.appJS)</script>
        </body>
        </html>
        """
    }

    public static func message(title: String, detail: String) -> String {
        document(
            title: title,
            body: "<h1>\(escapeHTML(title))</h1>\n<p class=\"render-error\">\(escapeHTML(detail))</p>"
        )
    }

    /// Whether the body has a Mermaid diagram to draw — a `mermaid` fence, or
    /// raw HTML using Mermaid's own `class="mermaid"` convention.
    static func usesMermaid(_ body: String) -> Bool {
        body.contains("class=\"mermaid\"")
    }

    /// Mermaid is a few megabytes of script, so only pages that draw a diagram
    /// load it.
    private static func mermaidScript(for body: String) -> String {
        guard usesMermaid(body) else { return "" }
        return "<script src=\"\(Scheme.assetURL("mermaid.js"))\"></script>\n"
    }

    private static func inlineMermaidScript(for body: String) -> String {
        guard usesMermaid(body) else { return "" }
        return "<script>\(Resources.mermaidJS)</script>\n"
    }

    /// The "Last modified" line above the document.
    private static func meta(modified: Date?) -> String {
        guard let modified else { return "" }
        return "<div class=\"doc-meta\">Last modified "
            + escapeHTML(DateFormatting.friendly(modified))
            + "</div>\n"
    }
}
