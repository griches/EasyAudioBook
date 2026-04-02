import SwiftUI
import os.log

private let log = Logger(subsystem: "mobi.bouncingball.EasyAudioBook", category: "URLHandler")

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
        log.info("handleURL called with: \(url.absoluteString, privacy: .public)")

        // Custom scheme: easyaudiobook://download?book=https://example.com/file.rar
        if url.scheme == "easyaudiobook" {
            let host = url.host ?? ""
            log.info("Scheme: easyaudiobook, host: \(host, privacy: .public)")

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

            if host == "delete" {
                // easyaudiobook://delete?book=My%20Audiobook%20Title
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let title = components.queryItems?.first(where: { $0.name == "book" })?.value,
                   let book = library.books.first(where: { $0.title == title }) {
                    player.stop()
                    library.deleteBook(book)
                }
                return
            }

            if host == "settings" {
                // easyaudiobook://settings?skipDurationSeconds=60&sleepTimerMinutes=45
                if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    for item in components.queryItems ?? [] {
                        switch item.name {
                        case "skipDurationSeconds":
                            if let val = Int(item.value ?? ""), val > 0, val <= 600 {
                                UserDefaults.standard.set(val, forKey: "skipDurationSeconds")
                            }
                        case "sleepTimerMinutes":
                            if let val = Int(item.value ?? ""), val > 0, val <= 480 {
                                UserDefaults.standard.set(val, forKey: "sleepTimerMinutes")
                            }
                        default:
                            break
                        }
                    }
                    NotificationCenter.default.post(name: .settingsChanged, object: nil)
                }
                return
            }

            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let bookParam = components?.queryItems?.first(where: { $0.name == "book" })?.value
            log.info("Download branch — components: \(components?.string ?? "nil", privacy: .public), bookParam: \(bookParam ?? "nil", privacy: .public)")

            if let bookParam, let downloadURL = URL(string: bookParam) {
                log.info("Starting download for: \(downloadURL.absoluteString, privacy: .public)")
                downloader.download(from: downloadURL) {
                    library.scan()
                }
            } else {
                log.error("Failed to parse download URL from link. Query items: \(components?.queryItems?.description ?? "nil", privacy: .public)")
            }
            return
        }

        // Regular file open (shared RAR/ZIP)
        log.info("Handling as file open: \(url.path, privacy: .public)")
        RARHandler.copyIncomingFile(at: url)
        NotificationCenter.default.post(name: .audiobookArchiveReceived, object: nil)
    }
}
