import Foundation

struct Article: Identifiable, Hashable, Sendable {
    let id: URL
    let title: String
    let slug: String
    let markdownURL: URL
    let imageDirectoryURL: URL
    let modifiedAt: Date?
    let published: Bool?
    let frontMatterError: String?
    let readError: String?

    var displayError: String? {
        readError ?? frontMatterError
    }

    var status: ArticleStatus {
        if readError != nil {
            return .readError
        }
        if frontMatterError != nil {
            return .frontMatterError
        }
        return switch published {
        case true: .published
        case false: .draft
        case nil: .unset
        }
    }
}

struct ArticleFrontMatter: Decodable, Sendable {
    let title: String?
    let published: Bool?
}

enum ArticleStatus: Equatable, Sendable {
    case draft
    case published
    case unset
    case frontMatterError
    case readError

    var label: String {
        switch self {
        case .draft: "Draft"
        case .published: "Published"
        case .unset: "—"
        case .frontMatterError: "Front Matter Error"
        case .readError: "Read Error"
        }
    }

    var sortRank: Int {
        switch self {
        case .draft: 0
        case .published: 1
        case .unset: 2
        case .frontMatterError, .readError: 3
        }
    }

    var isError: Bool {
        switch self {
        case .frontMatterError, .readError: true
        case .draft, .published, .unset: false
        }
    }
}

enum ArticleStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case draft = "Draft"
    case published = "Published"
    case unset = "Unset"
    case errors = "Errors"

    var id: Self { self }

    func matches(_ article: Article) -> Bool {
        switch self {
        case .all: true
        case .draft: article.status == .draft
        case .published: article.status == .published
        case .unset: article.status == .unset
        case .errors: article.status.isError
        }
    }
}

enum ArticleSortField: Sendable {
    case title
    case slug
    case status
    case modifiedAt
}

struct ArticleSortComparator: SortComparator, Sendable {
    var field: ArticleSortField
    var order: SortOrder = .forward

    func compare(_ lhs: Article, _ rhs: Article) -> ComparisonResult {
        switch field {
        case .title:
            ordered(lhs.title.localizedCaseInsensitiveCompare(rhs.title))
        case .slug:
            ordered(lhs.slug.localizedCaseInsensitiveCompare(rhs.slug))
        case .status:
            compareStatus(lhs.status, rhs.status)
        case .modifiedAt:
            compareOptionalDates(lhs.modifiedAt, rhs.modifiedAt)
        }
    }

    private func compareStatus(_ lhs: ArticleStatus, _ rhs: ArticleStatus) -> ComparisonResult {
        guard lhs.sortRank != rhs.sortRank else { return .orderedSame }
        if lhs.sortRank >= ArticleStatus.unset.sortRank || rhs.sortRank >= ArticleStatus.unset.sortRank {
            return lhs.sortRank < rhs.sortRank ? .orderedAscending : .orderedDescending
        }
        return ordered(lhs.sortRank < rhs.sortRank ? .orderedAscending : .orderedDescending)
    }

    private func compareOptionalDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedDescending
        case (_, nil): .orderedAscending
        case let (lhs?, rhs?): ordered(lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending))
        }
    }

    private func ordered(_ result: ComparisonResult) -> ComparisonResult {
        guard order == .reverse else { return result }
        return switch result {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }
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
    let published: Bool?
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
