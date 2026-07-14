import AppKit
import Foundation
import XCTest
@testable import SlugDock

final class SlugDockTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testCopyRepositoryPathCopiesOnlyAbsolutePath() {
        let state = AppState()
        let repository = URL(fileURLWithPath: "/tmp/Zenn Repository", isDirectory: true)
        state.repositoryURL = repository

        state.copyRepositoryPath()

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "/tmp/Zenn Repository")
        XCTAssertEqual(state.statusMessage, "Repository path copied")
    }

    func testFrontMatterParsesQuotedTitleContainingColon() {
        let result = FrontMatterParser.parse(markdown: """
        ---
        title: "Swift: はじめの一歩"
        published: false
        ---
        body
        """)

        XCTAssertEqual(result, FrontMatterResult(title: "Swift: はじめの一歩", published: false, error: nil))
    }

    func testFrontMatterParsesPublishedAndSeparatesUnsetFromInvalidValues() {
        XCTAssertEqual(
            FrontMatterParser.parse(markdown: "---\ntitle: Public\npublished: true\n---"),
            FrontMatterResult(title: "Public", published: true, error: nil)
        )
        XCTAssertEqual(
            FrontMatterParser.parse(markdown: "---\ntitle: Unset\n---"),
            FrontMatterResult(title: "Unset", published: nil, error: nil)
        )
        let invalid = FrontMatterParser.parse(markdown: "---\ntitle: Invalid\npublished: \"false\"\n---")
        XCTAssertNil(invalid.published)
        XCTAssertNotNil(invalid.error)
    }

    func testFrontMatterUsesUntitledForEmptyOrMissingFrontMatter() {
        XCTAssertEqual(
            FrontMatterParser.parse(markdown: "---\ntitle: \"   \"\n---\n"),
            FrontMatterResult(title: "Untitled", published: nil, error: nil)
        )
        XCTAssertEqual(
            FrontMatterParser.parse(markdown: "# Front Matterなし"),
            FrontMatterResult(title: "Untitled", published: nil, error: nil)
        )
    }

    func testFrontMatterReportsMissingDelimiterMalformedYAMLAndNonStringTitle() {
        XCTAssertNotNil(FrontMatterParser.parse(markdown: "---\ntitle: test").error)
        XCTAssertNotNil(FrontMatterParser.parse(markdown: "---\ntitle: [broken\n---").error)
        XCTAssertNotNil(FrontMatterParser.parse(markdown: "---\ntitle: 42\n---").error)
    }

    func testFrontMatterHandlesUTF8BOM() {
        let result = FrontMatterParser.parse(markdown: "\u{FEFF}---\ntitle: BOM対応\n---\n")
        XCTAssertEqual(result.title, "BOM対応")
        XCTAssertNil(result.error)
    }

    func testArticleScannerIncludesOnlyDirectLowercaseMarkdownAndReadsMetadata() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let articles = repository.appendingPathComponent("articles")
        let modifiedArticle = articles.appendingPathComponent("z.md")
        let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try write("---\ntitle: beta\npublished: true\n---", to: modifiedArticle)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: modifiedArticle.path)
        try write("---\ntitle: Alpha\n---", to: articles.appendingPathComponent("b.md"))
        try write("---\ntitle: alpha\n---", to: articles.appendingPathComponent("a.md"))
        try write("---\ntitle: excluded\n---", to: articles.appendingPathComponent("upper.MD"))
        try write("text", to: articles.appendingPathComponent("note.txt"))
        let nested = articles.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try write("---\ntitle: nested\n---", to: nested.appendingPathComponent("nested.md"))

        let result = try await FileSystemService().scanArticles(repositoryURL: repository)

        XCTAssertEqual(Set(result.map(\.slug)), Set(["a", "b", "z"]))
        let modifiedResult = try XCTUnwrap(result.first(where: { $0.slug == "z" }))
        XCTAssertEqual(modifiedResult.published, true)
        let scannedModifiedAt = try XCTUnwrap(modifiedResult.modifiedAt)
        XCTAssertEqual(scannedModifiedAt.timeIntervalSince1970, modifiedAt.timeIntervalSince1970, accuracy: 1)
    }

    @MainActor
    func testArticleListFiltersEveryStatusWithoutTreatingErrorsAsUnset() {
        let state = AppState()
        let repository = URL(fileURLWithPath: "/tmp/SlugDock", isDirectory: true)
        state.articles = [
            makeArticle(repository: repository, slug: "draft", published: false),
            makeArticle(repository: repository, slug: "published", published: true),
            makeArticle(repository: repository, slug: "unset"),
            makeArticle(repository: repository, slug: "front-matter-error", frontMatterError: "Invalid YAML"),
            makeArticle(repository: repository, slug: "read-error", readError: "Unreadable")
        ]

        let expectations: [(ArticleStatusFilter, [String])] = [
            (.all, ["draft", "front-matter-error", "published", "read-error", "unset"]),
            (.draft, ["draft"]),
            (.published, ["published"]),
            (.unset, ["unset"]),
            (.errors, ["front-matter-error", "read-error"])
        ]
        for (filter, expectedSlugs) in expectations {
            state.articleStatusFilter = filter
            XCTAssertEqual(state.visibleArticles.map(\.slug), expectedSlugs)
        }

        state.articleStatusFilter = .errors
        state.searchText = "front"
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["front-matter-error"])
    }

    @MainActor
    func testArticleListSortsAllColumnsAndKeepsUnavailableValuesLast() {
        let state = AppState()
        let repository = URL(fileURLWithPath: "/tmp/SlugDock", isDirectory: true)
        state.articles = [
            makeArticle(repository: repository, slug: "c", title: "Beta", modifiedAt: nil, published: nil),
            makeArticle(
                repository: repository,
                slug: "b",
                title: "alpha",
                modifiedAt: Date(timeIntervalSince1970: 200),
                published: true
            ),
            makeArticle(
                repository: repository,
                slug: "a",
                title: "Alpha",
                modifiedAt: Date(timeIntervalSince1970: 100),
                published: false
            ),
            makeArticle(repository: repository, slug: "d", title: "Gamma", readError: "Unreadable")
        ]

        XCTAssertEqual(state.visibleArticles.map(\.slug), ["b", "a", "c", "d"])
        state.articleSortOrder = [ArticleSortComparator(field: .title)]
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["a", "b", "c", "d"])
        state.articleSortOrder = [ArticleSortComparator(field: .slug, order: .reverse)]
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["d", "c", "b", "a"])
        state.articleSortOrder = [ArticleSortComparator(field: .modifiedAt)]
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["a", "b", "c", "d"])
        state.articleSortOrder = [ArticleSortComparator(field: .modifiedAt, order: .reverse)]
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["b", "a", "c", "d"])
        state.articleSortOrder = [ArticleSortComparator(field: .status)]
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["a", "b", "c", "d"])
        state.articleSortOrder = [ArticleSortComparator(field: .status, order: .reverse)]
        XCTAssertEqual(state.visibleArticles.map(\.slug), ["b", "a", "c", "d"])
    }

    func testArticleScannerSeparatesReadErrorFromFrontMatterError() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let file = repository.appendingPathComponent("articles/invalid.md")
        try Data([0xFF, 0xFE]).write(to: file)

        let scanned = try await FileSystemService().scanArticles(repositoryURL: repository)
        let article = try XCTUnwrap(scanned.first)

        XCTAssertEqual(article.title, "Read Error")
        XCTAssertNotNil(article.readError)
        XCTAssertNil(article.frontMatterError)
    }

    func testCollisionResolverHandlesSequentialAndMultipleDotNames() throws {
        let directory = URL(fileURLWithPath: "/tmp/test", isDirectory: true)
        let existing = Set(["/tmp/test/archive.tar.png", "/tmp/test/archive.tar-2.png"])
        let result = FileNameCollisionResolver.availableURL(
            for: directory.appendingPathComponent("archive.tar.png"),
            fileExists: { existing.contains($0) }
        )
        XCTAssertEqual(result.lastPathComponent, "archive.tar-3.png")

        let untouched = FileNameCollisionResolver.availableURL(
            for: directory.appendingPathComponent("new.png"),
            fileExists: { _ in false }
        )
        XCTAssertEqual(untouched.lastPathComponent, "new.png")
    }

    func testMarkdownFormatterPreservesUnicodeWrapsWhitespaceAndAddsNoNewline() {
        XCTAssertEqual(
            MarkdownImageFormatter.markdown(slug: "swift", fileName: "図解.png"),
            "![](/images/swift/図解.png)"
        )
        let spaced = MarkdownImageFormatter.markdown(slug: "swift article", fileName: "image 1.png")
        XCTAssertEqual(spaced, "![](</images/swift article/image 1.png>)")
        XCTAssertFalse(spaced.hasSuffix("\n"))
    }

    func testMarkdownApplicationPreferencePersistsBundleIdentifierAndPath() throws {
        let suiteName = "SlugDockTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = MarkdownApplicationPreference(
            bundleIdentifier: "com.example.MarkdownEditor",
            path: "/Applications/Markdown Editor.app"
        )

        SettingsService.saveMarkdownApplication(preference, to: defaults)

        XCTAssertEqual(SettingsService.loadMarkdownApplication(from: defaults), preference)
    }

    func testImageImportValidationAcceptsBoundaryAndRejectsOversizeUnsupportedAndDirectory() async throws {
        let repository = try makeTemporaryRepository()
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlugDockSources-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: repository)
            try? FileManager.default.removeItem(at: source)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let accepted = source.appendingPathComponent("accepted.PNG")
        let rejected = source.appendingPathComponent("large.webp")
        let unsupported = source.appendingPathComponent("note.txt")
        let directory = source.appendingPathComponent("folder.jpg", isDirectory: true)
        try Data(count: 3_000_000).write(to: accepted)
        try Data(count: 3_000_001).write(to: rejected)
        try Data("text".utf8).write(to: unsupported)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        let article = makeArticle(repository: repository)
        let result = await FileSystemService().importImages(
            from: [accepted, rejected, unsupported, directory],
            for: article
        )

        XCTAssertEqual(result.copied.map(\.fileName), ["accepted.PNG"])
        XCTAssertEqual(result.failures.count, 3)
        XCTAssertTrue(result.failures.contains(where: { $0.fileName == "large.webp" && $0.reason.contains("3 MB") }))
    }

    func testExistingOversizeImageIsStillListed() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let article = makeArticle(repository: repository)
        try FileManager.default.createDirectory(at: article.imageDirectoryURL, withIntermediateDirectories: true)
        try Data(count: 3_000_001).write(to: article.imageDirectoryURL.appendingPathComponent("large.JPEG"))

        let images = try await FileSystemService().scanImages(for: article)

        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.fileSize, 3_000_001)
    }

    func testImageRenameMovesFileAndRefreshesAssetMetadata() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let article = makeArticle(repository: repository)
        try FileManager.default.createDirectory(at: article.imageDirectoryURL, withIntermediateDirectories: true)
        let source = article.imageDirectoryURL.appendingPathComponent("before.png")
        try Data("image".utf8).write(to: source)
        let service = FileSystemService()
        let initialImages = try await service.scanImages(for: article)
        let image = try XCTUnwrap(initialImages.first)

        let destination = try await service.renameImage(image, toFileName: "図 解.png", for: article)
        let refreshedImages = try await service.scanImages(for: article)
        let refreshed = try XCTUnwrap(refreshedImages.first)

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(destination.lastPathComponent, "図 解.png")
        XCTAssertEqual(refreshed.fileURL.resolvingSymlinksInPath(), destination.resolvingSymlinksInPath())
        XCTAssertEqual(refreshed.fileName, "図 解.png")
        XCTAssertEqual(refreshed.markdownPath, "![](</images/test/図 解.png>)")
    }

    func testImageRenameRejectsInvalidExtensionAndCollisionWithoutChangingSource() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let article = makeArticle(repository: repository)
        try FileManager.default.createDirectory(at: article.imageDirectoryURL, withIntermediateDirectories: true)
        let source = article.imageDirectoryURL.appendingPathComponent("source.png")
        let existing = article.imageDirectoryURL.appendingPathComponent("existing.png")
        try Data("source".utf8).write(to: source)
        try Data("existing".utf8).write(to: existing)
        let service = FileSystemService()
        let images = try await service.scanImages(for: article)
        let image = try XCTUnwrap(images.first(where: { $0.fileName == source.lastPathComponent }))

        for (fileName, expectedError) in [
            (" \n", SlugDockError.invalidImageFileName),
            ("../outside.png", SlugDockError.invalidImageFileName),
            ("renamed.jpg", SlugDockError.imageExtensionCannotChange),
            ("existing.png", SlugDockError.imageNameAlreadyExists)
        ] {
            do {
                _ = try await service.renameImage(image, toFileName: fileName, for: article)
                XCTFail("\(fileName)への変更は失敗する必要があります")
            } catch let error as SlugDockError {
                XCTAssertEqual(error, expectedError)
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
    }

    private func makeTemporaryRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlugDockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("articles", isDirectory: true),
            withIntermediateDirectories: true
        )
        return repository
    }

    private func makeArticle(
        repository: URL,
        slug: String = "test",
        title: String = "Test",
        modifiedAt: Date? = nil,
        published: Bool? = nil,
        frontMatterError: String? = nil,
        readError: String? = nil
    ) -> Article {
        let markdown = repository.appendingPathComponent("articles/\(slug).md")
        return Article(
            id: markdown,
            title: title,
            slug: slug,
            markdownURL: markdown,
            imageDirectoryURL: repository.appendingPathComponent("images/\(slug)", isDirectory: true),
            modifiedAt: modifiedAt,
            published: published,
            frontMatterError: frontMatterError,
            readError: readError
        )
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }
}
