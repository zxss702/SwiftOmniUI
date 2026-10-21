// SPDX-License-Identifier: Apache-2.0
#include "Relay.h"
#include <dwrite_3.h>
#include <winrt/Windows.UI.ViewManagement.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cwctype>
#include <map>
#include <tuple>
#include <vector>
#include <climits>

IDWriteFontFace *swiftomniui_native_font_face(void *value);
using namespace swiftomniui;

namespace {
    struct RegisteredFont {
        std::vector<std::wstring> families;
        winrt::com_ptr<IDWriteFontFace3> face;
    };
    std::vector<RegisteredFont> registered;
    using MetricsKey = std::tuple<std::wstring, double, uint16_t, bool>;
    std::map<MetricsKey, std::vector<double>> metricsCache;
    void listenToFontEnvironment() {
        static winrt::Windows::UI::ViewManagement::UISettings settings{nullptr};
        if (settings) return;
        settings = winrt::Windows::UI::ViewManagement::UISettings();
        auto invalidate = [](auto const &, auto const &) {
            runOnUIThread([] { metricsCache.clear(); });
        };
        settings.ColorValuesChanged(invalidate);
        settings.TextScaleFactorChanged(invalidate);
    }
    std::wstring normalized(std::wstring value) {
        std::transform(value.begin(), value.end(), value.begin(), [](wchar_t ch) { return std::towlower(ch); });
        return value;
    }
    winrt::com_ptr<IDWriteFactory> metricsFactory() {
        static auto factory = [] {
            winrt::com_ptr<IDWriteFactory> result;
            winrt::check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), result.put_unknown()));
            return result;
        }();
        return factory;
    }
    controls::TextBlock metricProbe(int32_t style) {
        struct Probe { controls::TextBlock block{nullptr}; xaml::Style style{nullptr}; };
        static Probe probes[12];
        bool named = style >= 0 && style < 11;
        auto &probe = probes[named ? style + 1 : 0];
        if (!probe.block) probe.block = controls::TextBlock();
        xaml::Style wanted{nullptr};
        if (named) {
            wchar_t const *names[] = {L"TitleLargeTextBlockStyle", L"TitleTextBlockStyle", L"SubtitleTextBlockStyle",
                L"BodyLargeTextBlockStyle", L"BodyStrongTextBlockStyle", L"CaptionTextBlockStyle", L"BodyTextBlockStyle",
                L"BodyTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle"};
            if (auto app = xaml::Application::Current())
                wanted = app.Resources().TryLookup(winrt::box_value(names[style])).try_as<xaml::Style>();
        }
        if (wanted != probe.style || (wanted && !wanted.IsSealed())) {
            probe.block.Style(wanted); probe.style = wanted;
        }
        return probe.block;
    }
}

// Registration updates this process's private-family map. DirectWrite's system
// collection does not promise to discover AddFontResourceEx(FR_PRIVATE) fonts.
void swiftomniui_metrics_registered_font(char const *path) {
    try {
        double units = 0;
        void *opened = swiftomniui_winui_font_open(path, &units);
        if (!opened) return;
        auto native = swiftomniui_native_font_face(opened);
        winrt::com_ptr<IDWriteFontFace3> face;
        if (native) native->QueryInterface(__uuidof(IDWriteFontFace3), face.put_void());
        swiftomniui_winui_font_close(opened);
        if (!face) return;
        winrt::com_ptr<IDWriteLocalizedStrings> names;
        winrt::check_hresult(face->GetFamilyNames(names.put()));
        RegisteredFont entry; entry.face = face;
        for (UINT32 index = 0; index < names->GetCount(); ++index) {
            UINT32 count = 0; winrt::check_hresult(names->GetStringLength(index, &count));
            std::vector<WCHAR> buffer(static_cast<size_t>(count) + 1);
            winrt::check_hresult(names->GetString(index, buffer.data(), count + 1));
            entry.families.push_back(normalized(buffer.data()));
        }
        registered.push_back(std::move(entry)); metricsCache.clear();
    } catch (...) { report("reading registered font metrics"); }
}

