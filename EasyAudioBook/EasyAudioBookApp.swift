import SwiftUI

@main
struct EasyAudioBookApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var library = AudiobookLibrary()
    @State private var player = AudioPlayer()
    @State private var downloader = BookDownloader()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(player)
                .environment(downloader)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.downloader = downloader
                    library.scan()
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        // Custom scheme: easyaudiobook://download?book=https://example.com/file.rar
        if url.scheme == "easyaudiobook" {
            let host = url.host ?? ""

            if host == "deleteall" {
                // easyaudiobook://deleteall
                player.stop()
                let allBooks = library.books
                for book in allBooks {
                    library.deleteBook(book)
                }
                library.scan()
                return
            }

            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let bookParam = components.queryItems?.first(where: { $0.name == "book" })?.value,
               let downloadURL = URL(string: bookParam) {
                downloader.download(from: downloadURL) {
                    library.scan()
                }
            }
            return
        }

        // Regular file open (shared RAR/ZIP)
        RARHandler.copyIncomingFile(at: url)
        NotificationCenter.default.post(name: .audiobookArchiveReceived, object: nil)
    }
}
