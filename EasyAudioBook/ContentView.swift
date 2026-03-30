import SwiftUI

struct ContentView: View {
    @Environment(AudiobookLibrary.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(BookDownloader.self) private var downloader
    @State private var showPlayer = false
    @State private var isExtracting = false
    @State private var hasRestored = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if library.books.isEmpty && !isExtracting && !downloader.isDownloading {
                    emptyState
                } else {
                    LibraryView(showPlayer: $showPlayer)
                }

                if isExtracting {
                    extractingOverlay
                }

                if downloader.isDownloading {
                    downloadOverlay
                }
            }
            .navigationDestination(isPresented: $showPlayer) {
                if let book = library.selectedBook {
                    PlayerView(book: book)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            player.savePosition()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            player.savePosition()
        }
        .onChange(of: library.books) {
            if !hasRestored && !library.books.isEmpty {
                hasRestored = true
                if AudioPlayer.shouldRestorePlayer, let book = library.selectedBook {
                    player.loadBook(book)
                    showPlayer = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .audiobookArchiveReceived)) { _ in
            handleArchiveReceived()
        }
        .onChange(of: downloader.isDownloading) {
            if downloader.isDownloading {
                showPlayer = false
            }
        }
    }

    private func handleArchiveReceived() {
        isExtracting = true
        DispatchQueue.global(qos: .userInitiated).async {
            RARHandler.extractArchivesInDocuments()
            DispatchQueue.main.async {
                library.scan()
                isExtracting = false
            }
        }
    }

    private var downloadOverlay: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.white)

                Text(downloader.statusText)
                    .font(.system(.title2, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                ProgressView(value: downloader.progress)
                    .tint(.green)
                    .frame(maxWidth: 300)
                    .scaleEffect(y: 2)

                if let error = downloader.errorText {
                    Text(error)
                        .font(.system(.body))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
        }
    }

    private var extractingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(2)
                    .tint(.white)
                Text("Extracting audiobook...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 80))
                .foregroundColor(.gray)
            Text("No Audiobooks")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Text("Add audiobook folders using\nthe Files app")
                .font(.title3)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }
}
