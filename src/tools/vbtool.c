#include "core/vb_parse.h"
#include "core/vb_model.h"
#include "core/vb_util.h"
#include "core/vb_code.h"
#include "core/vb_grid.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GRID_EXPECT(cond, message) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "grid: FAIL: %s\n", message); \
            ok = 0; \
        } \
    } while (0)

static int grid_suite(void)
{
    VbGrid grid;
    int ok = 1;
    int row = -1;
    int column = -1;
    int border = -1;

    /* A 4x6 sheet with 100pt columns, 20pt rows and an 18pt header. */
    vb_grid_init(&grid, 6, 4, 100, 20);
    vb_grid_set_metrics(&grid, 100, 20, 18);
    GRID_EXPECT(grid.rows == 6 && grid.columns == 4, "init must create the requested sheet");
    GRID_EXPECT(vb_grid_column_width(&grid, 3) == 100, "columns start at the default width");
    GRID_EXPECT(vb_grid_cell(&grid, 0, 0)[0] == '\0', "cells start empty");

    /* Typing in a cell: F2 keeps the text, typing over it replaces it, Enter commits. */
    vb_grid_select(&grid, 1, 2);
    vb_grid_begin_edit(&grid);
    GRID_EXPECT(grid.editing && vb_grid_edit_text(&grid)[0] == '\0', "begin edit starts from the cell");
    vb_grid_edit_insert(&grid, "hello");
    GRID_EXPECT(vb_streq(vb_grid_edit_text(&grid), "hello"), "typing fills the edit buffer");
    vb_grid_commit_edit(&grid);
    GRID_EXPECT(!grid.editing, "Enter leaves edit mode");
    GRID_EXPECT(vb_streq(vb_grid_cell(&grid, 1, 2), "hello"), "the cell keeps the typed text");

    vb_grid_select(&grid, 1, 2);
    vb_grid_begin_edit(&grid);
    GRID_EXPECT(vb_streq(vb_grid_edit_text(&grid), "hello"), "F2 edits the existing text");
    vb_grid_edit_reset(&grid);
    vb_grid_edit_insert(&grid, "w");
    GRID_EXPECT(vb_streq(vb_grid_edit_text(&grid), "w"), "typing over a cell replaces its text");
    vb_grid_cancel_edit(&grid);
    GRID_EXPECT(vb_streq(vb_grid_cell(&grid, 1, 2), "hello"), "Esc restores the old text");

    /* Backspace is UTF-8 safe and empty cells clear. */
    vb_grid_select(&grid, 0, 0);
    vb_grid_begin_edit(&grid);
    vb_grid_edit_insert(&grid, "caff\xc3\xa8");
    vb_grid_edit_backspace(&grid);
    GRID_EXPECT(vb_streq(vb_grid_edit_text(&grid), "caff"), "backspace drops one character");
    vb_grid_commit_edit(&grid);
    GRID_EXPECT(vb_streq(vb_grid_cell(&grid, 0, 0), "caff"), "commit writes the buffer");
    vb_grid_clear_cell(&grid, 0, 0);
    GRID_EXPECT(vb_grid_cell(&grid, 0, 0)[0] == '\0', "clearing a cell empties it");

    /* Arrow keys move the selection, clamp at the edges and commit pending edits. */
    vb_grid_select(&grid, 0, 0);
    vb_grid_move_selection(&grid, 1, 0);
    GRID_EXPECT(grid.selected_row == 1 && grid.selected_column == 0, "down moves one row");
    vb_grid_move_selection(&grid, 0, 1);
    GRID_EXPECT(grid.selected_column == 1, "right moves one column");
    vb_grid_move_selection(&grid, -99, -99);
    GRID_EXPECT(grid.selected_row == 0 && grid.selected_column == 0, "selection clamps at 0,0");
    vb_grid_move_selection(&grid, 99, 99);
    GRID_EXPECT(grid.selected_row == 5 && grid.selected_column == 3, "selection clamps at the last cell");
    vb_grid_begin_edit(&grid);
    vb_grid_edit_insert(&grid, "x");
    vb_grid_move_selection(&grid, 0, -1);
    GRID_EXPECT(!grid.editing, "moving off a cell commits the edit");
    GRID_EXPECT(vb_streq(vb_grid_cell(&grid, 5, 3), "x"), "the committed text is in the cell");

    /* Hit testing: header row, body cells and the resize border under the pointer. */
    GRID_EXPECT(vb_grid_hit_test(&grid, 10, 5, 1, &row, &column, &border) && row == -1 && column == 0,
                "a click on the header maps to the header row");
    GRID_EXPECT(vb_grid_hit_test(&grid, 150, 45, 1, &row, &column, &border) && row == 1 && column == 1,
                "a body click maps to the cell under the pointer");
    GRID_EXPECT(vb_grid_hit_test(&grid, 99, 8, 1, &row, &column, &border) && border == 0,
                "the column edge in the header starts a resize");
    GRID_EXPECT(vb_grid_hit_test(&grid, 500, 45, 1, &row, &column, &border) && column == -1,
                "the empty area right of the last column has no cell");

    /* Layout: the columns fill the width once, the rows always fill the height. */
    {
        VbGrid laidOut;
        vb_grid_init(&laidOut, 0, 0, 100, 20);
        vb_grid_set_metrics(&laidOut, 100, 20, 18);
        vb_grid_fit(&laidOut, 410, 200);
        GRID_EXPECT(laidOut.columns == 4, "the layout fills the width with columns");
        GRID_EXPECT(laidOut.rows == 10, "the layout fills the height with rows");
        vb_grid_resize_column(&laidOut, 0, 160);
        vb_grid_fit(&laidOut, 600, 300);
        GRID_EXPECT(laidOut.columns == 4, "growing the control keeps the columns");
        GRID_EXPECT(laidOut.rows == 15, "growing the control adds rows");
        GRID_EXPECT(vb_grid_column_width(&laidOut, 0) == 160, "a resized column survives a re-layout");
        vb_grid_set_metrics(&laidOut, 90, 22, 18);
        GRID_EXPECT(vb_grid_column_width(&laidOut, 0) == 160, "a resized column ignores the new default");
        GRID_EXPECT(vb_grid_column_width(&laidOut, 1) == 90, "untouched columns follow the new default");
        vb_grid_free(&laidOut);
    }

    /* Dragging the header edge resizes that column and keeps a usable minimum. */
    GRID_EXPECT(vb_grid_resize_column(&grid, 1, 160) && vb_grid_column_width(&grid, 1) == 160,
                "a drag widens the column");
    GRID_EXPECT(vb_grid_resize_column(&grid, 1, 3) && vb_grid_column_width(&grid, 1) == 24,
                "a column cannot shrink below the minimum");
    GRID_EXPECT(!vb_grid_resize_column(&grid, 1, 24), "resizing to the same width is a no-op");

    /* Growing the sheet keeps the data, shrinking drops the removed cells. */
    vb_grid_set_cell(&grid, 0, 0, "keep");
    vb_grid_set_size(&grid, 8, 5);
    GRID_EXPECT(grid.rows == 8 && grid.columns == 5, "the sheet can grow at run time");
    GRID_EXPECT(vb_streq(vb_grid_cell(&grid, 0, 0), "keep"), "growing keeps the data");
    vb_grid_set_size(&grid, 1, 1);
    GRID_EXPECT(grid.rows == 1 && grid.columns == 1, "the sheet can shrink again");
    GRID_EXPECT(grid.selected_row == 0 && grid.selected_column == 0, "the selection follows a shrink");

    vb_grid_free(&grid);
    GRID_EXPECT(grid.rows == 0 && grid.cells == NULL, "free releases the sheet");
    return ok;
}

