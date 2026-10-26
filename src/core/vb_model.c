#include "vb_model.h"
#include "vb_util.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const VbToolDef tools[] = {
    {"VB.Label", "Label1", "Label", 1200, 255, 1},
    {"VB.TextBox", "", "Text", 1215, 315, 1},
    {"VB.CommandButton", "Command1", "Command", 1215, 495, 1},
    {"VB.CheckBox", "Check1", "Check", 1215, 255, 1},
    {"VB.OptionButton", "Option1", "Option", 1215, 255, 1},
    {"VB.Frame", "Frame1", "Frame", 2415, 1815, 1},
    {"VB.ListBox", "", "List", 1215, 1035, 1},
    {"VB.ComboBox", "", "Combo", 1215, 315, 1},
    {"VB.Timer", "", "Timer", 0, 0, 0},
    {"VB.Image", "", "Image", 1215, 975, 1},
    {"VB.PictureBox", "", "Picture", 1815, 1215, 1},
    {"VB.Line", "", "Line", 1215, 75, 1},
    {"VB.Shape", "", "Shape", 1215, 975, 1},
    {"VB.HScrollBar", "", "HScroll", 1215, 255, 1},
    {"VB.VScrollBar", "", "VScroll", 255, 1215, 1},
    {"VB.DriveListBox", "", "Drive", 1815, 315, 1},
    {"VB.DirListBox", "", "Dir", 1815, 1215, 1},
    {"VB.FileListBox", "", "File", 1815, 1215, 1},
    {"VB.Data", "Data1", "Data", 2415, 360, 1},
    {"VB.DataGrid", "DataGrid1", "DataGrid", 3015, 1815, 1},
    {"VB.CommonDialog", "CommonDialog1", "Dialog", 0, 0, 0},
    {"VB.Menu", "", "Menu", 0, 0, 0}
};

static int tool_count(void)
{
    return (int)(sizeof(tools) / sizeof(tools[0]));
}

const VbToolDef *vb_tool_defs(int *count)
{
    if (count) *count = tool_count();
    return tools;
}

const VbToolDef *vb_tool_def(const char *type)
{
    int i;
    if (!type) return NULL;
    for (i = 0; i < tool_count(); i++) {
        if (vb_streq_ci(tools[i].type, type)) return &tools[i];
    }
    return NULL;
}

VbControl *vb_control_new(const char *type, const char *name, VbControl *parent)
{
    VbControl *control = (VbControl *)calloc(1, sizeof(VbControl));
    if (!control) return NULL;
    control->type = vb_strdup(type ? type : "VB.Label");
    control->name = vb_strdup(name ? name : "Control1");
    control->parent = parent;
    return control;
}

void vb_control_free(VbControl *control)
{
    int i;
    if (!control) return;
    for (i = 0; i < control->nprops; i++) {
        free(control->props[i].key);
        free(control->props[i].value);
    }
    free(control->props);
    for (i = 0; i < control->nchildren; i++) vb_control_free(control->children[i]);
    free(control->children);
    free(control->type);
    free(control->name);
    free(control);
}

void vb_control_add_child(VbControl *parent, VbControl *child)
{
    if (!parent || !child) return;
    if (parent->nchildren == parent->cchildren) {
        int ncap = parent->cchildren ? parent->cchildren * 2 : 8;
        VbControl **children = (VbControl **)realloc(parent->children, (size_t)ncap * sizeof(VbControl *));
        if (!children) return;
        parent->children = children;
        parent->cchildren = ncap;
    }
    child->parent = parent;
    parent->children[parent->nchildren++] = child;
}

int vb_control_child_index(VbControl *parent, VbControl *child)
{
    int i;
    if (!parent) return -1;
    for (i = 0; i < parent->nchildren; i++) {
        if (parent->children[i] == child) return i;
    }
    return -1;
}

void vb_control_remove_child(VbControl *parent, VbControl *child)
{
    int index;
    if (!parent || !child) return;
    index = vb_control_child_index(parent, child);
    if (index < 0) return;
    memmove(&parent->children[index], &parent->children[index + 1],
            (size_t)(parent->nchildren - index - 1) * sizeof(VbControl *));
    parent->nchildren--;
    child->parent = NULL;
}

