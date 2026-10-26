#include "vb_code.h"
#include "vb_util.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <time.h>

static const char *const keywords[] = {
    "Private", "Public", "Friend", "Static", "Sub", "Function", "Property",
    "Get", "Let", "Set", "End", "If", "Then", "Else", "ElseIf", "For", "Each",
    "To", "Step", "Next", "Do", "Loop", "While", "Wend", "Until", "Select",
    "Case", "Is", "With", "Dim", "ReDim", "Preserve", "As", "New", "Type",
    "Enum", "Const", "Declare", "Lib", "Alias", "ByVal", "ByRef", "Optional",
    "ParamArray", "Exit", "GoTo", "GoSub", "Return", "Call", "On", "Error",
    "Resume", "Err", "RaiseEvent", "Event", "Implements", "Option", "Explicit",
    "Base", "Compare", "Text", "Binary", "Me", "MyBase", "MyClass", "Nothing",
    "Null", "Empty", "True", "False", "And", "Or", "Not", "Xor", "Eqv", "Imp",
    "Mod", "Like", "In", "Attribute", "DefInt", "DefLng", "DefStr", "DefBool",
    "DefObj", "DefVar", "Load", "Unload", "Print", "Write", "Open", "Close",
    "Input", "Line", "Get", "Put", "Lock", "Unlock", "Seek", "Width", "Name",
    "Kill", "MkDir", "RmDir", "ChDir", "ChDrive", "FileCopy", "Dir", NULL
};

static const char *const types[] = {
    "Integer", "Long", "Single", "Double", "String", "Boolean", "Byte",
    "Currency", "Date", "Variant", "Object", "Decimal", "Any", "Form",
    "Control", "Collection", NULL
};

static const char *const builtins[] = {
    "MsgBox", "InputBox", "Len", "Trim", "LTrim", "RTrim", "Mid", "Left",
    "Right", "UCase", "LCase", "CStr", "CInt", "CLng", "CDbl", "CSng", "CBool",
    "CByte", "CCur", "CDate", "Val", "Asc", "Chr", "Format", "Now", "Date",
    "Time", "IsNull", "IsEmpty", "IsNumeric", "IsObject", "IsMissing", "Shell",
    "DoEvents", "Beep", "Randomize", "Rnd", "Abs", "Sgn", "Int", "Fix", "Round",
    "Sqr", "Sin", "Cos", "Tan", "Log", "Exp", "Array", "Split", "Join",
    "Replace", "InStr", "InStrRev", "Space", "Tab", "Spc", "Choose", "IIf",
    "Switch", "TypeName", "VarType", "CreateObject", "GetObject", "Environ",
    "Command", "CurDir", "AppActivate", "SendKeys", "SavePicture", "LoadPicture",
    "Load", "Unload", NULL
};

static void push_span(VbSpanList *out, size_t start, size_t len, int cls)
{
    if (len == 0) return;
    if (out->count == out->cap) {
        size_t ncap = out->cap ? out->cap * 2 : 128;
        VbSpan *items = (VbSpan *)realloc(out->items, ncap * sizeof(VbSpan));
        if (!items) return;
        out->items = items;
        out->cap = ncap;
    }
    out->items[out->count].start = start;
    out->items[out->count].len = len;
    out->items[out->count].cls = cls;
    out->count++;
}

void vb_spanlist_init(VbSpanList *list)
{
    list->items = NULL;
    list->count = 0;
    list->cap = 0;
}

void vb_spanlist_free(VbSpanList *list)
{
    free(list->items);
    list->items = NULL;
    list->count = 0;
    list->cap = 0;
}

static int in_list(const char *word, size_t len, const char *const *list)
{
    int i;
    for (i = 0; list[i]; i++) {
        const char *entry = list[i];
        size_t elen = strlen(entry);
        if (elen == len && vb_streq_ci(word, entry)) return 1;
    }
    return 0;
}

static int is_constant_word(const char *word, size_t len)
{
    static const char *const constants[] = {
        "vbCrLf", "vbCr", "vbLf", "vbTab", "vbNullString", "vbNullChar",
        "vbBack", "vbFormFeed", "vbVerticalTab", "vbOKOnly", "vbOKCancel",
        "vbYesNo", "vbYesNoCancel", "vbAbortRetryIgnore", "vbRetryCancel",
        "vbCritical", "vbQuestion", "vbExclamation", "vbInformation",
        "vbDefaultButton1", "vbDefaultButton2", "vbDefaultButton3",
        "vbDefaultButton4", "vbYes", "vbNo", "vbOK", "vbCancel", "vbAbort",
        "vbRetry", "vbIgnore", "vbModal", "vbModeless", "vbNormal",
        "vbMinimized", "vbMaximized", "vbHide", "vbUnchecked", "vbChecked",
        "vbGrayed", "vbBlack", "vbWhite", "vbRed", "vbGreen", "vbBlue",
        "vbYellow", "vbMagenta", "vbCyan", "vbTextCompare", "vbBinaryCompare",
        "vbApplicationModal", "vbSystemModal", "vbLeftButton", "vbRightButton",
        "vbMiddleButton", "vbObjectError", NULL
    };
    if (in_list(word, len, constants)) return 1;
    if (len > 2 && (word[0] == 'v' || word[0] == 'V') && (word[1] == 'b' || word[1] == 'B') &&
        isupper((unsigned char)word[2])) return 1;
    if (len > 2 && (word[0] == 'a' || word[0] == 'A') && (word[1] == 'd' || word[1] == 'D') &&
        isupper((unsigned char)word[2])) return 1;
    return 0;
}

void vb_code_highlight(const char *text, size_t len, VbSpanList *out)
{
    size_t i = 0;
    int line_start = 1;
    if (!text || !out) return;

    while (i < len) {
        unsigned char c = (unsigned char)text[i];
        if (c == '\n') {
            line_start = 1;
            i++;
            continue;
        }
        if (isspace(c)) {
            i++;
            continue;
        }
        if (c == '\'') {
            size_t start = i;
            while (i < len && text[i] != '\n') i++;
            push_span(out, start, i - start, VB_TOK_COMMENT);
            line_start = 0;
            continue;
        }
        if (line_start && len - i >= 3 && vb_starts_ci(text + i, "Rem") &&
            (i + 3 == len || isspace((unsigned char)text[i + 3]) || text[i + 3] == '\'')) {
            size_t start = i;
            while (i < len && text[i] != '\n') i++;
            push_span(out, start, i - start, VB_TOK_COMMENT);
            line_start = 0;
            continue;
        }
        if (c == '"') {
            size_t start = i;
            i++;
            while (i < len) {
                if (text[i] == '"' && i + 1 < len && text[i + 1] == '"') {
                    i += 2;
                    continue;
                }
                if (text[i] == '"') { i++; break; }
                if (text[i] == '\n') break;
                i++;
            }
            push_span(out, start, i - start, VB_TOK_STRING);
            line_start = 0;
            continue;
        }
        if (isdigit(c) || (c == '&' && i + 1 < len && (text[i + 1] == 'H' || text[i + 1] == 'h'))) {
            size_t start = i;
            if (c == '&') {
                i += 2;
                while (i < len && (isxdigit((unsigned char)text[i]) || text[i] == '&')) i++;
            } else {
                while (i < len && (isdigit((unsigned char)text[i]) || text[i] == '.')) i++;
                if (i < len && (text[i] == 'e' || text[i] == 'E')) {
                    i++;
                    if (i < len && (text[i] == '+' || text[i] == '-')) i++;
                    while (i < len && isdigit((unsigned char)text[i])) i++;
                }
            }
            push_span(out, start, i - start, VB_TOK_NUMBER);
            line_start = 0;
            continue;
        }
        if (isalpha(c) || c == '_') {
            size_t start = i;
            size_t word_len;
            int cls = VB_TOK_DEFAULT;
            while (i < len && (isalnum((unsigned char)text[i]) || text[i] == '_')) i++;
            if (i < len && (text[i] == '$' || text[i] == '%' || text[i] == '&' ||
                            text[i] == '!' || text[i] == '#' || text[i] == '@')) i++;
            word_len = i - start;
            if (in_list(text + start, word_len, keywords)) cls = VB_TOK_KEYWORD;
            else if (in_list(text + start, word_len, types)) cls = VB_TOK_TYPE;
            else if (in_list(text + start, word_len, builtins)) cls = VB_TOK_FUNCTION;
            else if (is_constant_word(text + start, word_len)) cls = VB_TOK_CONSTANT;
            else {
                size_t j = i;
                while (j < len && isspace((unsigned char)text[j])) j++;
                if (j < len && text[j] == '(') cls = VB_TOK_FUNCTION;
            }
            if (cls != VB_TOK_DEFAULT) push_span(out, start, word_len, cls);
            line_start = 0;
            continue;
        }
        if (c == '=' || c == '<' || c == '>' || c == '+' || c == '-' || c == '*' ||
            c == '/' || c == '\\' || c == '^' || c == '&') {
            size_t start = i;
            i++;
            if (i < len && (text[i] == '=' || (c == '<' && text[i] == '>')) &&
                (c == '<' || c == '>' || c == '=')) i++;
            push_span(out, start, i - start, VB_TOK_OPERATOR);
            line_start = 0;
            continue;
        }
        line_start = 0;
        i++;
    }
}

