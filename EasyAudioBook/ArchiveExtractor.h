#ifndef ArchiveExtractor_h
#define ArchiveExtractor_h

/// Extract an archive (RAR, ZIP, 7z, tar, etc.) to a destination directory.
/// Returns 0 on success, non-zero on failure.
/// errorOut will point to a static error string on failure (do not free).
int extractArchive(const char *archivePath, const char *destPath, const char **errorOut);

#endif