int vb_control_move_to_front(VbControl *control)
{
    VbControl *parent;
    int index;
    int i;
    if (!control || !(parent = control->parent)) return 0;
    index = vb_control_child_index(parent, control);
    if (index < 0 || index == parent->nchildren - 1) return 0;
    for (i = index; i < parent->nchildren - 1; i++) {
        parent->children[i] = parent->children[i + 1];
    }
    parent->children[parent->nchildren - 1] = control;
    return 1;
}

int vb_control_move_to_back(VbControl *control)
{
    VbControl *parent;
    int index;
    int i;
    if (!control || !(parent = control->parent)) return 0;
    index = vb_control_child_index(parent, control);
    if (index <= 0) return 0;
    for (i = index; i > 0; i--) {
        parent->children[i] = parent->children[i - 1];
    }
    parent->children[0] = control;
    return 1;
}

static int control_type_takes_focus(const char *type)
{
    static const char *const tabbable[] = {
        "VB.TextBox", "VB.CommandButton", "VB.CheckBox", "VB.OptionButton",
        "VB.ComboBox", "VB.ListBox", "VB.DriveListBox", "VB.DirListBox",
        "VB.FileListBox", "VB.HScrollBar", "VB.VScrollBar", "VB.DataGrid", NULL
    };
    int i;
    if (!type) return 0;
    for (i = 0; tabbable[i]; i++) {
        if (vb_streq_ci(type, tabbable[i])) return 1;
    }
    return 0;
}

int vb_control_can_tab(const VbControl *control)
{
    if (!control) return 0;
    if (!control_type_takes_focus(control->type)) return 0;
    if (!vb_control_visible(control)) return 0;
    return vb_control_get_int(control, "TabStop", -1) != 0;
}

int vb_control_tab_index(const VbControl *control, int defval)
{
    return vb_control_get_int(control, "TabIndex", defval);
}

int vb_control_next_tab_index(VbControl *parent)
{
    int i;
    int best = -1;
    if (!parent) return 0;
    for (i = 0; i < parent->nchildren; i++) {
        int index = vb_control_get_int(parent->children[i], "TabIndex", -1);
        if (index > best) best = index;
    }
    return best < 0 ? 0 : best + 1;
}

void vb_control_set_tab_index(VbControl *control, int index)
{
    VbControl *parent;
    int own;
    int i;
    if (!control || !(parent = control->parent)) return;
    if (index < 0) index = 0;
    if (parent->nchildren > 0 && index > parent->nchildren - 1) index = parent->nchildren - 1;
    own = vb_control_get_int(control, "TabIndex", -1);
    /* VB6 keeps TabIndex unique: taking an occupied slot swaps the two controls. */
    for (i = 0; i < parent->nchildren; i++) {
        VbControl *other = parent->children[i];
        if (other == control) continue;
        if (vb_control_get_int(other, "TabIndex", -1) != index) continue;
        vb_control_set_int(other, "TabIndex", own >= 0 ? own : vb_control_next_tab_index(parent));
        break;
    }
    vb_control_set_int(control, "TabIndex", index);
}

static int tab_rank(const VbControl *control)
{
    int index = vb_control_get_int(control, "TabIndex", -1);
    return index < 0 ? 0x3FFFFFFF : index;
}

int vb_control_collect_tab_order(VbControl *parent, VbControl **out, int max)
{
    int i;
    int count = 0;
    if (!parent || !out || max <= 0) return 0;
    for (i = 0; i < parent->nchildren && count < max; i++) {
        VbControl *child = parent->children[i];
        if (!vb_control_can_tab(child)) continue;
        out[count++] = child;
    }
    /* Stable insertion sort: z-order breaks ties so the dialog always matches VB6. */
    for (i = 1; i < count; i++) {
        VbControl *key = out[i];
        int rank = tab_rank(key);
        int j = i - 1;
        while (j >= 0 && tab_rank(out[j]) > rank) {
            out[j + 1] = out[j];
            j--;
        }
        out[j + 1] = key;
    }
    return count;
}

int vb_control_sorted_children(VbControl *parent, VbControl **out, int max)
{
    int i;
    int count = 0;
    if (!parent || !out || max <= 0) return 0;
    for (i = 0; i < parent->nchildren && count < max; i++) out[count++] = parent->children[i];
    for (i = 1; i < count; i++) {
        VbControl *key = out[i];
        int rank = tab_rank(key);
        int j = i - 1;
        while (j >= 0 && tab_rank(out[j]) > rank) {
            out[j + 1] = out[j];
            j--;
        }
        out[j + 1] = key;
    }
    return count;
}

