import Foundation

struct Article: Identifiable, Hashable, Sendable {
    let id: URL
    let title: String
    let slug: String
    let markdownURL: URL
    let imageDirectoryURL: URL
    let modifiedAt: Date?
    let frontMatterError: String?
    let readError: String?

    var displayError: String? {
        readError ?? frontMatterError
    }
}

struct ArticleFrontMatter: Decodable, Sendable {
    let title: String?
}

struct ImageAsset: Identifiable, Hashable, Sendable {
    let id: URL
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let markdownPath: String
}

struct FrontMatterResult: Equatable, Sendable {
    let title: String
    let error: String?
}

struct ImageImportFailure: Equatable, Sendable {
    let fileName: String
    let reason: String
}

struct ImageImportResult: Sendable {
    let copied: [ImageAsset]
    let failures: [ImageImportFailure]
    let selectedURL: URL?
}