void vb_handler_list_init(VbHandlerList *list)
{
    list->items = NULL;
    list->count = 0;
    list->cap = 0;
}

void vb_handler_list_free(VbHandlerList *list)
{
    int i;
    for (i = 0; i < list->count; i++) {
        free(list->items[i].name);
        free(list->items[i].body);
    }
    free(list->items);
    list->items = NULL;
    list->count = 0;
    list->cap = 0;
}

static void handler_add(VbHandlerList *list, const char *name, const char *body, int body_line)
{
    VbHandler *handler;
    if (list->count == list->cap) {
        int ncap = list->cap ? list->cap * 2 : 8;
        VbHandler *items = (VbHandler *)realloc(list->items, (size_t)ncap * sizeof(VbHandler));
        if (!items) return;
        list->items = items;
        list->cap = ncap;
    }
    handler = &list->items[list->count++];
    handler->name = vb_strdup(name);
    handler->body = vb_strdup(body);
    handler->body_line = body_line;
}

static int is_end_proc(const char *line)
{
    if (vb_starts_ci(line, "End Sub")) return 1;
    if (vb_starts_ci(line, "End Function")) return 1;
    if (vb_starts_ci(line, "End Property")) return 1;
    return 0;
}

static const char *proc_start_name(const char *line, size_t *name_len)
{
    static const char *const starts[] = {
        "Private Sub ", "Public Sub ", "Friend Sub ", "Static Sub ", "Sub ",
        "Private Function ", "Public Function ", "Friend Function ", "Static Function ",
        "Function ", "Private Property Get ", "Public Property Get ",
        "Private Property Let ", "Public Property Let ", "Private Property Set ",
        "Public Property Set ", NULL
    };
    int i;
    for (i = 0; starts[i]; i++) {
        if (vb_starts_ci(line, starts[i])) {
            const char *p = line + strlen(starts[i]);
            const char *start = p;
            while (*p && *p != '(' && !isspace((unsigned char)*p)) p++;
            *name_len = (size_t)(p - start);
            return start;
        }
    }
    return NULL;
}

int vb_code_handlers(const char *code, VbHandlerList *out)
{
    char *work;
    char *cursor;
    char *current_name = NULL;
    VbBuf body;
    int in_proc = 0;
    int line_no = 0;
    int body_line = 0;
    if (!code || !out) return 0;
    work = vb_strdup(code);
    if (!work) return 0;
    vb_buf_init(&body);
    cursor = work;
    while (*cursor) {
        char *line_end = strchr(cursor, '\n');
        size_t len = line_end ? (size_t)(line_end - cursor) : strlen(cursor);
        char *line = vb_strndup(cursor, len);
        char *next = line_end ? line_end + 1 : cursor + len;
        char *trimmed;
        if (!line) break;
        vb_trim(line);
        trimmed = line;
        line_no++;
        if (!in_proc) {
            size_t name_len = 0;
            const char *name = proc_start_name(trimmed, &name_len);
            if (name && name_len > 0) {
                free(current_name);
                current_name = vb_strndup(name, name_len);
                in_proc = 1;
                body_line = line_no + 1;
                vb_buf_clear(&body);
            }
        } else if (is_end_proc(trimmed)) {
            handler_add(out, current_name ? current_name : "", body.data ? body.data : "", body_line);
            in_proc = 0;
            free(current_name);
            current_name = NULL;
        } else {
            vb_buf_append(&body, cursor);
            vb_buf_appendchar(&body, '\n');
        }
        cursor = next;
        free(line);
    }
    if (in_proc && current_name) {
        handler_add(out, current_name, body.data ? body.data : "", body_line);
    }
    free(current_name);
    vb_buf_free(&body);
    free(work);
    return out->count;
}

size_t vb_code_count_handlers(const char *code)
{
    VbHandlerList list;
    size_t count;
    vb_handler_list_init(&list);
    vb_code_handlers(code ? code : "", &list);
    count = (size_t)list.count;
    vb_handler_list_free(&list);
    return count;
}

char *vb_code_handler_body(const char *code, const char *name)
{
    VbHandlerList list;
    char *body = NULL;
    int i;
    if (!code || !name) return NULL;
    vb_handler_list_init(&list);
    vb_code_handlers(code, &list);
    for (i = 0; i < list.count; i++) {
        if (vb_streq_ci(list.items[i].name, name)) {
            body = vb_strdup(list.items[i].body);
            break;
        }
    }
    vb_handler_list_free(&list);
    return body;
}

static char *strip_comment(const char *line)
{
    const char *p = line;
    int in_quote = 0;
    while (*p) {
        if (*p == '"') {
            if (in_quote && p[1] == '"') { p += 2; continue; }
            in_quote = !in_quote;
        } else if (*p == '\'' && !in_quote) {
            break;
        }
        p++;
    }
    return vb_strndup(line, (size_t)(p - line));
}

static char *find_ci(const char *text, const char *needle)
{
    size_t nlen = strlen(needle);
    const char *p = text;
    int in_quote = 0;
    while (*p) {
        if (*p == '"') in_quote = !in_quote;
        if (!in_quote && vb_starts_ci(p, needle)) return (char *)p;
        p++;
    }
    (void)nlen;
    return NULL;
}

static char *find_top_level_ci(const char *text, const char *needle)
{
    const char *p = text;
    int in_quote = 0;
    int depth = 0;
    while (*p) {
        if (*p == '"') {
            if (in_quote && p[1] == '"') { p += 2; continue; }
            in_quote = !in_quote;
            p++;
            continue;
        }
        if (!in_quote) {
            if (depth == 0 && vb_starts_ci(p, needle)) return (char *)p;
            if (*p == '(') depth++;
            else if (*p == ')') depth = depth > 0 ? depth - 1 : 0;
        }
        p++;
    }
    return NULL;
}

static char *concat_values(const char *a, const char *b)
{
    VbBuf buf;
    vb_buf_init(&buf);
    vb_buf_append(&buf, a ? a : "");
    vb_buf_append(&buf, b ? b : "");
    return vb_buf_take(&buf);
}

static int value_is_number(const char *value)
{
    char *end = NULL;
    if (!value || !*value) return 0;
    strtod(value, &end);
    return end != value && *end == '\0';
}

static double value_to_number(const char *value)
{
    if (!value) return 0;
    return strtod(value, NULL);
}

static char *format_number(double value)
{
    char buffer[64];
    if (value == (double)(long long)value) {
        snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
    } else {
        snprintf(buffer, sizeof(buffer), "%g", value);
    }
    return vb_strdup(buffer);
}

static const char *split_prop(const char *text, char **target, char **prop)
{
    char *dot = find_top_level_ci(text, ".");
    if (!dot) {
        *target = NULL;
        *prop = vb_trim_copy(text);
        return "form";
    }
    *target = vb_strndup(text, (size_t)(dot - text));
    vb_trim(*target);
    *prop = vb_trim_copy(dot + 1);
    return "control";
}

