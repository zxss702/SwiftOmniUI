// SPDX-License-Identifier: Apache-2.0
// Exact file-backed OpenType shaping. DirectWrite owns script/bidi analysis,
// glyph substitution/positioning and Unicode line breaking.
#include "Relay.h"
#include <dwrite.h>
#include <algorithm>
#include <memory>
#include <iterator>
#include <numeric>
#include <vector>

IDWriteFontFace *swiftomniui_native_font_face(void *value);
using namespace swiftomniui;

namespace {
    struct FontTextAnalysis final : winrt::implements<FontTextAnalysis,
        IDWriteTextAnalysisSource, IDWriteTextAnalysisSink> {
        WCHAR const *text;
        UINT32 length;
        WCHAR locale[LOCALE_NAME_MAX_LENGTH]{};
        DWRITE_READING_DIRECTION direction = DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
        std::vector<DWRITE_SCRIPT_ANALYSIS> scripts;
        std::vector<UINT8> levels;
        std::vector<DWRITE_LINE_BREAKPOINT> breaks;
        FontTextAnalysis(WCHAR const *text, UINT32 length)
            : text(text), length(length), scripts(length), levels(length), breaks(length) {
            if (!GetUserDefaultLocaleName(locale, LOCALE_NAME_MAX_LENGTH)) {
                WCHAR const fallback[] = L"en-US";
                std::copy(std::begin(fallback), std::end(fallback), locale);
            }
            std::vector<WORD> classes(length);
            if (GetStringTypeW(CT_CTYPE2, text, static_cast<int>(length), classes.data())) {
                for (auto value : classes) {
                    if (value == C2_RIGHTTOLEFT) { direction = DWRITE_READING_DIRECTION_RIGHT_TO_LEFT; break; }
                    if (value == C2_LEFTTORIGHT) break;
                }
            }
        }
        HRESULT __stdcall GetTextAtPosition(UINT32 position, WCHAR const **out, UINT32 *count) noexcept override {
            *out = position < length ? text + position : nullptr;
            *count = position < length ? length - position : 0; return S_OK;
        }
        HRESULT __stdcall GetTextBeforePosition(UINT32 position, WCHAR const **out, UINT32 *count) noexcept override {
            position = std::min(position, length);
            *out = position ? text : nullptr; *count = position; return S_OK;
        }
        DWRITE_READING_DIRECTION __stdcall GetParagraphReadingDirection() noexcept override {
            return direction;
        }
        HRESULT __stdcall GetLocaleName(UINT32 position, UINT32 *count, WCHAR const **name) noexcept override {
            *count = position < length ? length - position : 0; *name = locale; return S_OK;
        }
        HRESULT __stdcall GetNumberSubstitution(UINT32 position, UINT32 *count,
            IDWriteNumberSubstitution **substitution) noexcept override {
            *count = position < length ? length - position : 0; *substitution = nullptr; return S_OK;
        }
        HRESULT __stdcall SetScriptAnalysis(UINT32 position, UINT32 count,
            DWRITE_SCRIPT_ANALYSIS const *analysis) noexcept override {
            if (position > length || count > length - position) return E_INVALIDARG;
            std::fill_n(scripts.begin() + position, count, *analysis); return S_OK;
        }
        HRESULT __stdcall SetLineBreakpoints(UINT32 position, UINT32 count,
            DWRITE_LINE_BREAKPOINT const *values) noexcept override {
            if (position > length || count > length - position) return E_INVALIDARG;
            std::copy_n(values, count, breaks.begin() + position); return S_OK;
        }
        HRESULT __stdcall SetBidiLevel(UINT32 position, UINT32 count, UINT8, UINT8 resolved) noexcept override {
            if (position > length || count > length - position) return E_INVALIDARG;
            std::fill_n(levels.begin() + position, count, resolved); return S_OK;
        }
        HRESULT __stdcall SetNumberSubstitution(UINT32, UINT32, IDWriteNumberSubstitution *) noexcept override { return S_OK; }
    };
    struct FontShapedText {
        std::vector<SwiftOmniUIShapedGlyph> glyphs;
        std::vector<uint8_t> breaks;
        double width = 0;
    };
    struct FontScriptRun { UINT32 start, length; DWRITE_SCRIPT_ANALYSIS script; UINT8 level; };

