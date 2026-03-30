#include "ArchiveExtractor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

// Forward declarations for libarchive (resolved at link time)
struct archive;
struct archive_entry;

extern struct archive *archive_read_new(void);
extern int archive_read_support_format_all(struct archive *);
extern int archive_read_support_filter_all(struct archive *);
extern int archive_read_open_filename(struct archive *, const char *, size_t);
extern int archive_read_next_header(struct archive *, struct archive_entry **);
extern int archive_read_close(struct archive *);
extern int archive_read_free(struct archive *);
extern const char *archive_error_string(struct archive *);

extern struct archive *archive_write_disk_new(void);
extern int archive_write_disk_set_options(struct archive *, int);
extern int archive_write_header(struct archive *, struct archive_entry *);
extern int archive_write_finish_entry(struct archive *);
extern int archive_write_close(struct archive *);
extern int archive_write_free(struct archive *);

extern const char *archive_entry_pathname(struct archive_entry *);
extern void archive_entry_set_pathname(struct archive_entry *, const char *);

extern int archive_read_data_block(struct archive *, const void **, size_t *, long long *);
extern long archive_write_data_block(struct archive *, const void *, size_t, long long);

#define LA_OK    0
#define LA_EOF   1
#define LA_WARN -20

#define EXTRACT_FLAGS (0x0004 | 0x0002 | 0x0020 | 0x0040)
// ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL | ARCHIVE_EXTRACT_FFLAGS

static int copy_data(struct archive *ar, struct archive *aw) {
    const void *buff;
    size_t size;
    long long offset;
    int r;

    for (;;) {
        r = archive_read_data_block(ar, &buff, &size, &offset);
        if (r == LA_EOF) return LA_OK;
        if (r < LA_OK) return r;
        r = (int)archive_write_data_block(aw, buff, size, offset);
        if (r < LA_OK) return r;
    }
}

int extractArchive(const char *archivePath, const char *destPath, const char **errorOut) {
    struct archive *a = archive_read_new();
    struct archive *ext = archive_write_disk_new();
    struct archive_entry *entry;
    int r;

    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);
    archive_write_disk_set_options(ext, EXTRACT_FLAGS);

    r = archive_read_open_filename(a, archivePath, 10240);
    if (r != LA_OK) {
        if (errorOut) *errorOut = archive_error_string(a);
        archive_read_free(a);
        archive_write_free(ext);
        return -1;
    }

    // Build full output paths by prepending destPath
    char fullPath[4096];
    size_t destLen = strlen(destPath);

    while ((r = archive_read_next_header(a, &entry)) == LA_OK) {
        const char *entryPath = archive_entry_pathname(entry);

        // Build dest/entryPath
        snprintf(fullPath, sizeof(fullPath), "%s/%s", destPath, entryPath);
        archive_entry_set_pathname(entry, fullPath);

        r = archive_write_header(ext, entry);
        if (r < LA_OK) {
            if (errorOut) *errorOut = archive_error_string(ext);
        } else {
            r = copy_data(a, ext);
            if (r < LA_OK && r != LA_WARN) {
                if (errorOut) *errorOut = archive_error_string(ext);
            }
        }
        archive_write_finish_entry(ext);
    }

    if (r != LA_EOF) {
        if (errorOut) *errorOut = archive_error_string(a);
        archive_read_close(a);
        archive_read_free(a);
        archive_write_close(ext);
        archive_write_free(ext);
        return -1;
    }

    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);
    return 0;
}
