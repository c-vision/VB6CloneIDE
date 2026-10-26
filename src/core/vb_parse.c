#include "vb_parse.h"
#include "vb_util.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Breakpoints live in the .frm as a trailing comment so the file stays valid VB6 source:
   "'@VB6CloneBreakpoints: 12,18". Reading removes that line from `code`, writing puts it
   back, so nothing else in the code text is touched. */
static void extract_breakpoints(VbForm *form)
{
    VbBuf kept;
    const char *cursor;
    int found = 0;
    if (!form || !form->code || !*form->code) return;
    vb_buf_init(&kept);
    cursor = form->code;
    while (*cursor) {
        const char *end = strchr(cursor, '\n');
        size_t len = end ? (size_t)(end - cursor) : strlen(cursor);
        char *line = vb_strndup(cursor, len);
        char *trimmed = line ? vb_trim(line) : NULL;
        if (!found && trimmed && vb_starts_ci(trimmed, VB_BREAKPOINT_MARKER)) {
            const char *numbers = trimmed + strlen(VB_BREAKPOINT_MARKER);
            found = 1;
            while (*numbers) {
                long value;
                char *stop = NULL;
                if (!isdigit((unsigned char)*numbers)) { numbers++; continue; }
                value = strtol(numbers, &stop, 10);
                if (stop == numbers) break;
                if (value > 0 && value < 1000000) vb_form_set_breakpoint(form, (int)value, 1);
                numbers = stop;
            }
        } else {
            vb_buf_appendn(&kept, cursor, len);
            if (end) vb_buf_appendchar(&kept, '\n');
        }
        free(line);
        if (!end) break;
        cursor = end + 1;
    }
    if (found) {
        free(form->code);
        form->code = vb_buf_take(&kept);
    } else {
        vb_buf_free(&kept);
    }
}

static void normalize_newlines(char *text)
{
    char *src = text;
    char *dst = text;
    while (*src) {
        if (src[0] == '\r' && src[1] == '\n') {
            *dst++ = '\n';
            src += 2;
        } else if (src[0] == '\r') {
            *dst++ = '\n';
            src++;
        } else {
            *dst++ = *src++;
        }
    }
    *dst = '\0';
}

static char *strip_value_comment(const char *value)
{
    const char *p = value;
    int in_quote = 0;
    while (*p) {
        if (*p == '"') {
            if (in_quote && p[1] == '"') {
                p += 2;
                continue;
            }
            in_quote = !in_quote;
        } else if (*p == '\'' && !in_quote) {
            break;
        }
        p++;
    }
    return vb_strndup(value, (size_t)(p - value));
}

static void parse_form_name(VbForm *form)
{
    const char *attribute = NULL;
    const char *p;
    if (!form || !form->code) return;
    p = form->code;
    while ((p = strstr(p, "Attribute VB_Name")) != NULL) {
        const char *eq = strchr(p, '=');
        if (eq) {
            const char *start;
            const char *end;
            while (*eq && *eq != '"') eq++;
            if (*eq == '"') {
                start = eq + 1;
                end = strchr(start, '"');
                if (end) {
                    char *name = vb_strndup(start, (size_t)(end - start));
                    if (name && *name && form->root) {
                        free(form->root->name);
                        form->root->name = name;
                    } else {
                        free(name);
                    }
                    attribute = p;
                    break;
                }
            }
        }
        p += 16;
    }
    (void)attribute;
}

