import Foundation
import Observation
import os.log

@Observable
class BookDownloader: NSObject, URLSessionDownloadDelegate {
    private static let log = Logger(subsystem: "mobi.bouncingball.EasyAudioBook", category: "BookDownloader")
    var isDownloading = false
    var progress: Double = 0
    var statusText = ""
    var errorText: String?

    private var session: URLSession?
    private var onComplete: (() -> Void)?
    var backgroundCompletionHandler: (() -> Void)?

    func download(from url: URL, completion: @escaping () -> Void) {
        guard !isDownloading else {
            Self.log.warning("Download rejected — already downloading")
            return
        }

        Self.log.info("Starting download from: \(url.absoluteString, privacy: .public)")
        isDownloading = true
        progress = 0
        statusText = "Checking available space..."
        errorText = nil
        onComplete = completion

        // HEAD request to get file size before downloading
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: headRequest) { [weak self] _, response, error in
            DispatchQueue.main.async {
                guard let self else {
                    Self.log.error("Self was deallocated during HEAD request")
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    Self.log.info("HEAD response: status=\(httpResponse.statusCode), contentLength=\(httpResponse.expectedContentLength)")
                }

                if let error {
                    Self.log.error("HEAD request failed: \(error.localizedDescription, privacy: .public) — proceeding with download anyway")
                    // Don't abort on HEAD failure — many servers block HEAD requests
                    self.statusText = "Downloading..."
                    self.startDownload(from: url)
                    return
                }

                let fileSize = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
                let freeBytes = self.availableStorageBytes()
                Self.log.info("File size: \(fileSize) bytes, free space: \(freeBytes ?? -1) bytes")

                if fileSize > 0, let freeBytes, fileSize > freeBytes {
                    let fileMB = Double(fileSize) / 1_000_000
                    let freeMB = Double(freeBytes) / 1_000_000
                    Self.log.error("Not enough storage: need \(fileMB)MB, have \(freeMB)MB")
                    self.errorText = String(format: "Not enough storage. The file needs %.0f MB but only %.0f MB is available.", fileMB, freeMB)
                    self.statusText = "Not enough space"
                    self.isDownloading = false
                    self.onComplete = nil
                    return
                }

                Self.log.info("Storage check passed, starting download")
                self.statusText = "Downloading..."
                self.startDownload(from: url)
            }
        }.resume()
    }

    private func startDownload(from url: URL) {
        Self.log.info("Creating background download session for: \(url.absoluteString, privacy: .public)")

        // Cancel any leftover tasks from a previous session with this identifier
        if let existing = session {
            existing.getAllTasks { tasks in
                for task in tasks {
                    Self.log.info("Cancelling leftover task: \(task.taskIdentifier)")
                    task.cancel()
                }
            }
            existing.invalidateAndCancel()
        }

        let config = URLSessionConfiguration.background(withIdentifier: "mobi.bouncingball.EasyAudioBook.download")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)

        // Also cancel any tasks reconnected from a prior app launch
        session?.getAllTasks { [weak self] tasks in
            for task in tasks {
                Self.log.info("Cancelling reconnected task: \(task.taskIdentifier)")
                task.cancel()
            }
            // Start the new download after clearing old tasks
            self?.session?.downloadTask(with: url).resume()
            Self.log.info("Download task started")
        }
    }

    private func availableStorageBytes() -> Int64? {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return bytes
    }

    // MARK: - URLSessionDownloadDelegate

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        Self.log.info("Download finished to temp location: \(location.path, privacy: .public)")
        let fm = FileManager.default
        guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Self.log.error("Could not get documents directory")
            return
        }

        // Use the filename from the response, or fall back to the URL's last path component
        let suggestedName = downloadTask.response?.suggestedFilename ?? downloadTask.originalRequest?.url?.lastPathComponent ?? "download.rar"
        let destFile = docsURL.appendingPathComponent(suggestedName)
        Self.log.info("Moving download to: \(destFile.path, privacy: .public)")

        do {
            try? fm.removeItem(at: destFile)
            try fm.moveItem(at: location, to: destFile)
            Self.log.info("File moved successfully")
        } catch {
            Self.log.error("Failed to move downloaded file: \(error.localizedDescription, privacy: .public)")
        }

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
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                Self.log.info("Ignoring cancelled task \(task.taskIdentifier)")
                return
            }
            Self.log.error("Download task completed with error: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async {
                self.errorText = error.localizedDescription
                self.statusText = "Download failed"
                self.isDownloading = false
                self.onComplete = nil
            }
        } else {
            Self.log.info("Download task completed successfully")
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