    winrt::com_ptr<IDWriteTextAnalyzer> fontAnalyzer() {
        static winrt::com_ptr<IDWriteTextAnalyzer> analyzer = [] {
            winrt::com_ptr<IDWriteFactory> factory;
            winrt::check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(factory.put())));
            winrt::com_ptr<IDWriteTextAnalyzer> result;
            winrt::check_hresult(factory->CreateTextAnalyzer(result.put()));
            return result;
        }();
        return analyzer;
    }
    void shapeFontRun(FontShapedText &result, IDWriteTextAnalyzer *analyzer, IDWriteFontFace *face,
        FontTextAnalysis const &analysis, FontScriptRun const &run, float em) {
        // Cluster maps are UINT16. Split very long runs before calling this
        // function; a native buffer can grow up to the representable glyph count.
        UINT32 capacity = std::min<UINT32>(65535, run.length * 3 / 2 + 16), count = 0;
        std::vector<UINT16> clusters(run.length), ids;
        std::vector<DWRITE_SHAPING_TEXT_PROPERTIES> textProperties(run.length);
        std::vector<DWRITE_SHAPING_GLYPH_PROPERTIES> glyphProperties;
        BOOL rtl = (run.level & 1) != 0;
        for (;;) {
            ids.resize(capacity); glyphProperties.resize(capacity);
            HRESULT status = analyzer->GetGlyphs(analysis.text + run.start, run.length, face,
                FALSE, rtl, &run.script, analysis.locale, nullptr, nullptr, nullptr, 0,
                capacity, clusters.data(), textProperties.data(), ids.data(), glyphProperties.data(), &count);
            if (SUCCEEDED(status)) break;
            if (status != HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER) || capacity == 65535)
                winrt::check_hresult(status);
            capacity = std::min<UINT32>(65535, capacity * 2);
        }
        if (!count) return;
        if (result.glyphs.size() > static_cast<size_t>(INT32_MAX) - count) winrt::throw_hresult(E_BOUNDS);
        std::vector<FLOAT> advances(count);
        std::vector<DWRITE_GLYPH_OFFSET> offsets(count);
        winrt::check_hresult(analyzer->GetGlyphPlacements(analysis.text + run.start, clusters.data(),
            textProperties.data(), run.length, ids.data(), glyphProperties.data(), count, face, em,
            FALSE, rtl, &run.script, analysis.locale, nullptr, nullptr, 0, advances.data(), offsets.data()));
        bool visible = (run.script.shapes & DWRITE_SCRIPT_SHAPES_NO_VISUAL) == 0;
        if (!visible) std::fill(advances.begin(), advances.end(), 0.0f);
        // Map each glyph to the complete original UTF-16 cluster in linear time.
        std::vector<UINT32> clusterStart(count, run.length), clusterEnd(count, 0);
        for (UINT32 character = 0; character < run.length; ++character) {
            auto glyph = clusters[character];
            if (glyph >= count) winrt::throw_hresult(E_UNEXPECTED);
            clusterStart[glyph] = std::min(clusterStart[glyph], character);
            clusterEnd[glyph] = std::max(clusterEnd[glyph], character + 1);
        }
        UINT32 current = 0;
        for (UINT32 glyph = 0; glyph < count; ++glyph) {
            if (clusterStart[glyph] != run.length) current = glyph;
            else {
                if (clusterStart[current] == run.length) winrt::throw_hresult(E_UNEXPECTED);
                clusterStart[glyph] = clusterStart[current]; clusterEnd[glyph] = clusterEnd[current];
            }
        }
        double runWidth = std::accumulate(advances.begin(), advances.end(), 0.0);
        double pen = rtl ? result.width + runWidth : result.width;
        for (UINT32 glyph = 0; glyph < count; ++glyph) {
            if (rtl) pen -= advances[glyph];
            result.glyphs.push_back({ids[glyph], run.start + clusterStart[glyph],
                clusterEnd[glyph] - clusterStart[glyph],
                pen + (rtl ? -offsets[glyph].advanceOffset : offsets[glyph].advanceOffset),
                offsets[glyph].ascenderOffset, advances[glyph], visible});
            if (!rtl) pen += advances[glyph];
        }
        result.width += runWidth;
    }
}