static char *host_get(VbRuntimeHost *host, const char *form_name, const char *target, const char *prop)
{
    const char *value;
    if (!host || !host->get_prop) return vb_strdup("");
    if (!target || vb_streq_ci(target, "Me") || (form_name && vb_streq_ci(target, form_name))) {
        value = host->get_prop(host->ctx, NULL, prop);
    } else {
        value = host->get_prop(host->ctx, target, prop);
    }
    return vb_strdup(value ? value : "");
}

static char *eval_expr(const char *expr, const char *form_name, VbRuntimeHost *host);
static char *eval_atom(const char *expr, const char *form_name, VbRuntimeHost *host);
static char *eval_binary(const char *expr, const char *form_name, VbRuntimeHost *host);

static int dialog_token_value(const char *token)
{
    static const struct { const char *name; int value; } map[] = {
        {"vbOKOnly", 0}, {"vbOKCancel", 1}, {"vbAbortRetryIgnore", 2},
        {"vbYesNoCancel", 3}, {"vbYesNo", 4}, {"vbRetryCancel", 5},
        {"vbCritical", 16}, {"vbQuestion", 32}, {"vbExclamation", 48},
        {"vbInformation", 64}, {"vbDefaultButton1", 0}, {"vbDefaultButton2", 256},
        {"vbDefaultButton3", 512}, {NULL, 0}
    };
    const char *p;
    size_t i;
    if (!token || !*token) return -1;
    for (i = 0; map[i].name; i++) {
        if (vb_streq_ci(token, map[i].name)) return map[i].value;
    }
    p = token;
    if (*p == '-') p++;
    if (!*p) return -1;
    while (*p) {
        if (!isdigit((unsigned char)*p)) return -1;
        p++;
    }
    return vb_parse_int(token, 0);
}

static int parse_dialog_style(const char *text)
{
    char *copy;
    char *token;
    char *save = NULL;
    int total = 0;
    int found = 0;
    if (!text) return -1;
    copy = vb_trim_copy(text);
    if (!copy) return -1;
    token = strtok_r(copy, "+", &save);
    while (token) {
        int value = dialog_token_value(vb_trim(token));
        if (value < 0) {
            free(copy);
            return -1;
        }
        total += value;
        found = 1;
        token = strtok_r(NULL, "+", &save);
    }
    free(copy);
    return found ? total : -1;
}

static int eval_dialog_style(const char *raw, const char *form_name, VbRuntimeHost *host)
{
    int style;
    char *value;
    if (!raw || !*raw) return 0;
    style = parse_dialog_style(raw);
    if (style >= 0) return style;
    value = eval_expr(raw, form_name, host);
    style = vb_parse_int(value, 0);
    free(value);
    return style;
}

static void split_arguments(const char *args, char **first, char **second, char **third)
{
    char *comma1;
    char *comma2;
    const char *rest;
    *first = NULL;
    *second = NULL;
    *third = NULL;
    if (!args) return;
    comma1 = find_top_level_ci(args, ",");
    if (!comma1) {
        *first = vb_strdup(args);
        return;
    }
    *first = vb_strndup(args, (size_t)(comma1 - args));
    rest = comma1 + 1;
    comma2 = find_top_level_ci(rest, ",");
    if (!comma2) {
        *second = vb_strdup(rest);
        return;
    }
    *second = vb_strndup(rest, (size_t)(comma2 - rest));
    *third = vb_strdup(comma2 + 1);
}

static char *eval_function(const char *name, const char *args, const char *form_name, VbRuntimeHost *host)
{
    char *first = NULL;
    char *second = NULL;
    char *result = NULL;
    if (vb_streq_ci(name, "vbCrLf") || vb_streq_ci(name, "vbCr") || vb_streq_ci(name, "vbLf")) {
        return vb_strdup("\n");
    }
    if (vb_streq_ci(name, "vbTab")) return vb_strdup("\t");
    if (vb_streq_ci(name, "vbNullString")) return vb_strdup("");
    if (vb_streq_ci(name, "True")) return vb_strdup("-1");
    if (vb_streq_ci(name, "False")) return vb_strdup("0");
    if (vb_streq_ci(name, "Nothing") || vb_streq_ci(name, "Null") || vb_streq_ci(name, "Empty")) {
        return vb_strdup("");
    }
    if (!args || !*args) return vb_strdup("");

    if (vb_streq_ci(name, "InputBox")) {
        char *a, *b, *c;
        char *prompt;
        char *title = NULL;
        char *defaultText = NULL;
        char *answer = NULL;
        split_arguments(args, &a, &b, &c);
        prompt = a ? eval_expr(a, form_name, host) : vb_strdup("");
        if (b) title = eval_expr(b, form_name, host);
        if (c) defaultText = eval_expr(c, form_name, host);
        if (host && host->inputbox) {
            answer = host->inputbox(host->ctx, prompt ? prompt : "", title ? title : "",
                                    defaultText ? defaultText : "");
        }
        free(a); free(b); free(c);
        free(prompt); free(title); free(defaultText);
        return answer ? answer : vb_strdup("");
    }

    if (vb_streq_ci(name, "MsgBox")) {
        char *a, *b, *c;
        char *prompt;
        char *title = NULL;
        int style;
        int answer = 1;
        split_arguments(args, &a, &b, &c);
        prompt = a ? eval_expr(a, form_name, host) : vb_strdup("");
        style = b ? eval_dialog_style(b, form_name, host) : 0;
        if (c) title = eval_expr(c, form_name, host);
        if (host && host->confirm) {
            answer = host->confirm(host->ctx, prompt ? prompt : "", title ? title : "", style);
        } else if (host && host->msgbox) {
            host->msgbox(host->ctx, prompt ? prompt : "");
        }
        free(a); free(b); free(c);
        free(prompt); free(title);
        {
            char buffer[16];
            snprintf(buffer, sizeof(buffer), "%d", answer);
            return vb_strdup(buffer);
        }
    }

    if (vb_streq_ci(name, "Now") || vb_streq_ci(name, "Date") || vb_streq_ci(name, "Time")) {
        time_t now = time(NULL);
        struct tm *tmv;
        char buffer[64];
        tmv = localtime(&now);
        if (vb_streq_ci(name, "Date")) strftime(buffer, sizeof(buffer), "%m/%d/%Y", tmv);
        else if (vb_streq_ci(name, "Time")) strftime(buffer, sizeof(buffer), "%H:%M:%S", tmv);
        else strftime(buffer, sizeof(buffer), "%m/%d/%Y %H:%M:%S", tmv);
        return vb_strdup(buffer);
    }

    {
        char *comma = find_top_level_ci(args, ",");
        if (comma) {
            first = vb_strndup(args, (size_t)(comma - args));
            second = vb_strdup(comma + 1);
        } else {
            first = vb_strdup(args);
        }
    }

    {
        char *v1 = eval_expr(first, form_name, host);
        if (vb_streq_ci(name, "Trim") || vb_streq_ci(name, "LTrim") || vb_streq_ci(name, "RTrim")) {
            char *t = vb_trim_copy(v1);
            if (vb_streq_ci(name, "LTrim")) {
                char *p = v1;
                while (*p && isspace((unsigned char)*p)) p++;
                free(t); t = vb_strdup(p);
            } else if (vb_streq_ci(name, "RTrim")) {
                size_t len = strlen(v1);
                while (len > 0 && isspace((unsigned char)v1[len - 1])) len--;
                free(t); t = vb_strndup(v1, len);
            }
            free(v1);
            free(first); free(second);
            return t;
        }
        if (vb_streq_ci(name, "UCase") || vb_streq_ci(name, "LCase")) {
            char *t = vb_strdup(v1);
            size_t i;
            for (i = 0; t && t[i]; i++) {
                t[i] = (char)(vb_streq_ci(name, "UCase") ? toupper((unsigned char)t[i]) : tolower((unsigned char)t[i]));
            }
            free(v1); free(first); free(second);
            return t;
        }
        if (vb_streq_ci(name, "CStr")) { free(first); free(second); return v1; }
        if (vb_streq_ci(name, "CInt") || vb_streq_ci(name, "CLng") || vb_streq_ci(name, "CDbl") || vb_streq_ci(name, "CSng")) {
            result = format_number(value_to_number(v1));
            free(v1); free(first); free(second);
            return result;
        }
        if (vb_streq_ci(name, "Val")) {
            result = format_number(value_to_number(v1));
            free(v1); free(first); free(second);
            return result;
        }
        if (vb_streq_ci(name, "Len")) {
            char buffer[32];
            snprintf(buffer, sizeof(buffer), "%lu", (unsigned long)strlen(v1));
            free(v1); free(first); free(second);
            return vb_strdup(buffer);
        }
        if (second && (vb_streq_ci(name, "Left") || vb_streq_ci(name, "Right"))) {
            char *v2 = eval_expr(second, form_name, host);
            long n = (long)value_to_number(v2);
            long len = (long)strlen(v1);
            char *out;
            if (n < 0) n = 0;
            if (n > len) n = len;
            if (vb_streq_ci(name, "Left")) out = vb_strndup(v1, (size_t)n);
            else out = vb_strdup(v1 + (len - n));
            free(v1); free(v2); free(first); free(second);
            return out;
        }
        if (second && vb_streq_ci(name, "Mid")) {
            char *comma2 = find_top_level_ci(second, ",");
            char *start_expr = comma2 ? vb_strndup(second, (size_t)(comma2 - second)) : vb_strdup(second);
            char *len_expr = comma2 ? vb_strdup(comma2 + 1) : NULL;
            char *v_start = eval_expr(start_expr, form_name, host);
            long start = (long)value_to_number(v_start);
            long len = (long)strlen(v1);
            char *out;
            if (start < 1) start = 1;
            if (len_expr) {
                char *v_len = eval_expr(len_expr, form_name, host);
                long n = (long)value_to_number(v_len);
                if (start - 1 > len) out = vb_strdup("");
                else {
                    if (n < 0) n = 0;
                    if (start - 1 + n > len) n = len - (start - 1);
                    out = vb_strndup(v1 + start - 1, (size_t)n);
                }
                free(v_len);
            } else {
                out = vb_strdup(v1 + (start - 1));
            }
            free(v1); free(v_start); free(start_expr); free(len_expr); free(first); free(second);
            return out;
        }
        if (second && (vb_streq_ci(name, "Format"))) {
            free(v1); free(first); free(second);
            return vb_strdup("");
        }
        free(v1);
    }
    free(first); free(second);
    return vb_strdup("");
}