extern "C" bool swiftomniui_winui_font_descriptor_metrics(char const *requestedFamily, double requestedSize,
    int32_t textStyle, double requestedWeight, int32_t attributes, int32_t design, double *out) {
    try {
        if (!out) return false;
        listenToFontEnvironment();
        auto probe = metricProbe(textStyle);
        double size = requestedSize > 0 ? requestedSize : probe.FontSize();
        if (!std::isfinite(size) || size <= 0) return false;
        uint16_t weight = requestedWeight > 0 ? static_cast<uint16_t>(std::clamp(requestedWeight, 1.0, 1000.0))
            : attributes & 1 ? 700 : probe.FontWeight().Weight;
        bool italic = (attributes & 2) != 0;
        std::wstring family = requestedFamily && *requestedFamily ? text(requestedFamily).c_str() : probe.FontFamily().Source().c_str();
        if ((!requestedFamily || !*requestedFamily) && design == 3) family = L"Consolas";
        else if ((!requestedFamily || !*requestedFamily) && design == 1) family = L"Cambria";
        auto fragment = family.find_last_of(L'#');
        if (fragment != std::wstring::npos) family = family.substr(fragment + 1);
        family = normalized(family);
        MetricsKey key{family, size, weight, italic};
        if (auto found = metricsCache.find(key); found != metricsCache.end()) {
            std::copy(found->second.begin(), found->second.end(), out); return true;
        }
        winrt::com_ptr<IDWriteFontFace> face;
        unsigned nearest = UINT_MAX;
        for (auto const &entry : registered) {
            if (std::find(entry.families.begin(), entry.families.end(), family) == entry.families.end()) continue;
            unsigned score = static_cast<unsigned>(std::abs(static_cast<int>(entry.face->GetWeight()) - weight))
                + ((entry.face->GetStyle() != DWRITE_FONT_STYLE_NORMAL) != italic ? 2000 : 0);
            if (score < nearest) { nearest = score; face = entry.face.as<IDWriteFontFace>(); }
        }
        if (!face) {
            winrt::com_ptr<IDWriteFontCollection> collection;
            winrt::check_hresult(metricsFactory()->GetSystemFontCollection(collection.put(), TRUE));
            UINT32 index = 0; BOOL exists = FALSE;
            winrt::check_hresult(collection->FindFamilyName(family.c_str(), &index, &exists));
            if (!exists && (family.empty() || family == L"xamlautofontfamily")) {
                winrt::check_hresult(collection->FindFamilyName(L"Segoe UI Variable Text", &index, &exists));
                if (!exists) winrt::check_hresult(collection->FindFamilyName(L"Segoe UI", &index, &exists));
            }
            if (!exists) return false;
            winrt::com_ptr<IDWriteFontFamily> nativeFamily;
            winrt::check_hresult(collection->GetFontFamily(index, nativeFamily.put()));
            winrt::com_ptr<IDWriteFont> font;
            winrt::check_hresult(nativeFamily->GetFirstMatchingFont(static_cast<DWRITE_FONT_WEIGHT>(weight),
                DWRITE_FONT_STRETCH_NORMAL, italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL, font.put()));
            winrt::check_hresult(font->CreateFontFace(face.put()));
        }
        DWRITE_FONT_METRICS metrics{}; face->GetMetrics(&metrics);
        if (!metrics.designUnitsPerEm) return false;
        double scale = size / metrics.designUnitsPerEm;
        double capHeight = metrics.capHeight;
        if (!capHeight) {
            UINT32 character = L'H'; UINT16 glyph = 0; DWRITE_GLYPH_METRICS ink{};
            if (SUCCEEDED(face->GetGlyphIndices(&character, 1, &glyph)) && glyph
                && SUCCEEDED(face->GetDesignGlyphMetrics(&glyph, 1, &ink)))
                capHeight = std::max(0.0, static_cast<double>(ink.verticalOriginY) - ink.topSideBearing);
        }
        std::vector<double> result{size, metrics.ascent * scale, -metrics.descent * scale,
            metrics.lineGap * scale, capHeight * scale};
        metricsCache.emplace(key, result);
        std::copy(result.begin(), result.end(), out); return true;
    } catch (...) { report("resolving native font metrics"); return false; }
}
