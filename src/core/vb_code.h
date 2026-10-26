#ifndef VB_CODE_H
#define VB_CODE_H

#include "vb_model.h"

#include <stddef.h>

typedef enum {
    VB_TOK_DEFAULT = 0,
    VB_TOK_COMMENT,
    VB_TOK_STRING,
    VB_TOK_KEYWORD,
    VB_TOK_TYPE,
    VB_TOK_NUMBER,
    VB_TOK_FUNCTION,
    VB_TOK_OPERATOR,
    VB_TOK_CONSTANT
} VbTokenClass;

typedef struct {
    size_t start;
    size_t len;
    int cls;
} VbSpan;

typedef struct {
    VbSpan *items;
    size_t count;
    size_t cap;
} VbSpanList;

typedef struct {
    char *name;
    char *body;
    int body_line;
} VbHandler;

typedef struct {
    VbHandler *items;
    int count;
    int cap;
} VbHandlerList;

/* VB6 Err object. The interpreter fills it when an error is trapped or raised; a host
   may point VbRuntimeHost.err at its own instance to inspect the result afterwards. */
typedef struct {
    int number;
    char description[256];
    char source[128];
} VbErrObject;

typedef struct VbRuntimeHost {
    void *ctx;
    const char *(*get_prop)(void *ctx, const char *control, const char *prop);
    void (*set_prop)(void *ctx, const char *control, const char *prop, const char *value);
    void (*msgbox)(void *ctx, const char *text);
    void (*close)(void *ctx);
    /* Returns a malloc'd string (caller frees) or NULL when cancelled. */
    char *(*inputbox)(void *ctx, const char *prompt, const char *title, const char *default_text);
    /* Returns the VB button constant (1 OK, 2 Cancel, 6 Yes, 7 No).
       buttons/icon is the combined VB MsgBox style value. */
    int (*confirm)(void *ctx, const char *text, const char *title, int style);
    /* <Control>.SetFocus; control is NULL for the form itself. Returns 0 when the
       control cannot take the focus (VB6 run-time error 5). */
    int (*set_focus)(void *ctx, const char *control);
    /* Optional storage for the Err object; NULL lets the interpreter use a private
       instance for the duration of the run. */
    VbErrObject *err;
    /* VB6 run-time error dialog (End/Debug). handler/line locate the statement.
       Only called for errors that no On Error handler traps; the return value is one
       of the VB_RUNTIME_ERROR_* constants below. End always stops the procedure;
       Debug keeps it alive when a break_hook is installed (the user steps out of the
       failure), otherwise it stops as well. */
    int (*runtime_error)(void *ctx, int number, const char *message,
                         const char *handler, int line);
    /* Break mode / single stepping, asked before every executable statement. The host
       pauses (running its own event loop) until the user continues or steps, then
       returns 0 to execute the statement or 1 to stop the procedure (Stop/End from
       break mode). line is absolute in the code window, so the IDE can highlight it. */
    int (*break_hook)(void *ctx, const char *handler, int line);
} VbRuntimeHost;

/* VbRuntimeHost.runtime_error results, matching the End and Debug buttons. */
enum {
    VB_RUNTIME_ERROR_END = 1,
    VB_RUNTIME_ERROR_DEBUG = 2
};

void vb_spanlist_init(VbSpanList *list);
void vb_spanlist_free(VbSpanList *list);
void vb_code_highlight(const char *text, size_t len, VbSpanList *out);

void vb_handler_list_init(VbHandlerList *list);
void vb_handler_list_free(VbHandlerList *list);
int vb_code_handlers(const char *code, VbHandlerList *out);
size_t vb_code_count_handlers(const char *code);
char *vb_code_handler_body(const char *code, const char *name);

/* 1 when the 1-based physical line of `code` holds an executable statement, i.e. the
   interpreter can stop on it (breakpoint / step). Declarations, block delimiters and
   bare labels answer 0, so the editor can refuse a breakpoint there. */
int vb_code_line_executable(const char *code, int line);

/* Carries breakpoints from a piece of code to the text that replaced it, the way VB6
   keeps a dot on its statement: lines inserted or removed above move the dot with the
   statement, Enter at the start of a line pushes it down, and a dot whose statement was
   deleted disappears. `lines` holds 1-based lines; the result is a malloc'd sorted array
   (unique, non-blank statements) with its length in out_count, or NULL when empty.
   Pure C: the code editor calls it on every text change and the CLI harness tests it
   without opening a window. */
int *vb_code_follow_breakpoints(const char *old_text, const char *new_text,
                                const int *lines, int count, int *out_count);

int vb_run_event(const char *code, const char *handler, const char *form_name, VbRuntimeHost *host);
int vb_form_run_event(VbForm *form, const char *handler, VbRuntimeHost *host);

#endif