static int compare_ci(const char *a, const char *b)
{
    int ca, cb;
    if (!a || !b) return a == b ? 0 : (a ? 1 : -1);
    while (*a && *b) {
        ca = tolower((unsigned char)*a);
        cb = tolower((unsigned char)*b);
        if (ca != cb) return ca < cb ? -1 : 1;
        a++;
        b++;
    }
    if (*a == *b) return 0;
    return *a ? 1 : -1;
}

static int binary_position(const char *expr, const char *pos)
{
    char prev;
    if (pos == expr) return 0;
    prev = pos[-1];
    if (strchr("(,=<>+-*/\\&", prev)) return 0;
    return 1;
}

static char *eval_binary(const char *expr, const char *form_name, VbRuntimeHost *host)
{
    const char *p;
    const char *last_add = NULL;
    const char *last_mul = NULL;
    const char *amp = NULL;
    int in_quote = 0;
    int depth = 0;

    for (p = expr; *p; p++) {
        if (*p == '"') {
            if (in_quote && p[1] == '"') { p++; continue; }
            in_quote = !in_quote;
            continue;
        }
        if (in_quote) continue;
        if (*p == '(') { depth++; continue; }
        if (*p == ')') { if (depth > 0) depth--; continue; }
        if (depth != 0) continue;
        if (*p == '&') {
            if (p[1] == 'H' || p[1] == 'h') continue;
            if (!binary_position(expr, p)) continue;
            amp = p;
        } else if (*p == '+' || *p == '-') {
            if (!binary_position(expr, p)) continue;
            last_add = p;
        } else if (*p == '*' || *p == '/' || *p == '\\') {
            if (!binary_position(expr, p)) continue;
            last_mul = p;
        }
    }

    if (amp) {
        char *left = vb_strndup(expr, (size_t)(amp - expr));
        char *right = vb_strdup(amp + 1);
        char *v1 = eval_expr(left, form_name, host);
        char *v2 = eval_expr(right, form_name, host);
        char *out = concat_values(v1, v2);
        free(left); free(right); free(v1); free(v2);
        return out;
    }

    {
        const char *op = last_add ? last_add : last_mul;
        if (op) {
            char *left = vb_strndup(expr, (size_t)(op - expr));
            char *right = vb_strdup(op + 1);
            char *v1 = eval_expr(left, form_name, host);
            char *v2 = eval_expr(right, form_name, host);
            char *out;
            if (*op == '+') {
                if (value_is_number(v1) && value_is_number(v2)) out = format_number(value_to_number(v1) + value_to_number(v2));
                else out = concat_values(v1, v2);
            } else if (*op == '-') {
                out = format_number(value_to_number(v1) - value_to_number(v2));
            } else if (*op == '*') {
                out = format_number(value_to_number(v1) * value_to_number(v2));
            } else if (*op == '/') {
                double d = value_to_number(v2);
                out = d == 0 ? vb_strdup("") : format_number(value_to_number(v1) / d);
            } else {
                double d = value_to_number(v2);
                out = d == 0 ? vb_strdup("") : format_number((double)((long long)(value_to_number(v1) / d)));
            }
            free(left); free(right); free(v1); free(v2);
            return out;
        }
    }
    return eval_atom(expr, form_name, host);
}

static char *eval_expr(const char *expr, const char *form_name, VbRuntimeHost *host)
{
    char *trimmed = vb_trim_copy(expr);
    char *result;
    if (!trimmed) return vb_strdup("");
    result = eval_binary(trimmed, form_name, host);
    free(trimmed);
    return result;
}

/* The Err object is read by the interpreter, not by the form: Err.Number and
   Err.Description are what a VB6 handler inspects after "On Error GoTo". */
static char *eval_err_property(VbRuntimeHost *host, const char *prop)
{
    const VbErrObject *err = host ? host->err : NULL;
    if (!prop) return vb_strdup("");
    if (vb_streq_ci(prop, "Number")) {
        return err ? vb_format_int(err->number) : vb_strdup("0");
    }
    if (vb_streq_ci(prop, "Description")) {
        return vb_strdup(err ? err->description : "");
    }
    if (vb_streq_ci(prop, "Source")) {
        return vb_strdup(err ? err->source : "");
    }
    if (vb_streq_ci(prop, "LastDllError")) return vb_strdup("0");
    return vb_strdup("");
}

static char *eval_atom(const char *expr, const char *form_name, VbRuntimeHost *host)
{
    char *text = vb_trim_copy(expr);
    size_t len;
    char *result;
    if (!text) return vb_strdup("");
    len = strlen(text);
    if (len >= 2 && text[0] == '(' && text[len - 1] == ')') {
        text[len - 1] = '\0';
        result = eval_expr(text + 1, form_name, host);
        free(text);
        return result;
    }
    if (vb_value_is_quoted(text)) {
        result = vb_value_unquote(text);
        free(text);
        return result;
    }
    {
        char *paren = find_top_level_ci(text, "(");
        if (paren) {
            char *close = strrchr(paren, ')');
            if (close) {
                char *name = vb_strndup(text, (size_t)(paren - text));
                char *args = vb_strndup(paren + 1, (size_t)(close - paren - 1));
                vb_trim(name);
                result = eval_function(name, args, form_name, host);
                free(name); free(args); free(text);
                return result;
            }
        }
    }
    if (vb_streq_ci(text, "True")) { free(text); return vb_strdup("-1"); }
    if (vb_streq_ci(text, "False")) { free(text); return vb_strdup("0"); }
    if (vb_streq_ci(text, "Nothing") || vb_streq_ci(text, "Null") || vb_streq_ci(text, "Empty")) {
        free(text); return vb_strdup("");
    }
    if (vb_streq_ci(text, "vbCrLf") || vb_streq_ci(text, "vbCr") || vb_streq_ci(text, "vbLf")) {
        free(text); return vb_strdup("\n");
    }
    if (vb_streq_ci(text, "vbTab")) { free(text); return vb_strdup("\t"); }
    if (vb_streq_ci(text, "vbNullString")) { free(text); return vb_strdup(""); }
    if (vb_streq_ci(text, "Now") || vb_streq_ci(text, "Date") || vb_streq_ci(text, "Time")) {
        result = eval_function(text, "", form_name, host);
        free(text);
        return result;
    }
    if (value_is_number(text)) { result = text; return result; }
    if (strchr(text, '.')) {
        char *target = NULL;
        char *prop = NULL;
        split_prop(text, &target, &prop);
        if (target && vb_streq_ci(target, "Err")) {
            result = eval_err_property(host, prop);
        } else {
            result = host_get(host, form_name, target, prop);
        }
        free(target); free(prop); free(text);
        return result;
    }
    if (host && host->get_prop) {
        const char *def = host->get_prop(host->ctx, text, "");
        if (def) {
            result = vb_strdup(def);
            free(text);
            return result;
        }
    }
    result = host_get(host, form_name, NULL, text);
    free(text);
    return result;
}