void vb_control_apply_tab_order(VbControl *parent, VbControl **ordered, int count)
{
    int i;
    if (!parent || !ordered) return;
    for (i = 0; i < count; i++) {
        if (!ordered[i] || ordered[i]->parent != parent) continue;
        vb_control_set_int(ordered[i], "TabIndex", i);
    }
}

const char *vb_control_get(const VbControl *control, const char *key)
{
    int i;
    if (!control || !key) return NULL;
    for (i = 0; i < control->nprops; i++) {
        if (vb_streq_ci(control->props[i].key, key)) return control->props[i].value;
    }
    return NULL;
}

int vb_control_has(const VbControl *control, const char *key)
{
    return vb_control_get(control, key) != NULL;
}

int vb_control_get_int(const VbControl *control, const char *key, int defval)
{
    const char *value = vb_control_get(control, key);
    if (!value) return defval;
    return vb_parse_int(value, defval);
}

void vb_control_set(VbControl *control, const char *key, const char *value)
{
    int i;
    if (!control || !key) return;
    for (i = 0; i < control->nprops; i++) {
        if (vb_streq_ci(control->props[i].key, key)) {
            free(control->props[i].value);
            control->props[i].value = vb_strdup(value ? value : "");
            return;
        }
    }
    if (control->nprops == control->cprops) {
        int ncap = control->cprops ? control->cprops * 2 : 8;
        VbProp *props = (VbProp *)realloc(control->props, (size_t)ncap * sizeof(VbProp));
        if (!props) return;
        control->props = props;
        control->cprops = ncap;
    }
    control->props[control->nprops].key = vb_strdup(key);
    control->props[control->nprops].value = vb_strdup(value ? value : "");
    control->nprops++;
}

void vb_control_set_int(VbControl *control, const char *key, int value)
{
    char *text = vb_format_int(value);
    vb_control_set(control, key, text);
    free(text);
}

void vb_control_remove(VbControl *control, const char *key)
{
    int i;
    if (!control || !key) return;
    for (i = 0; i < control->nprops; i++) {
        if (vb_streq_ci(control->props[i].key, key)) {
            free(control->props[i].key);
            free(control->props[i].value);
            memmove(&control->props[i], &control->props[i + 1],
                    (size_t)(control->nprops - i - 1) * sizeof(VbProp));
            control->nprops--;
            return;
        }
    }
}

int vb_control_is_container(const char *type)
{
    if (!type) return 0;
    return vb_streq_ci(type, "VB.Form") || vb_streq_ci(type, "VB.Frame") ||
           vb_streq_ci(type, "VB.PictureBox");
}

int vb_control_visible(const VbControl *control)
{
    const char *type;
    if (!control) return 0;
    type = control->type;
    /* Non-visual components live in the component tray, not on the form. */
    if (vb_streq_ci(type, "VB.Timer") || vb_streq_ci(type, "VB.Menu") ||
        vb_streq_ci(type, "VB.CommonDialog")) return 0;
    return vb_control_get_int(control, "Visible", -1) != 0;
}

const char *vb_control_caption(const VbControl *control)
{
    const char *value;
    if (!control) return "";
    value = vb_control_get(control, "Caption");
    if (value) return value;
    value = vb_control_get(control, "Text");
    if (value) return value;
    return control->name;
}

VbForm *vb_form_new(const char *name)
{
    VbForm *form = (VbForm *)calloc(1, sizeof(VbForm));
    if (!form) return NULL;
    form->root = vb_control_new("VB.Form", name ? name : "Form1", NULL);
    vb_control_set_int(form->root, "ClientWidth", 4680);
    vb_control_set_int(form->root, "ClientHeight", 3090);
    vb_control_set(form->root, "Caption", name ? name : "Form1");
    form->code = vb_strdup("Attribute VB_Name = \"");
    if (form->code) {
        VbBuf buf;
        vb_buf_init(&buf);
        vb_buf_append(&buf, "Attribute VB_Name = \"");
        vb_buf_append(&buf, name ? name : "Form1");
        vb_buf_append(&buf, "\"\nAttribute VB_GlobalNameSpace = False\nAttribute VB_Creatable = False\n"
                            "Attribute VB_PredeclaredId = True\nAttribute VB_Exposed = False\n"
                            "Option Explicit\n");
        free(form->code);
        form->code = vb_buf_take(&buf);
    }
    return form;
}