#undef GRID_EXPECT

static int cmd_grid(void)
{
    int ok = grid_suite();
    printf("grid: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}

static void print_control(VbControl *control, int depth)
{
    int i;
    for (i = 0; i < depth; i++) printf("  ");
    printf("%s %s (%d,%d %dx%d)\n", control->type, control->name,
           vb_control_get_int(control, "Left", 0), vb_control_get_int(control, "Top", 0),
           vb_control_get_int(control, "Width", 0), vb_control_get_int(control, "Height", 0));
    for (i = 0; i < control->nchildren; i++) print_control(control->children[i], depth + 1);
}

static int cmd_ids(const char *path)
{
    VbProject *project = vb_project_load(path);
    int i;
    if (!project) { fprintf(stderr, "cannot load %s\n", path); return 1; }
    printf("project=%s startup=%s items=%d\n", project->name, project->startup, project->nitems);
    for (i = 0; i < project->nitems; i++) {
        VbItem *item = &project->items[i];
        printf("  [%s] %s -> %s%s\n", item->kind_key, item->name, item->file,
               item->form ? " (form ok)" : "");
    }
    vb_project_free(project);
    return 0;
}

static int cmd_dump(const char *path)
{
    VbForm *form = vb_form_load(path);
    size_t handlers = 0;
    if (!form) { fprintf(stderr, "cannot parse form %s\n", path); return 1; }
    printf("form=%s caption=%s client=%dx%d\n", vb_form_name(form), vb_form_caption(form),
           vb_form_client_width(form), vb_form_client_height(form));
    print_control(form->root, 0);
    handlers = vb_code_count_handlers(form->code ? form->code : "");
    printf("handlers=%lu code_bytes=%lu\n", (unsigned long)handlers,
           (unsigned long)(form->code ? strlen(form->code) : 0));
    vb_form_free(form);
    return 0;
}

static int compare_controls(VbControl *a, VbControl *b, const char *path)
{
    int i;
    if (!a || !b) return a == b;
    if (!vb_streq_ci(a->type, b->type) || !vb_streq_ci(a->name, b->name)) {
        fprintf(stderr, "mismatch type/name %s/%s vs %s/%s in %s\n", a->type, a->name, b->type, b->name, path);
        return 0;
    }
    if (a->nprops != b->nprops) {
        fprintf(stderr, "mismatch prop count %s.%s: %d vs %d in %s\n", a->type, a->name, a->nprops, b->nprops, path);
        return 0;
    }
    for (i = 0; i < a->nprops; i++) {
        const char *bv = vb_control_get(b, a->props[i].key);
        if (!bv || !vb_streq(bv, a->props[i].value)) {
            fprintf(stderr, "mismatch prop %s.%s.%s: %s vs %s in %s\n", a->type, a->name, a->props[i].key,
                    a->props[i].value, bv ? bv : "(null)", path);
            return 0;
        }
    }
    if (a->nchildren != b->nchildren) {
        fprintf(stderr, "mismatch child count %s.%s: %d vs %d in %s\n", a->type, a->name,
                a->nchildren, b->nchildren, path);
        return 0;
    }
    for (i = 0; i < a->nchildren; i++) {
        if (!compare_controls(a->children[i], b->children[i], path)) return 0;
    }
    return 1;
}

static int cmd_verify(const char *path)
{
    VbForm *form = vb_form_load(path);
    VbForm *again;
    char *data;
    int ok = 0;
    if (!form) { fprintf(stderr, "cannot parse %s\n", path); return 1; }
    data = vb_form_serialize(form, NULL);
    again = vb_form_parse(data, path);
    if (again) {
        ok = compare_controls(form->root, again->root, path);
        if (ok && form->code && again->code && !vb_streq(form->code, again->code)) {
            fprintf(stderr, "code mismatch in %s\n", path);
            ok = 0;
        }
        if (ok) printf("verify ok %s\n", path);
        vb_form_free(again);
    } else {
        fprintf(stderr, "reparse failed %s\n", path);
    }
    free(data);
    vb_form_free(form);
    return ok ? 0 : 1;
}

static int cmd_roundtrip(const char *path)
{
    VbForm *form = vb_form_load(path);
    VbForm *again;
    size_t len = 0;
    char *data;
    if (!form) { fprintf(stderr, "cannot parse %s\n", path); return 1; }
    data = vb_form_serialize(form, &len);
    again = vb_form_parse(data, path);
    printf("roundtrip %s: %s (%lu bytes)\n", path, again ? "ok" : "FAILED", (unsigned long)len);
    if (again) {
        printf("  again form=%s controls=%d\n", vb_form_name(again), again->root ? again->root->nchildren : 0);
        vb_form_free(again);
    }
    free(data);
    vb_form_free(form);
    return again ? 0 : 1;
}

static int cmd_save(const char *path, const char *out)
{
    VbProject *project = vb_project_load(path);
    int ok;
    if (!project) { fprintf(stderr, "cannot load %s\n", path); return 1; }
    ok = vb_project_save(project, out ? out : path);
    if (ok) printf("saved %s\n", out ? out : path);
    else fprintf(stderr, "cannot save %s\n", out ? out : path);
    vb_project_free(project);
    return ok ? 0 : 1;
}

static int cmd_scan(const char *dir)
{
    (void)dir;
    return 0;
}

typedef struct {
    VbForm *form;
} ToolHost;

static char g_display[8192];

static const char *tool_display(const char *raw)
{
    char *value;
    if (!raw) return NULL;
    value = vb_value_unquote(raw);
    snprintf(g_display, sizeof(g_display), "%s", value ? value : "");
    free(value);
    return g_display;
}

static VbControl *tool_target(ToolHost *host, const char *control)
{
    if (!control || !*control) return host->form->root;
    return vb_form_find_control(host->form, control);
}

static const char *tool_get(void *ctx, const char *control, const char *prop)
{
    ToolHost *host = (ToolHost *)ctx;
    VbControl *target;
    const char *raw;
    target = tool_target(host, control);
    if (!target) return NULL;
    if (!prop || !*prop) {
        raw = vb_control_get(target, "Text");
        if (raw) return tool_display(raw);
        raw = vb_control_get(target, "Caption");
        if (raw) return tool_display(raw);
        raw = vb_control_get(target, "Value");
        if (raw) return tool_display(raw);
        return "";
    }
    if (vb_streq_ci(prop, "Name")) return target->name;
    raw = vb_control_get(target, prop);
    if (!raw) return NULL;
    return tool_display(raw);
}

static void tool_set(void *ctx, const char *control, const char *prop, const char *value)
{
    ToolHost *host = (ToolHost *)ctx;
    VbControl *target = tool_target(host, control);
    if (!target || !prop) return;
    vb_control_set_display(target, prop, value ? value : "");
}

static void tool_msgbox(void *ctx, const char *text)
{
    (void)ctx;
    printf("[MsgBox] %s\n", text ? text : "");
}

static void tool_close(void *ctx)
{
    (void)ctx;
    printf("[Close]\n");
}

static char *tool_inputbox(void *ctx, const char *prompt, const char *title, const char *default_text)
{
    (void)ctx;
    printf("[InputBox] title=%s prompt=%s default=%s\n", title ? title : "",
           prompt ? prompt : "", default_text ? default_text : "");
    return NULL;
}

static int tool_confirm(void *ctx, const char *text, const char *title, int style)
{
    (void)ctx;
    printf("[MsgBox style=%d title=%s] %s\n", style, title ? title : "", text ? text : "");
    return 1;
}

static int tool_set_focus(void *ctx, const char *control)
{
    ToolHost *host = (ToolHost *)ctx;
    printf("[SetFocus] %s\n", control && *control ? control : "Me");
    return tool_target(host, control) ? 1 : 0;
}

static int tool_runtime_error(void *ctx, int number, const char *message,
                              const char *handler, int line)
{
    (void)ctx;
    fprintf(stderr, "run-time error %d: %s (%s line %d)\n", number,
            message ? message : "", handler ? handler : "", line);
    return 1;
}

/* The check harness runs handlers for their side effects, not for their dialogs. */
static void tool_quiet_msgbox(void *ctx, const char *text)
{
    (void)ctx;
    (void)text;
}

static int tool_quiet_confirm(void *ctx, const char *text, const char *title, int style)
{
    (void)ctx;
    (void)text;
    (void)title;
    (void)style;
    return 1;
}

static int cmd_run(int argc, char **argv)
{
    VbForm *form;
    VbRuntimeHost host;
    ToolHost state;
    int i;
    int events = 0;
    if (argc < 3) return 2;
    form = vb_form_load(argv[2]);
    if (!form) { fprintf(stderr, "cannot load %s\n", argv[2]); return 1; }
    state.form = form;
    memset(&host, 0, sizeof(host));
    host.ctx = &state;
    host.get_prop = tool_get;
    host.set_prop = tool_set;
    host.msgbox = tool_msgbox;
    host.close = tool_close;
    host.inputbox = tool_inputbox;
    host.confirm = tool_confirm;
    host.set_focus = tool_set_focus;
    host.runtime_error = tool_runtime_error;
    for (i = 4; i < argc; i++) {
        char *eq = strchr(argv[i], '=');
        if (!eq) continue;
        *eq = '\0';
        {
            char *target = argv[i];
            char *dot = strchr(target, '.');
            char *prop = eq + 1;
            if (dot) {
                *dot = '\0';
                vb_control_set_display(tool_target(&state, target), dot + 1, prop);
            }
        }
    }
    events += vb_form_run_event(form, "Form_Load", &host);
    if (argc >= 4) events += vb_form_run_event(form, argv[3], &host);
    printf("events=%d\n", events);
    {
        int c;
        for (c = 0; c < form->root->nchildren; c++) {
            VbControl *child = form->root->children[c];
            const char *caption = tool_get(&state, child->name, "Caption");
            const char *text = tool_get(&state, child->name, "Text");
            printf("  %s: Caption=%s Text=%s\n", child->name,
                   caption ? caption : "", text ? text : "");
        }
    }
    vb_form_free(form);
    return 0;
}

/* Line (1-based) whose text contains needle, or 0. Used to place breakpoints in the
   headless harness without depending on the sample's exact line numbers. */
static int code_line_containing(const char *code, const char *needle)
{
    int line = 1;
    const char *cursor = code;
    size_t needleLength;
    if (!code || !needle) return 0;
    needleLength = strlen(needle);
    while (*cursor) {
        const char *end = strchr(cursor, '\n');
        size_t length = end ? (size_t)(end - cursor) : strlen(cursor);
        size_t i;
        for (i = 0; i + needleLength <= length; i++) {
            if (memcmp(cursor + i, needle, needleLength) == 0) return line;
        }
        if (!end) break;
        line++;
        cursor = end + 1;
    }
    return 0;
}

static size_t check_line_start(const char *text, int line)
{
    size_t location = 0;
    int current = 1;
    while (current < line && text[location]) {
        const char *end = strchr(text + location, '\n');
        if (!end) break;
        location = (size_t)(end - text) + 1;
        current++;
    }
    return location;
}

/* Applies one edit the way the editor would, for the breakpoint-mapping checks. */
static char *check_replace(const char *text, size_t location, size_t length,
                           const char *replacement)
{
    size_t textLength = strlen(text);
    size_t replacementLength = strlen(replacement);
    char *result = (char *)malloc(textLength - length + replacementLength + 1);
    if (!result) return NULL;
    memcpy(result, text, location);
    memcpy(result + location, replacement, replacementLength);
    strcpy(result + location + replacementLength, text + location + length);
    return result;
}

#define CHECK_EXPECT(cond, message) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "check: FAIL: %s\n", message); \
            sectionOk = 0; \
            ok = 0; \
        } \
    } while (0)

