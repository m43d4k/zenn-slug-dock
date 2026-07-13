import AppKit
import Foundation
import Yams

enum FrontMatterParser {
    static func parse(markdown: String) -> FrontMatterResult {
        var normalized = markdown
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first.map(stripCarriageReturn) == "---" else {
            return FrontMatterResult(title: "タイトル未設定", error: nil)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { stripCarriageReturn($0) == "---" }) else {
            return FrontMatterResult(
                title: "Front Matterエラー",
                error: "Front Matterの終了区切りがありません"
            )
        }

        let yaml = lines[1..<closingIndex]
            .map { String(stripCarriageReturn($0)) }
            .joined(separator: "\n")

        do {
            let rawFrontMatter = try Yams.load(yaml: yaml)
            if let mapping = rawFrontMatter as? [String: Any],
               mapping.keys.contains("title"),
               !(mapping["title"] is String) {
                return FrontMatterResult(
                    title: "Front Matterエラー",
                    error: "Front Matterのtitleは文字列で指定してください"
                )
            }
            let frontMatter = try YAMLDecoder().decode(ArticleFrontMatter.self, from: yaml)
            let title = frontMatter.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return FrontMatterResult(title: title.isEmpty ? "タイトル未設定" : title, error: nil)
        } catch {
            return FrontMatterResult(
                title: "Front Matterエラー",
                error: "Front Matterを解析できません: \(error.localizedDescription)"
            )
        }
    }

    private static func stripCarriageReturn(_ line: Substring) -> Substring {
        line.last == "\r" ? line.dropLast() : line
    }
}

actor FileSystemService {
    static let supportedImageExtensions = Set(["png", "jpg", "jpeg", "gif", "webp"])
    static let maximumImportSize: Int64 = 3_000_000

    func scanArticles(repositoryURL: URL) throws -> [Article] {
        let articlesURL = repositoryURL.appendingPathComponent("articles", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: articlesURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SlugDockError.articlesDirectoryMissing
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: articlesURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return urls.compactMap { url -> Article? in
            guard url.pathExtension == "md",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }

            let slug = url.deletingPathExtension().lastPathComponent
            let imageDirectoryURL = repositoryURL
                .appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent(slug, isDirectory: true)
            let modifiedAt = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

            do {
                let data = try Data(contentsOf: url)
                guard let markdown = String(data: data, encoding: .utf8) else {
                    return Article(
                        id: url,
                        title: "読み取りエラー",
                        slug: slug,
                        markdownURL: url,
                        imageDirectoryURL: imageDirectoryURL,
                        modifiedAt: modifiedAt,
                        frontMatterError: nil,
                        readError: "MarkdownをUTF-8として読み取れません"
                    )
                }
                let parsed = FrontMatterParser.parse(markdown: markdown)
                return Article(
                    id: url,
                    title: parsed.title,
                    slug: slug,
                    markdownURL: url,
                    imageDirectoryURL: imageDirectoryURL,
                    modifiedAt: modifiedAt,
                    frontMatterError: parsed.error,
                    readError: nil
                )
            } catch {
                return Article(
                    id: url,
                    title: "読み取りエラー",
                    slug: slug,
                    markdownURL: url,
                    imageDirectoryURL: imageDirectoryURL,
                    modifiedAt: modifiedAt,
                    frontMatterError: nil,
                    readError: "Markdownを読み取れません: \(error.localizedDescription)"
                )
            }
        }
        .sorted(by: articleSort)
    }

    func scanImages(for article: Article) throws -> [ImageAsset] {
        let directory = article.imageDirectoryURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw SlugDockError.imagePathIsNotDirectory
        }

        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            guard Self.supportedImageExtensions.contains(url.pathExtension.lowercased()) else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else {
                return nil
            }
            return makeImageAsset(url: url, slug: article.slug, fileSize: Int64(values?.fileSize ?? 0))
        }
        .sorted {
            $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
        }
    }

    func createImageDirectory(for article: Article) throws {
        try FileManager.default.createDirectory(
            at: article.imageDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    func importImages(from sourceURLs: [URL], for article: Article) -> ImageImportResult {
        var copied: [ImageAsset] = []
        var failures: [ImageImportFailure] = []
        var selectedURL: URL?

        do {
            try createImageDirectory(for: article)
        } catch {
            let reason = "画像フォルダを作成できません: \(error.localizedDescription)"
            return ImageImportResult(
                copied: [],
                failures: sourceURLs.map { ImageImportFailure(fileName: $0.lastPathComponent, reason: reason) },
                selectedURL: nil
            )
        }

        for sourceURL in sourceURLs {
            do {
                let fileSize = try validateImportSource(sourceURL)
                let originalDestination = article.imageDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)

                if sourceURL.standardizedFileURL == originalDestination.standardizedFileURL {
                    selectedURL = sourceURL
                    continue
                }

                let destination = FileNameCollisionResolver.availableURL(for: originalDestination)
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                let asset = makeImageAsset(url: destination, slug: article.slug, fileSize: fileSize)
                copied.append(asset)
                selectedURL = destination
            } catch {
                failures.append(
                    ImageImportFailure(fileName: sourceURL.lastPathComponent, reason: userFacingReason(for: error))
                )
            }
        }

        return ImageImportResult(copied: copied, failures: failures, selectedURL: selectedURL)
    }

    private func validateImportSource(_ url: URL) throws -> Int64 {
        guard url.isFileURL else {
            throw SlugDockError.remoteURLNotSupported
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw SlugDockError.notARegularFile
        }
        guard Self.supportedImageExtensions.contains(url.pathExtension.lowercased()) else {
            throw SlugDockError.unsupportedImageType
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw SlugDockError.fileNotReadable
        }
        let size = Int64(values.fileSize ?? 0)
        guard size <= Self.maximumImportSize else {
            throw SlugDockError.imageTooLarge
        }
        return size
    }

    private func makeImageAsset(url: URL, slug: String, fileSize: Int64) -> ImageAsset {
        ImageAsset(
            id: url,
            fileURL: url,
            fileName: url.lastPathComponent,
            fileSize: fileSize,
            markdownPath: MarkdownImageFormatter.markdown(slug: slug, fileName: url.lastPathComponent)
        )
    }

    private func userFacingReason(for error: Error) -> String {
        if let error = error as? SlugDockError {
            return error.errorDescription ?? "追加できませんでした"
        }
        return "コピーできません: \(error.localizedDescription)"
    }

    private func articleSort(_ lhs: Article, _ rhs: Article) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder == .orderedSame {
            return lhs.slug.localizedCaseInsensitiveCompare(rhs.slug) == .orderedAscending
        }
        return titleOrder == .orderedAscending
    }
}

