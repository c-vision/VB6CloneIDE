#ifndef VB_PARSE_H
#define VB_PARSE_H

#include "vb_model.h"

VbForm *vb_form_parse(const char *text, const char *path);
VbForm *vb_form_load(const char *path);
char *vb_form_serialize(VbForm *form, size_t *out_len);
int vb_form_save(VbForm *form, const char *path);

VbProject *vb_project_load(const char *path);
int vb_project_save(VbProject *project, const char *path);
int vb_project_reload_forms(VbProject *project);
char *vb_project_item_path(VbProject *project, VbItem *item);
char *vb_project_item_relative_path(VbProject *project, VbItem *item);
char *vb_project_load_code(VbProject *project, VbItem *item, size_t *out_len);
int vb_project_save_item(VbProject *project, VbItem *item);

#endif