/* ------------------------------------------------------------------------------------
   Runtime host used by the headless sections: it records what the interpreter asks the
   IDE to do (error dialogs, break-mode pauses, SetFocus) instead of showing anything.
   The first field mirrors ToolHost so the shared get/set property helpers can cast it.
   ------------------------------------------------------------------------------------ */

typedef struct {
    VbForm *form;
    int errorCount;
    int errorNumber;
    int errorLine;
    int errorChoice;          /* what the End/Debug dialog answers (VB_RUNTIME_ERROR_*) */
    char errorHandler[64];
    char errorMessage[256];
    int breakCount;
    int breakStopAt;          /* pause number that answers "stop", 0 for never */
    int breakLines[64];
    int focusCalls;
    char focusTarget[64];
} CheckHost;

static const char *check_get(void *ctx, const char *control, const char *prop)
{
    return tool_get(ctx, control, prop);
}

static void check_set(void *ctx, const char *control, const char *prop, const char *value)
{
    tool_set(ctx, control, prop, value);
}

static int check_set_focus(void *ctx, const char *control)
{
    CheckHost *host = (CheckHost *)ctx;
    host->focusCalls++;
    snprintf(host->focusTarget, sizeof(host->focusTarget), "%s",
             control && *control ? control : "Me");
    if (!control || !*control) return 1;
    /* Labels and unknown names cannot take the focus: VB6 raises error 5. */
    if (vb_streq_ci(control, "Missing")) return 0;
    {
        VbControl *target = vb_form_find_control(host->form, control);
        if (!target) return 0;
        return !vb_streq_ci(target->type, "VB.Label");
    }
}