static int truthy(const char *value)
{
    if (!value) return 0;
    if (vb_streq_ci(value, "0") || vb_streq_ci(value, "False") || vb_streq_ci(value, "")) return 0;
    return 1;
}

static int eval_condition(const char *cond, const char *form_name, VbRuntimeHost *host)
{
    char *text = vb_trim_copy(cond);
    char *op = NULL;
    const char *ops[] = {"<>", ">=", "<=", "=", ">", "<", NULL};
    int i;
    if (!text) return 0;

    {
        char *and_pos = find_top_level_ci(text, " And ");
        char *or_pos = find_top_level_ci(text, " Or ");
        if (and_pos && (!or_pos || and_pos < or_pos)) {
            char *left = vb_strndup(text, (size_t)(and_pos - text));
            char *right = vb_strdup(and_pos + 5);
            int r = eval_condition(left, form_name, host) && eval_condition(right, form_name, host);
            free(left); free(right); free(text);
            return r;
        }
        if (or_pos) {
            char *left = vb_strndup(text, (size_t)(or_pos - text));
            char *right = vb_strdup(or_pos + 4);
            int r = eval_condition(left, form_name, host) || eval_condition(right, form_name, host);
            free(left); free(right); free(text);
            return r;
        }
    }
    if (vb_starts_ci(text, "Not ")) {
        int r = !eval_condition(text + 4, form_name, host);
        free(text);
        return r;
    }
    if (find_top_level_ci(text, " Is ")) {
        free(text);
        return 0;
    }
    for (i = 0; ops[i]; i++) {
        op = find_top_level_ci(text, ops[i]);
        if (op) break;
    }
    if (op) {
        char *left = vb_strndup(text, (size_t)(op - text));
        char *right = vb_strdup(op + strlen(ops[i]));
        char *v1 = eval_expr(left, form_name, host);
        char *v2 = eval_expr(right, form_name, host);
        int result = 0;
        if (value_is_number(v1) && value_is_number(v2)) {
            double a = value_to_number(v1);
            double b = value_to_number(v2);
            if (strcmp(ops[i], "=") == 0) result = a == b;
            else if (strcmp(ops[i], "<>") == 0) result = a != b;
            else if (strcmp(ops[i], ">") == 0) result = a > b;
            else if (strcmp(ops[i], "<") == 0) result = a < b;
            else if (strcmp(ops[i], ">=") == 0) result = a >= b;
            else if (strcmp(ops[i], "<=") == 0) result = a <= b;
        } else {
            int cmp = compare_ci(v1, v2);
            if (strcmp(ops[i], "=") == 0) result = cmp == 0;
            else if (strcmp(ops[i], "<>") == 0) result = cmp != 0;
            else if (strcmp(ops[i], ">") == 0) result = cmp > 0;
            else if (strcmp(ops[i], "<") == 0) result = cmp < 0;
            else if (strcmp(ops[i], ">=") == 0) result = cmp >= 0;
            else if (strcmp(ops[i], "<=") == 0) result = cmp <= 0;
        }
        free(left); free(right); free(v1); free(v2); free(text);
        return result;
    }
    {
        char *v = eval_expr(text, form_name, host);
        int r = truthy(v);
        free(v); free(text);
        return r;
    }
}

/* Statement lines of one handler. abs[] keeps the position of each statement in the
   handler body, so a one-line If that runs its statement from a temporary array still
   reports (and resumes at) the right physical line. */
typedef struct {
    char **lines;
    int *abs;
    int count;
} VbLines;

static void lines_free(VbLines *lines)
{
    int i;
    for (i = 0; i < lines->count; i++) free(lines->lines[i]);
    free(lines->lines);
    free(lines->abs);
    lines->lines = NULL;
    lines->abs = NULL;
    lines->count = 0;
}

static VbLines split_lines(const char *text, int base)
{
    VbLines result;
    const char *cursor = text ? text : "";
    result.lines = NULL;
    result.abs = NULL;
    result.count = 0;
    while (*cursor) {
        const char *end = strchr(cursor, '\n');
        size_t len = end ? (size_t)(end - cursor) : strlen(cursor);
        char *line = vb_strndup(cursor, len);
        char *clean;
        char **new_lines;
        int *new_abs;
        if (!line) break;
        clean = strip_comment(line);
        free(line);
        if (clean) {
            vb_trim(clean);
            new_lines = (char **)realloc(result.lines, (size_t)(result.count + 1) * sizeof(char *));
            if (!new_lines) { free(clean); break; }
            result.lines = new_lines;
            new_abs = (int *)realloc(result.abs, (size_t)(result.count + 1) * sizeof(int));
            if (!new_abs) { free(clean); break; }
            result.abs = new_abs;
            result.abs[result.count] = base + result.count;
            result.lines[result.count++] = clean;
        }
        if (!end) break;
        cursor = end + 1;
    }
    return result;
}

/* Control flow out of run_lines. An unhandled error, Exit Sub and End all stop the
   procedure; a trapped error either continues with the next statement or unwinds to
   the driver, which knows the whole handler and can jump to a label. */
enum {
    VB_FLOW_NEXT = 0,
    VB_FLOW_STOP,
    VB_FLOW_GOTO,
    VB_FLOW_RESUME,
    VB_FLOW_RESUME_NEXT
};

typedef enum {
    VB_ERROR_MODE_NONE = 0,
    VB_ERROR_MODE_RESUME_NEXT,
    VB_ERROR_MODE_GOTO
} VbErrorMode;

/* Per-procedure state: the Err object plus whatever "On Error" armed. VB6 scopes error
   handling to the procedure, so one instance follows the whole handler body. */
typedef struct {
    VbRuntimeHost *host;
    const char *form_name;
    const char *handler;
    int body_line;
    VbErrObject *err;
    VbErrorMode mode;
    char label[64];
    int in_handler;      /* a GoTo handler is running: a new error is unhandled (VB6) */
    char jump_label[64];
    int error_abs;       /* statement that raised the error */
    int resume_abs;
    char resume_label[64];
    int resume_count;
} VbRunState;

static const char *vb_error_message(int number)
{
    switch (number) {
    case 5: return "Invalid procedure call or argument";
    case 6: return "Overflow";
    case 7: return "Out of memory";
    case 9: return "Subscript out of range";
    case 11: return "Division by zero";
    case 13: return "Type mismatch";
    case 20: return "Resume without error";
    case 28: return "Out of stack space";
    case 35: return "Sub or Function not defined";
    case 53: return "File not found";
    case 75: return "Path/File access error";
    case 76: return "Path not found";
    case 91: return "Object variable or With block variable not set";
    case 380: return "Invalid property value";
    case 424: return "Object required";
    case 438: return "Object doesn't support this property or method";
    case 440: return "Automation error";
    case 457: return "This key is already associated with an element of this collection";
    default: return "Application-defined or object-defined error";
    }
}

static void err_clear(VbRunState *st)
{
    if (!st->err) return;
    st->err->number = 0;
    st->err->description[0] = '\0';
    st->err->source[0] = '\0';
}