VbForm *vb_form_parse(const char *text, const char *path)
{
    char *work;
    char *cursor;
    VbForm *form;
    VbControl *stack[256];
    int depth = 0;
    char prop_prefix[64];
    int in_prop = 0;
    size_t code_offset = 0;
    int finished = 0;

    if (!text) return NULL;
    work = vb_strdup(text);
    if (!work) return NULL;
    normalize_newlines(work);
    form = (VbForm *)calloc(1, sizeof(VbForm));
    if (!form) {
        free(work);
        return NULL;
    }
    form->path = path ? vb_strdup(path) : NULL;

    cursor = work;
    while (*cursor && !finished) {
        char *line_end = strchr(cursor, '\n');
        size_t len = line_end ? (size_t)(line_end - cursor) : strlen(cursor);
        char *line = vb_strndup(cursor, len);
        char *next = line_end ? line_end + 1 : cursor + len;
        char *trimmed;

        if (!line) break;
        vb_trim(line);
        trimmed = line;

        if (*trimmed == '\0') {
            cursor = next;
            free(line);
            continue;
        }

        if (vb_starts_ci(trimmed, "BeginProperty ")) {
            char *name = trimmed + 14;
            vb_trim(name);
            snprintf(prop_prefix, sizeof(prop_prefix), "%s", name);
            in_prop = 1;
            cursor = next;
            free(line);
            continue;
        }
        if (vb_starts_ci(trimmed, "EndProperty")) {
            in_prop = 0;
            cursor = next;
            free(line);
            continue;
        }

        if (vb_starts_ci(trimmed, "Begin ")) {
            char *p = trimmed + 6;
            char *type;
            char *name;
            VbControl *control;
            while (*p && isspace((unsigned char)*p)) p++;
            type = p;
            while (*p && !isspace((unsigned char)*p)) p++;
            if (*p) *p++ = '\0';
            while (*p && isspace((unsigned char)*p)) p++;
            name = p;
            while (*p && !isspace((unsigned char)*p)) p++;
            if (*p) *p = '\0';
            control = vb_control_new(type, name, NULL);
            if (control) {
                if (depth == 0) {
                    form->root = control;
                } else {
                    vb_control_add_child(stack[depth - 1], control);
                }
                if (depth < 256) stack[depth] = control;
                depth++;
            }
            in_prop = 0;
            cursor = next;
            free(line);
            continue;
        }

        if (vb_streq_ci(trimmed, "End")) {
            if (depth > 0) depth--;
            if (depth == 0) {
                code_offset = (size_t)(next - work);
                finished = 1;
            }
            in_prop = 0;
            cursor = next;
            free(line);
            continue;
        }

        if (depth > 0 && strchr(trimmed, '=')) {
            char *eq = strchr(trimmed, '=');
            char *key;
            char *value;
            char *clean;
            *eq = '\0';
            key = vb_trim(trimmed);
            value = vb_trim(eq + 1);
            clean = strip_value_comment(value);
            if (clean) {
                char fullkey[256];
                vb_trim(clean);
                if (in_prop) {
                    snprintf(fullkey, sizeof(fullkey), "%s.%s", prop_prefix, key);
                } else {
                    snprintf(fullkey, sizeof(fullkey), "%s", key);
                }
                if (depth > 0 && stack[depth - 1]) {
                    vb_control_set(stack[depth - 1], fullkey, clean);
                }
                free(clean);
            }
        }

        cursor = next;
        free(line);
    }

    form->code = vb_strdup(work + code_offset);
    extract_breakpoints(form);
    if (!form->root) {
        free(work);
        vb_form_free(form);
        return NULL;
    }
    parse_form_name(form);
    if (!vb_control_get(form->root, "ClientWidth")) {
        const char *scale = vb_control_get(form->root, "ScaleWidth");
        vb_control_set(form->root, "ClientWidth", scale ? scale : "4680");
    }
    if (!vb_control_get(form->root, "ClientHeight")) {
        const char *scale = vb_control_get(form->root, "ScaleHeight");
        vb_control_set(form->root, "ClientHeight", scale ? scale : "3090");
    }
    free(work);
    return form;
}

VbForm *vb_form_load(const char *path)
{
    size_t len = 0;
    char *data;
    VbForm *form;
    if (!path) return NULL;
    data = vb_read_file(path, &len);
    if (!data) return NULL;
    form = vb_form_parse(data, path);
    free(data);
    (void)len;
    return form;
}

static void append_prop(VbBuf *buf, int depth, const VbProp *prop)
{
    int i;
    for (i = 0; i < depth + 1; i++) vb_buf_append(buf, "   ");
    vb_buf_appendf(buf, "%-16s=   %s\n", prop->key, prop->value);
}

static int is_font_prop(const char *key)
{
    return vb_starts_ci(key, "Font.");
}

static void append_font_props(VbBuf *buf, int depth, VbControl *control)
{
    static const char *const order[] = {
        "Name", "Size", "Charset", "Weight", "Underline", "Italic", "Strikethrough", NULL
    };
    int any = 0;
    int i;
    for (i = 0; i < control->nprops; i++) {
        if (is_font_prop(control->props[i].key)) { any = 1; break; }
    }
    if (!any) return;
    for (i = 0; i < depth + 1; i++) vb_buf_append(buf, "   ");
    vb_buf_append(buf, "BeginProperty Font \n");
    for (i = 0; order[i]; i++) {
        char key[64];
        const char *value;
        snprintf(key, sizeof(key), "Font.%s", order[i]);
        value = vb_control_get(control, key);
        if (value) {
            for (int j = 0; j < depth + 2; j++) vb_buf_append(buf, "   ");
            vb_buf_appendf(buf, "%-16s=   %s\n", order[i], value);
        }
    }
    for (i = 0; i < depth + 1; i++) vb_buf_append(buf, "   ");
    vb_buf_append(buf, "EndProperty\n");
}

