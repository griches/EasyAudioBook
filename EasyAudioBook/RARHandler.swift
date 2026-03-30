import Foundation

enum RARHandler {
    private static let archiveExtensions: Set<String> = ["rar", "zip", "7z", "tar", "gz", "bz2"]

    /// Scans the Documents directory for archive files, extracts each one, then deletes the archive.
    static func extractArchivesInDocuments() {
        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        guard let contents = try? fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil) else { return }

        for file in contents {
            let ext = file.pathExtension.lowercased()
            guard archiveExtensions.contains(ext) else { continue }

            let folderName = file.deletingPathExtension().lastPathComponent
            let destURL = docsURL.appendingPathComponent(folderName)

            // Skip if already extracted
            if fm.fileExists(atPath: destURL.path) { continue }

            do {
                try fm.createDirectory(at: destURL, withIntermediateDirectories: true)
            } catch {
                print("Failed to create directory \(destURL): \(error)")
                continue
            }

            let archivePath = file.path
            let destPath = destURL.path

            var errorPtr: UnsafePointer<CChar>?
            let result = extractArchive(archivePath, destPath, &errorPtr)

            if result == 0 {
                // Success — delete the archive
                try? fm.removeItem(at: file)
                // If the archive contained a single subfolder, flatten it
                flattenSingleSubfolder(at: destURL)
            } else {
                let errorMsg = errorPtr.map { String(cString: $0) } ?? "Unknown error"
                print("Failed to extract \(file.lastPathComponent): \(errorMsg)")
                // Clean up failed extraction
                try? fm.removeItem(at: destURL)
            }
        }
    }

    /// Copy an incoming file to Documents (does not extract — call extractArchivesInDocuments separately)
    static func copyIncomingFile(at url: URL) {
        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()
        let destFile = docsURL.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: destFile)

        if archiveExtensions.contains(ext) {
            try? fm.copyItem(at: url, to: destFile)
        } else {
            // Not an archive — copy as-is
            if !fm.fileExists(atPath: destFile.path) {
                try? fm.copyItem(at: url, to: destFile)
            }
        }
    }

    /// If extraction produced a single subfolder inside destURL, move its contents up.
    private static func flattenSingleSubfolder(at url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        // Filter out hidden files
        let visible = contents.filter { !$0.lastPathComponent.hasPrefix(".") }

        if visible.count == 1 {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: visible[0].path, isDirectory: &isDir), isDir.boolValue {
                // Single subfolder — move its contents up
                let subfolder = visible[0]
                if let subContents = try? fm.contentsOfDirectory(at: subfolder, includingPropertiesForKeys: nil) {
                    for item in subContents {
                        let dest = url.appendingPathComponent(item.lastPathComponent)
                        try? fm.moveItem(at: item, to: dest)
                    }
                    try? fm.removeItem(at: subfolder)
                }
            }
        }
    }
}