extern "C" void *swiftomniui_winui_font_shape(void *value, uint16_t const *text, int32_t length) {
    try {
        auto face = swiftomniui_native_font_face(value);
        if (!face || length < 0 || (length && !text)) return nullptr;
        auto result = std::make_unique<FontShapedText>();
        result->breaks.resize(static_cast<size_t>(length) + 1);
        if (!length) { result->breaks[0] = 1; return result.release(); }
        auto analysis = winrt::make_self<FontTextAnalysis>(reinterpret_cast<WCHAR const *>(text), static_cast<UINT32>(length));
        auto analyzer = fontAnalyzer();
        winrt::check_hresult(analyzer->AnalyzeScript(analysis.get(), 0, length, analysis.get()));
        winrt::check_hresult(analyzer->AnalyzeBidi(analysis.get(), 0, length, analysis.get()));
        winrt::check_hresult(analyzer->AnalyzeLineBreakpoints(analysis.get(), 0, length, analysis.get()));
        for (UINT32 position = 1; position <= static_cast<UINT32>(length); ++position) {
            auto after = analysis->breaks[position - 1].breakConditionAfter;
            auto before = position < static_cast<UINT32>(length)
                ? analysis->breaks[position].breakConditionBefore : DWRITE_BREAK_CONDITION_NEUTRAL;
            if (after == DWRITE_BREAK_CONDITION_MUST_BREAK || before == DWRITE_BREAK_CONDITION_MUST_BREAK)
                result->breaks[position] = 2;
            else if (after != DWRITE_BREAK_CONDITION_MAY_NOT_BREAK && before != DWRITE_BREAK_CONDITION_MAY_NOT_BREAK
                && (after == DWRITE_BREAK_CONDITION_CAN_BREAK || before == DWRITE_BREAK_CONDITION_CAN_BREAK))
                result->breaks[position] = 1;
        }
        if (!result->breaks[length]) result->breaks[length] = 1;
        std::vector<FontScriptRun> runs;
        for (UINT32 start = 0; start < static_cast<UINT32>(length);) {
            UINT32 end = start + 1;
            auto script = analysis->scripts[start]; auto level = analysis->levels[start];
            while (end < static_cast<UINT32>(length) && end - start < 32767
                && analysis->scripts[end].script == script.script && analysis->scripts[end].shapes == script.shapes
                && analysis->levels[end] == level) ++end;
            if (end < static_cast<UINT32>(length) && end - start == 32767
                && analysis->scripts[end].script == script.script && analysis->scripts[end].shapes == script.shapes
                && analysis->levels[end] == level) {
                // A UINT16 cluster map cannot represent an arbitrarily long
                // unbroken shaping run. Use an actual native break boundary;
                // never silently bisect a ligature or combining sequence.
                UINT32 boundary = end;
                while (boundary > start && !result->breaks[boundary]) --boundary;
                if (boundary == start) winrt::throw_hresult(E_BOUNDS);
                end = boundary;
            }
            if (end < static_cast<UINT32>(length) && text[end - 1] >= 0xD800 && text[end - 1] <= 0xDBFF
                && text[end] >= 0xDC00 && text[end] <= 0xDFFF) {
                if (end > start + 1) --end;
                else ++end;
            }
            runs.push_back({start, end - start, script, level}); start = end;
        }
        // Reorder native script runs by their resolved bidi levels (UAX #9 L2).
        UINT8 maximum = 0, minimumOdd = 255;
        for (auto const &run : runs) { maximum = std::max(maximum, run.level); if (run.level & 1) minimumOdd = std::min(minimumOdd, run.level); }
        for (int level = maximum; level >= minimumOdd; --level) {
            for (size_t first = 0; first < runs.size();) {
                if (runs[first].level < level) { ++first; continue; }
                size_t end = first + 1;
                while (end < runs.size() && runs[end].level >= level) ++end;
                std::reverse(runs.begin() + first, runs.begin() + end); first = end;
            }
        }
        DWRITE_FONT_METRICS metrics{}; face->GetMetrics(&metrics);
        for (auto const &run : runs) shapeFontRun(*result, analyzer.get(), face, *analysis, run, metrics.designUnitsPerEm);
        return result.release();
    } catch (...) { report("shaping a private font face"); return nullptr; }
}
extern "C" int32_t swiftomniui_winui_shaped_glyph_count(void *shape) {
    auto result = static_cast<FontShapedText *>(shape); return result ? static_cast<int32_t>(result->glyphs.size()) : 0;
}
extern "C" SwiftOmniUIShapedGlyph const *swiftomniui_winui_shaped_glyphs(void *shape) {
    auto result = static_cast<FontShapedText *>(shape); return result ? result->glyphs.data() : nullptr;
}
extern "C" uint8_t const *swiftomniui_winui_shaped_breaks(void *shape) {
    auto result = static_cast<FontShapedText *>(shape); return result ? result->breaks.data() : nullptr;
}
extern "C" double swiftomniui_winui_shaped_width(void *shape) {
    auto result = static_cast<FontShapedText *>(shape); return result ? result->width : 0;
}
extern "C" void swiftomniui_winui_shaped_close(void *shape) { delete static_cast<FontShapedText *>(shape); }