static void serialize_control(VbBuf *buf, VbControl *control, int depth)
{
    int i;
    for (i = 0; i < depth; i++) vb_buf_append(buf, "   ");
    vb_buf_appendf(buf, "Begin %s %s \n", control->type, control->name);
    for (i = 0; i < control->nprops; i++) {
        if (!is_font_prop(control->props[i].key)) {
            append_prop(buf, depth, &control->props[i]);
        }
    }
    append_font_props(buf, depth, control);
    for (i = 0; i < control->nchildren; i++) {
        serialize_control(buf, control->children[i], depth + 1);
    }
    for (i = 0; i < depth; i++) vb_buf_append(buf, "   ");
    vb_buf_append(buf, "End\n");
}

char *vb_form_serialize(VbForm *form, size_t *out_len)
{
    VbBuf buf;
    if (!form || !form->root) return NULL;
    vb_buf_init(&buf);
    vb_buf_append(&buf, "VERSION 5.00\n");
    serialize_control(&buf, form->root, 0);
    if (form->code && *form->code) {
        vb_buf_append(&buf, form->code);
        if (buf.len > 0 && buf.data[buf.len - 1] != '\n') vb_buf_appendchar(&buf, '\n');
    } else {
        vb_buf_appendf(&buf, "Attribute VB_Name = \"%s\"\n"
                             "Attribute VB_GlobalNameSpace = False\n"
                             "Attribute VB_Creatable = False\n"
                             "Attribute VB_PredeclaredId = True\n"
                             "Attribute VB_Exposed = False\n",
                       form->root->name);
    }
    if (form->nbreakpoints > 0) {
        int i;
        vb_buf_append(&buf, VB_BREAKPOINT_MARKER ": ");
        for (i = 0; i < form->nbreakpoints; i++) {
            vb_buf_appendf(&buf, i ? ",%d" : "%d", form->breakpoints[i]);
        }
        vb_buf_appendchar(&buf, '\n');
    }
    if (out_len) *out_len = buf.len;
    return vb_buf_take(&buf);
}

int vb_form_save(VbForm *form, const char *path)
{
    size_t len = 0;
    char *data;
    int ok;
    if (!form) return 0;
    data = vb_form_serialize(form, &len);
    if (!data) return 0;
    ok = vb_write_file(path ? path : form->path, data, len);
    free(data);
    if (ok && path) {
        free(form->path);
        form->path = vb_strdup(path);
    }
    if (ok) form->dirty = 0;
    return ok;
}

static VbItemKind kind_from_key(const char *key)
{
    if (vb_streq_ci(key, "Form")) return VB_ITEM_FORM;
    if (vb_streq_ci(key, "Module")) return VB_ITEM_MODULE;
    if (vb_streq_ci(key, "Class")) return VB_ITEM_CLASS;
    if (vb_streq_ci(key, "UserControl")) return VB_ITEM_USERCONTROL;
    return VB_ITEM_OTHER;
}

static int is_item_key(const char *key)
{
    return vb_streq_ci(key, "Form") || vb_streq_ci(key, "Module") ||
           vb_streq_ci(key, "Class") || vb_streq_ci(key, "UserControl") ||
           vb_streq_ci(key, "RelatedDoc") || vb_streq_ci(key, "Designer");
}

VbProject *vb_project_load(const char *path)
{
    char *data;
    char *work;
    char *cursor;
    VbProject *project;
    if (!path) return NULL;
    data = vb_read_file(path, NULL);
    if (!data) return NULL;
    normalize_newlines(data);
    work = data;
    project = vb_project_new();
    if (!project) {
        free(data);
        return NULL;
    }
    project->path = vb_strdup(path);
    project->dir = vb_path_dirname(path);
    if (!project->dir) project->dir = vb_strdup(".");

    cursor = work;
    while (*cursor) {
        char *line_end = strchr(cursor, '\n');
        size_t len = line_end ? (size_t)(line_end - cursor) : strlen(cursor);
        char *line = vb_strndup(cursor, len);
        char *eq;
        char *next = line_end ? line_end + 1 : cursor + len;
        if (!line) break;
        vb_trim(line);
        if (*line == '\0' || *line == '[') {
            cursor = next;
            free(line);
            continue;
        }
        eq = strchr(line, '=');
        if (!eq) {
            cursor = next;
            free(line);
            continue;
        }
        *eq = '\0';
        {
            char *key = vb_trim(line);
            char *value = vb_trim(eq + 1);
            if (vb_streq_ci(key, "Name")) {
                char *v = vb_value_unquote(value);
                free(project->name);
                project->name = v;
            } else if (vb_streq_ci(key, "Startup")) {
                char *v = vb_value_unquote(value);
                free(project->startup);
                project->startup = v;
            } else if (is_item_key(key)) {
                char *name = NULL;
                char *file = NULL;
                char *semi = strchr(value, ';');
                if (semi) {
                    *semi = '\0';
                    name = vb_trim_copy(value);
                    file = vb_trim_copy(semi + 1);
                } else {
                    file = vb_trim_copy(value);
                    if (file && *file) name = vb_path_stem(file);
                }
                if (file && *file) {
                    VbItem *item;
                    char *full;
                    VbItemKind kind = kind_from_key(key);
                    if (!name || !*name) {
                        free(name);
                        name = vb_path_stem(file);
                    }
                    full = vb_path_normalize(file, project->dir);
                    item = vb_project_add_item(project, kind, name, full);
                    if (item) {
                        snprintf(item->kind_key, sizeof(item->kind_key), "%s", key);
                        if (kind == VB_ITEM_FORM && full) {
                            item->form = vb_form_load(full);
                            if (item->form) {
                                free(item->form->path);
                                item->form->path = vb_strdup(full);
                            }
                        }
                    }
                    free(full);
                }
                free(name);
                free(file);
            }
        }
        cursor = next;
        free(line);
    }
    if (!project->name) {
        char *stem = vb_path_stem(path);
        project->name = stem ? stem : vb_strdup("Project");
    }
    if (!project->startup) {
        int i;
        for (i = 0; i < project->nitems; i++) {
            if (project->items[i].kind == VB_ITEM_FORM) {
                project->startup = vb_strdup(project->items[i].name);
                break;
            }
        }
        if (!project->startup) project->startup = vb_strdup("Sub Main");
    }
    free(data);
    return project;
}

