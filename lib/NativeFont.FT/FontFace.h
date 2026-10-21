// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_OUTLINE_H
#include FT_TRUETYPE_TABLES_H
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>

typedef struct { FT_Library library; FT_Face face; } SOUIFontFace;
static inline SOUIFontFace *soui_font_open(const char *path, double *units) {
    if (!path || !units) return NULL;
    SOUIFontFace *f = (SOUIFontFace *)calloc(1, sizeof(*f));
    if (!f) return NULL;
    if (FT_Init_FreeType(&f->library) || FT_New_Face(f->library, path, 0, &f->face)) {
        if (f->library) FT_Done_FreeType(f->library); free(f); return NULL;
    }
    if (!FT_IS_SCALABLE(f->face) || !f->face->units_per_EM) {
        FT_Done_Face(f->face); FT_Done_FreeType(f->library); free(f); return NULL;
    }
    *units = f->face->units_per_EM; return f;
}
static inline void soui_font_close(SOUIFontFace *f) { if (f) { FT_Done_Face(f->face); FT_Done_FreeType(f->library); free(f); } }
static inline uint16_t soui_font_glyph(SOUIFontFace *f, uint32_t scalar) {
    return f ? (uint16_t)FT_Get_Char_Index(f->face, scalar) : 0;
}
static inline int soui_font_metrics(SOUIFontFace *f, uint16_t glyph, double *out) {
    if (!f || !out) return 0;
    if (FT_Load_Glyph(f->face, glyph, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP)) return 0;
    FT_Glyph_Metrics m = f->face->glyph->metrics;
    out[0] = m.horiAdvance; out[1] = m.horiBearingX; out[2] = m.horiBearingY - m.height;
    out[3] = m.width; out[4] = m.height; return 1;
}
typedef struct { char *bytes; size_t length, capacity; } SOUIFontPath;
static inline int soui_font_append(SOUIFontPath *p, const char *bytes, size_t count) {
    if (count >= INT32_MAX || p->length > (size_t)INT32_MAX - count - 1) return 1;
    size_t needed = p->length + count + 1;
    if (needed > p->capacity) {
        size_t cap = needed <= (size_t)INT32_MAX / 2 ? needed * 2 : needed;
        char *next = (char *)realloc(p->bytes, cap);
        if (!next) return 1;
        p->bytes = next; p->capacity = cap;
    }
    memcpy(p->bytes + p->length, bytes, count);
    p->length += count; p->bytes[p->length] = 0;
    return 0;
}
static inline int soui_font_point(SOUIFontPath *p, char kind, const FT_Vector *v) {
    char bytes[96]; int n = snprintf(bytes, sizeof(bytes), "%c%ld %ld ", kind, (long)v->x, (long)v->y);
    if (n < 0 || (size_t)n >= sizeof(bytes)) return 1;
    return soui_font_append(p, bytes, (size_t)n);
}
static int soui_font_move(const FT_Vector *v, void *context) {
    SOUIFontPath *p = (SOUIFontPath *)context;
    if (p->length && soui_font_append(p, "Z ", 2)) return 1;
    return soui_font_point(p, 'M', v);
}
static int soui_font_line(const FT_Vector *v, void *p) { return soui_font_point((SOUIFontPath *)p, 'L', v); }
static int soui_font_conic(const FT_Vector *a, const FT_Vector *b, void *p) {
    return soui_font_point((SOUIFontPath *)p, 'Q', a) || soui_font_point((SOUIFontPath *)p, ' ', b);
}
static int soui_font_cubic(const FT_Vector *a, const FT_Vector *b, const FT_Vector *c, void *p) {
    return soui_font_point((SOUIFontPath *)p, 'C', a) || soui_font_point((SOUIFontPath *)p, ' ', b)
        || soui_font_point((SOUIFontPath *)p, ' ', c);
}
static inline int32_t soui_font_outline(SOUIFontFace *f, uint16_t glyph, char *out, int32_t capacity) {
    if (!f) return 0;
    if (FT_Load_Glyph(f->face, glyph, FT_LOAD_NO_SCALE | FT_LOAD_NO_HINTING | FT_LOAD_NO_BITMAP)) return 0;
    if (f->face->glyph->format != FT_GLYPH_FORMAT_OUTLINE) return 0;
    SOUIFontPath p = {0}; FT_Outline_Funcs functions = {soui_font_move, soui_font_line, soui_font_conic, soui_font_cubic, 0, 0};
    if (FT_Outline_Decompose(&f->face->glyph->outline, &functions, &p)) { free(p.bytes); return 0; }
    if (p.length && soui_font_append(&p, "Z ", 2)) { free(p.bytes); return 0; }
    if (out && capacity > (int32_t)p.length) {
        if (p.length) memcpy(out, p.bytes, p.length + 1);
        else out[0] = 0;
    }
    int32_t count = (int32_t)p.length; free(p.bytes); return count;
}
static inline int32_t soui_font_table(SOUIFontFace *f, const char *tag, uint8_t *out, int32_t capacity) {
    if (!f || !tag || strlen(tag) != 4) return 0;
    FT_ULong key = FT_MAKE_TAG(tag[0], tag[1], tag[2], tag[3]), count = 0;
    if (FT_Load_Sfnt_Table(f->face, key, 0, NULL, &count)) return 0;
    if (count > INT32_MAX) return 0;
    if (out && capacity >= (int32_t)count && FT_Load_Sfnt_Table(f->face, key, 0, out, &count)) return 0;
    return (int32_t)count;
}
