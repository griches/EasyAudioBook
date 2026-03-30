import Foundation
import Observation

@Observable
class BookDownloader: NSObject, URLSessionDownloadDelegate {
    var isDownloading = false
    var progress: Double = 0
    var statusText = ""
    var errorText: String?

    private var session: URLSession?
    private var onComplete: (() -> Void)?

    func download(from url: URL, completion: @escaping () -> Void) {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        statusText = "Downloading..."
        errorText = nil
        onComplete = completion

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        session?.downloadTask(with: url).resume()
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        // Use the filename from the response, or fall back to the URL's last path component
        let suggestedName = downloadTask.response?.suggestedFilename ?? downloadTask.originalRequest?.url?.lastPathComponent ?? "download.rar"
        let destFile = docsURL.appendingPathComponent(suggestedName)

        try? fm.removeItem(at: destFile)
        try? fm.moveItem(at: location, to: destFile)

        DispatchQueue.main.async {
            self.statusText = "Extracting..."
            self.progress = 1.0

            DispatchQueue.global(qos: .userInitiated).async {
                RARHandler.extractArchivesInDocuments()
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.statusText = ""
                    self.onComplete?()
                    self.onComplete = nil
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        DispatchQueue.main.async {
            if totalBytesExpectedToWrite > 0 {
                self.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                let mb = Double(totalBytesWritten) / 1_000_000
                let totalMB = Double(totalBytesExpectedToWrite) / 1_000_000
                self.statusText = String(format: "Downloading... %.0f / %.0f MB", mb, totalMB)
            } else {
                let mb = Double(totalBytesWritten) / 1_000_000
                self.statusText = String(format: "Downloading... %.0f MB", mb)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            DispatchQueue.main.async {
                self.errorText = error.localizedDescription
                self.statusText = "Download failed"
                self.isDownloading = false
                self.onComplete = nil
            }
        }
    }
}
