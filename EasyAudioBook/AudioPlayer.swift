import Foundation
import AVFoundation
import MediaPlayer
import Observation

@Observable
class AudioPlayer {
    var isPlaying = false
    var sleepTimerActive = false
    var sleepTimerRemaining: TimeInterval = 0
    var totalDuration: TimeInterval = 0
    var currentPosition: TimeInterval = 0

    private var queuePlayer: AVQueuePlayer?
    private var playerItems: [AVPlayerItem] = []
    private var allFileURLs: [URL] = []
    private var trackDurations: [TimeInterval] = []
    private var currentBookID: String?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    private var endObservers: [NSObjectProtocol] = []
    private var startTrackIndex: Int = 0
    private var queuedUpToIndex: Int = 0
    private var bookFinished: Bool = false

    private let positionKeyPrefix = "bookPosition_"
    private let trackKeyPrefix = "bookTrack_"

    deinit {
        cleanup()
    }

    var progressText: String {
        "\(formatTime(currentPosition)) / \(formatTime(totalDuration))"
    }

    var progressFraction: Double {
        guard totalDuration > 0 else { return 0 }
        return currentPosition / totalDuration
    }

    // MARK: - Public

    func loadBook(_ book: Audiobook) {
        if currentBookID == book.id && queuePlayer != nil {
            return
        }

        let t0 = CFAbsoluteTimeGetCurrent()
        cleanup()
        print("[LOAD] cleanup: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        currentBookID = book.id
        allFileURLs = book.mp3Files

        guard !book.mp3Files.isEmpty else { return }

        setupAudioSession()
        print("[LOAD] audioSession: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        setupNowPlaying(book)
        print("[LOAD] nowPlaying: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")

        // Calculate total duration in background to avoid blocking UI
        let files = book.mp3Files
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let dt0 = CFAbsoluteTimeGetCurrent()
            var durations: [TimeInterval] = []
            var total: TimeInterval = 0
            for url in files {
                let asset = AVURLAsset(url: url)
                let d = CMTimeGetSeconds(asset.duration)
                let duration = d.isFinite && d > 0 ? d : 0
                durations.append(duration)
                total += duration
            }
            print("[LOAD] duration calc (bg): \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - dt0) * 1000))ms")
            DispatchQueue.main.async {
                self?.trackDurations = durations
                self?.totalDuration = total
                self?.updateCurrentPosition()
                self?.updateNowPlayingInfo()
            }
        }

        let savedTrack = UserDefaults.standard.integer(forKey: trackKeyPrefix + book.id)
        let savedPosition = UserDefaults.standard.double(forKey: positionKeyPrefix + book.id)

        startTrackIndex = min(savedTrack, book.mp3Files.count - 1)

        // Only queue a few items at a time — add more as they finish
        let initialBatch = min(3, book.mp3Files.count - startTrackIndex)
        playerItems = book.mp3Files[startTrackIndex..<(startTrackIndex + initialBatch)].map { AVPlayerItem(url: $0) }
        queuedUpToIndex = startTrackIndex + initialBatch

        queuePlayer = AVQueuePlayer(items: playerItems)
        queuePlayer?.actionAtItemEnd = .advance

        observeTrackChanges(book: book)

        if savedPosition > 0 {
            let seekTime = CMTime(seconds: savedPosition, preferredTimescale: 600)
            queuePlayer?.currentItem?.seek(to: seekTime, completionHandler: nil)
        }

        // Update position immediately from saved state
        updateCurrentPosition()

        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = queuePlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateCurrentPosition()
            self?.saveCurrentPosition()
            self?.updateNowPlayingInfo()
        }

        setupRemoteCommands()
    }

    func play() {
        if bookFinished {
            // Book ended — reload from the beginning
            bookFinished = false
            seekToAbsolutePosition(0)
            queuePlayer?.play()
            isPlaying = true
            updateNowPlayingPlaybackState()
            return
        }
        queuePlayer?.play()
        isPlaying = true
        updateNowPlayingPlaybackState()
    }

