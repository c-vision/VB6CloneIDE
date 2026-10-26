#include "vb_grid.h"
#include "vb_util.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define VB_GRID_MIN_COLUMN_WIDTH 24.0
#define VB_GRID_RESIZE_SLOP 3.0

static char **grid_alloc_cells(int rows, int columns)
{
    size_t count;
    char **cells;
    if (rows <= 0 || columns <= 0) return NULL;
    count = (size_t)rows * (size_t)columns;
    cells = (char **)calloc(count, sizeof(char *));
    return cells;
}

void vb_grid_init(VbGrid *grid, int rows, int columns, double default_width, double row_height)
{
    if (!grid) return;
    memset(grid, 0, sizeof(*grid));
    grid->default_width = default_width > 0 ? default_width : 80.0;
    grid->row_height = row_height > 0 ? row_height : 17.0;
    grid->selected_row = 0;
    grid->selected_column = 0;
    vb_grid_set_size(grid, rows, columns);
}

void vb_grid_free(VbGrid *grid)
{
    int i;
    if (!grid) return;
    if (grid->cells) {
        for (i = 0; i < grid->rows * grid->columns; i++) free(grid->cells[i]);
        free(grid->cells);
    }
    free(grid->widths);
    free(grid->edit);
    memset(grid, 0, sizeof(*grid));
}

void vb_grid_set_metrics(VbGrid *grid, double default_width, double row_height, double header_height)
{
    if (!grid) return;
    if (default_width > 0 && default_width != grid->default_width) {
        /* Only columns the user never resized follow the new default. */
        int i;
        for (i = 0; i < grid->columns; i++) {
            if (grid->widths && grid->widths[i] == grid->default_width) grid->widths[i] = default_width;
        }
        grid->default_width = default_width;
    }
    if (row_height > 0) grid->row_height = row_height;
    grid->header_height = header_height >= 0 ? header_height : grid->header_height;
}

void vb_grid_set_size(VbGrid *grid, int rows, int columns)
{
    char **cells;
    double *widths;
    int r, c;
    int old_rows, old_columns;
    if (!grid) return;
    if (rows < 0) rows = 0;
    if (columns < 0) columns = 0;
    if (rows == grid->rows && columns == grid->columns) return;

    old_rows = grid->rows;
    old_columns = grid->columns;
    cells = grid_alloc_cells(rows, columns);
    for (r = 0; r < rows && r < old_rows; r++) {
        for (c = 0; c < columns && c < old_columns; c++) {
            cells[(size_t)r * columns + c] = grid->cells[(size_t)r * old_columns + c];
            grid->cells[(size_t)r * old_columns + c] = NULL;
        }
    }
    if (grid->cells) {
        for (r = 0; r < old_rows * old_columns; r++) free(grid->cells[r]);
        free(grid->cells);
    }
    grid->cells = cells;
    grid->rows = rows;
    grid->columns = columns;

    widths = columns > 0 ? (double *)calloc((size_t)columns, sizeof(double)) : NULL;
    for (c = 0; c < columns; c++) {
        widths[c] = c < old_columns && grid->widths ? grid->widths[c] : grid->default_width;
    }
    free(grid->widths);
    grid->widths = widths;

    if (grid->selected_row >= rows) grid->selected_row = rows > 0 ? rows - 1 : 0;
    if (grid->selected_column >= columns) grid->selected_column = columns > 0 ? columns - 1 : 0;
}

void vb_grid_fit(VbGrid *grid, double width, double height)
{
    int columns, rows;
    if (!grid) return;
    if (grid->columns == 0) {
        columns = (int)floor(width / (grid->default_width > 0 ? grid->default_width : 80.0));
        if (columns < 1) columns = 1;
    } else {
        columns = grid->columns;
    }
    rows = (int)ceil((height - grid->header_height) /
                     (grid->row_height > 0 ? grid->row_height : 17.0));
    if (rows < 1) rows = 1;
    vb_grid_set_size(grid, rows, columns);
}

double vb_grid_column_width(const VbGrid *grid, int column)
{
    if (!grid || column < 0 || column >= grid->columns || !grid->widths) return grid ? grid->default_width : 0;
    return grid->widths[column];
}

int vb_grid_resize_column(VbGrid *grid, int column, double width)
{
    if (!grid || column < 0 || column >= grid->columns || !grid->widths) return 0;
    if (width < VB_GRID_MIN_COLUMN_WIDTH) width = VB_GRID_MIN_COLUMN_WIDTH;
    if (fabs(width - grid->widths[column]) < 0.01) return 0;
    grid->widths[column] = width;
    return 1;
}

const char *vb_grid_cell(const VbGrid *grid, int row, int column)
{
    if (!grid || !grid->cells) return "";
    if (row < 0 || row >= grid->rows || column < 0 || column >= grid->columns) return "";
    return grid->cells[(size_t)row * grid->columns + column]
               ? grid->cells[(size_t)row * grid->columns + column]
               : "";
}

