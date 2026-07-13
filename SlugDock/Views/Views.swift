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
                WritingView(state: state, article: article)
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
        .alert("エラー", isPresented: Binding(
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
            Label("Zennリポジトリを選択", systemImage: "folder")
        } description: {
            Text("articles フォルダを含むリポジトリを選択してください。")
        } actions: {
            Button("リポジトリを選択…") {
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
                TextField("title または slug を検索", text: $state.searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("記事を検索")
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
                                .accessibilityLabel("エラーあり")
                        }
                        Text(article.title)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("タイトル \(article.title)")
                }
                TableColumn("Slug") { article in
                    Text(article.slug)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("スラッグ \(article.slug)")
                }
            }
            .contextMenu(forSelectionType: URL.self) { selection in
                Button("執筆モードで開く") {
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
                        state.searchText.isEmpty ? "記事がありません" : "検索結果がありません",
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
                    Label("リポジトリをFinderで開く", systemImage: "folder")
                }
                Button {
                    state.chooseRepository()
                } label: {
                    Label("リポジトリを変更", systemImage: "folder.badge.gearshape")
                }
                Button {
                    state.reload()
                } label: {
                    Label("再読み込み", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("記事を再読み込み")
            }
        }
    }
}

private struct WritingView: View {
    @Bindable var state: AppState
    let article: Article
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    state.returnToArticleList()
                } label: {
                    Label("戻る", systemImage: "chevron.left")
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

            HStack {
                Button("MDパスをコピー") { state.copyMarkdownPath() }
                Button("MDをFinderで表示") { state.revealMarkdown() }
                Divider().frame(height: 20)
                Button("画像フォルダパスをコピー") { state.copyImageDirectoryPath() }
                Button("画像フォルダをFinderで開く") { state.openImageDirectory() }
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
                Label("再読み込み", systemImage: "arrow.clockwise")
            }
            .accessibilityLabel("記事と画像を再読み込み")
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
                    Label("画像はありません", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("ここへ画像をドロップ")
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
                            Button("Markdownとしてコピー") {
                                state.selectedImageID = image.id
                                state.copySelectedImageMarkdown()
                            }
                            Button("フルパスをコピー") {
                                state.selectedImageID = image.id
                                state.copySelectedImagePath()
                            }
                            Button("Finderで表示") {
                                state.selectedImageID = image.id
                                state.revealSelectedImage()
                            }
                            Divider()
                            Button("画像名を変更…") {
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
        .accessibilityLabel("画像一覧。ここへ画像をドロップできます")
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
            Text("画像名を変更")
                .font(.headline)
            HStack(spacing: 6) {
                TextField("ファイル名", text: $baseName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("新しい画像ファイル名")
                    .onSubmit(submit)
                Text(".\(image.fileURL.pathExtension)")
                    .foregroundStyle(.secondary)
            }
            Text("拡張子は変更できません。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("変更") { submit() }
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
        .accessibilityLabel("画像 \(image.fileName)、\(FileSizeTextFormatter.string(fromByteCount: image.fileSize))")
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
