#include "vb_util.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void vb_buf_init(VbBuf *buf)
{
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
}

void vb_buf_free(VbBuf *buf)
{
    free(buf->data);
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
}

void vb_buf_clear(VbBuf *buf)
{
    buf->len = 0;
    if (buf->data) buf->data[0] = '\0';
}

static int buf_reserve(VbBuf *buf, size_t extra)
{
    size_t need = buf->len + extra + 1;
    if (need <= buf->cap) return 1;
    size_t ncap = buf->cap ? buf->cap : 256;
    while (ncap < need) ncap *= 2;
    char *data = (char *)realloc(buf->data, ncap);
    if (!data) return 0;
    buf->data = data;
    buf->cap = ncap;
    return 1;
}

void vb_buf_appendn(VbBuf *buf, const char *text, size_t len)
{
    if (!text || len == 0) return;
    if (!buf_reserve(buf, len)) return;
    memcpy(buf->data + buf->len, text, len);
    buf->len += len;
    buf->data[buf->len] = '\0';
}

void vb_buf_append(VbBuf *buf, const char *text)
{
    if (!text) return;
    vb_buf_appendn(buf, text, strlen(text));
}

void vb_buf_appendchar(VbBuf *buf, char c)
{
    if (!buf_reserve(buf, 1)) return;
    buf->data[buf->len++] = c;
    buf->data[buf->len] = '\0';
}

void vb_buf_appendf(VbBuf *buf, const char *fmt, ...)
{
    va_list args;
    int needed;
    va_start(args, fmt);
    needed = vsnprintf(NULL, 0, fmt, args);
    va_end(args);
    if (needed < 0) return;
    if (!buf_reserve(buf, (size_t)needed)) return;
    va_start(args, fmt);
    vsnprintf(buf->data + buf->len, (size_t)needed + 1, fmt, args);
    va_end(args);
    buf->len += (size_t)needed;
}

char *vb_buf_take(VbBuf *buf)
{
    char *data = buf->data;
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
    return data;
}

char *vb_strdup(const char *text)
{
    size_t len;
    char *copy;
    if (!text) return NULL;
    len = strlen(text);
    copy = (char *)malloc(len + 1);
    if (!copy) return NULL;
    memcpy(copy, text, len + 1);
    return copy;
}

char *vb_strndup(const char *text, size_t len)
{
    char *copy = (char *)malloc(len + 1);
    if (!copy) return NULL;
    memcpy(copy, text, len);
    copy[len] = '\0';
    return copy;
}

char *vb_trim(char *text)
{
    char *start;
    char *end;
    if (!text) return text;
    start = text;
    while (*start && isspace((unsigned char)*start)) start++;
    end = start + strlen(start);
    while (end > start && isspace((unsigned char)end[-1])) end--;
    *end = '\0';
    if (start != text) memmove(text, start, (size_t)(end - start) + 1);
    return text;
}

char *vb_trim_copy(const char *text)
{
    char *copy;
    if (!text) return NULL;
    copy = vb_strdup(text);
    if (copy) vb_trim(copy);
    return copy;
}

int vb_streq(const char *a, const char *b)
{
    if (!a || !b) return a == b;
    return strcmp(a, b) == 0;
}

