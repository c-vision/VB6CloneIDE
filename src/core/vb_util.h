#ifndef VB_UTIL_H
#define VB_UTIL_H

#include <stddef.h>

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} VbBuf;

void vb_buf_init(VbBuf *buf);
void vb_buf_free(VbBuf *buf);
void vb_buf_clear(VbBuf *buf);
void vb_buf_append(VbBuf *buf, const char *text);
void vb_buf_appendn(VbBuf *buf, const char *text, size_t len);
void vb_buf_appendf(VbBuf *buf, const char *fmt, ...);
void vb_buf_appendchar(VbBuf *buf, char c);
char *vb_buf_take(VbBuf *buf);

char *vb_strdup(const char *text);
char *vb_strndup(const char *text, size_t len);
char *vb_trim(char *text);
char *vb_trim_copy(const char *text);
int vb_streq(const char *a, const char *b);
int vb_streq_ci(const char *a, const char *b);
int vb_starts_ci(const char *text, const char *prefix);
int vb_ends_ci(const char *text, const char *suffix);
char *vb_lower_copy(const char *text);
int vb_parse_int(const char *text, int defval);
char *vb_format_int(int value);

char *vb_read_file(const char *path, size_t *out_len);
int vb_write_file(const char *path, const char *data, size_t len);
char *vb_path_join(const char *dir, const char *rel);
char *vb_path_dirname(const char *path);
char *vb_path_basename(const char *path);
char *vb_path_stem(const char *path);
char *vb_path_normalize(const char *path, const char *base_dir);

#endif