void vb_grid_set_cell(VbGrid *grid, int row, int column, const char *text)
{
    size_t index;
    char *copy;
    if (!grid || !grid->cells) return;
    if (row < 0 || row >= grid->rows || column < 0 || column >= grid->columns) return;
    index = (size_t)row * grid->columns + column;
    copy = (text && *text) ? vb_strdup(text) : NULL;
    free(grid->cells[index]);
    grid->cells[index] = copy;
}

void vb_grid_clear_cell(VbGrid *grid, int row, int column)
{
    vb_grid_set_cell(grid, row, column, NULL);
}

void vb_grid_select(VbGrid *grid, int row, int column)
{
    if (!grid) return;
    if (row < 0) row = 0;
    if (row >= grid->rows) row = grid->rows > 0 ? grid->rows - 1 : 0;
    if (column < 0) column = 0;
    if (column >= grid->columns) column = grid->columns > 0 ? grid->columns - 1 : 0;
    grid->selected_row = row;
    grid->selected_column = column;
}

void vb_grid_move_selection(VbGrid *grid, int delta_row, int delta_column)
{
    if (!grid) return;
    vb_grid_commit_edit(grid);
    vb_grid_select(grid, grid->selected_row + delta_row, grid->selected_column + delta_column);
}

int vb_grid_hit_test(const VbGrid *grid, double x, double y, int headers,
                     int *row, int *column, int *border_column)
{
    double cumulative = 0;
    double content_height;
    int c;
    int hit_row = -1;
    int hit_column = -1;
    int border = -1;
    if (row) *row = -1;
    if (column) *column = -1;
    if (border_column) *border_column = -1;
    if (!grid || grid->columns <= 0 || x < 0 || y < 0) return 0;

    content_height = grid->header_height + grid->rows * grid->row_height;
    if (y >= content_height && grid->rows > 0) return 0;

    for (c = 0; c < grid->columns; c++) {
        double edge = cumulative + vb_grid_column_width(grid, c);
        if (x < edge) {
            hit_column = c;
            break;
        }
        cumulative = edge;
    }
    if (border_column) *border_column = border;
    if (hit_column < 0) return 1;

    if (headers && y < grid->header_height) {
        if (row) *row = -1;
        if (column) *column = hit_column;
        if (border_column) {
            double cumulative_edge = 0;
            for (c = 0; c <= hit_column; c++) cumulative_edge += vb_grid_column_width(grid, c);
            *border_column = fabs(x - cumulative_edge) <= VB_GRID_RESIZE_SLOP ? hit_column : -1;
        }
        return 1;
    }

    if (grid->row_height <= 0) return 0;
    hit_row = (int)floor((y - grid->header_height) / grid->row_height);
    if (hit_row < 0) hit_row = 0;
    if (hit_row >= grid->rows) hit_row = grid->rows > 0 ? grid->rows - 1 : 0;
    if (row) *row = hit_row;
    if (column) *column = hit_column;
    if (border_column) *border_column = -1;
    return 1;
}

void vb_grid_begin_edit(VbGrid *grid)
{
    if (!grid || grid->editing) return;
    free(grid->edit);
    grid->edit = vb_strdup(vb_grid_cell(grid, grid->selected_row, grid->selected_column));
    grid->editing = 1;
}

void vb_grid_edit_reset(VbGrid *grid)
{
    if (!grid) return;
    free(grid->edit);
    grid->edit = vb_strdup("");
    grid->editing = 1;
}

void vb_grid_cancel_edit(VbGrid *grid)
{
    if (!grid) return;
    free(grid->edit);
    grid->edit = NULL;
    grid->editing = 0;
}

void vb_grid_commit_edit(VbGrid *grid)
{
    if (!grid || !grid->editing) return;
    vb_grid_set_cell(grid, grid->selected_row, grid->selected_column,
                     grid->edit ? grid->edit : "");
    free(grid->edit);
    grid->edit = NULL;
    grid->editing = 0;
}

const char *vb_grid_edit_text(const VbGrid *grid)
{
    if (!grid) return "";
    return grid->edit ? grid->edit : "";
}

void vb_grid_edit_insert(VbGrid *grid, const char *text)
{
    VbBuf buffer;
    if (!grid || !text || !*text) return;
    if (!grid->editing) vb_grid_begin_edit(grid);
    vb_buf_init(&buffer);
    vb_buf_append(&buffer, grid->edit ? grid->edit : "");
    vb_buf_append(&buffer, text);
    free(grid->edit);
    grid->edit = vb_buf_take(&buffer);
}

void vb_grid_edit_backspace(VbGrid *grid)
{
    size_t length;
    char *text;
    if (!grid || !grid->editing || !grid->edit) return;
    text = grid->edit;
    length = strlen(text);
    if (!length) return;
    /* UTF-8 safe: drop the last character, not the last byte. */
    length--;
    while (length > 0 && ((unsigned char)text[length] & 0xC0) == 0x80) length--;
    text[length] = '\0';
}