int vb_streq_ci(const char *a, const char *b)
{
    if (!a || !b) return a == b;
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return 0;
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

int vb_starts_ci(const char *text, const char *prefix)
{
    if (!text || !prefix) return 0;
    while (*prefix) {
        if (tolower((unsigned char)*text) != tolower((unsigned char)*prefix)) return 0;
        text++;
        prefix++;
    }
    return 1;
}

int vb_ends_ci(const char *text, const char *suffix)
{
    size_t tl, sl;
    if (!text || !suffix) return 0;
    tl = strlen(text);
    sl = strlen(suffix);
    if (sl > tl) return 0;
    return vb_streq_ci(text + tl - sl, suffix);
}

char *vb_lower_copy(const char *text)
{
    char *copy;
    size_t i;
    if (!text) return NULL;
    copy = vb_strdup(text);
    if (!copy) return NULL;
    for (i = 0; copy[i]; i++) copy[i] = (char)tolower((unsigned char)copy[i]);
    return copy;
}

int vb_parse_int(const char *text, int defval)
{
    char *trimmed;
    long value;
    if (!text) return defval;
    trimmed = vb_trim_copy(text);
    if (!trimmed || !*trimmed) {
        free(trimmed);
        return defval;
    }
    if (trimmed[0] == '&' && (trimmed[1] == 'H' || trimmed[1] == 'h')) {
        value = strtol(trimmed + 2, NULL, 16);
    } else {
        value = strtol(trimmed, NULL, 10);
    }
    free(trimmed);
    return (int)value;
}

char *vb_format_int(int value)
{
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%d", value);
    return vb_strdup(buffer);
}

char *vb_read_file(const char *path, size_t *out_len)
{
    FILE *file;
    long size;
    char *data;
    size_t read;
    if (!path) return NULL;
    file = fopen(path, "rb");
    if (!file) return NULL;
    if (fseek(file, 0, SEEK_END) != 0) {
        fclose(file);
        return NULL;
    }
    size = ftell(file);
    if (size < 0) {
        fclose(file);
        return NULL;
    }
    rewind(file);
    data = (char *)malloc((size_t)size + 1);
    if (!data) {
        fclose(file);
        return NULL;
    }
    read = fread(data, 1, (size_t)size, file);
    fclose(file);
    data[read] = '\0';
    if (out_len) *out_len = read;
    return data;
}

int vb_write_file(const char *path, const char *data, size_t len)
{
    FILE *file;
    size_t written;
    if (!path || !data) return 0;
    file = fopen(path, "wb");
    if (!file) return 0;
    written = fwrite(data, 1, len, file);
    fclose(file);
    return written == len;
}

char *vb_path_join(const char *dir, const char *rel)
{
    VbBuf buf;
    size_t i;
    if (!dir || !*dir) return vb_strdup(rel ? rel : "");
    if (!rel || !*rel) return vb_strdup(dir);
    if (rel[0] == '/') return vb_strdup(rel);
    vb_buf_init(&buf);
    vb_buf_append(&buf, dir);
    if (buf.len > 0 && buf.data[buf.len - 1] != '/') vb_buf_appendchar(&buf, '/');
    for (i = 0; rel[i]; i++) {
        if (rel[i] == '\\') vb_buf_appendchar(&buf, '/');
        else vb_buf_appendchar(&buf, rel[i]);
    }
    return vb_buf_take(&buf);
}

char *vb_path_dirname(const char *path)
{
    const char *slash;
    if (!path) return NULL;
    slash = strrchr(path, '/');
    if (!slash) return vb_strdup(".");
    if (slash == path) return vb_strdup("/");
    return vb_strndup(path, (size_t)(slash - path));
}

char *vb_path_basename(const char *path)
{
    const char *slash;
    if (!path) return NULL;
    slash = strrchr(path, '/');
    return vb_strdup(slash ? slash + 1 : path);
}

char *vb_path_stem(const char *path)
{
    char *base = vb_path_basename(path);
    char *dot;
    if (!base) return NULL;
    dot = strrchr(base, '.');
    if (dot) *dot = '\0';
    return base;
}

char *vb_path_normalize(const char *path, const char *base_dir)
{
    char *joined = vb_path_join(base_dir, path);
    char *segments[256];
    int count = 0;
    char *copy;
    char *token;
    char *save = NULL;
    VbBuf out;
    int absolute;
    int i;

    if (!joined) return NULL;
    absolute = joined[0] == '/';
    copy = vb_strdup(joined);
    free(joined);
    if (!copy) return NULL;

    token = strtok_r(copy, "/", &save);
    while (token && count < 256) {
        if (strcmp(token, ".") == 0 || token[0] == '\0') {
        } else if (strcmp(token, "..") == 0) {
            if (count > 0) count--;
        } else {
            segments[count++] = token;
        }
        token = strtok_r(NULL, "/", &save);
    }

    vb_buf_init(&out);
    if (absolute) vb_buf_appendchar(&out, '/');
    for (i = 0; i < count; i++) {
        if (i > 0) vb_buf_appendchar(&out, '/');
        vb_buf_append(&out, segments[i]);
    }
    free(copy);
    if (out.len == 0) {
        vb_buf_append(&out, absolute ? "/" : ".");
    }
    return vb_buf_take(&out);
}