void vb_form_free(VbForm *form)
{
    if (!form) return;
    vb_control_free(form->root);
    free(form->path);
    free(form->code);
    free(form->breakpoints);
    free(form);
}

int vb_form_has_breakpoint(const VbForm *form, int line)
{
    int i;
    if (!form) return 0;
    for (i = 0; i < form->nbreakpoints; i++) {
        if (form->breakpoints[i] == line) return 1;
        if (form->breakpoints[i] > line) break;
    }
    return 0;
}

int vb_form_set_breakpoint(VbForm *form, int line, int on)
{
    int i;
    int at = -1;
    if (!form || line <= 0) return 0;
    for (i = 0; i < form->nbreakpoints; i++) {
        if (form->breakpoints[i] == line) { at = i; break; }
        if (form->breakpoints[i] > line) { at = i; break; }
    }
    if (on) {
        if (at >= 0 && form->breakpoints[at] == line) return 0;
        if (form->nbreakpoints == form->cbreakpoints) {
            int ncap = form->cbreakpoints ? form->cbreakpoints * 2 : 8;
            int *items = (int *)realloc(form->breakpoints, (size_t)ncap * sizeof(int));
            if (!items) return 0;
            form->breakpoints = items;
            form->cbreakpoints = ncap;
        }
        if (at < 0) at = form->nbreakpoints;
        memmove(form->breakpoints + at + 1, form->breakpoints + at,
                (size_t)(form->nbreakpoints - at) * sizeof(int));
        form->breakpoints[at] = line;
        form->nbreakpoints++;
        return 1;
    }
    if (at < 0 || form->breakpoints[at] != line) return 0;
    memmove(form->breakpoints + at, form->breakpoints + at + 1,
            (size_t)(form->nbreakpoints - at - 1) * sizeof(int));
    form->nbreakpoints--;
    return 1;
}

void vb_form_clear_breakpoints(VbForm *form)
{
    if (!form) return;
    form->nbreakpoints = 0;
}

int vb_form_breakpoint_count(const VbForm *form)
{
    return form ? form->nbreakpoints : 0;
}

int vb_form_breakpoint_at(const VbForm *form, int index)
{
    if (!form || index < 0 || index >= form->nbreakpoints) return 0;
    return form->breakpoints[index];
}

const char *vb_form_name(const VbForm *form)
{
    return form && form->root ? form->root->name : "";
}

const char *vb_form_caption(const VbForm *form)
{
    return form && form->root ? vb_control_caption(form->root) : "";
}

int vb_form_client_width(const VbForm *form)
{
    return form && form->root ? vb_control_get_int(form->root, "ClientWidth", 4680) : 4680;
}

int vb_form_client_height(const VbForm *form)
{
    return form && form->root ? vb_control_get_int(form->root, "ClientHeight", 3090) : 3090;
}

char *vb_next_control_name(VbForm *form, const char *type)
{
    const VbToolDef *def = vb_tool_def(type);
    const char *prefix = def ? def->prefix : "Control";
    int index;
    if (!form) return vb_strdup("Control1");
    for (index = 1; index < 10000; index++) {
        char buffer[128];
        VbControl *existing;
        snprintf(buffer, sizeof(buffer), "%s%d", prefix, index);
        existing = vb_form_find_control(form, buffer);
        if (!existing) return vb_strdup(buffer);
    }
    return vb_strdup("Control");
}

VbControl *vb_form_find_control(VbForm *form, const char *name)
{
    VbControl *stack[512];
    int top = 0;
    if (!form || !form->root || !name) return NULL;
    stack[top++] = form->root;
    while (top > 0) {
        VbControl *control = stack[--top];
        int i;
        if (vb_streq_ci(control->name, name)) return control;
        for (i = control->nchildren - 1; i >= 0 && top < 512; i--) {
            stack[top++] = control->children[i];
        }
    }
    return NULL;
}

