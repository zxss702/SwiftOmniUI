// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The application's own fonts: files it carries, loaded privately for this
// process - Windows' own process-private font registration - so a `Font.custom`
// family has the chance to name them. How far the registration reaches -
// whether XAML's `FontFamily` resolves a family it holds - is Windows' to say;
// a family it does not resolve falls back as it did.
// Design: docs/design/platforms/winui/controls.md#words

#include "Relay.h"

using namespace swiftomniui;
void swiftomniui_metrics_registered_font(char const *path);

extern "C" int32_t swiftomniui_winui_register_font(char const *path) {
    if (!path || !*path) return 0;
    auto count = AddFontResourceExW(text(path).c_str(), FR_PRIVATE, nullptr);
    if (count > 0) swiftomniui_metrics_registered_font(path);
    return count;
}

#include <memory>
#include <map>
#include <dwrite.h>
#include <d2d1.h>
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <string>

namespace {
    struct FontFileFace { winrt::com_ptr<IDWriteFontFace> face; };
    using FontFileHandle = std::shared_ptr<FontFileFace>;
    // Font metrics/shaping and bitmap replay share the very same file-backed
    // face. Weak entries do not extend its lifetime after both callers release it.
    // Font access, like Canvas replay, runs on the desktop UI thread.
    std::map<std::wstring, std::weak_ptr<FontFileFace>> fontFiles;
    FontFileFace *fontFile(void *value) {
        return value ? static_cast<FontFileHandle *>(value)->get() : nullptr;
    }
    struct FontOutline : winrt::implements<FontOutline, ID2D1SimplifiedGeometrySink> {
        std::string path;
        void point(char kind, float x, float y) {
            char bytes[96]; std::snprintf(bytes, sizeof bytes, "%c%.9g %.9g ", kind, x, -y); path += bytes;
        }
        void __stdcall SetFillMode(D2D1_FILL_MODE) noexcept override {}
        void __stdcall SetSegmentFlags(D2D1_PATH_SEGMENT) noexcept override {}
        void __stdcall BeginFigure(D2D1_POINT_2F p, D2D1_FIGURE_BEGIN) noexcept override { point('M', p.x, p.y); }
        void __stdcall AddLines(D2D1_POINT_2F const *p, UINT32 count) noexcept override {
            for (UINT32 i = 0; i < count; ++i) point('L', p[i].x, p[i].y);
        }
        void __stdcall AddBeziers(D2D1_BEZIER_SEGMENT const *p, UINT32 count) noexcept override {
            for (UINT32 i = 0; i < count; ++i) {
                point('C', p[i].point1.x, p[i].point1.y);
                point(' ', p[i].point2.x, p[i].point2.y); point(' ', p[i].point3.x, p[i].point3.y);
            }
        }
        void __stdcall EndFigure(D2D1_FIGURE_END end) noexcept override { if (end == D2D1_FIGURE_END_CLOSED) path += "Z "; }
        HRESULT __stdcall Close() noexcept override { return S_OK; }
    };
}
// Borrowed by the native shaping bridge; the FontFace owner outlives each
// synchronous shaping call and keeps this exact, file-backed face alive.
IDWriteFontFace *swiftomniui_native_font_face(void *value) {
    auto face = fontFile(value);
    return face ? face->face.get() : nullptr;
}
extern "C" void *swiftomniui_winui_font_open(char const *path, double *units) {
    try {
        if (!path || !*path || !units) return nullptr;
        auto name = std::wstring(text(path).c_str());
        for (auto entry = fontFiles.begin(); entry != fontFiles.end();) {
            if (entry->second.expired()) entry = fontFiles.erase(entry);
            else ++entry;
        }
        auto cached = fontFiles.find(name);
        if (cached != fontFiles.end()) {
            if (auto face = cached->second.lock()) {
                DWRITE_FONT_METRICS metrics; face->face->GetMetrics(&metrics);
                *units = metrics.designUnitsPerEm;
                return new FontFileHandle(std::move(face));
            }
        }
        winrt::com_ptr<IDWriteFactory> factory;
        winrt::check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown **>(factory.put())));
        winrt::com_ptr<IDWriteFontFile> file;
        winrt::check_hresult(factory->CreateFontFileReference(name.c_str(), nullptr, file.put()));
        BOOL supported = FALSE; DWRITE_FONT_FILE_TYPE fileType; DWRITE_FONT_FACE_TYPE faceType; UINT32 count = 0;
        winrt::check_hresult(file->Analyze(&supported, &fileType, &faceType, &count));
        if (!supported || !count) return nullptr;
        auto result = std::make_shared<FontFileFace>();
        IDWriteFontFile *files[] = {file.get()};
        winrt::check_hresult(factory->CreateFontFace(faceType, 1, files, 0, DWRITE_FONT_SIMULATIONS_NONE, result->face.put()));
        DWRITE_FONT_METRICS metrics; result->face->GetMetrics(&metrics); *units = metrics.designUnitsPerEm;
        fontFiles[name] = result;
        return new FontFileHandle(std::move(result));
    } catch (...) { report("opening a private font face"); return nullptr; }
}
extern "C" void swiftomniui_winui_font_close(void *face) { delete static_cast<FontFileHandle *>(face); }
extern "C" uint16_t swiftomniui_winui_font_glyph(void *value, uint32_t scalar) {
    UINT16 glyph = 0; auto face = fontFile(value);
    if (face) face->face->GetGlyphIndices(&scalar, 1, &glyph);
    return glyph;
}
extern "C" bool swiftomniui_winui_font_metrics(void *value, uint16_t glyph, double *out) {
    auto face = fontFile(value); DWRITE_GLYPH_METRICS m{};
    if (!face || FAILED(face->face->GetDesignGlyphMetrics(&glyph, 1, &m))) return false;
    auto top = static_cast<double>(m.verticalOriginY) - m.topSideBearing;
    auto height = static_cast<double>(m.advanceHeight) - m.topSideBearing - m.bottomSideBearing;
    out[0] = m.advanceWidth; out[1] = m.leftSideBearing; out[2] = top - height;
    out[3] = static_cast<double>(m.advanceWidth) - m.leftSideBearing - m.rightSideBearing; out[4] = height;
    return true;
}
extern "C" int32_t swiftomniui_winui_font_outline(void *value, uint16_t glyph, char *out, int32_t capacity) {
    try {
        auto face = fontFile(value); if (!face) return 0;
        DWRITE_FONT_METRICS metrics; face->face->GetMetrics(&metrics);
        auto sink = winrt::make_self<FontOutline>();
        winrt::check_hresult(face->face->GetGlyphRunOutline(metrics.designUnitsPerEm, &glyph, nullptr, nullptr, 1, FALSE, FALSE, sink.get()));
        if (out && capacity > static_cast<int32_t>(sink->path.size())) {
            std::memcpy(out, sink->path.data(), sink->path.size()); out[sink->path.size()] = 0;
        }
        return static_cast<int32_t>(sink->path.size());
    } catch (...) { report("reading a font outline"); return 0; }
}
extern "C" int32_t swiftomniui_winui_font_table(void *value, char const *tag, uint8_t *out, int32_t capacity) {
    auto face = fontFile(value); if (!face || !tag || std::strlen(tag) != 4) return 0;
    void const *data = nullptr; UINT32 size = 0; void *context = nullptr; BOOL exists = FALSE;
    UINT32 key = DWRITE_MAKE_OPENTYPE_TAG(tag[0], tag[1], tag[2], tag[3]);
    if (FAILED(face->face->TryGetFontTable(key, &data, &size, &context, &exists)) || !exists) return 0;
    if (out && capacity >= static_cast<int32_t>(size)) std::memcpy(out, data, size);
    face->face->ReleaseFontTable(context);
    return static_cast<int32_t>(size);
}
