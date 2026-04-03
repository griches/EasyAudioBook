import SwiftUI

struct LibraryView: View {
    @Environment(AudiobookLibrary.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Binding var showPlayer: Bool
    @State private var showEditSheet = false
    @State private var showAddSheet = false
    @State private var gradientTop: Color = Color(red: 0.05, green: 0.05, blue: 0.1)
    @State private var gradientBottom: Color = .black
    @State private var refreshID = UUID()

    var body: some View {
        GeometryReader { geo in
            let artworkSize = min(geo.size.width * 0.75, 440.0)
            let artworkHeight = min(geo.size.height * 0.42, 440.0)
            let topPadding = geo.size.height * 0.06

            ZStack {
                LinearGradient(
                    colors: [gradientTop, gradientBottom, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if let book = library.selectedBook {
                        // Match the back button area from PlayerView
                        HStack {
                            Spacer()
                            Button {
                                showAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.trailing, 20)
                        }
                        .padding(.top, 8)
                        .frame(height: 30)

                        Spacer().frame(height: topPadding)

                        // Cover, title & author — grouped as one accessibility element
                        VStack(spacing: 0) {
                            coverView(for: book, width: artworkSize, height: artworkHeight)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 50, coordinateSpace: .local)
                                        .onEnded { value in
                                            guard library.books.count > 1 else { return }
                                            if value.translation.width < -50 {
                                                library.selectNext()
                                                updateGradient()
                                            } else if value.translation.width > 50 {
                                                library.selectPrevious()
                                                updateGradient()
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.5)
                                        .onEnded { _ in
                                            showEditSheet = true
                                        }
                                )
                                .simultaneousGesture(
                                    TapGesture()
                                        .onEnded {
                                            player.loadBook(book)
                                            showPlayer = true
                                        }
                                )

                            Spacer().frame(height: geo.size.height * 0.03)

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
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel({
                            let label = "\(book.title), by \(book.author)"
                            print("[A11Y] Library label: \(label)")
                            return label
                        }())

                        Spacer()

                        // Play/Resume with optional chevrons
                        if library.books.count > 1 {
                            HStack(spacing: 12) {
                                Button {
                                    library.selectPrevious()
                                    updateGradient()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .frame(width: 44, height: 56)
                                }

                                playButton(for: book, width: artworkSize - 120)

                                Button {
                                    library.selectNext()
                                    updateGradient()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                        .frame(width: 44, height: 56)
                                }
                            }
                            .frame(width: artworkSize)
                        } else {
                            playButton(for: book, width: artworkSize)
                        }

                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 50, coordinateSpace: .local)
                        .onEnded { value in
                            guard library.books.count > 1 else { return }
                            if value.translation.width < -50 {
                                library.selectNext()
                                updateGradient()
                            } else if value.translation.width > 50 {
                                library.selectPrevious()
                                updateGradient()
                            }
                        }
                )
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            updateGradient()
            refreshID = UUID()
        }
        .onChange(of: showPlayer) {
            if !showPlayer {
                updateGradient()
                refreshID = UUID()
            }
        }
        .onChange(of: library.selectedIndex) {
            updateGradient()
        }
        .onChange(of: library.books) {
            updateGradient()
        }
        .sheet(isPresented: $showAddSheet, onDismiss: {
            updateGradient()
            refreshID = UUID()
        }) {
            AddBookView()
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            updateGradient()
            refreshID = UUID()
        }) {
            if let book = library.selectedBook {
                EditBookView(book: book)
            }
        }
    }

    // MARK: - Subviews

    private func playButton(for book: Audiobook, width: CGFloat) -> some View {
        let _ = refreshID // force re-evaluation when this changes
        let hasStarted = UserDefaults.standard.integer(forKey: "bookTrack_\(book.id)") > 0
            || UserDefaults.standard.double(forKey: "bookPosition_\(book.id)") > 0

        return Button {
            let t0 = CFAbsoluteTimeGetCurrent()
            print("[TIMING] Button tapped")
            player.loadBook(book)
            print("[TIMING] loadBook done: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            player.play()
            print("[TIMING] play done: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
            showPlayer = true
            print("[TIMING] showPlayer set: \(String(format: "%.0f", (CFAbsoluteTimeGetCurrent() - t0) * 1000))ms")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                    .font(.system(size: 22))
                Text(hasStarted ? "Resume" : "Play")
                    .font(.system(.title2, weight: .bold))
            }
            .foregroundColor(.black)
            .frame(minHeight: 60)
            .frame(width: width)
            .background(
                LinearGradient(
                    colors: [Color.orange, Color.yellow],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    @ViewBuilder
    private func coverView(for book: Audiobook, width: CGFloat, height: CGFloat) -> some View {
        if let image = book.coverImage {
            Image(uiImage: image)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .white.opacity(0.15), radius: 12)
                .accessibilityHidden(true)
                .accessibilityLabel("")
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: width * 0.85, height: height)
                VStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text(book.title)
                        .font(.system(.title2))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                        .padding(.horizontal)
                }
            }
            .shadow(color: .white.opacity(0.15), radius: 12)
        }
    }

    private func updateGradient() {
        if let image = library.selectedBook?.coverImage {
            let (top, bottom) = ColorExtractor.gradientColors(from: image)
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientTop = top
                gradientBottom = bottom
            }
        } else {
            withAnimation(.easeInOut(duration: 0.5)) {
                gradientTop = Color(red: 0.05, green: 0.05, blue: 0.1)
                gradientBottom = .black
            }
        }
    }
}

#Preview("Library") {
    struct PreviewWrapper: View {
        @State var library: AudiobookLibrary = {
            let lib = AudiobookLibrary()
            lib.books = [.preview]
            return lib
        }()
        var body: some View {
            NavigationStack {
                LibraryView(showPlayer: .constant(false))
            }
            .environment(library)
            .environment(AudioPlayer())
            .preferredColorScheme(.dark)
        }
    }
    return PreviewWrapper()
}