static void set_bool(VbControl *control, const char *key, int on)
{
    vb_control_set(control, key, on ? "-1" : "0");
}

/* VB6 fonts default to MS Sans Serif 9 on a 96 dpi desktop; the property panel shows
   the same values when a form omits the Font block. */
static void apply_default_font(VbControl *control)
{
    vb_control_set(control, "Font.Name", "MS Sans Serif");
    vb_control_set(control, "Font.Size", "9");
    vb_control_set(control, "Font.Charset", "0");
    vb_control_set(control, "Font.Weight", "400");
    set_bool(control, "Font.Underline", 0);
    set_bool(control, "Font.Italic", 0);
    set_bool(control, "Font.Strikethrough", 0);
}

/* Properties a freshly dropped control carries in VB6: the ones the designer, the
   runtime and the Properties window are expected to act on. Values follow VB6 defaults
   (system colors as &H800000xx&, True as -1). */
static void apply_control_defaults(VbControl *control, const VbToolDef *def)
{
    const char *type = def->type;
    int takes_focus = control_type_takes_focus(type);

    if (vb_streq_ci(type, "VB.Menu")) return;
    set_bool(control, "Enabled", 1);
    if (!vb_streq_ci(type, "VB.Timer") && !vb_streq_ci(type, "VB.CommonDialog")) {
        set_bool(control, "Visible", 1);
    }
    if (takes_focus) set_bool(control, "TabStop", 1);

    if (vb_streq_ci(type, "VB.Timer")) {
        vb_control_set_int(control, "Interval", 0);
        return;
    }
    if (vb_streq_ci(type, "VB.CommonDialog")) {
        vb_control_set_int(control, "Action", 0);
        set_bool(control, "CancelError", 0);
        vb_control_set(control, "DialogTitle", "");
        vb_control_set(control, "FileName", "");
        vb_control_set(control, "Filter", "");
        vb_control_set_int(control, "FilterIndex", 1);
        vb_control_set_int(control, "Flags", 0);
        vb_control_set_int(control, "Color", 0);
        return;
    }
    if (vb_streq_ci(type, "VB.Line")) {
        vb_control_set_int(control, "BorderStyle", 1);
        vb_control_set_int(control, "BorderWidth", 1);
        vb_control_set_int(control, "X1", 0);
        vb_control_set_int(control, "Y1", 0);
        vb_control_set_int(control, "X2", def->width);
        vb_control_set_int(control, "Y2", 0);
        return;
    }
    if (vb_streq_ci(type, "VB.Shape")) {
        vb_control_set_int(control, "Shape", 0);
        vb_control_set_int(control, "BorderStyle", 1);
        vb_control_set_int(control, "BorderWidth", 1);
        vb_control_set_int(control, "FillStyle", 1);
        vb_control_set(control, "FillColor", "&H8000000F&");
        return;
    }
    if (vb_streq_ci(type, "VB.Image")) {
        set_bool(control, "Stretch", 0);
        vb_control_set_int(control, "BorderStyle", 0);
        return;
    }

    apply_default_font(control);
    vb_control_set(control, "ForeColor", "&H80000012&");

    if (vb_streq_ci(type, "VB.Label")) {
        vb_control_set(control, "Caption", def->caption);
        set_bool(control, "AutoSize", 1);
        set_bool(control, "WordWrap", 1);
        vb_control_set_int(control, "BackStyle", 0);
        vb_control_set_int(control, "BorderStyle", 0);
        vb_control_set_int(control, "Alignment", 0);
        vb_control_set(control, "BackColor", "&H8000000F&");
        return;
    }
    if (vb_streq_ci(type, "VB.TextBox")) {
        vb_control_set(control, "Text", "");
        vb_control_set(control, "BackColor", "&H80000005&");
        vb_control_set_int(control, "BorderStyle", 0);
        set_bool(control, "MultiLine", 0);
        set_bool(control, "Locked", 0);
        vb_control_set(control, "PasswordChar", "");
        vb_control_set_int(control, "MaxLength", 0);
        vb_control_set_int(control, "ScrollBars", 0);
        vb_control_set_int(control, "Alignment", 0);
        return;
    }
    if (vb_streq_ci(type, "VB.CommandButton")) {
        vb_control_set(control, "Caption", def->caption);
        vb_control_set(control, "BackColor", "&H8000000F&");
        set_bool(control, "Default", 0);
        set_bool(control, "Cancel", 0);
        vb_control_set_int(control, "Style", 0);
        return;
    }
    if (vb_streq_ci(type, "VB.CheckBox") || vb_streq_ci(type, "VB.OptionButton")) {
        vb_control_set(control, "Caption", def->caption);
        vb_control_set_int(control, "Value", 0);
        vb_control_set_int(control, "Style", 0);
        vb_control_set(control, "BackColor", "&H8000000F&");
        return;
    }
    if (vb_streq_ci(type, "VB.Frame") || vb_streq_ci(type, "VB.PictureBox")) {
        if (vb_streq_ci(type, "VB.Frame")) vb_control_set(control, "Caption", def->caption);
        vb_control_set(control, "BackColor", "&H8000000F&");
        vb_control_set_int(control, "BorderStyle", 0);
        if (vb_streq_ci(type, "VB.PictureBox")) {
            set_bool(control, "AutoRedraw", 0);
            set_bool(control, "AutoSize", 0);
        }
        /* Containers own their client coordinate system. */
        return;
    }
    if (vb_streq_ci(type, "VB.ListBox") || vb_streq_ci(type, "VB.ComboBox")) {
        vb_control_set(control, "Text", "");
        vb_control_set(control, "BackColor", "&H80000005&");
        vb_control_set_int(control, "Style", 0);
        set_bool(control, "Sorted", 0);
        if (vb_streq_ci(type, "VB.ListBox")) {
            set_bool(control, "IntegralHeight", 1);
            vb_control_set_int(control, "Columns", 0);
        }
        return;
    }
    if (vb_streq_ci(type, "VB.DriveListBox") || vb_streq_ci(type, "VB.DirListBox") ||
        vb_streq_ci(type, "VB.FileListBox")) {
        vb_control_set(control, "BackColor", "&H80000005&");
        vb_control_set(control, "Path", "");
        if (vb_streq_ci(type, "VB.FileListBox")) {
            vb_control_set(control, "Pattern", "*.*");
            vb_control_set(control, "FileName", "");
        }
        return;
    }
    if (vb_streq_ci(type, "VB.HScrollBar") || vb_streq_ci(type, "VB.VScrollBar")) {
        vb_control_set(control, "BackColor", "&H8000000F&");
        vb_control_set_int(control, "Min", 0);
        vb_control_set_int(control, "Max", 100);
        vb_control_set_int(control, "Value", 0);
        vb_control_set_int(control, "LargeChange", 20);
        vb_control_set_int(control, "SmallChange", 1);
        return;
    }
    if (vb_streq_ci(type, "VB.Data")) {
        vb_control_set(control, "Caption", def->caption);
        vb_control_set(control, "BackColor", "&H8000000F&");
        vb_control_set(control, "Connect", "");
        vb_control_set(control, "DatabaseName", "");
        vb_control_set(control, "RecordSource", "");
        vb_control_set_int(control, "RecordsetType", 0);
        vb_control_set_int(control, "BOFAction", 0);
        vb_control_set_int(control, "EOFAction", 0);
        set_bool(control, "ReadOnly", 0);
        set_bool(control, "Exclusive", 0);
        vb_control_set_int(control, "Options", 0);
        return;
    }
    if (vb_streq_ci(type, "VB.DataGrid")) {
        /* VB6's DataGrid has no Caption: the header row is the column captions. */
        vb_control_set(control, "BackColor", "&H80000005&");
        vb_control_set(control, "DataSource", "");
        set_bool(control, "AllowAddNew", 0);
        set_bool(control, "AllowDelete", 0);
        set_bool(control, "AllowUpdate", 1);
        set_bool(control, "AllowRowSizing", 1);
        set_bool(control, "AllowColSizing", 0);
        set_bool(control, "ColumnHeaders", 1);
        vb_control_set_int(control, "DefColWidth", 1275); /* ~85 pt per column */
        vb_control_set_int(control, "RowHeight", 255);
        return;
    }
    vb_control_set(control, "Caption", def->caption);
}