static int check_runtime_error(void *ctx, int number, const char *message,
                               const char *handler, int line)
{
    CheckHost *host = (CheckHost *)ctx;
    host->errorCount++;
    host->errorNumber = number;
    host->errorLine = line;
    snprintf(host->errorHandler, sizeof(host->errorHandler), "%s", handler ? handler : "");
    snprintf(host->errorMessage, sizeof(host->errorMessage), "%s", message ? message : "");
    return host->errorChoice;
}

static int check_break_hook(void *ctx, const char *handler, int line)
{
    CheckHost *host = (CheckHost *)ctx;
    (void)handler;
    host->breakCount++;
    if (host->breakCount <= (int)(sizeof(host->breakLines) / sizeof(host->breakLines[0]))) {
        host->breakLines[host->breakCount - 1] = line;
    }
    return host->breakStopAt > 0 && host->breakCount == host->breakStopAt;
}

static void check_host_init(VbRuntimeHost *runtime, CheckHost *host, VbForm *form)
{
    memset(host, 0, sizeof(*host));
    memset(runtime, 0, sizeof(*runtime));
    host->form = form;
    host->errorChoice = VB_RUNTIME_ERROR_END;
    runtime->ctx = host;
    runtime->get_prop = check_get;
    runtime->set_prop = check_set;
    runtime->msgbox = tool_quiet_msgbox;
    runtime->close = tool_close;
    runtime->inputbox = tool_inputbox;
    runtime->confirm = tool_quiet_confirm;
    runtime->set_focus = check_set_focus;
    runtime->runtime_error = check_runtime_error;
    runtime->break_hook = check_break_hook;
}

/* A form with one Label and one TextBox, so a handler has something to touch. */
static VbForm *check_fixture_form(const char *code)
{
    VbForm *form = vb_form_new("Form1");
    if (!form) return NULL;
    vb_form_add_control(form, form->root, "VB.Label", 120, 120, 2400, 300);
    vb_form_add_control(form, form->root, "VB.TextBox", 120, 600, 2400, 300);
    free(form->code);
    form->code = vb_strdup(code);
    return form;
}

static char *check_caption(VbForm *form)
{
    VbControl *label = vb_form_find_control(form, "Label1");
    return label ? vb_control_get_display(label, "Caption") : NULL;
}

/* 6. Run-time errors without a window: an unhandled error reaches the End/Debug hook and
   stops the procedure, Debug continues when break mode exists, and a trapped error never
   reaches the hook. This is the logic the End/Debug dialog and the On Error suite used to
   assert by running the IDE. */
