import Foundation
import XCTest
@testable import SlugDock

final class SlugDockTests: XCTestCase, @unchecked Sendable {
    func testFrontMatterParsesQuotedTitleContainingColon() {
        let result = FrontMatterParser.parse(markdown: """
        ---
        title: "Swift: はじめの一歩"
        published: false
        ---
        body
        """)

        XCTAssertEqual(result, FrontMatterResult(title: "Swift: はじめの一歩", error: nil))
    }

    func testFrontMatterUsesUntitledForEmptyOrMissingFrontMatter() {
        XCTAssertEqual(
            FrontMatterParser.parse(markdown: "---\ntitle: \"   \"\n---\n"),
            FrontMatterResult(title: "タイトル未設定", error: nil)
        )
        XCTAssertEqual(
            FrontMatterParser.parse(markdown: "# Front Matterなし"),
            FrontMatterResult(title: "タイトル未設定", error: nil)
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

    func testArticleScannerIncludesOnlyDirectLowercaseMarkdownAndSortsByTitleThenSlug() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let articles = repository.appendingPathComponent("articles")
        try write("---\ntitle: beta\n---", to: articles.appendingPathComponent("z.md"))
        try write("---\ntitle: Alpha\n---", to: articles.appendingPathComponent("b.md"))
        try write("---\ntitle: alpha\n---", to: articles.appendingPathComponent("a.md"))
        try write("---\ntitle: excluded\n---", to: articles.appendingPathComponent("upper.MD"))
        try write("text", to: articles.appendingPathComponent("note.txt"))
        let nested = articles.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try write("---\ntitle: nested\n---", to: nested.appendingPathComponent("nested.md"))

        let result = try await FileSystemService().scanArticles(repositoryURL: repository)

        XCTAssertEqual(result.map(\.slug), ["a", "b", "z"])
        XCTAssertEqual(result.map(\.title), ["alpha", "Alpha", "beta"])
    }

    func testArticleScannerSeparatesReadErrorFromFrontMatterError() async throws {
        let repository = try makeTemporaryRepository()
        defer { try? FileManager.default.removeItem(at: repository) }
        let file = repository.appendingPathComponent("articles/invalid.md")
        try Data([0xFF, 0xFE]).write(to: file)

        let scanned = try await FileSystemService().scanArticles(repositoryURL: repository)
        let article = try XCTUnwrap(scanned.first)

        XCTAssertEqual(article.title, "読み取りエラー")
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
        XCTAssertTrue(result.failures.contains(where: { $0.fileName == "large.webp" && $0.reason.contains("3MB") }))
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

    private func makeTemporaryRepository() throws -> URL {
        let repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlugDockTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("articles", isDirectory: true),
            withIntermediateDirectories: true
        )
        return repository
    }

    private func makeArticle(repository: URL) -> Article {
        let markdown = repository.appendingPathComponent("articles/test.md")
        return Article(
            id: markdown,
            title: "Test",
            slug: "test",
            markdownURL: markdown,
            imageDirectoryURL: repository.appendingPathComponent("images/test", isDirectory: true),
            modifiedAt: nil,
            frontMatterError: nil,
            readError: nil
        )
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }
}
