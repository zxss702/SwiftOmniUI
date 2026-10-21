// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <hb.h>
#include <hb-ot.h>
#include <pango/pangocairo.h>
#include <stdint.h>
#include <stdlib.h>
#include <limits.h>

typedef struct { hb_font_t *font; PangoContext *context; } SOUIShapingFont;
typedef struct {
    uint16_t glyph;
    uint32_t clusterStart, clusterLength;
    double x, y, advance;
} SOUIShapedGlyph;
typedef struct {
    SOUIShapedGlyph *glyphs;
    int32_t count;
    double width;
    uint8_t *breaks; /* UTF-16 boundaries: 0 forbidden, 1 allowed, 2 mandatory. */
} SOUIShapedText;

static inline SOUIShapingFont *soui_shaping_font_open(const char *path, int units) {
    if (!path || units <= 0) return NULL;
    hb_blob_t *blob = hb_blob_create_from_file(path);
    if (!blob || !hb_blob_get_length(blob)) { if (blob) hb_blob_destroy(blob); return NULL; }
    hb_face_t *face = hb_face_create(blob, 0);
    hb_blob_destroy(blob);
    if (!face || !hb_face_get_glyph_count(face)) { if (face) hb_face_destroy(face); return NULL; }
    SOUIShapingFont *result = (SOUIShapingFont *)calloc(1, sizeof(*result));
    if (!result) { hb_face_destroy(face); return NULL; }
    result->font = hb_font_create(face);
    hb_face_destroy(face);
    hb_ot_font_set_funcs(result->font);
    hb_font_set_scale(result->font, units, units);
    result->context = pango_font_map_create_context(pango_cairo_font_map_get_default());
    if (!result->context) { hb_font_destroy(result->font); free(result); return NULL; }
    return result;
}
static inline void soui_shaping_font_close(SOUIShapingFont *font) {
    if (!font) return;
    hb_font_destroy(font->font); g_object_unref(font->context); free(font);
}
static inline void soui_shaped_text_close(SOUIShapedText *text) {
    if (!text) return;
    free(text->glyphs); free(text->breaks); free(text);
}
static inline void soui_shaping_item_free(gpointer item) { pango_item_free((PangoItem *)item); }

/* Pango supplies script, bidi runs and Unicode break rules. Only HarfBuzz's
 * exact file-backed face supplies glyphs and metrics; Pango's font choice is
 * not used for drawing and cannot silently change the mathematical font. */
