import SwiftUI

struct PlayerView: View {
    let book: Audiobook
    @Environment(AudioPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var skipTimer: Timer?
    @State private var gradientTop: Color = Color(red: 0.05, green: 0.05, blue: 0.1)
    @State private var gradientBottom: Color = .black
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var skipSeconds: Int = {
        let val = UserDefaults.standard.integer(forKey: "skipDurationSeconds")
        return val > 0 ? val : 120
    }()
    @State private var sleepMinutes: Int = {
        let val = UserDefaults.standard.integer(forKey: "sleepTimerMinutes")
        return val > 0 ? val : 30
    }()

    var body: some View {
        GeometryReader { geo in
            let artworkSize = min(geo.size.width * 0.75, 440.0)
            let artworkHeight = min(geo.size.height * 0.42, 440.0)
            let topPadding = geo.size.height * 0.06
            let buttonSize: CGFloat = 90

            ZStack {
                // Gradient background from cover colours
                LinearGradient(
                    colors: [gradientTop, gradientBottom, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Custom back button — matches empty spacer on LibraryView
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(.body, weight: .semibold))
                                Text("Books")
                                    .font(.system(.body))
                            }
                            .foregroundColor(.white)
                        }
                        .padding(.leading, 20)
                        Spacer()
                    }
                    .padding(.top, 8)
                    .frame(height: 30)

                    Spacer().frame(height: topPadding)

                    // Cover
                    coverView(size: artworkSize, height: artworkHeight)

                    Spacer().frame(height: geo.size.height * 0.03)

                    // Title & author
                    Text(book.title)
                        .font(.system(.title, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.9), radius: 26, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 8)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                        .padding(.horizontal, 20)

                    Text(book.author)
                        .font(.system(.title3))
                        .foregroundColor(.gray)
                        .shadow(color: .black.opacity(0.9), radius: 26, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 8)
                        .padding(.top, 6)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                    Spacer()

                    // Scrub bar
                    VStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubValue : player.progressFraction },
                                set: { newValue in
                                    scrubValue = newValue
                                    isScrubbing = true
                                }
                            ),
                            in: 0...1,
                            onEditingChanged: { editing in
                                if !editing {
                                    let target = scrubValue * player.totalDuration
                                    player.seekToAbsolutePosition(target)
                                    isScrubbing = false
                                }
                            }
                        )
                        .tint(.white)

                        HStack {
                            Text(isScrubbing ? formatTime(scrubValue * player.totalDuration) : elapsedText)
                                .font(.system(.callout, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.gray)
                            Spacer()
                            Text(isScrubbing ? formatTime(max(0, player.totalDuration - scrubValue * player.totalDuration)) : remainingText)
                                .font(.system(.callout, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.gray)
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .frame(width: artworkSize)

                    Spacer()

                    // Transport: Back — Play/Stop — Forward
                    HStack(alignment: .center, spacing: 0) {
                        // Back
                        VStack(spacing: 10) {
                            Button {} label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: buttonSize, height: buttonSize)
                                    Image(systemName: "gobackward")
                                        .font(.system(size: buttonSize * 0.38, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .simultaneousGesture(skipGesture(seconds: Double(-skipSeconds)))
                            Text("Back")
                                .font(.system(.callout, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        // Play/Stop — rounded square
                        VStack(spacing: 10) {
                            Button {
                                if player.isPlaying { player.stop() } else { player.play() }
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(player.isPlaying ? Color.red : Color.green)
                                        .frame(width: buttonSize, height: buttonSize)
                                    Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                                        .font(.system(size: buttonSize * 0.42, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            Text(player.isPlaying ? "Stop" : "Play")
                                .font(.system(.callout, weight: .semibold))
                                .foregroundColor(player.isPlaying ? .red : .green)
                        }

                        Spacer()

                        // Forward
                        VStack(spacing: 10) {
                            Button {} label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.12))
                                        .frame(width: buttonSize, height: buttonSize)
                                    Image(systemName: "goforward")
                                        .font(.system(size: buttonSize * 0.38, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .simultaneousGesture(skipGesture(seconds: Double(skipSeconds)))
                            Text("Forward")
                                .font(.system(.callout, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .frame(width: artworkSize)

                    Spacer()

                    // Sleep timer lozenge
                    Group {
                        if player.sleepTimerActive {
                            HStack(spacing: 12) {
                                Image(systemName: "moon.fill")
                                    .font(.system(size: 26))
                                Text("\(timerText) remaining")
                                    .font(.system(.title2, weight: .bold))
                                    .monospacedDigit()
                            }
                            .foregroundColor(.black)
                            .frame(minHeight: 70)
                            .frame(width: artworkSize)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange, Color.yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        } else {
                            Button {
                                player.playForMinutes(sleepMinutes)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "moon.zzz.fill")
                                        .font(.system(size: 26))
                                    Text("Play for \(sleepMinutes) minutes")
                                        .font(.system(.title2, weight: .bold))
                                }
                                .foregroundColor(.black)
                                .frame(minHeight: 70)
                                .frame(width: artworkSize)
                                .background(
                                    LinearGradient(
                                        colors: [Color.orange, Color.yellow],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            let t0 = CFAbsoluteTimeGetCurrent()
            print("[PLAYER] onAppear start")
            player.loadBook(book)
            print("[PLAYER] loadBook: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            if let image = book.coverImage {
                let (top, bottom) = ColorExtractor.gradientColors(from: image)
                gradientTop = top
                gradientBottom = bottom
            }
            print("[PLAYER] gradient: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            refreshSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsChanged)) { _ in
            refreshSettings()
        }
    }

    private func refreshSettings() {
        let skip = UserDefaults.standard.integer(forKey: "skipDurationSeconds")
        skipSeconds = skip > 0 ? skip : 120
        let sleep = UserDefaults.standard.integer(forKey: "sleepTimerMinutes")
        sleepMinutes = sleep > 0 ? sleep : 30
    }

    // MARK: - Subviews

    @ViewBuilder
    private func coverView(size: CGFloat, height: CGFloat) -> some View {
        if let image = book.coverImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .white.opacity(0.15), radius: 12)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: size * 0.85, height: height)
                Image(systemName: "book.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
            }
            .shadow(color: .white.opacity(0.15), radius: 12)
        }
    }

    // MARK: - Gestures & Helpers

    private func skipGesture(seconds: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if skipTimer == nil {
                    player.skip(seconds: seconds)
                    skipTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                        player.skip(seconds: seconds)
                    }
                }
            }
            .onEnded { _ in
                skipTimer?.invalidate()
                skipTimer = nil
            }
    }

    private var elapsedText: String {
        formatTime(player.currentPosition)
    }

    private var remainingText: String {
        formatTime(max(0, player.totalDuration - player.currentPosition))
    }

    private var timerText: String {
        let minutes = Int(player.sleepTimerRemaining) / 60
        let seconds = Int(player.sleepTimerRemaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
}

#Preview("Player") {
    NavigationStack {
        PlayerView(book: .preview)
    }
    .environment(AudioPlayer())
    .preferredColorScheme(.dark)
}
