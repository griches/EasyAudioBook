import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    var downloader: BookDownloader?

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        RARHandler.copyIncomingFile(at: url)
        NotificationCenter.default.post(name: .audiobookArchiveReceived, object: nil)
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        downloader?.backgroundCompletionHandler = completionHandler
    }
}

extension Notification.Name {
    static let audiobookArchiveReceived = Notification.Name("audiobookArchiveReceived")
}