enum SlugDockError: LocalizedError, Equatable {
    case articlesDirectoryMissing
    case imagePathIsNotDirectory
    case remoteURLNotSupported
    case notARegularFile
    case unsupportedImageType
    case fileNotReadable
    case imageTooLarge
    case targetMissing
    case clipboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .articlesDirectoryMissing: "articles ディレクトリが見つかりません"
        case .imagePathIsNotDirectory: "画像の保存先がフォルダではありません"
        case .remoteURLNotSupported: "ローカルファイルではありません"
        case .notARegularFile: "通常のファイルではありません"
        case .unsupportedImageType: "対応していない画像形式です"
        case .fileNotReadable: "ファイルを読み取れません"
        case .imageTooLarge: "3MBを超えているため追加できません"
        case .targetMissing: "対象が見つかりません"
        case .clipboardWriteFailed: "クリップボードへコピーできません"
        }
    }
}

@MainActor
enum SystemService {
    static func copyToClipboard(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw SlugDockError.clipboardWriteFailed
        }
    }

    static func revealInFinder(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SlugDockError.targetMissing
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openInFinder(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SlugDockError.targetMissing
        }
        NSWorkspace.shared.open(url)
    }
}

enum SettingsService {
    private static let repositoryPathKey = "repositoryRootPath"
    private static let windowWidthKey = "windowWidth"
    private static let windowHeightKey = "windowHeight"

    static var repositoryURL: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: repositoryPathKey) else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            UserDefaults.standard.set(newValue?.path, forKey: repositoryPathKey)
        }
    }

    static var windowSize: CGSize {
        get {
            let width = UserDefaults.standard.double(forKey: windowWidthKey)
            let height = UserDefaults.standard.double(forKey: windowHeightKey)
            return CGSize(width: width > 0 ? width : 960, height: height > 0 ? height : 680)
        }
        set {
            UserDefaults.standard.set(newValue.width, forKey: windowWidthKey)
            UserDefaults.standard.set(newValue.height, forKey: windowHeightKey)
        }
    }
}