VbControl *vb_control_new_from_tool(const VbToolDef *def, const char *name)
{
    VbControl *control;
    if (!def) return NULL;
    control = vb_control_new(def->type, name ? name : def->caption, NULL);
    if (!control) return NULL;
    vb_control_set_int(control, "Width", def->width);
    vb_control_set_int(control, "Height", def->height);
    vb_control_set_int(control, "Left", 0);
    vb_control_set_int(control, "Top", 0);
    apply_control_defaults(control, def);
    return control;
}

VbControl *vb_form_add_control(VbForm *form, VbControl *parent, const char *type,
                               int left, int top, int width, int height)
{
    const VbToolDef *def;
    VbControl *control;
    char *name;
    if (!form || !form->root) return NULL;
    def = vb_tool_def(type);
    if (!def) return NULL;
    name = vb_next_control_name(form, type);
    control = vb_control_new_from_tool(def, name);
    free(name);
    if (!control) return NULL;
    vb_control_set_int(control, "Left", left);
    vb_control_set_int(control, "Top", top);
    vb_control_set_int(control, "Width", width > 0 ? width : def->width);
    vb_control_set_int(control, "Height", height > 0 ? height : def->height);
    if (!parent || !vb_control_is_container(parent->type)) parent = form->root;
    vb_control_add_child(parent, control);
    /* New controls go in front and take the next free TabIndex, as in VB6. Only
       controls that VB6 exposes a TabIndex for (focusable ones and labels) get one. */
    if (control_type_takes_focus(control->type) || vb_streq_ci(control->type, "VB.Label")) {
        vb_control_set_int(control, "TabIndex", vb_control_next_tab_index(parent));
    }
    form->dirty = 1;
    return control;
}