    func seekToAbsolutePosition(_ position: TimeInterval) {
        guard !allFileURLs.isEmpty else { return }

        // Find which track this position falls in
        var remaining = position
        var targetTrack = 0
        for i in 0..<trackDurations.count {
            if remaining <= trackDurations[i] {
                targetTrack = i
                break
            }
            remaining -= trackDurations[i]
            targetTrack = i + 1
        }

        targetTrack = min(targetTrack, allFileURLs.count - 1)
        let seekPos = max(0, remaining)

        // Rebuild queue from target track
        let wasPlaying = isPlaying
        queuePlayer?.pause()

        startTrackIndex = targetTrack
        let initialBatch = min(3, allFileURLs.count - targetTrack)
        playerItems = allFileURLs[targetTrack..<(targetTrack + initialBatch)].map { AVPlayerItem(url: $0) }
        queuedUpToIndex = targetTrack + initialBatch

        queuePlayer = AVQueuePlayer(items: playerItems)
        queuePlayer?.actionAtItemEnd = .advance

        let seekTime = CMTime(seconds: seekPos, preferredTimescale: 600)
        queuePlayer?.currentItem?.seek(to: seekTime, completionHandler: nil)

        // Re-setup time observer
        if let obs = timeObserver { timeObserver = nil }
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = queuePlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateCurrentPosition()
            self?.saveCurrentPosition()
            self?.updateNowPlayingInfo()
        }

