import Foundation
import UIKit

struct Audiobook: Identifiable, Sendable, Equatable {
    static func == (lhs: Audiobook, rhs: Audiobook) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.author == rhs.author
    }

    let id: String
    let folderURL: URL
    let title: String
    let author: String
    let narrator: String
    let bookDescription: String
    let coverImage: UIImage?
    let mp3Files: [URL]

    static var preview: Audiobook {
        Audiobook(
            id: "preview-book",
            folderURL: URL(fileURLWithPath: "/tmp"),
            title: "Dead at First Sight",
            author: "Peter James",
            narrator: "Daniel Weyman",
            bookDescription: "A gripping thriller",
            coverImage: nil,
            mp3Files: []
        )
    }

    nonisolated static func load(from folderURL: URL) -> Audiobook? {
        let fm = FileManager.default
        let folderName = folderURL.lastPathComponent

        guard let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        let mp3s = contents
            .filter { $0.pathExtension.lowercased() == "mp3" }
            .sorted { extractTrackNumber($0.lastPathComponent) < extractTrackNumber($1.lastPathComponent) }

        guard !mp3s.isEmpty else { return nil }

        let coverImage = loadCover(in: folderURL, contents: contents)
        let nfoFile = contents.first { $0.pathExtension.lowercased() == "nfo" }
        let nfoData = parseNFO(nfoFile)

        // Check for user overrides
        let overrideTitle = UserDefaults.standard.string(forKey: "bookTitle_\(folderName)")
        let overrideAuthor = UserDefaults.standard.string(forKey: "bookAuthor_\(folderName)")

        return Audiobook(
            id: folderName,
            folderURL: folderURL,
            title: overrideTitle ?? nfoData.title ?? folderName,
            author: overrideAuthor ?? nfoData.author ?? "Unknown Author",
            narrator: nfoData.narrator ?? "",
            bookDescription: nfoData.description ?? "",
            coverImage: coverImage,
            mp3Files: mp3s
        )
    }

    private nonisolated static func extractTrackNumber(_ filename: String) -> Int {
        let noExt = (filename as NSString).deletingPathExtension

        // Match NNN-NNN pattern at end (track-total): "Name 001-130" -> 1
        if let range = noExt.range(of: #"(\d+)\s*-\s*\d+$"#, options: .regularExpression) {
            let match = String(noExt[range])
            let trackPart = match.components(separatedBy: "-").first ?? match
            if let num = Int(trackPart.trimmingCharacters(in: .whitespaces)) {
                return num
            }
        }

        // Fallback: last number group in filename
        let parts = noExt.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if let last = parts.last, let num = Int(last) {
            return num
        }
        return 0
    }

    private nonisolated static func loadCover(in folder: URL, contents: [URL]) -> UIImage? {
        let coverNames = ["cover", "folder", "front"]
        let imageExts = ["jpg", "jpeg", "png", "webp"]

        for file in contents {
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            let ext = file.pathExtension.lowercased()
            if coverNames.contains(name) && imageExts.contains(ext) {
                return UIImage(contentsOfFile: file.path)
            }
        }
        return nil
    }

    private struct NFOData: Sendable {
        var title: String?
        var author: String?
        var narrator: String?
        var description: String?
    }

    private nonisolated static func parseNFO(_ url: URL?) -> NFOData {
        guard let url = url else { return NFOData() }

        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = latin1
        } else {
            return NFOData()
        }

        return extractNFOFields(from: content)
    }

    private nonisolated static func extractNFOFields(from content: String) -> NFOData {
        var data = NFOData()
        let lines = content.components(separatedBy: .newlines)

        var inDescription = false
        var descriptionLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Title:") {
                data.title = trimmed.replacingOccurrences(of: "Title:", with: "").trimmingCharacters(in: .whitespaces)
                inDescription = false
            } else if trimmed.hasPrefix("Author:") {
                data.author = trimmed.replacingOccurrences(of: "Author:", with: "").trimmingCharacters(in: .whitespaces)
                inDescription = false
            } else if trimmed.hasPrefix("Read By:") || trimmed.hasPrefix("Narrator:") {
                let value = trimmed
                    .replacingOccurrences(of: "Read By:", with: "")
                    .replacingOccurrences(of: "Narrator:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                data.narrator = value
                inDescription = false
            } else if trimmed == "Book Description" || trimmed == "Description" {
                inDescription = true
            } else if trimmed.contains("====") || trimmed.contains("----") {
                // separator line
            } else if inDescription && !trimmed.isEmpty {
                descriptionLines.append(trimmed)
            }
        }

        if !descriptionLines.isEmpty {
            data.description = descriptionLines.joined(separator: " ")
        }

        return data
    }
}