static inline SOUIShapedText *soui_font_shape(SOUIShapingFont *font, const uint16_t *text, int32_t length) {
    if (!font || length < 0 || (length && !text)) return NULL;
    SOUIShapedText *result = (SOUIShapedText *)calloc(1, sizeof(*result));
    if (!result) return NULL;
    result->breaks = (uint8_t *)calloc((size_t)length + 1, 1);
    if (!result->breaks) { soui_shaped_text_close(result); return NULL; }
    if (!length) { result->breaks[0] = 1; return result; }
    glong byteLength = 0;
    gchar *utf8 = g_utf16_to_utf8(text, length, NULL, &byteLength, NULL);
    if (!utf8 || byteLength >= INT32_MAX) { g_free(utf8); soui_shaped_text_close(result); return NULL; }
    uint32_t *offsets = (uint32_t *)calloc((size_t)byteLength + 1, sizeof(uint32_t));
    int characterCount = (int)g_utf8_strlen(utf8, byteLength);
    PangoLogAttr *attributes = (PangoLogAttr *)calloc((size_t)characterCount + 1, sizeof(PangoLogAttr));
    if (!offsets || !attributes) {
        free(offsets); free(attributes); g_free(utf8); soui_shaped_text_close(result); return NULL;
    }
    PangoLanguage *textLanguage = pango_context_get_language(font->context);
    pango_get_log_attrs(utf8, (int)byteLength, 0, textLanguage ? textLanguage : pango_language_get_default(),
                        attributes, characterCount + 1);
    const char *cursor = utf8;
    uint32_t offset = 0;
    for (int index = 0; index <= characterCount; ++index) {
        offsets[cursor - utf8] = offset;
        if (attributes[index].is_line_break)
            result->breaks[offset] = attributes[index].is_mandatory_break ? 2 : 1;
        if (index != characterCount) {
            offset += g_utf8_get_char(cursor) > 0xFFFF ? 2 : 1;
            cursor = g_utf8_next_char(cursor);
        }
    }
    free(attributes);
    result->breaks[length] = result->breaks[length] ? result->breaks[length] : 1;
    PangoDirection direction = pango_find_base_dir(utf8, (int)byteLength);
    pango_context_set_base_dir(font->context, direction == PANGO_DIRECTION_RTL ? PANGO_DIRECTION_RTL : PANGO_DIRECTION_LTR);
    GList *items = pango_itemize(font->context, utf8, 0, (int)byteLength, NULL, NULL);
    /* Font fallback can add Pango item boundaries. Merge those boundaries when
     * the script/bidi/language properties agree: the exact loaded face will
     * shape the whole run, including ligatures across that artificial split. */
    for (GList *node = items; node && node->next;) {
        PangoItem *item = (PangoItem *)node->data;
        GList *next = node->next;
        PangoItem *other = (PangoItem *)next->data;
        if (item->analysis.script == other->analysis.script && item->analysis.level == other->analysis.level
            && item->analysis.language == other->analysis.language) {
            item->length += other->length; item->num_chars += other->num_chars;
            pango_item_free(other); items = g_list_delete_link(items, next);
        } else { node = next; }
    }
    GList *visual = pango_reorder_items(items);
    int failed = items == NULL;
    for (GList *node = visual; node && !failed; node = node->next) {
        PangoItem *item = (PangoItem *)node->data;
        uint32_t start = offsets[item->offset], end = offsets[item->offset + item->length];
        hb_buffer_t *buffer = hb_buffer_create();
        hb_buffer_add_utf16(buffer, text, length, start, (int)(end - start));
        hb_buffer_set_direction(buffer, item->analysis.level & 1 ? HB_DIRECTION_RTL : HB_DIRECTION_LTR);
        hb_buffer_set_script(buffer, hb_script_from_iso15924_tag(
            g_unicode_script_to_iso15924((GUnicodeScript)item->analysis.script)));
        PangoLanguage *language = item->analysis.language ? item->analysis.language : pango_language_get_default();
        hb_buffer_set_language(buffer, hb_language_from_string(pango_language_to_string(language), -1));
        hb_buffer_set_cluster_level(buffer, HB_BUFFER_CLUSTER_LEVEL_MONOTONE_GRAPHEMES);
        hb_shape(font->font, buffer, NULL, 0);
        unsigned count = 0;
        hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buffer, &count);
        hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, NULL);
        if (!hb_buffer_allocation_successful(buffer) || count > (unsigned)INT32_MAX - (unsigned)result->count) {
            hb_buffer_destroy(buffer); failed = 1; break;
        }
        SOUIShapedGlyph *glyphs = (SOUIShapedGlyph *)realloc(result->glyphs,
            ((size_t)result->count + count) * sizeof(SOUIShapedGlyph));
        if (count && !glyphs) { hb_buffer_destroy(buffer); failed = 1; break; }
        result->glyphs = glyphs;
        uint32_t *clusterEnds = (uint32_t *)calloc((size_t)(end - start) + 1, sizeof(uint32_t));
        if (!clusterEnds) { hb_buffer_destroy(buffer); failed = 1; break; }
        for (unsigned index = 0; index < count; ++index) {
            if (info[index].cluster < start || info[index].cluster >= end) { failed = 1; break; }
            clusterEnds[info[index].cluster - start] = 1;
        }
        uint32_t nextCluster = end;
        for (uint32_t source = end; source > start;) {
            --source;
            if (clusterEnds[source - start]) {
                clusterEnds[source - start] = nextCluster;
                nextCluster = source;
            }
        }
        if (failed) { free(clusterEnds); hb_buffer_destroy(buffer); break; }
        double pen = result->width;
        for (unsigned index = 0; index < count; ++index) {
            /* HB clusters descend in RTL runs; determine ranges by logical
             * source boundaries, independently of the glyph drawing order. */
            uint32_t clusterEnd = clusterEnds[info[index].cluster - start];
            SOUIShapedGlyph glyph = { (uint16_t)info[index].codepoint, info[index].cluster,
                clusterEnd - info[index].cluster,
                pen + positions[index].x_offset, positions[index].y_offset, positions[index].x_advance };
            result->glyphs[result->count++] = glyph;
            pen += positions[index].x_advance;
        }
        free(clusterEnds);
        result->width = pen;
        hb_buffer_destroy(buffer);
    }
    g_list_free(visual); g_list_free_full(items, soui_shaping_item_free);
    free(offsets); g_free(utf8);
    if (failed) { soui_shaped_text_close(result); return NULL; }
    return result;
}