VbProject *vb_project_new(void)
{
    return (VbProject *)calloc(1, sizeof(VbProject));
}

void vb_project_free(VbProject *project)
{
    int i;
    if (!project) return;
    for (i = 0; i < project->nitems; i++) {
        free(project->items[i].name);
        free(project->items[i].file);
        if (project->items[i].form) vb_form_free(project->items[i].form);
    }
    free(project->items);
    free(project->path);
    free(project->dir);
    free(project->name);
    free(project->startup);
    free(project);
}

VbItem *vb_project_add_item(VbProject *project, VbItemKind kind, const char *name, const char *file)
{
    VbItem *item;
    if (!project) return NULL;
    if (project->nitems == project->citems) {
        int ncap = project->citems ? project->citems * 2 : 16;
        VbItem *items = (VbItem *)realloc(project->items, (size_t)ncap * sizeof(VbItem));
        if (!items) return NULL;
        project->items = items;
        project->citems = ncap;
    }
    item = &project->items[project->nitems++];
    memset(item, 0, sizeof(*item));
    item->kind = kind;
    item->name = vb_strdup(name ? name : "");
    item->file = vb_strdup(file ? file : "");
    return item;
}

VbItem *vb_project_find_item(VbProject *project, const char *name)
{
    int i;
    if (!project || !name) return NULL;
    for (i = 0; i < project->nitems; i++) {
        if (vb_streq_ci(project->items[i].name, name)) return &project->items[i];
    }
    return NULL;
}

VbItem *vb_project_find_file(VbProject *project, const char *file)
{
    int i;
    if (!project || !file) return NULL;
    for (i = 0; i < project->nitems; i++) {
        if (vb_streq_ci(project->items[i].file, file)) return &project->items[i];
    }
    return NULL;
}

int vb_color_from_value(const char *value, int *r, int *g, int *b)
{
    unsigned long color = 0;
    const char *p;
    if (!value) return 0;
    p = value;
    while (*p && isspace((unsigned char)*p)) p++;
    if (p[0] == '&' && (p[1] == 'H' || p[1] == 'h')) {
        color = strtoul(p + 2, NULL, 16);
    } else {
        color = strtoul(p, NULL, 10);
    }
    if (r) *r = (int)(color & 0xFF);
    if (g) *g = (int)((color >> 8) & 0xFF);
    if (b) *b = (int)((color >> 16) & 0xFF);
    return 1;
}

int vb_value_is_quoted(const char *raw)
{
    size_t len;
    if (!raw) return 0;
    len = strlen(raw);
    return len >= 2 && raw[0] == '"' && raw[len - 1] == '"';
}

