import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var repositoryURL: URL?
    var articles: [Article] = []
    var articleSelection: Set<URL> = []
    var selectedArticle: Article?
    var images: [ImageAsset] = []
    var selectedImageID: URL?
    var searchText = ""
    var statusMessage: String?
    var alertMessage: String?
    var isLoading = false

    @ObservationIgnored private let fileSystem = FileSystemService()
    @ObservationIgnored private var loadingOperationCount = 0

    init() {
        repositoryURL = SettingsService.repositoryURL
    }

    var filteredArticles: [Article] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return articles }
        return articles.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.slug.localizedCaseInsensitiveContains(query)
        }
    }

    func start() {
        guard let repositoryURL else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: repositoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            SettingsService.repositoryURL = nil
            self.repositoryURL = nil
            return
        }
        reload()
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Zennリポジトリを選択"
        panel.prompt = "選択"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let normalizedURL = selectedURL.standardizedFileURL
        let articlesURL = normalizedURL.appendingPathComponent("articles", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: articlesURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            alertMessage = "選択したフォルダに articles ディレクトリがありません。"
            return
        }

        repositoryURL = normalizedURL
        SettingsService.repositoryURL = normalizedURL
        selectedArticle = nil
        articleSelection = []
        selectedImageID = nil
        images = []
        searchText = ""
        reload()
    }

    func reload() {
        guard let repositoryURL else { return }
        if let selectedArticle {
            reloadWritingMode(articleID: selectedArticle.id, repositoryURL: repositoryURL)
        } else {
            reloadArticles(repositoryURL: repositoryURL)
        }
    }

    func applicationBecameActive() {
        guard repositoryURL != nil else { return }
        reload()
    }

    func openSelectedArticle() {
        guard let id = articleSelection.first,
              let article = articles.first(where: { $0.id == id }) else { return }
        openArticle(article)
    }

    func openArticle(_ article: Article) {
        selectedArticle = article
        articleSelection = [article.id]
        selectedImageID = nil
        loadImages(for: article)
    }

    func returnToArticleList() {
        selectedArticle = nil
        selectedImageID = nil
        images = []
    }

    func copyMarkdownPath() {
        guard let article = selectedArticle else { return }
        copy(article.markdownURL.path, successMessage: "MDパスをコピーしました")
    }

    func revealMarkdown() {
        guard let article = selectedArticle else { return }
        perform { try SystemService.revealInFinder(article.markdownURL) }
    }

    func copyImageDirectoryPath() {
        guard let article = selectedArticle else { return }
        copy(article.imageDirectoryURL.path, successMessage: "画像フォルダパスをコピーしました")
    }

    func openImageDirectory() {
        guard let article = selectedArticle else { return }
        Task {
            do {
                try await fileSystem.createImageDirectory(for: article)
                try SystemService.openInFinder(article.imageDirectoryURL)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func openRepositoryInFinder() {
        guard let repositoryURL else { return }
        perform { try SystemService.openInFinder(repositoryURL) }
    }

    func copySelectedImageMarkdown() {
        guard let image = selectedImage else { return }
        copy(image.markdownPath, successMessage: "Markdownをコピーしました")
    }

    func copySelectedImagePath() {
        guard let image = selectedImage else { return }
        copy(image.fileURL.path, successMessage: "画像のフルパスをコピーしました")
    }

    func revealSelectedImage() {
        guard let image = selectedImage else { return }
        perform { try SystemService.revealInFinder(image.fileURL) }
    }

    func importImages(_ urls: [URL]) {
        guard let article = selectedArticle, !urls.isEmpty else { return }
        beginLoading()
        Task {
            defer { endLoading() }
            let result = await fileSystem.importImages(from: urls, for: article)
            guard selectedArticle?.id == article.id else { return }
            await refreshImages(for: article, preferredSelection: result.selectedURL)
            showImportResult(result)
        }
    }

    private var selectedImage: ImageAsset? {
        guard let selectedImageID else { return nil }
        return images.first(where: { $0.id == selectedImageID })
    }

    private func reloadArticles(repositoryURL: URL) {
        beginLoading()
        Task {
            defer { endLoading() }
            do {
                let scanned = try await fileSystem.scanArticles(repositoryURL: repositoryURL)
                guard self.repositoryURL == repositoryURL, selectedArticle == nil else { return }
                articles = scanned
                articleSelection = articleSelection.filter { id in scanned.contains(where: { $0.id == id }) }
                statusMessage = nil
            } catch {
                guard self.repositoryURL == repositoryURL else { return }
                articles = []
                statusMessage = error.localizedDescription
            }
        }
    }

    private func reloadWritingMode(articleID: URL, repositoryURL: URL) {
        beginLoading()
        Task {
            defer { endLoading() }
            do {
                let scanned = try await fileSystem.scanArticles(repositoryURL: repositoryURL)
                guard self.repositoryURL == repositoryURL else { return }
                articles = scanned
                guard let refreshedArticle = scanned.first(where: { $0.id == articleID }) else {
                    selectedArticle = nil
                    images = []
                    selectedImageID = nil
                    statusMessage = "記事ファイルが見つかりません"
                    return
                }
                selectedArticle = refreshedArticle
                await refreshImages(for: refreshedArticle, preferredSelection: selectedImageID)
                statusMessage = refreshedArticle.displayError
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func loadImages(for article: Article) {
        beginLoading()
        Task {
            defer { endLoading() }
            await refreshImages(for: article, preferredSelection: nil)
        }
    }

    private func refreshImages(for article: Article, preferredSelection: URL?) async {
        do {
            let scanned = try await fileSystem.scanImages(for: article)
            guard selectedArticle?.id == article.id else { return }
            images = scanned
            selectedImageID = preferredSelection.flatMap { id in
                scanned.contains(where: { $0.id == id }) ? id : nil
            }
            statusMessage = article.displayError
        } catch {
            guard selectedArticle?.id == article.id else { return }
            images = []
            selectedImageID = nil
            statusMessage = error.localizedDescription
        }
    }

    private func copy(_ text: String, successMessage: String) {
        perform {
            try SystemService.copyToClipboard(text)
            showStatus(successMessage)
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == message {
                statusMessage = selectedArticle?.displayError
            }
        }
    }

    private func showImportResult(_ result: ImageImportResult) {
        var parts: [String] = []
        if !result.copied.isEmpty {
            parts.append("\(result.copied.count)件の画像を追加しました")
        } else if result.selectedURL != nil && result.failures.isEmpty {
            parts.append("画像一覧を更新しました")
        }
        if !result.failures.isEmpty {
            let details = result.failures.map { "\($0.fileName): \($0.reason)" }.joined(separator: "\n")
            parts.append("\(result.failures.count)件を追加できませんでした\n\(details)")
        }
        statusMessage = parts.joined(separator: "\n")
    }

    private func beginLoading() {
        loadingOperationCount += 1
        isLoading = true
    }

    private func endLoading() {
        loadingOperationCount = max(0, loadingOperationCount - 1)
        isLoading = loadingOperationCount > 0
    }
}
