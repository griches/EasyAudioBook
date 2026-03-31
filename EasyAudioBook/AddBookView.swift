import SwiftUI
import UniformTypeIdentifiers

struct AddBookView: View {
    @Environment(AudiobookLibrary.self) private var library
    @Environment(BookDownloader.self) private var downloader
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var showURLPrompt = false
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    Spacer().frame(height: 20)

                    Text("Add Audiobook")
                        .font(.system(.title2, weight: .bold))
                        .foregroundColor(.white)

                    Spacer().frame(height: 20)

                    Button {
                        showFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 22))
                            Text("Import Files")
                                .font(.system(.title3, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(minHeight: 56)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(14)
                        .padding(.horizontal, 30)
                    }

                    Button {
                        showURLPrompt = true
                    } label: {
                        HStack {
                            Image(systemName: "link")
                                .font(.system(size: 22))
                            Text("Download from URL")
                                .font(.system(.title3, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(minHeight: 56)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(14)
                        .padding(.horizontal, 30)
                    }

                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker { urls in
                for url in urls {
                    let accessing = url.startAccessingSecurityScopedResource()
                    RARHandler.copyIncomingFile(at: url)
                    // Delete the original file after importing
                    try? FileManager.default.removeItem(at: url)
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                RARHandler.extractArchivesInDocuments()
                library.scan()
                dismiss()
            }
        }
        .alert("Download from URL", isPresented: $showURLPrompt) {
            TextField("https://example.com/book.rar", text: $urlText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Download") {
                if let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    downloader.download(from: url) {
                        library.scan()
                    }
                    urlText = ""
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {
                urlText = ""
            }
        } message: {
            Text("Enter the URL of an audiobook archive")
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            .archive,
            .zip,
            UTType("com.rarlab.rar-archive") ?? .data,
            .mp3,
            UTType("com.apple.m4a-audio") ?? .audio,
            UTType("public.audiobook") ?? .audio,
            .audio,
            .folder
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}