/* VB6 error dispatch. Returns the flow the statement must follow: continue with the
   next statement (On Error Resume Next), unwind to a label, or stop the procedure and
   show the End/Debug dialog, which is reserved for errors nobody trapped. */
static int raise_error(VbRunState *st, int number, const char *message, const char *source,
                       int abs_line)
{
    if (st->err) {
        st->err->number = number;
        snprintf(st->err->description, sizeof(st->err->description), "%s",
                 message ? message : vb_error_message(number));
        snprintf(st->err->source, sizeof(st->err->source), "%s", source ? source : "");
    }
    st->error_abs = abs_line;
    if (st->mode == VB_ERROR_MODE_RESUME_NEXT) return VB_FLOW_RESUME_NEXT;
    if (st->mode == VB_ERROR_MODE_GOTO && !st->in_handler) {
        snprintf(st->jump_label, sizeof(st->jump_label), "%s", st->label);
        st->in_handler = 1;
        return VB_FLOW_GOTO;
    }
    if (st->host && st->host->runtime_error) {
        int choice = st->host->runtime_error(st->host->ctx, number,
                                             message ? message : vb_error_message(number),
                                             st->handler, st->body_line + abs_line);
        /* Debug keeps the procedure alive when the host can break: the user is paused on
           the failing statement and steps through the rest of the handler. Without break
           support (CLI, tests) the procedure stops, as it always did. */
        if (choice == VB_RUNTIME_ERROR_DEBUG && st->host->break_hook) {
            if (st->host->break_hook(st->host->ctx, st->handler, st->body_line + abs_line)) {
                return VB_FLOW_STOP;
            }
            return VB_FLOW_RESUME_NEXT;
        }
    }
    return VB_FLOW_STOP;
}

static int is_label_line(const char *line, const char *label)
{
    size_t len;
    char *name;
    int match;
    if (!line || !label || !*label) return 0;
    len = strlen(line);
    if (len < 2 || line[len - 1] != ':') return 0;
    if (memchr(line, ':', len - 1)) return 0;
    name = vb_strndup(line, len - 1);
    if (!name) return 0;
    vb_trim(name);
    match = vb_streq_ci(name, label);
    free(name);
    return match;
}

static int find_label_index(VbLines *lines, const char *label)
{
    int i;
    if (!label || !*label) return -1;
    for (i = 0; i < lines->count; i++) {
        if (is_label_line(lines->lines[i], label)) return i;
    }
    return -1;
}

static int index_for_abs(VbLines *lines, int abs)
{
    int i;
    for (i = 0; i < lines->count; i++) {
        if (lines->abs[i] >= abs) return i;
    }
    return lines->count;
}

/* Procedure declarations and .frm metadata lines are not statements, so neither a
   breakpoint nor a step can land on them. */
static int is_declaration_line(const char *line)
{
    const char *p = line;
    if (vb_starts_ci(p, "Attribute ")) return 1;
    if (vb_starts_ci(p, "Private ")) p += 8;
    else if (vb_starts_ci(p, "Public ")) p += 7;
    else if (vb_starts_ci(p, "Friend ")) p += 7;
    else if (vb_starts_ci(p, "Static ")) p += 7;
    else return 0;
    return vb_starts_ci(p, "Sub ") || vb_starts_ci(p, "Function ") ||
           vb_starts_ci(p, "Property ");
}

/* Lines that do not become an instruction: stepping (F8) must not stop on declarations,
   block delimiters or a bare label such as "Caught:". */
static int is_executable_line(const char *line)
{
    size_t len;
    if (!line || !*line) return 0;
    if (is_declaration_line(line)) return 0;
    if (vb_starts_ci(line, "Dim ") || vb_starts_ci(line, "Option ") ||
        vb_starts_ci(line, "End If") || vb_starts_ci(line, "Else") ||
        vb_starts_ci(line, "ElseIf ") || vb_starts_ci(line, "End Sub") ||
        vb_starts_ci(line, "End Function") || vb_starts_ci(line, "Rem ")) return 0;
    len = strlen(line);
    if (len >= 2 && line[len - 1] == ':' && !memchr(line, ':', len - 1)) return 0;
    return 1;
}

/* ---- Breakpoints that follow code edits (pure C, unit-tested by the CLI harness) ---- */

static size_t edit_line_start(const char *text, size_t length, size_t location)
{
    if (location > length) location = length;
    while (location > 0 && text[location - 1] != '\n') location--;
    return location;
}

static size_t edit_line_end(const char *text, size_t length, size_t location)
{
    if (location > length) location = length;
    while (location < length && text[location] != '\n') location++;
    return location < length ? location + 1 : length;
}

static size_t edit_line_start_for_line(const char *text, size_t length, int line)
{
    size_t location = 0;
    int current = 1;
    if (line <= 1) return 0;
    while (current < line && location < length) {
        location = edit_line_end(text, length, location);
        current++;
    }
    return location;
}

static int edit_line_at(const char *text, size_t length, size_t location)
{
    size_t i;
    int line = 1;
    if (location > length) location = length;
    for (i = 0; i < location; i++) {
        if (text[i] == '\n') line++;
    }
    return line;
}

static int edit_line_is_blank(const char *text, size_t length, int line)
{
    size_t start = edit_line_start_for_line(text, length, line);
    size_t end = edit_line_end(text, length, start);
    size_t i;
    for (i = start; i < end; i++) {
        if (text[i] != ' ' && text[i] != '\t' && text[i] != '\r' && text[i] != '\n') return 0;
    }
    return 1;
}

int *vb_code_follow_breakpoints(const char *old_text, const char *new_text,
                                const int *lines, int count, int *out_count)
{
    const char *oldText = old_text ? old_text : "";
    const char *newText = new_text ? new_text : "";
    size_t oldLength = strlen(oldText);
    size_t newLength = strlen(newText);
    size_t prefix = 0;
    size_t suffix = 0;
    size_t rawEnd;
    size_t regionStart;
    size_t regionEnd;
    long delta;
    int insertion;
    int *moved = NULL;
    int movedCount = 0;
    int i;

    if (out_count) *out_count = 0;
    if (!lines || count <= 0) return NULL;

    while (prefix < oldLength && prefix < newLength && oldText[prefix] == newText[prefix]) prefix++;
    while (suffix < oldLength - prefix && suffix < newLength - prefix &&
           oldText[oldLength - 1 - suffix] == newText[newLength - 1 - suffix]) {
        suffix++;
    }
    rawEnd = oldLength - suffix;
    delta = (long)(newLength - suffix) - (long)rawEnd;
    /* Nothing was removed: typing or pasting at one point. The dot at that exact point
       belongs to the text being pushed, so Enter at column 0 keeps the dot on the
       statement, now one line lower. */
    insertion = (rawEnd == prefix);
    regionStart = insertion ? prefix : edit_line_start(oldText, oldLength, prefix);
    regionEnd = rawEnd;

    for (i = 0; i < count; i++) {
        size_t anchor, location, oldLineEnd;
        int newLine;
        if (lines[i] <= 0) continue;
        anchor = edit_line_start_for_line(oldText, oldLength, lines[i]);
        location = anchor;
        if (insertion) {
            if (anchor >= prefix) location = (size_t)((long)anchor + delta);
        } else if (anchor < regionStart) {
            /* The statement starts before the edit: untouched. */
        } else if (anchor >= regionEnd) {
            /* The statement starts after the edit: it slides with the inserted or
               removed text, so a line added above pushes it down. */
            location = (size_t)((long)anchor + delta);
        } else {
            /* The dot is inside the replaced block. If the edit removed the end of the
               old line (its line break) the statement is gone and the dot goes away,
               as in VB6; when the edit was inside the line the dot stays there. */
            oldLineEnd = edit_line_end(oldText, oldLength, anchor);
            if (rawEnd >= oldLineEnd) continue;
            location = regionStart;
        }
        if (location > newLength) location = newLength;
        newLine = edit_line_at(newText, newLength, location);
        if (edit_line_is_blank(newText, newLength, newLine)) continue;
        if (movedCount == 0 || moved[movedCount - 1] != newLine) {
            int *grown = (int *)realloc(moved, sizeof(int) * (size_t)(movedCount + 1));
            if (!grown) break;
            moved = grown;
            moved[movedCount++] = newLine;
        }
    }

    if (out_count) *out_count = movedCount;
    return moved;
}

