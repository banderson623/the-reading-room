import SwiftUI
import TheReadingRoomCore

struct Sidebar: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        // The header sits above the List rather than in a safe-area inset: an
        // inset lets rows scroll underneath it, and the sidebar's background is
        // transparent, so they showed through the search field.
        VStack(spacing: 0) {
            header
            if model.isSearchActive {
                resultSummary
            }
            List(selection: $model.selection) {
                NodeRows(nodes: model.visibleTree)
            }
            .listStyle(.sidebar)
            .overlay {
                if model.visibleTree.isEmpty {
                    emptyOverlay
                }
            }
        }
        .onChange(of: model.focusSearch) { _, wants in
            if wants {
                searchFocused = true
                model.focusSearch = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            SearchField(text: $model.searchText, isSearching: model.isSearching) {
                model.clearSearch()
            }
            .focused($searchFocused)
            SortMenu(order: $model.sortOrder)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var resultSummary: some View {
        HStack {
            Text(summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var summaryText: String {
        if model.isSearching { return "Searching…" }
        let files = model.searchResults.count
        let matches = model.searchResults.reduce(0) { $0 + $1.matchCount }
        let names = model.nameOnlyMatchCount
        if files == 0 && names == 0 { return "No matches" }

        var parts: [String] = []
        if files > 0 {
            parts.append("\(matches) match\(matches == 1 ? "" : "es") in \(files) file\(files == 1 ? "" : "s")")
        }
        if names > 0 {
            parts.append("\(names) matching name\(names == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if model.isScanning {
            ProgressView().controlSize(.small)
        } else if model.isSearchActive {
            // The summary line above already says "No matches".
            EmptyView()
        } else if model.root != nil {
            Text("No markdown files")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// Recursive rows. Directories keep their own expansion state in the model so it
/// survives searching and tree refreshes.
private struct NodeRows: View {
    let nodes: [FileNode]
    @EnvironmentObject var model: AppModel

    var body: some View {
        ForEach(nodes) { node in
            if node.isDirectory {
                DisclosureGroup(isExpanded: model.expansionBinding(for: node.url)) {
                    NodeRows(nodes: node.children ?? [])
                } label: {
                    Label(node.name, systemImage: "folder")
                        .lineLimit(1)
                        .help(node.name)
                        .contentShape(.rect)
                        .onTapGesture { model.toggleExpansion(node.url) }
                }
            } else {
                FileRow(node: node)
                    .tag(node.url)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([node.url])
                        }
                        Button("Open in Default App") {
                            NSWorkspace.shared.open(node.url)
                        }
                        Divider()
                        Button("Copy Relative Path") {
                            model.copyToClipboard(model.relativePath(of: node.url))
                        }
                        Button("Copy Path") {
                            model.copyToClipboard(node.url.path)
                        }
                        Button("Copy Name") {
                            model.copyToClipboard(node.name)
                        }
                        Button("Copy Deep Link") {
                            model.copyDeepLink(to: node.url)
                        }
                    }
            }
        }
    }
}

/// A file row: its title, and during a search the match count and a preview of
/// the matching text.
private struct FileRow: View {
    let node: FileNode
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Label(node.label, systemImage: "doc.text")
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let count = model.matchCount(for: node.url) {
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
            }
            if let snippet = model.snippet(for: node.url) {
                Text(highlighted(snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.leading, 20)
                    .padding(.bottom, 2)
            }
        }
        .help(tooltip)
    }

    /// The filename is still worth knowing when the row shows a title instead.
    private var tooltip: String {
        node.title == nil ? node.url.path : "\(node.name)\n\(node.url.path)"
    }

    /// Bolds the matched text inside the snippet.
    private func highlighted(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let query = model.searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return attributed }

        var searchRange = attributed.startIndex..<attributed.endIndex
        while let found = attributed[searchRange].range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            attributed[found].font = .caption.bold()
            attributed[found].foregroundColor = .primary
            guard found.upperBound < attributed.endIndex else { break }
            searchRange = found.upperBound..<attributed.endIndex
        }
        return attributed
    }
}

private struct SortMenu: View {
    @Binding var order: FileTree.SortOrder

    var body: some View {
        Menu {
            Picker("Sort By", selection: $order) {
                ForEach(FileTree.SortOrder.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: order == .alphabetical
                ? "arrow.up.arrow.down"
                : "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort by \(order.label)")
    }
}

private struct SearchField: View {
    @Binding var text: String
    var isSearching: Bool
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
                .font(.system(size: 11, weight: .medium))
            TextField("Search contents", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
            } else if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 6))
    }
}
