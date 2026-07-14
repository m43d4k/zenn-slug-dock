import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    var repositoryURL: URL?
    var articles: [Article] = []
    var articleSelection: Set<URL> = []
    var selectedArticle: Article?
    var images: [ImageAsset] = []
    var selectedImageID: URL?
    var imageBeingRenamed: ImageAsset?
    var searchText = ""
    var articleStatusFilter = ArticleStatusFilter.all
    var articleSortOrder = [ArticleSortComparator(field: .modifiedAt, order: .reverse)]
    var statusMessage: String?
    var alertMessage: String?
    var isLoading = false

    @ObservationIgnored private let fileSystem = FileSystemService()
    @ObservationIgnored private var loadingOperationCount = 0

    init() {
        repositoryURL = SettingsService.repositoryURL
    }

    var visibleArticles: [Article] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = articles.filter { article in
            let matchesSearch = query.isEmpty
                || article.title.localizedCaseInsensitiveContains(query)
                || article.slug.localizedCaseInsensitiveContains(query)
            return matchesSearch && articleStatusFilter.matches(article)
        }
        let comparators = articleSortOrder.isEmpty
            ? [ArticleSortComparator(field: .modifiedAt, order: .reverse)]
            : articleSortOrder
        return filtered.sorted { lhs, rhs in
            for comparator in comparators {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return lhs.slug.localizedCaseInsensitiveCompare(rhs.slug) == .orderedAscending
        }
    }

    var hasActiveArticleQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || articleStatusFilter != .all
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
        panel.title = "Select a Zenn Repository"
        panel.prompt = "Select"
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
            alertMessage = "The selected folder does not contain an articles directory."
            return
        }

        repositoryURL = normalizedURL
        SettingsService.repositoryURL = normalizedURL
        selectedArticle = nil
        articleSelection = []
        selectedImageID = nil
        imageBeingRenamed = nil
        images = []
        searchText = ""
        articleStatusFilter = .all
        articleSortOrder = [ArticleSortComparator(field: .modifiedAt, order: .reverse)]
        reload()
    }

    func reload() {
        guard let repositoryURL else { return }
        if let selectedArticle {
            reloadWorkspace(articleID: selectedArticle.id, repositoryURL: repositoryURL)
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
        imageBeingRenamed = nil
        loadImages(for: article)
    }

    func returnToArticleList() {
        selectedArticle = nil
        selectedImageID = nil
        imageBeingRenamed = nil
        images = []
    }

    func copyMarkdownPath() {
        guard let article = selectedArticle else { return }
        copy(article.markdownURL.path, successMessage: "MD path copied")
    }

    func revealMarkdown() {
        guard let article = selectedArticle else { return }
        perform { try SystemService.revealInFinder(article.markdownURL) }
    }

    func openMarkdownInApplication() {
        guard let article = selectedArticle else { return }
        guard let preference = SettingsService.markdownApplication else {
            chooseMarkdownApplication(openCurrentArticle: true)
            return
        }
        guard let applicationURL = SystemService.markdownApplicationURL(for: preference) else {
            alertMessage = SlugDockError.markdownApplicationMissing.localizedDescription
            return
        }

        Task {
            do {
                try await SystemService.openMarkdown(article.markdownURL, withApplicationAt: applicationURL)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func chooseMarkdownApplication(openCurrentArticle: Bool = false) {
        let panel = NSOpenPanel()
        panel.title = "Select a Markdown Application"
        panel.prompt = "Select"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        let normalizedURL = selectedURL.standardizedFileURL
        guard let bundleIdentifier = Bundle(url: normalizedURL)?.bundleIdentifier else {
            alertMessage = SlugDockError.invalidMarkdownApplication.localizedDescription
            return
        }

        SettingsService.markdownApplication = MarkdownApplicationPreference(
            bundleIdentifier: bundleIdentifier,
            path: normalizedURL.path
        )
        if openCurrentArticle {
            openMarkdownInApplication()
        }
    }

    func copyImageDirectoryPath() {
        guard let article = selectedArticle else { return }
        copy(article.imageDirectoryURL.path, successMessage: "Image folder path copied")
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

    func copyRepositoryPath() {
        guard let repositoryURL else { return }
        copy(repositoryURL.path, successMessage: "Repository path copied")
    }

    func copySelectedImageMarkdown() {
        guard let image = selectedImage else { return }
        copy(image.markdownPath, successMessage: "Copied as Markdown")
    }

    func copySelectedImagePath() {
        guard let image = selectedImage else { return }
        copy(image.fileURL.path, successMessage: "Image full path copied")
    }

    func revealSelectedImage() {
        guard let image = selectedImage else { return }
        perform { try SystemService.revealInFinder(image.fileURL) }
    }

    func requestRenameSelectedImage() {
        imageBeingRenamed = selectedImage
    }

    func renameImage(_ image: ImageAsset, toFileName fileName: String) {
        guard let article = selectedArticle else { return }
        imageBeingRenamed = nil
        beginLoading()
        Task {
            defer { endLoading() }
            do {
                let renamedURL = try await fileSystem.renameImage(image, toFileName: fileName, for: article)
                guard selectedArticle?.id == article.id else { return }
                await refreshImages(for: article, preferredSelection: renamedURL)
                if renamedURL == image.fileURL {
                    showStatus("Image name unchanged")
                } else {
                    showStatus("Image renamed")
                }
            } catch {
                guard selectedArticle?.id == article.id else { return }
                statusMessage = error.localizedDescription
            }
        }
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

    private func reloadWorkspace(articleID: URL, repositoryURL: URL) {
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
                    statusMessage = "Article file not found"
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
                let resolvedID = id.resolvingSymlinksInPath()
                return scanned.first(where: { $0.id.resolvingSymlinksInPath() == resolvedID })?.id
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
            parts.append("Added \(result.copied.count) image(s)")
        } else if result.selectedURL != nil && result.failures.isEmpty {
            parts.append("Image list updated")
        }
        if !result.failures.isEmpty {
            let details = result.failures.map { "\($0.fileName): \($0.reason)" }.joined(separator: "\n")
            parts.append("Failed to add \(result.failures.count) item(s)\n\(details)")
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
