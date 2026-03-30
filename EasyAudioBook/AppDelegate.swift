import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        RARHandler.copyIncomingFile(at: url)
        NotificationCenter.default.post(name: .audiobookArchiveReceived, object: nil)
        return true
    }
}

extension Notification.Name {
    static let audiobookArchiveReceived = Notification.Name("audiobookArchiveReceived")
}
