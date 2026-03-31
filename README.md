# Easy Audiobook

A simple, elegant audiobook player for iOS built with SwiftUI.

## Features

- **Library management** — automatically detects audiobook folders in the app's Documents directory
- **Multiple audio formats** — supports MP3, M4A, and M4B files
- **Archive import** — download and extract audiobooks from RAR, ZIP, 7z, TAR, and GZ archives
- **URL scheme support** — add books or manage your library via custom URLs
- **Metadata parsing** — reads title, author, narrator, and description from .nfo files
- **Cover art** — displays cover.jpg from each audiobook folder, with adaptive gradient backgrounds
- **Sleep timer** — configurable duration via Settings
- **Configurable skip** — adjust forward/back skip duration in Settings
- **File sharing** — accessible via iTunes/Finder file sharing and the iOS Files app

## Adding Books

1. **Files app** — copy audiobook folders directly into Easy Audiobook's Documents directory
2. **In-app** — tap the + button to import audio files or archives
3. **URL scheme** — open `easyaudiobook://download?book=<URL>` to download and extract an archive
4. **Open In** — share audio files or archives to Easy Audiobook from other apps

### Folder Structure

Each audiobook should be in its own folder:

```
My Audiobook/
  cover.jpg          # optional cover art
  info.nfo           # optional metadata (Title, Author, Read By, Description)
  Chapter 001.mp3
  Chapter 002.mp3
  ...
```

Loose audio files placed in the Documents root are automatically wrapped into their own folder.

## URL Schemes

| URL | Action |
|-----|--------|
| `easyaudiobook://download?book=<URL>` | Download and extract an audiobook archive |
| `easyaudiobook://deleteall` | Stop playback and remove all books |

## Settings

Open **Settings > Easy Audiobook** to configure:

- **Skip Duration** — how far the back/forward buttons jump (default: 2 minutes)
- **Sleep Timer Duration** — how long the sleep timer plays (default: 30 minutes)

## Requirements

- iOS 17.0+
- Xcode 15+

## Building

Open `EasyAudioBook.xcodeproj` in Xcode and build for your target device or simulator.
