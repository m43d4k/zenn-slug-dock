import AppKit
import ImageIO
import SwiftUI

struct RootView: View {
    @Bindable var state: AppState

    var body: some View {
        Group {
            if state.repositoryURL == nil {
                RepositorySelectionView(state: state)
            } else if let article = state.selectedArticle {
                WorkspaceView(state: state, article: article)
            } else {
                ArticleListView(state: state)
            }
        }
        .overlay(alignment: .top) {
            if let message = state.statusMessage {
                ErrorBanner(message: message)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .alert("Error", isPresented: Binding(
            get: { state.alertMessage != nil },
            set: { if !$0 { state.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.alertMessage ?? "")
        }
        .sheet(item: $state.imageBeingRenamed) { image in
            RenameImageSheet(image: image) { fileName in
                state.renameImage(image, toFileName: fileName)
            }
        }
        .task { state.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.applicationBecameActive()
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onChange(of: geometry.size) { _, size in
                        SettingsService.windowSize = size
                    }
            }
        }
    }
}

private struct RepositorySelectionView: View {
    let state: AppState

    var body: some View {
        ContentUnavailableView {
            Label("Select a Zenn Repository", systemImage: "folder")
        } description: {
            Text("Select a repository that contains an articles folder.")
        } actions: {
            Button("Select Repository…") {
                state.chooseRepository()
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct ArticleListView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by title or slug", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search articles")
            }
            .padding(9)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .padding()

            Table(state.filteredArticles, selection: $state.articleSelection) {
                TableColumn("Title") { article in
                    HStack(spacing: 6) {
                        if article.displayError != nil {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Has an error")
                        }
                        Text(article.title)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Title: \(article.title)")
                }
                TableColumn("Slug") { article in
                    Text(article.slug)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Slug: \(article.slug)")
                }
                TableColumn("Date Modified") { article in
                    if let modifiedAt = article.modifiedAt {
                        Text(modifiedAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Date modified: \(modifiedAt.formatted(date: .long, time: .shortened))")
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Date modified unavailable")
                    }
                }
                .width(min: 140, ideal: 170)
            }
            .contextMenu(forSelectionType: URL.self) { selection in
                Button("Open Workspace") {
                    guard let id = selection.first,
                          let article = state.articles.first(where: { $0.id == id }) else { return }
                    state.openArticle(article)
                }
                .disabled(selection.count != 1)
            } primaryAction: { selection in
                guard let id = selection.first,
                      let article = state.articles.first(where: { $0.id == id }) else { return }
                state.openArticle(article)
            }
            .overlay {
                if state.filteredArticles.isEmpty && !state.isLoading {
                    ContentUnavailableView(
                        state.searchText.isEmpty ? "No Articles" : "No Results",
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
        }
        .navigationTitle("SlugDock")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.openRepositoryInFinder()
                } label: {
                    Label("Open Repository in Finder", systemImage: "folder")
                }
                .help("Open Repository in Finder")
                Button {
                    state.copyRepositoryPath()
                } label: {
                    Label("Copy Repository Path", systemImage: "doc.on.doc")
                }
                .help("Copy Repository Path")
                Button {
                    state.chooseRepository()
                } label: {
                    Label("Change Repository", systemImage: "folder.badge.gearshape")
                }
                .help("Change Repository")
                Button {
                    state.reload()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("Reload articles")
                .help("Reload Articles (⌘R)")
            }
        }
    }
}

private struct WorkspaceButton<Label: View>: View {
    private let expandsWidth: Bool
    private let action: () -> Void
    private let label: Label

    init(
        expandsWidth: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.expandsWidth = expandsWidth
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: expandsWidth ? .infinity : nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }
}

private extension WorkspaceButton where Label == Text {
    init(_ title: String, expandsWidth: Bool = false, action: @escaping () -> Void) {
        self.init(expandsWidth: expandsWidth, action: action) {
            Text(title)
        }
    }
}

private struct WorkspaceView: View {
    @Bindable var state: AppState
    let article: Article
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                WorkspaceButton {
                    state.returnToArticleList()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title)
                        .font(.title2.bold())
                    Text(article.slug)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                Spacer()
            }

            HStack(spacing: 8) {
                WorkspaceButton("Copy MD Path", expandsWidth: true) { state.copyMarkdownPath() }
                WorkspaceButton("Show MD in Finder", expandsWidth: true) { state.revealMarkdown() }
                WorkspaceButton("Open MD in App", expandsWidth: true) { state.openMarkdownInApplication() }
                Divider().frame(height: 20)
                WorkspaceButton("Copy Image Folder Path", expandsWidth: true) { state.copyImageDirectoryPath() }
                WorkspaceButton("Open Image Folder", expandsWidth: true) { state.openImageDirectory() }
            }

            ImageGridView(state: state, isDropTargeted: isDropTargeted)
                .dropDestination(for: URL.self) { urls, _ in
                    state.importImages(urls)
                    return !urls.isEmpty
                } isTargeted: { targeted in
                    isDropTargeted = targeted
                }
        }
        .padding()
        .navigationTitle(article.title)
        .toolbar {
            Button {
                state.reload()
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("Reload article and images")
        }
    }
}

private struct ImageGridView: View {
    @Bindable var state: AppState
    let isDropTargeted: Bool
    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 14)]

    var body: some View {
        ScrollView {
            if state.images.isEmpty {
                ContentUnavailableView {
                    Label("No Images", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Drop images here")
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(state.images) { image in
                        ImageCell(
                            image: image,
                            isSelected: state.selectedImageID == image.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            state.selectedImageID = image.id
                            state.revealSelectedImage()
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            state.selectedImageID = image.id
                        })
                        .contextMenu {
                            Button("Copy as Markdown") {
                                state.selectedImageID = image.id
                                state.copySelectedImageMarkdown()
                            }
                            Button("Copy Full Path") {
                                state.selectedImageID = image.id
                                state.copySelectedImagePath()
                            }
                            Button("Show in Finder") {
                                state.selectedImageID = image.id
                                state.revealSelectedImage()
                            }
                            Divider()
                            Button("Rename Image…") {
                                state.selectedImageID = image.id
                                state.requestRenameSelectedImage()
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(isDropTargeted ? Color.accentColor.opacity(0.14) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [7])
                )
        }
        .accessibilityLabel("Image list. You can drop images here.")
    }
}

private struct RenameImageSheet: View {
    let image: ImageAsset
    let rename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var baseName: String

    init(image: ImageAsset, rename: @escaping (String) -> Void) {
        self.image = image
        self.rename = rename
        _baseName = State(initialValue: image.fileURL.deletingPathExtension().lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Image")
                .font(.headline)
            HStack(spacing: 6) {
                TextField("File name", text: $baseName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("New image file name")
                    .onSubmit(submit)
                Text(".\(image.fileURL.pathExtension)")
                    .foregroundStyle(.secondary)
            }
            Text("The file extension cannot be changed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(baseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func submit() {
        let normalizedBaseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBaseName.isEmpty else { return }
        rename("\(normalizedBaseName).\(image.fileURL.pathExtension)")
        dismiss()
    }
}

private struct ImageCell: View {
    let image: ImageAsset
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThumbnailView(url: image.fileURL)
                .frame(maxWidth: .infinity)
                .aspectRatio(4 / 3, contentMode: .fit)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))

            Text(image.fileURL.deletingPathExtension().lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .font(.callout)
            HStack {
                Text(FileSizeTextFormatter.string(fromByteCount: image.fileSize))
                Spacer(minLength: 8)
                Text(".\(image.fileURL.pathExtension)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 3 : 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image: \(image.fileName), \(FileSizeTextFormatter.string(fromByteCount: image.fileSize))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ThumbnailView: View {
    let url: URL
    @State private var thumbnail: SendableCGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail.value, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
                    .padding(36)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            thumbnail = await Task.detached(priority: .utility) {
                ThumbnailLoader.load(url: url)
            }.value
        }
    }
}

private struct SendableCGImage: @unchecked Sendable {
    let value: CGImage
}

private enum ThumbnailLoader {
    static func load(url: URL) -> SendableCGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return SendableCGImage(value: image)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.callout)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            .shadow(radius: 4, y: 2)
            .accessibilityLabel(message)
    }
}
