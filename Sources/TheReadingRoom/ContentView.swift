import SwiftUI
import UniformTypeIdentifiers
import TheReadingRoomCore

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 180, ideal: 250, max: 460)
        } detail: {
            detail
        }
        .navigationTitle(model.titleOfSelection ?? "The Reading Room")
        .navigationSubtitle(model.subtitle)
        .toolbar { toolbarContent }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.openPreferringNewWindow(url)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.selection) { _, newValue in
            if let newValue { model.select(newValue) }
        }
        .background(zoomInAlternateShortcut)
    }

    /// The menu shows ⌘+, which on a US keyboard means ⌘⇧=. Almost everyone
    /// presses ⌘= instead, so accept that too — from a zero-sized button, since
    /// a second menu item would just be a confusing duplicate.
    private var zoomInAlternateShortcut: some View {
        Button("Zoom In") { model.webViewController.zoomIn() }
            .keyboardShortcut("=", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var detail: some View {
        if model.root == nil {
            WelcomeView()
        } else if model.selection == nil {
            ContentUnavailableView(
                "No file selected",
                systemImage: "doc.text",
                description: Text("Pick a file from the sidebar.")
            )
        } else {
            ZStack(alignment: .topTrailing) {
                MarkdownWebView(
                    controller: model.webViewController,
                    path: model.selection?.path,
                    onNavigate: { path in model.pageNavigated(to: path) }
                )
                .id("markdown-web-view")

                if model.findBarVisible {
                    FindBar(
                        text: $model.findText,
                        notFound: model.webViewController.findFoundNothing,
                        onFind: { backwards in
                            model.webViewController.find(model.findText, backwards: backwards)
                        },
                        onClose: {
                            model.findBarVisible = false
                            model.webViewController.clearFind()
                        }
                    )
                    .padding(12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onChange(of: model.findText) {
                        model.webViewController.resetFindFeedback()
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            ControlGroup {
                Button {
                    model.webViewController.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.webViewController.canGoBack)
                .help("Back (⌘[)")

                Button {
                    model.webViewController.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.webViewController.canGoForward)
                .help("Forward (⌘])")
            }
        }

        ToolbarItemGroup {
            Spacer()

            Menu {
                OutlineMenuItems(model: model)
            } label: {
                Image(systemName: "list.bullet")
            }
            .disabled(model.outline.isEmpty)
            .help("Document Outline")

            Button {
                model.findBarVisible = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(model.selection == nil)
            .help("Find in Page (⌘F)")

            Menu {
                Button("Zoom In") { model.webViewController.zoomIn() }
                    .disabled(!model.webViewController.canZoomIn)
                Button("Zoom Out") { model.webViewController.zoomOut() }
                    .disabled(!model.webViewController.canZoomOut)
                Button("Actual Size (\(model.webViewController.zoomPercent))") {
                    model.webViewController.resetZoom()
                }
                Divider()
                Button("Copy Deep Link") {
                    if let selection = model.selection { model.copyDeepLink(to: selection) }
                }
                Button("Reveal in Finder") { model.revealInFinder() }
                Button("Open in Default App") { model.openInDefaultEditor() }
                Divider()
                Button("Reload") { model.webViewController.reload() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(model.selection == nil)
        }
    }
}

// MARK: - Outline

/// The document's headings as menu items, indented by level. Menus have no
/// real indentation, so nesting is drawn with leading spaces relative to the
/// shallowest heading in the document.
private struct OutlineMenuItems: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let minLevel = model.outline.map(\.level).min() ?? 1
        ForEach(model.outline) { item in
            Button {
                model.webViewController.scrollTo(anchor: item.slug)
            } label: {
                Text(String(repeating: "    ", count: item.level - minLevel) + item.text)
            }
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            // "doc.text", not "text.document": the latter needs SF Symbols 6
            // (macOS 15) and renders as nothing on macOS 14.
            Image(systemName: "doc.text")
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(.tertiary)

            VStack(spacing: 5) {
                Text("The Reading Room")
                    .font(.title2.weight(.semibold))
                Text("Drop a folder here, or open one.")
                    .foregroundStyle(.secondary)
            }

            Button("Open Folder…") { model.presentOpenPanel() }
                .controlSize(.large)
                .keyboardShortcut("o")

            if !model.recentFolders.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 2)
                    ForEach(model.recentFolders.prefix(5), id: \.self) { url in
                        Button {
                            model.openPreferringNewWindow(url)
                        } label: {
                            Label(url.lastPathComponent, systemImage: "folder")
                                .font(.callout)
                        }
                        .buttonStyle(.link)
                        .help(url.path)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Find bar

struct FindBar: View {
    @Binding var text: String
    /// The last find came up empty; say so instead of silently doing nothing.
    var notFound = false
    var onFind: (Bool) -> Void
    var onClose: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .medium))

            TextField("Find in page", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 170)
                .focused($focused)
                .onSubmit { onFind(false) }

            if notFound, !text.isEmpty {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 14)

            Button { onFind(true) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button { onFind(false) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .keyboardShortcut("g", modifiers: .command)
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator)
        }
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }
}
