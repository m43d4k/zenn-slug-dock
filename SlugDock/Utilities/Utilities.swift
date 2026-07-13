import Foundation

enum FileNameCollisionResolver {
    static func availableURL(
        for proposedURL: URL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> URL {
        guard fileExists(proposedURL.path) else {
            return proposedURL
        }

        let directory = proposedURL.deletingLastPathComponent()
        let fileExtension = proposedURL.pathExtension
        let stem = proposedURL.deletingPathExtension().lastPathComponent
        var suffix = 2

        while true {
            let candidateName = fileExtension.isEmpty
                ? "\(stem)-\(suffix)"
                : "\(stem)-\(suffix).\(fileExtension)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fileExists(candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }
}

enum MarkdownImageFormatter {
    static func markdown(slug: String, fileName: String) -> String {
        let path = "/images/\(slug)/\(fileName)"
        if path.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return "![](<\(path)>)"
        }
        return "![](\(path))"
    }
}

enum FileSizeTextFormatter {
    static func string(fromByteCount byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: byteCount)
    }
}