int vb_code_line_executable(const char *code, int line)
{
    const char *cursor = code ? code : "";
    int current = 1;
    if (line <= 0) return 0;
    while (current < line && *cursor) {
        const char *end = strchr(cursor, '\n');
        if (!end) return 0;
        cursor = end + 1;
        current++;
    }
    if (current != line || !*cursor) return 0;
    {
        const char *end = strchr(cursor, '\n');
        size_t len = end ? (size_t)(end - cursor) : strlen(cursor);
        char *text = vb_strndup(cursor, len);
        char *clean;
        int ok;
        if (!text) return 0;
        clean = strip_comment(text);
        free(text);
        if (!clean) return 0;
        vb_trim(clean);
        ok = is_executable_line(clean);
        free(clean);
        return ok;
    }
}

/* Break mode: the host pauses here (it runs the debugger event loop) and returns 1 when
   the user stopped the procedure. */
static int break_before_statement(const char *line, VbLines *lines, int index, VbRunState *st)
{
    if (!st->host || !st->host->break_hook) return 0;
    if (!is_executable_line(line)) return 0;
    return st->host->break_hook(st->host->ctx, st->handler, st->body_line + lines->abs[index]);
}

static int run_lines(VbLines *lines, int start, int end, VbRunState *st, int allow_break);

static int find_matching_end_if(VbLines *lines, int start, int end, int *else_index)
{
    int depth = 0;
    int i;
    *else_index = -1;
    for (i = start; i < end; i++) {
        const char *line = lines->lines[i];
        if (vb_starts_ci(line, "If ") && vb_ends_ci(line, "Then") && !find_ci(line, " Then ")) {
            depth++;
        } else if (vb_starts_ci(line, "End If")) {
            if (depth == 0) return i;
            depth--;
        } else if (depth == 0 && vb_streq_ci(line, "Else")) {
            *else_index = i;
        }
    }
    return end;
}

static int run_lines(VbLines *lines, int start, int end, VbRunState *st, int allow_break)
{
    const char *form_name = st->form_name;
    VbRuntimeHost *host = st->host;
    int i;
    for (i = start; i < end; i++) {
        char *line = lines->lines[i];
        char *target = NULL;
        char *prop = NULL;
        if (!line || !*line) continue;
        if (allow_break && break_before_statement(line, lines, i, st)) return VB_FLOW_STOP;

        if (vb_starts_ci(line, "If ")) {
            char *then_pos = find_top_level_ci(line, " Then");
            if (then_pos) {
                char *cond = vb_strndup(line + 3, (size_t)(then_pos - (line + 3)));
                char *after = then_pos + 5;
                while (*after && isspace((unsigned char)*after)) after++;
                if (*after) {
                    if (eval_condition(cond, form_name, host)) {
                        VbLines one;
                        char *copy = vb_strdup(after);
                        int flow;
                        one.lines = (char **)malloc(sizeof(char *));
                        one.abs = (int *)malloc(sizeof(int));
                        one.lines[0] = copy;
                        one.abs[0] = lines->abs[i];
                        one.count = 1;
                        /* The If line itself was already offered to break mode. */
                        flow = run_lines(&one, 0, 1, st, 0);
                        lines_free(&one);
                        if (flow != VB_FLOW_NEXT) {
                            free(cond);
                            return flow;
                        }
                    }
                } else {
                    int else_index = -1;
                    int end_if = find_matching_end_if(lines, i + 1, end, &else_index);
                    int flow = VB_FLOW_NEXT;
                    if (eval_condition(cond, form_name, host)) {
                        flow = run_lines(lines, i + 1, else_index >= 0 ? else_index : end_if, st, 1);
                    } else if (else_index >= 0) {
                        flow = run_lines(lines, else_index + 1, end_if, st, 1);
                    }
                    if (flow != VB_FLOW_NEXT) {
                        free(cond);
                        return flow;
                    }
                    if (end_if < end) i = end_if;
                }
                free(cond);
                continue;
            }
        }
        if (vb_starts_ci(line, "ElseIf ")) continue;
        if (vb_starts_ci(line, "Else")) continue;
        if (vb_starts_ci(line, "End If")) continue;
        if (vb_starts_ci(line, "Exit Sub") || vb_starts_ci(line, "Exit Function")) return 1;

        /* VB6 error handling: "On Error Resume Next", "On Error GoTo <label>" and
           "On Error GoTo 0". The scope is the whole procedure, not the block. */
        if (vb_starts_ci(line, "On Error") &&
            (line[8] == '\0' || isspace((unsigned char)line[8]))) {
            char *argument = vb_trim_copy(line + 8);
            if (argument && vb_starts_ci(argument, "Resume Next")) {
                st->mode = VB_ERROR_MODE_RESUME_NEXT;
                st->in_handler = 0;
            } else if (argument && vb_starts_ci(argument, "GoTo")) {
                char *label = vb_trim_copy(argument + 4);
                size_t len = label ? strlen(label) : 0;
                if (len > 0 && label[len - 1] == ':') label[len - 1] = '\0';
                if (!label || !*label || vb_streq_ci(label, "0")) {
                    st->mode = VB_ERROR_MODE_NONE;
                    st->in_handler = 0;
                } else {
                    snprintf(st->label, sizeof(st->label), "%s", label);
                    st->mode = VB_ERROR_MODE_GOTO;
                    st->in_handler = 0;
                }
                free(label);
            }
            free(argument);
            continue;
        }

        /* Resume / Resume Next / Resume <label> leave the handler and continue at the
           failing statement, after it, or at a label. */
        if (vb_starts_ci(line, "Resume") &&
            (line[6] == '\0' || isspace((unsigned char)line[6]))) {
            char *argument = vb_trim_copy(line + 6);
            int flow;
            if (!st->err || st->err->number == 0) {
                /* VB6: error 20, "Resume without error". */
                flow = raise_error(st, 20, vb_error_message(20), NULL, lines->abs[i]);
            } else {
                st->in_handler = 0;
                st->resume_label[0] = '\0';
                st->resume_abs = -1;
                if (!argument || !*argument) {
                    st->resume_abs = st->error_abs;
                } else if (vb_starts_ci(argument, "Next")) {
                    st->resume_abs = st->error_abs + 1;
                } else {
                    size_t len = strlen(argument);
                    if (len > 0 && argument[len - 1] == ':') argument[len - 1] = '\0';
                    snprintf(st->resume_label, sizeof(st->resume_label), "%s", argument);
                }
                flow = VB_FLOW_RESUME;
            }
            free(argument);
            if (flow == VB_FLOW_RESUME_NEXT) continue;
            return flow;
        }

        if (vb_starts_ci(line, "Err.Clear")) {
            err_clear(st);
            continue;
        }

        if (vb_starts_ci(line, "Err.Raise") &&
            (line[9] == '\0' || isspace((unsigned char)line[9]))) {
            char *a, *b, *c;
            char *number_expr;
            char *source = NULL;
            char *description = NULL;
            int number;
            int flow;
            split_arguments(line + 9, &a, &b, &c);
            number_expr = a ? eval_expr(a, form_name, host) : vb_strdup("0");
            number = vb_parse_int(number_expr, 0);
            if (b) {
                char *value = eval_expr(b, form_name, host);
                if (value && *value) source = value;
                else free(value);
            }
            if (c) {
                char *value = eval_expr(c, form_name, host);
                if (value && *value) description = value;
                else free(value);
            }
            flow = raise_error(st, number, description ? description : vb_error_message(number),
                               source, lines->abs[i]);
            free(a); free(b); free(c);
            free(number_expr);
            free(source);
            free(description);
            if (flow == VB_FLOW_RESUME_NEXT) continue;
            return flow;
        }

        if (vb_starts_ci(line, "MsgBox")) {
            const char *args = line + 6;
            char *a, *b, *c;
            char *text;
            char *title = NULL;
            int style = 0;
            while (*args && isspace((unsigned char)*args)) args++;
            split_arguments(args, &a, &b, &c);
            text = a ? eval_expr(a, form_name, host) : vb_strdup("");
            if (b) style = eval_dialog_style(b, form_name, host);
            if (c) title = eval_expr(c, form_name, host);
            if (host && host->confirm) {
                host->confirm(host->ctx, text ? text : "", title ? title : "", style);
            } else if (host && host->msgbox) {
                host->msgbox(host->ctx, text ? text : "");
            }
            free(a); free(b); free(c);
            free(text);
            free(title);
            continue;
        }

        if (vb_starts_ci(line, "Unload ")) {
            char *text = vb_trim_copy(line + 7);
            if (!text || !*text || vb_streq_ci(text, "Me")) {
                free(text);
                if (host && host->close) host->close(host->ctx);
                return 1;
            }
            if (host && host->close) host->close(host->ctx);
            free(text);
            return 1;
        }
        if (vb_streq_ci(line, "End") || vb_streq_ci(line, "Stop")) {
            if (host && host->close) host->close(host->ctx);
            return 1;
        }
        if (vb_starts_ci(line, "End Sub") || vb_starts_ci(line, "End Function")) return 1;
        /* Method statements, e.g. "Text1.SetFocus" (also written as "Call Text1.SetFocus"). */
        {
            const char *statement = line;
            char *methodTarget = NULL;
            char *method = NULL;
            if (vb_starts_ci(statement, "Call ")) {
                statement += 5;
                while (*statement && isspace((unsigned char)*statement)) statement++;
            }
            if (!find_top_level_ci(statement, "=") && *statement) {
                split_prop(statement, &methodTarget, &method);
                if (vb_streq_ci(method ? method : "", "SetFocus")) {
                    int focused = 1;
                    if (host && host->set_focus) {
                        if (!methodTarget || vb_streq_ci(methodTarget, "Me")) {
                            focused = host->set_focus(host->ctx, NULL);
                        } else {
                            focused = host->set_focus(host->ctx, methodTarget);
                        }
                    }
                    if (!focused) {
                        /* VB6: "Run-time error '5': Invalid procedure call or argument".
                           On Error decides what happens next; without a handler the
                           procedure stops here and the End/Debug dialog appears. */
                        int flow;
                        free(methodTarget);
                        free(method);
                        flow = raise_error(st, 5, "Invalid procedure call or argument",
                                           NULL, lines->abs[i]);
                        if (flow == VB_FLOW_RESUME_NEXT) continue;
                        return flow;
                    }
                    free(methodTarget);
                    free(method);
                    continue;
                }
                free(methodTarget);
                free(method);
            }
        }
        if (vb_starts_ci(line, "Call ")) {
            continue;
        }
        if (vb_starts_ci(line, "Set ")) {
            continue;
        }
        if (vb_starts_ci(line, "Dim ") || vb_starts_ci(line, "ReDim ") ||
            vb_starts_ci(line, "Const ") || vb_starts_ci(line, "Static ") ||
            vb_starts_ci(line, "Public ") || vb_starts_ci(line, "Private ") ||
            vb_starts_ci(line, "Global ") || vb_starts_ci(line, "Option ") ||
            vb_starts_ci(line, "On ") || vb_starts_ci(line, "GoTo ") ||
            vb_starts_ci(line, "GoSub ") || vb_starts_ci(line, "Return") ||
            vb_starts_ci(line, "Err.") || vb_starts_ci(line, "With ") ||
            vb_starts_ci(line, "End With") || vb_starts_ci(line, "For ") ||
            vb_starts_ci(line, "Next") || vb_starts_ci(line, "Do") ||
            vb_starts_ci(line, "Loop") || vb_starts_ci(line, "While ") ||
            vb_starts_ci(line, "Wend") || vb_starts_ci(line, "Select ") ||
            vb_starts_ci(line, "Case ") || vb_starts_ci(line, "End Select") ||
            vb_starts_ci(line, "Print ") || vb_starts_ci(line, "Debug.") ||
            vb_starts_ci(line, "Rem ")) {
            continue;
        }

        {
            char *eq = find_top_level_ci(line, "=");
            if (eq) {
                char *left;
                char *right;
                char *value;
                if (*(eq + 1) == '=') continue;
                left = vb_strndup(line, (size_t)(eq - line));
                right = vb_strdup(eq + 1);
                vb_trim(left);
                vb_trim(right);
                split_prop(left, &target, &prop);
                value = eval_expr(right, form_name, host);
                if (host && host->set_prop) {
                    if (!target || vb_streq_ci(target, "Me") ||
                        (form_name && vb_streq_ci(target, form_name))) {
                        host->set_prop(host->ctx, NULL, prop, value);
                    } else {
                        host->set_prop(host->ctx, target, prop, value);
                    }
                }
                free(left); free(right); free(value);
                free(target); free(prop);
                continue;
            }
        }
    }
    return 0;
}

