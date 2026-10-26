#ifndef VB_MODEL_H
#define VB_MODEL_H

#include <stddef.h>

#define VB_TWIPS_PER_PIXEL 15

typedef struct {
    char *key;
    char *value;
} VbProp;

typedef struct VbControl {
    char *type;
    char *name;
    VbProp *props;
    int nprops;
    int cprops;
    struct VbControl *parent;
    struct VbControl **children;
    int nchildren;
    int cchildren;
    int selected;
} VbControl;

typedef struct {
    char *path;
    VbControl *root;
    char *code;
    int dirty;
    /* Breakpoints: 1-based lines of `code`, kept sorted. They survive a save because
       the .frm gets a trailing comment ("'@VB6CloneBreakpoints: 12,18"), which VB6
       reads as a comment; vb_form_load strips it back out of `code`. */
    int *breakpoints;
    int nbreakpoints;
    int cbreakpoints;
} VbForm;

typedef enum {
    VB_ITEM_FORM = 0,
    VB_ITEM_MODULE,
    VB_ITEM_CLASS,
    VB_ITEM_USERCONTROL,
    VB_ITEM_OTHER
} VbItemKind;

typedef struct {
    VbItemKind kind;
    char kind_key[24];
    char *name;
    char *file;
    VbForm *form;
} VbItem;

typedef struct {
    char *path;
    char *dir;
    char *name;
    char *startup;
    VbItem *items;
    int nitems;
    int citems;
} VbProject;

typedef struct {
    const char *type;
    const char *caption;
    const char *prefix;
    int width;
    int height;
    int visible;
} VbToolDef;

VbControl *vb_control_new(const char *type, const char *name, VbControl *parent);
void vb_control_free(VbControl *control);
void vb_control_add_child(VbControl *parent, VbControl *child);
const char *vb_control_get(const VbControl *control, const char *key);
int vb_control_get_int(const VbControl *control, const char *key, int defval);
void vb_control_set(VbControl *control, const char *key, const char *value);
void vb_control_set_int(VbControl *control, const char *key, int value);
void vb_control_remove(VbControl *control, const char *key);
int vb_control_has(const VbControl *control, const char *key);
int vb_control_child_index(VbControl *parent, VbControl *child);
void vb_control_remove_child(VbControl *parent, VbControl *child);

/* Z-order. Sibling order is paint order: children[0] is the back-most control and
   later siblings are painted on top, which is also the order written to the .frm. */
int vb_control_move_to_front(VbControl *control);
int vb_control_move_to_back(VbControl *control);

/* Tab order. TabIndex is unique per container; the Tab Order dialog renumbers it 0..n-1. */
int vb_control_can_tab(const VbControl *control);
int vb_control_tab_index(const VbControl *control, int defval);
int vb_control_next_tab_index(VbControl *parent);
void vb_control_set_tab_index(VbControl *control, int index);
int vb_control_collect_tab_order(VbControl *parent, VbControl **out, int max);
void vb_control_apply_tab_order(VbControl *parent, VbControl **ordered, int count);
/* Every child ordered by TabIndex (missing indices last, z-order keeps ties). */
int vb_control_sorted_children(VbControl *parent, VbControl **out, int max);
int vb_control_is_container(const char *type);
int vb_control_visible(const VbControl *control);
const char *vb_control_caption(const VbControl *control);

VbForm *vb_form_new(const char *name);
void vb_form_free(VbForm *form);
const char *vb_form_name(const VbForm *form);
const char *vb_form_caption(const VbForm *form);
int vb_form_client_width(const VbForm *form);
int vb_form_client_height(const VbForm *form);
VbControl *vb_form_add_control(VbForm *form, VbControl *parent, const char *type,
                               int left, int top, int width, int height);
char *vb_next_control_name(VbForm *form, const char *type);
VbControl *vb_form_find_control(VbForm *form, const char *name);

/* Code breakpoints (1-based physical lines). Returns 1 when the form changed. */
int vb_form_set_breakpoint(VbForm *form, int line, int on);
int vb_form_has_breakpoint(const VbForm *form, int line);
void vb_form_clear_breakpoints(VbForm *form);
int vb_form_breakpoint_count(const VbForm *form);
int vb_form_breakpoint_at(const VbForm *form, int index);
#define VB_BREAKPOINT_MARKER "'@VB6CloneBreakpoints"

VbProject *vb_project_new(void);
void vb_project_free(VbProject *project);
VbItem *vb_project_add_item(VbProject *project, VbItemKind kind, const char *name, const char *file);
VbItem *vb_project_find_item(VbProject *project, const char *name);
VbItem *vb_project_find_file(VbProject *project, const char *file);

const VbToolDef *vb_tool_defs(int *count);
const VbToolDef *vb_tool_def(const char *type);
VbControl *vb_control_new_from_tool(const VbToolDef *def, const char *name);

int vb_color_from_value(const char *value, int *r, int *g, int *b);
int vb_value_is_quoted(const char *raw);
char *vb_value_unquote(const char *raw);
char *vb_value_quote(const char *text);
int vb_prop_is_string(const char *key);
/* 1 for VB6 boolean properties (serialized as -1/0, shown as True/False). */
int vb_prop_is_boolean(const char *key);
int vb_value_is_numeric(const char *text);
char *vb_control_get_display(const VbControl *control, const char *key);
void vb_control_set_display(VbControl *control, const char *key, const char *text);

#endif
