import Foundation
import Observation

@Observable
class AudiobookLibrary {
    var books: [Audiobook] = []
    var selectedIndex: Int = 0

    var selectedBook: Audiobook? {
        guard !books.isEmpty else { return nil }
        return books[selectedIndex]
    }

    private let lastBookKey = "lastBookID"

    func scan() {
        let fm = FileManager.default

        // Write instructions file so iOS registers the Documents folder with Files app
        if let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let instructions = docsURL.appendingPathComponent("Instructions.txt")
            if !fm.fileExists(atPath: instructions.path) {
                let text = """
                Easy Audiobook - Instructions
                =============================

                Adding audiobooks manually:
                - Copy an audiobook folder into this directory using the Files app
                - Each folder should contain MP3 files and optionally a cover.jpg and .nfo file
                - The app will detect the folder and display it in your library

                Downloading audiobooks via URL scheme:
                - Easy Audiobook supports a custom URL scheme for downloading books
                  directly into the app from a link:

                  easyaudiobook://download?book=URL_TO_FILE

                - Replace URL_TO_FILE with the full web address of the audiobook archive
                - Example: easyaudiobook://download?book=https://myserver.com/books/thriller.rar
                - When this link is opened on the device, the app will launch,
                  download the file, extract it, and add it to the library automatically
                - Supported archive formats: RAR, ZIP, 7z, TAR, GZ

                Folder structure:
                - Folder name becomes the book title (unless an .nfo file is present)
                - cover.jpg — displayed as the book cover
                - .nfo file — parsed for Title, Author, Read By, and Description
                - MP3 files — played in order, numbered like "Name 001-130.mp3"
                """
                fm.createFile(atPath: instructions.path, contents: Data(text.utf8))
            }
        }

        // Extract any archive files before scanning for books
        RARHandler.extractArchivesInDocuments()

        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        var loadedBooks: [Audiobook] = []

        if let folders = try? fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: [.isDirectoryKey]) {
            for folder in folders {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: folder.path, isDirectory: &isDir)
                if isDir.boolValue {
                    if let book = Audiobook.load(from: folder) {
                        loadedBooks.append(book)
                    }
                }
            }
        }

        loadedBooks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        // Detect newly added books
        let oldIDs = Set(books.map { $0.id })
        let newIDs = Set(loadedBooks.map { $0.id })
        let addedIDs = newIDs.subtracting(oldIDs)

        books = loadedBooks

        if let newID = addedIDs.first, let idx = books.firstIndex(where: { $0.id == newID }) {
            // Select the newly added book
            selectedIndex = idx
            saveSelection()
        } else if let lastID = UserDefaults.standard.string(forKey: lastBookKey),
           let idx = books.firstIndex(where: { $0.id == lastID }) {
            selectedIndex = idx
        } else {
            selectedIndex = 0
        }
    }

    func selectNext() {
        guard !books.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % books.count
        saveSelection()
    }

    func selectPrevious() {
        guard !books.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + books.count) % books.count
        saveSelection()
    }

    func saveSelection() {
        if let book = selectedBook {
            UserDefaults.standard.set(book.id, forKey: lastBookKey)
        }
    }

    func updateBookMetadata(bookID: String, title: String, author: String) {
        UserDefaults.standard.set(title, forKey: "bookTitle_\(bookID)")
        UserDefaults.standard.set(author, forKey: "bookAuthor_\(bookID)")

        if let idx = books.firstIndex(where: { $0.id == bookID }) {
            // Reload from disk to pick up overrides
            if let updated = Audiobook.load(from: books[idx].folderURL) {
                books[idx] = updated
            }
        }
    }

    func deleteBook(_ book: Audiobook) {
        try? FileManager.default.removeItem(at: book.folderURL)

        // Clear saved position
        UserDefaults.standard.removeObject(forKey: "bookPosition_\(book.id)")
        UserDefaults.standard.removeObject(forKey: "bookTrack_\(book.id)")

        books.removeAll { $0.id == book.id }

        if books.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, books.count - 1)
        }
        saveSelection()
    }
}