static int check_runtime_errors(void)
{
    static const char *code =
        "Attribute VB_Name = \"Form1\"\n"
        "Option Explicit\n\n"
        "Private Sub Unhandled()\n"
        "    Missing.SetFocus\n"
        "    Label1.Caption = \"after\"\n"
        "End Sub\n\n"
        "Private Sub TrappedResumeNext()\n"
        "    On Error Resume Next\n"
        "    Label1.SetFocus\n"
        "    Label1.Caption = \"resume:\" & Err.Number & \":\" & Err.Description\n"
        "    Err.Clear\n"
        "    Label1.Caption = Label1.Caption & \":clear:\" & Err.Number\n"
        "    Missing.SetFocus\n"
        "    Label1.Caption = Label1.Caption & \":missing:\" & Err.Number\n"
        "End Sub\n\n"
        "Private Sub TrappedGoTo()\n"
        "    On Error GoTo Caught\n"
        "    Label1.SetFocus\n"
        "    Label1.Caption = \"not reached\"\n"
        "    Exit Sub\n"
        "Caught:\n"
        "    Label1.Caption = \"caught:\" & Err.Number\n"
        "    Exit Sub\n"
        "End Sub\n\n"
        "Private Sub ResumeNextFromHandler()\n"
        "    On Error GoTo Caught\n"
        "    Label1.SetFocus\n"
        "    Label1.Caption = Label1.Caption & \"resumed\"\n"
        "    Exit Sub\n"
        "Caught:\n"
        "    Label1.Caption = \"handler:\" & Err.Number & \";\"\n"
        "    Resume Next\n"
        "End Sub\n\n"
        "Private Sub TrappedInsideIf()\n"
        "    On Error Resume Next\n"
        "    If 1 = 1 Then\n"
        "        Label1.SetFocus\n"
        "        Label1.Caption = \"in-if\"\n"
        "    End If\n"
        "    Label1.Caption = Label1.Caption & \":after\"\n"
        "End Sub\n\n"
        "Private Sub ResumeToLabel()\n"
        "    On Error GoTo Caught\n"
        "    Label1.SetFocus\n"
        "    Exit Sub\n"
        "Caught:\n"
        "    Label1.Caption = \"handler\"\n"
        "    Resume Done\n"
        "Done:\n"
        "    Label1.Caption = Label1.Caption & \":done\"\n"
        "End Sub\n\n"
        "Private Sub RaisedError()\n"
        "    On Error Resume Next\n"
        "    Err.Raise 53\n"
        "    Label1.Caption = \"raised:\" & Err.Number & \":\" & Err.Description\n"
        "End Sub\n\n"
        "Private Sub Reraised()\n"
        "    On Error GoTo Caught\n"
        "    Label1.SetFocus\n"
        "    Exit Sub\n"
        "Caught:\n"
        "    On Error GoTo 0\n"
        "    Label1.Caption = \"reraised\"\n"
        "    Label1.SetFocus\n"
        "    Label1.Caption = \"unreachable\"\n"
        "End Sub\n";
    VbRuntimeHost runtime;
    CheckHost host;
    VbForm *form = check_fixture_form(code);
    char *caption;
    int ok = 1;
    if (!form) { fprintf(stderr, "check: FAIL: the runtime-error fixture must be created\n"); return 0; }
    check_host_init(&runtime, &host, form);

    /* End: the error stops the procedure before the next statement. */
    vb_control_set(form->root->children[0], "Caption", "initial");
    vb_form_run_event(form, "Unhandled", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 1 && host.errorNumber == 5 &&
          vb_streq(host.errorHandler, "Unhandled") && host.errorLine > 0 &&
          vb_streq(host.errorMessage, "Invalid procedure call or argument"))) {
        fprintf(stderr, "check: FAIL: End must report error 5 with its handler and line "
                        "(got %d at %s line %d: %s)\n", host.errorNumber,
                host.errorHandler, host.errorLine, host.errorMessage);
        ok = 0;
    }
    if (!(caption && vb_streq(caption, "initial"))) {
        fprintf(stderr, "check: FAIL: End must not run the statement after the error\n");
        ok = 0;
    }
    free(caption);

    /* Debug with break support: the procedure continues after the failing statement. */
    host.errorChoice = VB_RUNTIME_ERROR_DEBUG;
    host.errorCount = 0;
    host.breakCount = 0;
    vb_form_run_event(form, "Unhandled", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 1 && host.breakCount >= 1 && host.breakLines[0] == host.errorLine &&
          caption && vb_streq(caption, "after"))) {
        fprintf(stderr, "check: FAIL: Debug must pause on the failing line and keep running "
                        "(errors %d, pauses %d, pause at %d, error at %d, caption '%s')\n",
                host.errorCount, host.breakCount,
                host.breakCount ? host.breakLines[0] : -1, host.errorLine,
                caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* Debug without break mode (no debugger attached): the procedure stops anyway. */
    runtime.break_hook = NULL;
    host.errorChoice = VB_RUNTIME_ERROR_DEBUG;
    host.errorCount = 0;
    vb_control_set(form->root->children[0], "Caption", "stopped");
    vb_form_run_event(form, "Unhandled", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 1 && caption && vb_streq(caption, "stopped"))) {
        fprintf(stderr, "check: FAIL: Debug without break support must stop the procedure\n");
        ok = 0;
    }
    free(caption);
    runtime.break_hook = check_break_hook;
    host.errorChoice = VB_RUNTIME_ERROR_END;

    /* On Error Resume Next: no dialog, Err.Number/Description filled, Clear empties it. */
    host.errorCount = 0;
    host.focusCalls = 0;
    vb_control_set(form->root->children[0], "Caption", "");
    vb_form_run_event(form, "TrappedResumeNext", &runtime);
    caption = check_caption(form);
    if (host.errorCount != 0) {
        fprintf(stderr, "check: FAIL: a trapped error must not reach the End/Debug dialog\n");
        ok = 0;
    }
    if (!(caption && vb_streq(caption,
                              "resume:5:Invalid procedure call or argument:clear:0:missing:5"))) {
        fprintf(stderr, "check: FAIL: On Error Resume Next must keep running and fill Err "
                        "(got '%s')\n", caption ? caption : "");
        ok = 0;
    }
    free(caption);
    if (!(host.focusCalls > 0 && vb_streq(host.focusTarget, "Missing"))) {
        fprintf(stderr, "check: FAIL: the handler must call SetFocus on the failing controls\n");
        ok = 0;
    }

    /* On Error GoTo: control jumps to the label and does not retry the statement. */
    host.errorCount = 0;
    vb_form_run_event(form, "TrappedGoTo", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 0 && caption && vb_streq(caption, "caught:5"))) {
        fprintf(stderr, "check: FAIL: On Error GoTo must reach the label without a dialog "
                        "(got '%s')\n", caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* Resume Next in the handler continues right after the failing statement. */
    host.errorCount = 0;
    vb_form_run_event(form, "ResumeNextFromHandler", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 0 && caption && vb_streq(caption, "handler:5;resumed"))) {
        fprintf(stderr, "check: FAIL: Resume Next in a handler must continue after the error "
                        "(got '%s')\n", caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* The handler scope is the procedure: Resume Next also works inside an If block. */
    host.errorCount = 0;
    vb_form_run_event(form, "TrappedInsideIf", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 0 && caption && vb_streq(caption, "in-if:after"))) {
        fprintf(stderr, "check: FAIL: Resume Next must work inside an If block (got '%s')\n",
                caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* Resume <label> continues at the label. */
    host.errorCount = 0;
    vb_form_run_event(form, "ResumeToLabel", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 0 && caption && vb_streq(caption, "handler:done"))) {
        fprintf(stderr, "check: FAIL: Resume <label> must continue at the label (got '%s')\n",
                caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* Err.Raise fills Err with VB6's description for the number. */
    host.errorCount = 0;
    vb_form_run_event(form, "RaisedError", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 0 && caption && vb_streq(caption, "raised:53:File not found"))) {
        fprintf(stderr, "check: FAIL: Err.Raise must fill Number/Description (got '%s')\n",
                caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* On Error GoTo 0: the next error is unhandled again, so the dialog is back. */
    host.errorCount = 0;
    vb_form_run_event(form, "Reraised", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 1 && host.errorNumber == 5 &&
          vb_streq(host.errorHandler, "Reraised") &&
          caption && vb_streq(caption, "reraised"))) {
        fprintf(stderr, "check: FAIL: On Error GoTo 0 must let the error reach the dialog "
                        "(errors %d, handler %s, caption '%s')\n", host.errorCount,
                host.errorHandler, caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* A trapped handler still behaves the same after an unhandled error was shown. */
    host.errorCount = 0;
    vb_form_run_event(form, "TrappedGoTo", &runtime);
    caption = check_caption(form);
    if (!(host.errorCount == 0 && caption && vb_streq(caption, "caught:5"))) {
        fprintf(stderr, "check: FAIL: a handler must keep trapping after an unhandled error\n");
        ok = 0;
    }
    free(caption);

    vb_form_free(form);
    return ok;
}

/* 7. Break mode and stepping: the break hook sees exactly the executable statements, in
   order, and answering "stop" leaves the rest of the procedure unexecuted. */
static int check_break_mode(void)
{
    static const char *code =
        "Attribute VB_Name = \"Form1\"\n"
        "Option Explicit\n\n"
        "Private Sub Steps()\n"
        "    Dim counter As Integer\n"
        "    Label1.Caption = \"one\"\n"
        "    Label1.Caption = \"two\"\n"
        "    Label1.Caption = \"three\"\n"
        "End Sub\n";
    VbRuntimeHost runtime;
    CheckHost host;
    VbForm *form = check_fixture_form(code);
    char *caption;
    int ok = 1;
    int i;
    if (!form) { fprintf(stderr, "check: FAIL: the break-mode fixture must be created\n"); return 0; }
    check_host_init(&runtime, &host, form);

    vb_form_run_event(form, "Steps", &runtime);
    caption = check_caption(form);
    if (!(host.breakCount == 3 && caption && vb_streq(caption, "three"))) {
        fprintf(stderr, "check: FAIL: stepping must stop on the three statements "
                        "(got %d pauses, caption '%s')\n", host.breakCount, caption ? caption : "");
        ok = 0;
    }
    free(caption);
    for (i = 1; i < host.breakCount; i++) {
        if (host.breakLines[i] <= host.breakLines[i - 1]) {
            fprintf(stderr, "check: FAIL: the pause lines must increase\n");
            ok = 0;
            break;
        }
    }
    /* Dim and End Sub are not statements the interpreter stops on. */
    if (!(host.breakCount == 3 && host.breakLines[0] > 0)) {
        fprintf(stderr, "check: FAIL: declarations or End Sub must not pause\n");
        ok = 0;
    }

    /* Stop on the second pause (before its statement): "one" ran, "two" must not. */
    host.breakCount = 0;
    host.breakStopAt = 2;
    vb_form_run_event(form, "Steps", &runtime);
    caption = check_caption(form);
    if (!(host.breakCount == 2 && caption && vb_streq(caption, "one"))) {
        fprintf(stderr, "check: FAIL: Stop must leave the remaining statements unexecuted "
                        "(got %d pauses, caption '%s')\n", host.breakCount, caption ? caption : "");
        ok = 0;
    }
    free(caption);

    /* A breakpoint must be placeable only on executable lines, as the gutter does. */
    {
        static const char *lines =
            "Private Sub Target()\n"
            "    Dim n As Integer\n"
            "again:\n"
            "    n = n + 1\n"
            "    If n > 2 Then\n"
            "        n = 0\n"
            "    End If\n"
            "End Sub\n";
        if (!(vb_code_line_executable(lines, 2) == 0 &&
              vb_code_line_executable(lines, 3) == 0 &&
              vb_code_line_executable(lines, 4) == 1 &&
              vb_code_line_executable(lines, 5) == 1 &&
              vb_code_line_executable(lines, 6) == 1 &&
              vb_code_line_executable(lines, 7) == 0 &&
              vb_code_line_executable(lines, 8) == 0)) {
            fprintf(stderr, "check: FAIL: only executable statements accept a breakpoint\n");
            ok = 0;
        }
    }

    vb_form_free(form);
    return ok;
}

/* 8. Tab order in the model: TabIndex ranks the container's tabbable children, ties keep
   the z-order, and the Tab Order dialog renumbers them 0..n-1. */
static int check_tab_order(void)
{
    VbForm *form = vb_form_new("Form1");
    VbControl *order[16];
    VbControl *text1, *text2, *label, *grid, *frame, *data;
    int count;
    int ok = 1;
    if (!form) return 0;
    text1 = vb_form_add_control(form, form->root, "VB.TextBox", 0, 0, 1200, 300);
    text2 = vb_form_add_control(form, form->root, "VB.TextBox", 0, 0, 1200, 300);
    label = vb_form_add_control(form, form->root, "VB.Label", 0, 0, 1200, 300);
    grid = vb_form_add_control(form, form->root, "VB.DataGrid", 0, 0, 1200, 600);
    frame = vb_form_add_control(form, form->root, "VB.Frame", 0, 0, 2400, 1200);
    data = vb_form_add_control(form, form->root, "VB.Data", 0, 0, 1200, 600);
    if (!(text1 && text2 && label && grid && frame && data)) {
        fprintf(stderr, "check: FAIL: the tab-order fixture must be created\n");
        vb_form_free(form);
        return 0;
    }
    vb_control_set_int(text1, "TabIndex", 2);
    vb_control_set_int(text2, "TabIndex", 1);
    vb_control_set_int(label, "TabIndex", 0);   /* a Label never takes the focus */
    vb_control_set_int(grid, "TabIndex", 0);
    vb_control_set_int(frame, "TabIndex", 0);   /* a Frame is a container, not a tab stop */

    count = vb_control_collect_tab_order(form->root, order, 16);
    if (!(count == 3 && order[0] == grid && order[1] == text2 && order[2] == text1)) {
        fprintf(stderr, "check: FAIL: tab order must follow TabIndex, then z-order (got %d)\n", count);
        ok = 0;
    }
    if (!(vb_control_can_tab(grid) && !vb_control_can_tab(label) && !vb_control_can_tab(data) &&
          !vb_control_can_tab(frame))) {
        fprintf(stderr, "check: FAIL: only focusable controls can tab (DataGrid yes, Label/Data/Frame no)\n");
        ok = 0;
    }

    /* TabStop = False and Visible = False take a control out of the order. */
    vb_control_set_int(text2, "TabStop", 0);
    vb_control_set_int(text1, "Visible", 0);
    count = vb_control_collect_tab_order(form->root, order, 16);
    if (!(count == 1 && order[0] == grid)) {
        fprintf(stderr, "check: FAIL: TabStop=False and Visible=False must leave the order\n");
        ok = 0;
    }
    vb_control_set_int(text2, "TabStop", -1);
    vb_control_set_int(text1, "Visible", -1);

    /* The Tab Order dialog renumbers the ordered controls 0..n-1. */
    count = vb_control_collect_tab_order(form->root, order, 16);
    vb_control_apply_tab_order(form->root, order, count);
    if (!(vb_control_tab_index(grid, -1) == 0 && vb_control_tab_index(text2, -1) == 1 &&
          vb_control_tab_index(text1, -1) == 2)) {
        fprintf(stderr, "check: FAIL: applying a tab order must renumber TabIndex 0..n-1\n");
        ok = 0;
    }
    if (!(vb_control_next_tab_index(form->root) == 3)) {
        fprintf(stderr, "check: FAIL: a new control must take the next free TabIndex\n");
        ok = 0;
    }

    /* sorted_children keeps every child, tabbable or not, ordered by TabIndex. */
    count = vb_control_sorted_children(form->root, order, 16);
    if (count != form->root->nchildren) {
        fprintf(stderr, "check: FAIL: sorted_children must keep every control\n");
        ok = 0;
    }

    vb_form_free(form);
    return ok;
}

/* The headless verification suite: no Cocoa, no windows. `make check` runs this and
   nothing else, so a regression is caught without the app ever appearing on screen. */
static int cmd_check(const char *samplePath)
{
    int ok = 1;
    int sectionOk;
    VbForm *form;

    /* 1. The sample parses, and serialize -> parse keeps every control and the code. */
    sectionOk = 1;
    form = vb_form_load(samplePath);
    CHECK_EXPECT(form != NULL, "the sample form must load");
    if (!form) return 1;
    {
        size_t len = 0;
        char *data = vb_form_serialize(form, &len);
        CHECK_EXPECT(data != NULL, "the form must serialize");
        if (data) {
            VbForm *again = vb_form_parse(data, samplePath);
            CHECK_EXPECT(again != NULL, "the serialized form must parse again");
            if (again) {
                CHECK_EXPECT(again->root && form->root &&
                             again->root->nchildren == form->root->nchildren,
                             "the controls must survive the round-trip");
                CHECK_EXPECT(again->code && form->code && vb_streq(again->code, form->code),
                             "the code must survive the round-trip");
                vb_form_free(again);
            }
            free(data);
        }
    }
    fprintf(stderr, "check: round-trip %s\n", sectionOk ? "PASS" : "FAIL");

    /* 2. The interpreter runs the sample's Click handler against its controls. */
    sectionOk = 1;
    {
        ToolHost state;
        VbRuntimeHost host;
        VbControl *text = vb_form_find_control(form, "Text1");
        VbControl *label = vb_form_find_control(form, "Label1");
        memset(&host, 0, sizeof(host));
        state.form = form;
        host.ctx = &state;
        host.get_prop = tool_get;
        host.set_prop = tool_set;
        host.msgbox = tool_quiet_msgbox;
        host.close = tool_close;
        host.inputbox = tool_inputbox;
        host.confirm = tool_quiet_confirm;
        host.set_focus = tool_set_focus;
        host.runtime_error = tool_runtime_error;
        CHECK_EXPECT(text && label, "the sample must have Text1 and Label1");
        if (text) vb_control_set_display(text, "Text", "Gaetano");
        vb_form_run_event(form, "Form_Load", &host);
        vb_form_run_event(form, "Command1_Click", &host);
        {
            char *caption = label ? vb_control_get_display(label, "Caption") : NULL;
            CHECK_EXPECT(caption && vb_streq(caption, "Hello Gaetano"),
                         "Command1_Click must set Label1.Caption");
            free(caption);
        }
    }
    fprintf(stderr, "check: interpreter %s\n", sectionOk ? "PASS" : "FAIL");

    /* 3. Breakpoints: model, .frm marker, byte-identical save/load/save. */
    sectionOk = 1;
    {
        int line = code_line_containing(form->code, "Label1.Caption");
        size_t len = 0;
        char *data;
        CHECK_EXPECT(line > 0, "the sample must contain a Label1.Caption statement");
        CHECK_EXPECT(vb_form_set_breakpoint(form, line, 1), "setting a breakpoint must change the form");
        CHECK_EXPECT(vb_form_has_breakpoint(form, line), "the breakpoint must be in the model");
        CHECK_EXPECT(vb_form_breakpoint_count(form) == 1 && vb_form_breakpoint_at(form, 0) == line,
                     "the breakpoint set must hold exactly that line");
        data = vb_form_serialize(form, &len);
        CHECK_EXPECT(data && strstr(data, VB_BREAKPOINT_MARKER) != NULL,
                     "the .frm must carry the breakpoint marker");
        if (data) {
            VbForm *again = vb_form_parse(data, samplePath);
            CHECK_EXPECT(again != NULL, "the form with a marker must parse again");
            if (again) {
                size_t againLen = 0;
                char *second = vb_form_serialize(again, &againLen);
                CHECK_EXPECT(vb_form_has_breakpoint(again, line),
                             "loading must restore the breakpoint");
                CHECK_EXPECT(again->code && strstr(again->code, VB_BREAKPOINT_MARKER) == NULL,
                             "the marker must not reach the code");
                CHECK_EXPECT(second && vb_streq(second, data) && againLen == len,
                             "save/load/save must be byte-identical");
                free(second);
                vb_form_free(again);
            }
            free(data);
        }
        vb_form_clear_breakpoints(form);
        CHECK_EXPECT(vb_form_breakpoint_count(form) == 0, "clearing must empty the set");
    }
    fprintf(stderr, "check: breakpoints %s\n", sectionOk ? "PASS" : "FAIL");

    /* 4. Toolbox and defaults: Data/DataGrid are offered with VB6's properties. */
    sectionOk = 1;
    {
        int count = 0, i;
        const VbToolDef *tools = vb_tool_defs(&count);
        int hasData = 0, hasGrid = 0;
        for (i = 0; i < count; i++) {
            if (vb_streq(tools[i].type, "VB.Data")) hasData = 1;
            if (vb_streq(tools[i].type, "VB.DataGrid")) hasGrid = 1;
        }
        CHECK_EXPECT(hasData && hasGrid, "the toolbox must offer Data and DataGrid");
        {
            VbControl *data = vb_form_add_control(form, form->root, "VB.Data", 0, 0, 0, 0);
            VbControl *grid = vb_form_add_control(form, form->root, "VB.DataGrid", 0, 0, 0, 0);
            CHECK_EXPECT(data && grid, "Data and DataGrid must be creatable");
            if (data && grid) {
                CHECK_EXPECT(vb_control_get_int(grid, "ColumnHeaders", 0) == -1,
                             "DataGrid defaults to ColumnHeaders = True");
                CHECK_EXPECT(vb_control_get_int(grid, "DefColWidth", 0) == 1275 &&
                             vb_control_get_int(grid, "RowHeight", 0) == 255,
                             "DataGrid must use VB6's default metrics");
                CHECK_EXPECT(vb_control_get(grid, "Caption") == NULL,
                             "DataGrid has no Caption in VB6");
                CHECK_EXPECT(vb_control_get(data, "Caption") != NULL,
                             "the Data control keeps its Caption");
                CHECK_EXPECT(vb_control_get(grid, "TabIndex") != NULL,
                             "DataGrid takes a TabIndex");
                CHECK_EXPECT(vb_control_get_int(data, "TabIndex", -999) == -999,
                             "the Data control is not tabbable");
                {
                    size_t len = 0;
                    char *text = vb_form_serialize(form, &len);
                    VbForm *again = text ? vb_form_parse(text, samplePath) : NULL;
                    VbControl *reloaded = again ? vb_form_find_control(again, "DataGrid1") : NULL;
                    CHECK_EXPECT(reloaded != NULL, "DataGrid1 must survive the round-trip");
                    CHECK_EXPECT(reloaded && vb_control_get_int(reloaded, "ColumnHeaders", 0) == -1 &&
                                 vb_control_get_int(reloaded, "DefColWidth", 0) == 1275,
                                 "DataGrid properties must survive the round-trip");
                    CHECK_EXPECT(reloaded && vb_control_get(reloaded, "Caption") == NULL,
                                 "the reloaded DataGrid must stay captionless");
                    if (again) vb_form_free(again);
                    free(text);
                }
            }
        }
    }
    fprintf(stderr, "check: controls %s\n", sectionOk ? "PASS" : "FAIL");

    /* 5. Breakpoints follow the code: the same core function the code editor calls on
       every text change, so inserted/removed lines are covered without the window. */
    sectionOk = 1;
    {
        static const char *base =
            "Attribute VB_Name = \"Form1\"\n"
            "Private Sub Test()\n"
            "    x = 1\n"
            "    y = 2\n"
            "    z = 3\n"
            "End Sub\n";
        int lines[1] = {4};  /*    y = 2 */
        int current = 4;
        int *mapped;
        int count;
        char *inserted;

        inserted = check_replace(base, 0, 0, "\n");
        mapped = vb_code_follow_breakpoints(base, inserted, lines, 1, &count);
        CHECK_EXPECT(count == 1 && mapped && mapped[0] == 5,
                     "a line inserted above must push the dot down");
        if (mapped && count == 1) current = mapped[0];
        free(mapped);
        {
            char *back = check_replace(inserted, 0, 1, "");
            lines[0] = current;
            mapped = vb_code_follow_breakpoints(inserted, back, lines, 1, &count);
            CHECK_EXPECT(count == 1 && mapped && mapped[0] == 4,
                         "deleting that line must bring the dot back");
            if (mapped && count == 1) current = mapped[0];
            free(mapped);
            free(back);
        }
        free(inserted);
        {
            size_t start = check_line_start(base, 4);
            char *split = check_replace(base, start, 0, "\n");
            lines[0] = current;
            mapped = vb_code_follow_breakpoints(base, split, lines, 1, &count);
            CHECK_EXPECT(count == 1 && mapped && mapped[0] == 5,
                         "Enter at column 0 must move the dot with the statement");
            if (mapped && count == 1) current = mapped[0];
            free(mapped);
            {
                char *joined = check_replace(split, start, 1, "");
                lines[0] = current;
                mapped = vb_code_follow_breakpoints(split, joined, lines, 1, &count);
                CHECK_EXPECT(count == 1 && mapped && mapped[0] == 4,
                             "removing the blank line must restore the dot");
                if (mapped && count == 1) current = mapped[0];
                free(mapped);
                free(joined);
            }
            free(split);
        }
        {
            char *below = check_replace(base, strlen(base), 0, "\n' note\n");
            lines[0] = current;
            mapped = vb_code_follow_breakpoints(base, below, lines, 1, &count);
            CHECK_EXPECT(count == 1 && mapped && mapped[0] == 4,
                         "editing below the dot must leave it alone");
            free(mapped);
            free(below);
        }
        {
            size_t start = check_line_start(base, 4);
            char *typed = check_replace(base, start, 0, " ");
            lines[0] = current;
            mapped = vb_code_follow_breakpoints(base, typed, lines, 1, &count);
            CHECK_EXPECT(count == 1 && mapped && mapped[0] == 4,
                         "typing on the statement must keep the dot");
            free(mapped);
            free(typed);
        }
        {
            size_t start = check_line_start(base, 4);
            char *removed = check_replace(base, start, strlen("    y = 2\n"), "");
            lines[0] = current;
            mapped = vb_code_follow_breakpoints(base, removed, lines, 1, &count);
            CHECK_EXPECT(count == 0, "deleting the statement must drop the dot");
            free(mapped);
            free(removed);
        }
        {
            size_t start = check_line_start(base, 3);
            char *removed = check_replace(base, start, strlen("    x = 1\n"), "");
            lines[0] = current;
            mapped = vb_code_follow_breakpoints(base, removed, lines, 1, &count);
            CHECK_EXPECT(count == 1 && mapped && mapped[0] == 3,
                         "deleting a line above must move the dot up");
            free(mapped);
            free(removed);
        }
        /* Several dots keep their order and spacing. */
        {
            int pair[2];
            pair[0] = 3;
            pair[1] = 5;
            inserted = check_replace(base, 0, 0, "\n\n");
            mapped = vb_code_follow_breakpoints(base, inserted, pair, 2, &count);
            CHECK_EXPECT(count == 2 && mapped && mapped[0] == 5 && mapped[1] == 7,
                         "every dot must slide by the inserted lines");
            free(mapped);
            free(inserted);
        }
        /* Two statements with the same prefix: the line-widened diff must still see the
           first one as deleted instead of moving its dot onto the second. */
        {
            static const char *source =
                "Private Sub Test()\n"
                "    Label1.Caption = \"first\"\n"
                "    Label1.Caption = \"second\"\n"
                "End Sub\n";
            int target[1];
            size_t start = check_line_start(source, 2);
            char *removed = check_replace(source, start, strlen("    Label1.Caption = \"first\"\n"), "");
            target[0] = 2;
            mapped = vb_code_follow_breakpoints(source, removed, target, 1, &count);
            CHECK_EXPECT(count == 0,
                         "deleting a statement must drop its dot even with a similar line below");
            free(mapped);
            free(removed);
        }
    }
    fprintf(stderr, "check: breakpoint edits %s\n", sectionOk ? "PASS" : "FAIL");

    vb_form_free(form);

    /* 6. End/Debug, On Error and the Err object, driven through the interpreter hooks. */
    sectionOk = check_runtime_errors();
    if (!sectionOk) ok = 0;
    fprintf(stderr, "check: runtime errors %s\n", sectionOk ? "PASS" : "FAIL");

    /* 7. Break mode and single stepping, without the IDE's pause loop. */
    sectionOk = check_break_mode();
    if (!sectionOk) ok = 0;
    fprintf(stderr, "check: break mode %s\n", sectionOk ? "PASS" : "FAIL");

    /* 8. Tab order in the model (runtime windows add their dynamic overrides). */
    sectionOk = check_tab_order();
    if (!sectionOk) ok = 0;
    fprintf(stderr, "check: tab order %s\n", sectionOk ? "PASS" : "FAIL");

    /* 9. DataGrid behaviour (selection, editing, hit-test, resize, layout). */
    sectionOk = grid_suite();
    if (!sectionOk) ok = 0;
    fprintf(stderr, "check: datagrid %s\n", sectionOk ? "PASS" : "FAIL");

    printf("check: %s\n", ok ? "PASS" : "FAIL");
    return ok ? 0 : 1;
}

#undef CHECK_EXPECT

int main(int argc, char **argv)
{
    if (argc >= 2 && strcmp(argv[1], "check") == 0) {
        return cmd_check(argc > 2 ? argv[2] : "samples/HelloWorld/frmHello.frm");
    }
    if (argc >= 2 && strcmp(argv[1], "grid") == 0) return cmd_grid();
    if (argc < 3) {
        fprintf(stderr, "usage: vbtool ids|dump|roundtrip|verify|save <file> [out] | run <form> <handler> [Control.Prop=Value...] | grid | check [form]\n");
        return 2;
    }
    if (strcmp(argv[1], "ids") == 0) return cmd_ids(argv[2]);
    if (strcmp(argv[1], "dump") == 0) return cmd_dump(argv[2]);
    if (strcmp(argv[1], "roundtrip") == 0) return cmd_roundtrip(argv[2]);
    if (strcmp(argv[1], "verify") == 0) return cmd_verify(argv[2]);
    if (strcmp(argv[1], "run") == 0) return cmd_run(argc, argv);
    if (strcmp(argv[1], "save") == 0) return cmd_save(argv[2], argc > 3 ? argv[3] : NULL);
    if (strcmp(argv[1], "scan") == 0) return cmd_scan(argv[2]);
    (void)argc;
    return 2;
}
