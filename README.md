# Easy Audiobook

An audiobook player for iOS designed for simplicity and accessibility above all else.

## Why this exists

I built Easy Audiobook for my dad. He's partially sighted, has poor motor control, and still loves listening to books. Every audiobook app I tried was too cluttered, too small, or too confusing. He doesn't need playlists, social features, or a store. He just needs to press play.

So I made something he can actually use: large touch targets, high contrast, a clean layout with nothing to get lost in, and a sleep timer because he tends to drift off mid-chapter. The whole interface is built around the idea that if you have to squint or think about what to tap, it's already failed.

The URL scheme means I can manage his library remotely -- send him a new book via a Shortcut link, or clear old ones to free up space, without needing to walk him through anything.

## Design Principles

- **Large, high-contrast controls** -- oversized play/pause, skip, and sleep timer buttons that are easy to see and hard to miss
- **Minimal interface** -- no tabs, no menus, no settings screens to get lost in. One screen for your library, one screen for playback
- **Nothing to configure** -- drop a book in and it just works. Metadata, cover art, and track order are handled automatically
- **Remotely manageable** -- a family member or carer can add and remove books without touching the device, using URL schemes and Shortcuts
- **Forgiving** -- position is saved constantly, so falling asleep, closing the app, or restarting the phone never loses your place

## Features

- **Large, accessible UI** -- designed for users with impaired vision or limited motor control
- **Multiple audio formats** -- supports MP3, M4A, and M4B files
- **Embedded metadata** -- automatically reads title, author, narrator, and cover art from M4B files
- **NFO support** -- also reads metadata from .nfo files for MP3-based audiobooks
- **Sleep timer** -- configurable duration so the book stops when you fall asleep (default: 30 minutes)
- **Configurable skip** -- adjust how far the back/forward buttons jump (default: 2 minutes)
- **Archive import** -- download and extract audiobooks from RAR, ZIP, 7z, TAR, and GZ archives
- **Adaptive cover art** -- background gradients extracted from the book's cover image
- **Automatic position saving** -- never lose your place, even across app restarts
- **Remote administration** -- add or remove books via URL schemes, perfect for carers managing a device remotely

## Adding Books

1. **In-app** -- tap the + button to import audio files or archives directly
2. **Files app** -- copy audiobook folders into Easy Audiobook's Documents directory
3. **URL scheme** -- send a link like `easyaudiobook://download?book=<URL>` to download a book remotely
4. **Open In** -- share audio files or archives to Easy Audiobook from other apps

Loose audio files (like a single .m4b) are automatically wrapped into their own folder.

### Folder Structure

```
My Audiobook/
  cover.jpg          # optional cover art
  info.nfo           # optional metadata (Title, Author, Read By, Description)
  Chapter 001.mp3
  Chapter 002.mp3
  ...
```

M4B files with embedded metadata don't need a cover image or .nfo file -- the app reads everything from the file itself.

## URL Schemes

These can be triggered from Safari, Shortcuts, or any app that opens URLs -- useful for family members managing the device remotely.

| URL | Action |
|-----|--------|
| `easyaudiobook://download?book=<URL>` | Download and extract an audiobook archive |
| `easyaudiobook://deleteall` | Stop playback and remove all books |

## Settings

Open **Settings > Easy Audiobook** on the device to configure:

- **Skip Duration** -- how far the back/forward buttons jump (default: 2 minutes)
- **Sleep Timer Duration** -- how long the sleep timer plays before stopping (default: 30 minutes)

These are in the iOS Settings app rather than in-app to keep the main interface completely clean.

## Requirements

- iOS 17.0+
- Xcode 15+

## Building

Open `EasyAudioBook.xcodeproj` in Xcode and build for your target device or simulator.