char *vb_value_unquote(const char *raw)
{
    VbBuf buf;
    size_t i;
    size_t len;
    if (!raw) return vb_strdup("");
    if (!vb_value_is_quoted(raw)) return vb_strdup(raw);
    len = strlen(raw);
    vb_buf_init(&buf);
    for (i = 1; i + 1 < len; i++) {
        if (raw[i] == '"' && i + 2 < len && raw[i + 1] == '"') {
            vb_buf_appendchar(&buf, '"');
            i++;
        } else {
            vb_buf_appendchar(&buf, raw[i]);
        }
    }
    return vb_buf_take(&buf);
}

char *vb_value_quote(const char *text)
{
    VbBuf buf;
    size_t i;
    vb_buf_init(&buf);
    vb_buf_appendchar(&buf, '"');
    if (text) {
        for (i = 0; text[i]; i++) {
            if (text[i] == '"') vb_buf_appendchar(&buf, '"');
            vb_buf_appendchar(&buf, text[i]);
        }
    }
    vb_buf_appendchar(&buf, '"');
    return vb_buf_take(&buf);
}

static const char *const string_props[] = {
    "Caption", "Text", "Tag", "ToolTipText", "PasswordChar", "LinkTopic",
    "LinkItem", "LinkMode", "WhatsThisHelpID", "Name", "Key", "FileName",
    "Path", "Pattern", "Filter", "Font.Name", "Version",
    "Connect", "DatabaseName", "RecordSource", "DataSource", "DialogTitle", "DefaultExt",
    "Comment", "Title", "HelpFile", "ExeName32", "Command32", "VersionCompanyName",
    "VersionProductName", "VersionLegalCopyright", "VersionLegalTrademarks",
    "VersionComments", "VersionFileDescription", NULL
};

/* Properties the Properties window shows as True/False and the interpreter treats as
   booleans (VB6 stores True as -1). */
static const char *const bool_props[] = {
    "Visible", "Enabled", "TabStop", "Locked", "MultiLine", "Default", "Cancel",
    "AutoSize", "AutoRedraw", "WordWrap", "Stretch", "Sorted", "IntegralHeight",
    "MinButton", "MaxButton", "ReadOnly", "Exclusive", "CancelError",
    "AllowAddNew", "AllowDelete", "AllowUpdate", "AllowRowSizing", "AllowColSizing",
    "ColumnHeaders", "UseMnemonic", "AutoSize", NULL
};

int vb_prop_is_boolean(const char *key)
{
    int i;
    const char *dot;
    if (!key) return 0;
    for (i = 0; bool_props[i]; i++) {
        if (vb_streq_ci(key, bool_props[i])) return 1;
    }
    dot = strrchr(key, '.');
    if (dot) return vb_prop_is_boolean(dot + 1);
    return 0;
}

int vb_prop_is_string(const char *key)
{
    int i;
    const char *dot;
    if (!key) return 0;
    for (i = 0; string_props[i]; i++) {
        if (vb_streq_ci(key, string_props[i])) return 1;
    }
    dot = strrchr(key, '.');
    if (dot) return vb_prop_is_string(dot + 1);
    return 0;
}

int vb_value_is_numeric(const char *text)
{
    const char *p;
    char *end = NULL;
    if (!text || !*text) return 0;
    if (vb_value_is_quoted(text)) return 0;
    p = text;
    while (*p && isspace((unsigned char)*p)) p++;
    if (*p == '&') {
        strtoul(p + 2, &end, 16);
        return end != NULL && (*end == '\0' || *end == '&');
    }
    strtod(p, &end);
    return end != NULL && end != p && (*end == '\0' || isspace((unsigned char)*end));
}

char *vb_control_get_display(const VbControl *control, const char *key)
{
    const char *raw = vb_control_get(control, key);
    if (!raw) return NULL;
    return vb_value_unquote(raw);
}

void vb_control_set_display(VbControl *control, const char *key, const char *text)
{
    const char *old = vb_control_get(control, key);
    char *encoded;
    if (!control || !key) return;
    if (vb_value_is_quoted(old)) {
        encoded = vb_value_quote(text);
    } else if (old && vb_value_is_numeric(old)) {
        encoded = vb_strdup(text ? text : "");
    } else if (vb_prop_is_string(key)) {
        encoded = vb_value_quote(text);
    } else {
        encoded = vb_strdup(text ? text : "");
    }
    vb_control_set(control, key, encoded);
    free(encoded);
}