        currentPosition = position
        if wasPlaying { queuePlayer?.play() }
        saveCurrentPosition()
        updateNowPlayingInfo()
    }

    func stop() {
        saveCurrentPosition()
        queuePlayer?.pause()
        isPlaying = false
        cancelSleepTimer()
        updateNowPlayingPlaybackState()
    }

    func skip(seconds: TimeInterval) {
        guard let player = queuePlayer,
              let currentItem = player.currentItem else { return }

        let current = currentItem.currentTime().seconds
        guard current.isFinite else { return }

        let target = current + seconds

        if target >= 0 {
            // Forward or backward within this track
            let duration = currentItem.duration.seconds
            if target < duration || !duration.isFinite {
                let seekTime = CMTime(seconds: max(0, target), preferredTimescale: 600)
                player.seek(to: seekTime)
                updateCurrentPosition()
                return
            }
            // Past end of track — advance to next
            enqueueNextItems()
            if let idx = playerItems.firstIndex(of: currentItem),
               idx + 1 < playerItems.count {
                player.advanceToNextItem()
                let overflow = target - duration
                if overflow > 0 {
                    let seekTime = CMTime(seconds: overflow, preferredTimescale: 600)
                    player.currentItem?.seek(to: seekTime, completionHandler: nil)
                }
                updateCurrentPosition()
            }
        } else {
            // Before start of track — go to previous track
            let deficit = abs(target)
            if let idx = playerItems.firstIndex(of: currentItem) {
                let absoluteTrack = startTrackIndex + idx
                if absoluteTrack > 0 {
                    // Rebuild queue from previous track
                    let prevTrack = absoluteTrack - 1
                    let prevDuration = prevTrack < trackDurations.count ? trackDurations[prevTrack] : 0
                    let seekPos = max(0, prevDuration - deficit)

                    // Reload from this track with lazy queue
                    startTrackIndex = prevTrack
                    let initialBatch = min(3, allFileURLs.count - prevTrack)
                    playerItems = allFileURLs[prevTrack..<(prevTrack + initialBatch)].map { AVPlayerItem(url: $0) }
                    queuedUpToIndex = prevTrack + initialBatch
                    let wasPlaying = isPlaying
                    queuePlayer?.pause()
                    queuePlayer = AVQueuePlayer(items: playerItems)
                    queuePlayer?.actionAtItemEnd = .advance
                    let seekTime = CMTime(seconds: seekPos, preferredTimescale: 600)
                    queuePlayer?.currentItem?.seek(to: seekTime, completionHandler: nil)

                    // Re-setup time observer
                    if let obs = timeObserver {
                        // old player is gone, just nil it
                        timeObserver = nil
                    }
                    let interval = CMTime(seconds: 1, preferredTimescale: 600)
                    timeObserver = queuePlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
                        self?.updateCurrentPosition()
                        self?.saveCurrentPosition()
                    }

                    if wasPlaying { queuePlayer?.play() }
                    updateCurrentPosition()
                } else {
                    // Already at start — just seek to 0
                    player.seek(to: .zero)
                    updateCurrentPosition()
                }
            }
        }
    }

    func playFor30Minutes() {
        playForMinutes(30)
    }

    func playForMinutes(_ minutes: Int) {
        play()
        cancelSleepTimer()
        sleepTimerActive = true
        sleepTimerRemaining = TimeInterval(minutes * 60)

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.sleepTimerRemaining -= 1
            if self.sleepTimerRemaining <= 0 {
                self.stop()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerActive = false
        sleepTimerRemaining = 0
    }

    func savePosition() {
        saveCurrentPosition()
        UserDefaults.standard.set(currentBookID != nil, forKey: "wasInPlayer")
    }

    static var shouldRestorePlayer: Bool {
        UserDefaults.standard.bool(forKey: "wasInPlayer")
    }

    // MARK: - Private

    private func calculateTotalDuration(for files: [URL]) {
        trackDurations = []
        var total: TimeInterval = 0

        for url in files {
            let asset = AVURLAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            let d = duration.isFinite && duration > 0 ? duration : 0
            trackDurations.append(d)
            total += d
        }

        totalDuration = total
    }

    private func updateCurrentPosition() {
        guard let player = queuePlayer,
              let currentItem = player.currentItem else { return }

        let posInTrack = currentItem.currentTime().seconds
        guard posInTrack.isFinite && posInTrack >= 0 else { return }

        // Sum durations of all tracks before the current one
        var elapsed: TimeInterval = 0
        if let idx = playerItems.firstIndex(of: currentItem) {
            let absoluteTrack = startTrackIndex + idx
            for i in 0..<absoluteTrack {
                if i < trackDurations.count {
                    elapsed += trackDurations[i]
                }
            }
            elapsed += posInTrack
        }

        currentPosition = elapsed
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            if type == .began {
                self.isPlaying = false
                self.updateNowPlayingPlaybackState()
            } else if type == .ended {
                if let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.play()
                    }
                }
            }
        }
    }

    private func observeTrackChanges(book: Audiobook) {
        for observer in endObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        endObservers.removeAll()

        let bookID = book.id
        let totalTracks = book.mp3Files.count

        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let finishedItem = notification.object as? AVPlayerItem else { return }

            if let idx = self.playerItems.firstIndex(of: finishedItem) {
                let absoluteTrack = self.startTrackIndex + idx + 1
                if absoluteTrack < totalTracks {
                    UserDefaults.standard.set(absoluteTrack, forKey: self.trackKeyPrefix + bookID)
                    UserDefaults.standard.set(0, forKey: self.positionKeyPrefix + bookID)
                } else {
                    // Last track finished — book is done
                    UserDefaults.standard.set(0, forKey: self.trackKeyPrefix + bookID)
                    UserDefaults.standard.set(0, forKey: self.positionKeyPrefix + bookID)
                    self.bookFinished = true
                    self.isPlaying = false
                    self.cancelSleepTimer()
                    self.currentPosition = 0
                    self.updateNowPlayingPlaybackState()
                    return
                }
            }

            // Feed more items into the queue
            self.enqueueNextItems()
        }
        endObservers.append(observer)
    }

    private func enqueueNextItems() {
        guard let player = queuePlayer else { return }
        let totalFiles = allFileURLs.count

        // Keep 3 items queued ahead
        while queuedUpToIndex < totalFiles && player.items().count < 3 {
            let item = AVPlayerItem(url: allFileURLs[queuedUpToIndex])
            player.insert(item, after: player.items().last)
            playerItems.append(item)
            queuedUpToIndex += 1
        }
    }

    private func saveCurrentPosition() {
        guard let bookID = currentBookID,
              let player = queuePlayer,
              let currentItem = player.currentItem else { return }

        let position = currentItem.currentTime().seconds
        guard position.isFinite && position >= 0 else { return }

        if let idx = playerItems.firstIndex(of: currentItem) {
            let absoluteTrack = startTrackIndex + idx
            UserDefaults.standard.set(absoluteTrack, forKey: trackKeyPrefix + bookID)
            UserDefaults.standard.set(position, forKey: positionKeyPrefix + bookID)
        }
    }

    private func cleanup() {
        saveCurrentPosition()
        queuePlayer?.pause()

        if let observer = timeObserver {
            queuePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }

        for observer in endObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        endObservers.removeAll()

        cancelSleepTimer()
        queuePlayer = nil
        playerItems = []
        isPlaying = false
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Now Playing / Remote Commands

    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var nowPlayingBook: (title: String, author: String)?

    private func setupNowPlaying(_ book: Audiobook) {
        nowPlayingBook = (title: book.title, author: book.author)

        if let image = book.coverImage {
            // Create artwork with a strong reference so it persists
            let size = image.size
            nowPlayingArtwork = MPMediaItemArtwork(boundsSize: size) { _ in
                return image
            }
        } else {
            nowPlayingArtwork = nil
        }

        updateNowPlayingInfo()
    }

    private func updateNowPlayingInfo() {
        guard let book = nowPlayingBook else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyPlaybackDuration: totalDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateNowPlayingInfo()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPlaying { self.stop() } else { self.play() }
            return .success
        }
    }
}
