#ifndef VB_GRID_H
#define VB_GRID_H

/* In-memory recordset behind the runtime DataGrid: columns with their own width,
   rows of string cells, the selected cell and the text being edited. It is deliberately
   UI-free (no Cocoa, no units) so the whole editing behaviour can be tested from vbtool
   without opening the app: the view passes points and the coordinator passes properties. */

typedef struct {
    double *widths;      /* per column, in the caller's units (points in the view) */
    int columns;
    int rows;
    char **cells;        /* rows * columns, NULL when a cell was never written */
    int selected_row;
    int selected_column;
    int editing;
    double default_width;
    double row_height;
    double header_height;
    char *edit;          /* editing buffer, NULL when not editing */
} VbGrid;

void vb_grid_init(VbGrid *grid, int rows, int columns, double default_width, double row_height);
void vb_grid_free(VbGrid *grid);

/* Grows or shrinks the sheet keeping the existing cells (new cells start empty). */
void vb_grid_set_size(VbGrid *grid, int rows, int columns);
void vb_grid_set_metrics(VbGrid *grid, double default_width, double row_height, double header_height);
/* Sizes the sheet to fill an area (the control's inner rect): the first call derives the
   column count from the default width, the rows always fill the height below the header. */
void vb_grid_fit(VbGrid *grid, double width, double height);

double vb_grid_column_width(const VbGrid *grid, int column);
/* VB6 keeps a usable minimum: returns 1 when the width changed. */
int vb_grid_resize_column(VbGrid *grid, int column, double width);

const char *vb_grid_cell(const VbGrid *grid, int row, int column);
void vb_grid_set_cell(VbGrid *grid, int row, int column, const char *text);
void vb_grid_clear_cell(VbGrid *grid, int row, int column);

void vb_grid_select(VbGrid *grid, int row, int column);
/* Commits a pending edit, then clamps the new position (arrows, Tab, Enter). */
void vb_grid_move_selection(VbGrid *grid, int delta_row, int delta_column);

/* Point in the grid's own flipped coordinates; row is -1 on the column header.
   border_column receives the column whose right edge is under the point, or -1. */
int vb_grid_hit_test(const VbGrid *grid, double x, double y, int headers,
                     int *row, int *column, int *border_column);

void vb_grid_begin_edit(VbGrid *grid);
void vb_grid_cancel_edit(VbGrid *grid);
void vb_grid_commit_edit(VbGrid *grid);
const char *vb_grid_edit_text(const VbGrid *grid);
/* Typing over a selected cell replaces its content: VB6 starts the edit buffer empty. */
void vb_grid_edit_reset(VbGrid *grid);
void vb_grid_edit_insert(VbGrid *grid, const char *text);
void vb_grid_edit_backspace(VbGrid *grid);

#endif