/* Runs the handler body, following GoTo labels and Resume requests. run_lines only
   unwinds for those jumps: a Resume Next is handled where the error happens, so nested
   statement ranges (If blocks) keep working. */
static int run_body(VbLines *lines, VbRunState *st)
{
    int pc = 0;
    for (;;) {
        int flow = run_lines(lines, pc, lines->count, st, 1);
        int target;
        if (flow == VB_FLOW_GOTO) {
            target = find_label_index(lines, st->jump_label);
            if (target < 0) {
                fprintf(stderr, "on-error: label '%s' not found\n", st->jump_label);
                return VB_FLOW_STOP;
            }
            pc = target + 1;
        } else if (flow == VB_FLOW_RESUME) {
            if (st->resume_label[0]) {
                target = find_label_index(lines, st->resume_label);
                if (target < 0) {
                    fprintf(stderr, "on-error: label '%s' not found\n", st->resume_label);
                    return VB_FLOW_STOP;
                }
                pc = target;
            } else {
                pc = index_for_abs(lines, st->resume_abs);
            }
            st->resume_label[0] = '\0';
            /* A handler that Resumes onto a statement that fails again loops forever in
               VB6; without a break mode a cap keeps the app responsive. */
            if (++st->resume_count > 10000) {
                fprintf(stderr, "on-error: Resume loop guard tripped\n");
                return VB_FLOW_STOP;
            }
        } else {
            return flow;
        }
        if (pc >= lines->count) return VB_FLOW_NEXT;
    }
}

int vb_run_event(const char *code, const char *handler, const char *form_name, VbRuntimeHost *host)
{
    VbHandlerList handlers;
    VbErrObject local_err;
    VbErrObject *saved_err = host ? host->err : NULL;
    VbRunState state;
    char *body;
    VbLines lines;
    int body_line = 0;
    if (!code || !handler) return 0;
    body = vb_code_handler_body(code, handler);
    if (!body) return 0;
    /* The body starts on the physical line after "Private Sub <name>"; run-time errors
       report an absolute line number so the IDE can jump to the offending statement. */
    vb_handler_list_init(&handlers);
    if (vb_code_handlers(code, &handlers)) {
        for (int i = 0; i < handlers.count; i++) {
            if (vb_streq_ci(handlers.items[i].name, handler)) {
                body_line = handlers.items[i].body_line;
                break;
            }
        }
    }
    vb_handler_list_free(&handlers);
    memset(&local_err, 0, sizeof(local_err));
    /* VB6 has one Err object per thread; the host may own the storage to inspect it. */
    if (host && !host->err) host->err = &local_err;
    memset(&state, 0, sizeof(state));
    state.host = host;
    state.form_name = form_name;
    state.handler = handler;
    state.body_line = body_line;
    state.err = host ? host->err : &local_err;
    state.error_abs = -1;
    /* Exiting a procedure clears Err in VB6, so every handler starts clean. */
    err_clear(&state);
    lines = split_lines(body, 0);
    run_body(&lines, &state);
    lines_free(&lines);
    free(body);
    if (host) host->err = saved_err;
    return 1;
}

int vb_form_run_event(VbForm *form, const char *handler, VbRuntimeHost *host)
{
    if (!form) return 0;
    return vb_run_event(form->code ? form->code : "", handler, vb_form_name(form), host);
}