char *vb_project_item_relative_path(VbProject *project, VbItem *item)
{
    const char *base_dir;
    const char *file;
    size_t dir_len;
    if (!item || !item->file || !*item->file) return NULL;
    file = item->file;
    base_dir = project ? project->dir : NULL;
    if (!base_dir || !*base_dir) return vb_path_basename(file);
    dir_len = strlen(base_dir);
    if (strncmp(file, base_dir, dir_len) == 0 && (file[dir_len] == '/' || file[dir_len] == '\0')) {
        const char *rel = file + dir_len;
        while (*rel == '/') rel++;
        if (*rel) return vb_strdup(rel);
    }
    return vb_path_basename(file);
}

int vb_project_save(VbProject *project, const char *path)
{
    VbBuf buf;
    int i;
    int ok;
    if (!project) return 0;
    vb_buf_init(&buf);
    vb_buf_append(&buf, "Type=Exe\n");
    for (i = 0; i < project->nitems; i++) {
        VbItem *item = &project->items[i];
        char *rel;
        if (!item->file || !*item->file) continue;
        rel = vb_project_item_relative_path(project, item);
        if (!rel) continue;
        if (item->kind == VB_ITEM_FORM) {
            vb_buf_appendf(&buf, "%s=%s\n", item->kind_key[0] ? item->kind_key : "Form", rel);
        } else {
            vb_buf_appendf(&buf, "%s=%s;%s\n",
                           item->kind_key[0] ? item->kind_key : "Module",
                           item->name ? item->name : "", rel);
        }
        free(rel);
    }
    {
        char *quoted = vb_value_quote(project->name ? project->name : "Project1");
        vb_buf_appendf(&buf, "Name=%s\n", quoted ? quoted : "\"Project1\"");
        free(quoted);
    }
    {
        char *quoted = vb_value_quote(project->startup ? project->startup : "Form1");
        vb_buf_appendf(&buf, "Startup=%s\n", quoted ? quoted : "\"Form1\"");
        free(quoted);
    }
    ok = vb_write_file(path ? path : project->path, buf.data, buf.len);
    if (ok && path) {
        free(project->path);
        free(project->dir);
        project->path = vb_strdup(path);
        project->dir = vb_path_dirname(path);
    }
    vb_buf_free(&buf);
    return ok;
}

int vb_project_reload_forms(VbProject *project)
{
    int i;
    int loaded = 0;
    if (!project) return 0;
    for (i = 0; i < project->nitems; i++) {
        VbItem *item = &project->items[i];
        if (item->kind != VB_ITEM_FORM || !item->file) continue;
        if (item->form) {
            vb_form_free(item->form);
            item->form = NULL;
        }
        item->form = vb_form_load(item->file);
        if (item->form) loaded++;
    }
    return loaded;
}

char *vb_project_item_path(VbProject *project, VbItem *item)
{
    if (!item) return NULL;
    if (item->file && *item->file) return vb_strdup(item->file);
    if (!project) return NULL;
    return NULL;
}

char *vb_project_load_code(VbProject *project, VbItem *item, size_t *out_len)
{
    char *path;
    char *data;
    if (!item) return NULL;
    path = vb_project_item_path(project, item);
    if (!path) return NULL;
    data = vb_read_file(path, out_len);
    free(path);
    return data;
}

int vb_project_save_item(VbProject *project, VbItem *item)
{
    (void)project;
    if (!item) return 0;
    if (item->kind == VB_ITEM_FORM && item->form) {
        return vb_form_save(item->form, item->file);
    }
    return 0;
}
