// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#include "Relay.h"
#include "CompositionClips.h"
#include <d2d1_1.h>
#include <windows.graphics.interop.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>

using namespace swiftomniui;
namespace composition = winrt::Microsoft::UI::Composition;

namespace {
    // Geometry has no device dependency. Keep one factory rather than creating
    // a graphics device or a bitmap for each clip.
    ID2D1Factory *factory() {
        static winrt::com_ptr<ID2D1Factory> held;
        if (!held) winrt::check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED, held.put()));
        return held.get();
    }

    winrt::com_ptr<ID2D1PathGeometry> geometry(double const *commands, int32_t count, bool evenOdd) {
        if (count < 0 || (count > 0 && !commands)) throw winrt::hresult_invalid_argument();
        winrt::com_ptr<ID2D1PathGeometry> path;
        winrt::com_ptr<ID2D1GeometrySink> sink;
        winrt::check_hresult(factory()->CreatePathGeometry(path.put()));
        winrt::check_hresult(path->Open(sink.put()));
        sink->SetFillMode(evenOdd ? D2D1_FILL_MODE_ALTERNATE : D2D1_FILL_MODE_WINDING);
        bool open = false;
        D2D1_POINT_2F start{};
        auto begin = [&] {
            if (!open) { sink->BeginFigure(start, D2D1_FIGURE_BEGIN_FILLED); open = true; }
        };
        for (int32_t index = 0; index < count;) {
            auto kind = commands[index++];
            auto need = kind == 0 || kind == 1 ? 2 : kind == 2 ? 6 : kind == 3 ? 4 : 0;
            if ((kind != 0 && kind != 1 && kind != 2 && kind != 3 && kind != 4) || index + need > count)
                throw winrt::hresult_invalid_argument();
            auto p = commands + index;
            index += need;
            auto point = [&](int at) { return D2D1::Point2F(static_cast<float>(p[at]), static_cast<float>(p[at + 1])); };
            if (kind == 0) {
                if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
                start = point(0); open = false; begin();
            } else if (kind == 4) {
                if (open) sink->EndFigure(D2D1_FIGURE_END_CLOSED);
                open = false;
            } else {
                begin();
                if (kind == 1) sink->AddLine(point(0));
                else if (kind == 2) sink->AddBezier(D2D1::BezierSegment(point(0), point(2), point(4)));
                else sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(point(0), point(2)));
            }
        }
        if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
        winrt::check_hresult(sink->Close());
        return path;
    }

    // The documented native GeometrySource interop gives Composition the D2D
    // geometry directly. No Win2D dependency and no rasterized mask.
    struct GeometrySource : winrt::implements<GeometrySource,
        winrt::Windows::Graphics::IGeometrySource2D, ABI::Windows::Graphics::IGeometrySource2DInterop> {
        winrt::com_ptr<ID2D1Geometry> path;
        bool evenOdd;
        GeometrySource(winrt::com_ptr<ID2D1Geometry> value, bool rule) : path(std::move(value)), evenOdd(rule) {}

        HRESULT __stdcall GetGeometry(ID2D1Geometry **result) noexcept override {
            if (!result) return E_POINTER;
            path.copy_to(result);
            return S_OK;
        }
        HRESULT __stdcall TryGetGeometryUsingFactory(ID2D1Factory *wanted, ID2D1Geometry **result) noexcept override {
            if (!result) return E_POINTER;
            *result = nullptr;
            if (!wanted) return E_INVALIDARG;
            try {
                winrt::com_ptr<ID2D1Factory> own;
                path->GetFactory(own.put());
                if (own.get() == wanted) return GetGeometry(result);
                winrt::com_ptr<ID2D1PathGeometry> copy;
                winrt::com_ptr<ID2D1GeometrySink> sink;
                winrt::check_hresult(wanted->CreatePathGeometry(copy.put()));
                winrt::check_hresult(copy->Open(sink.put()));
                sink->SetFillMode(evenOdd ? D2D1_FILL_MODE_ALTERNATE : D2D1_FILL_MODE_WINDING);
                winrt::check_hresult(path->Simplify(D2D1_GEOMETRY_SIMPLIFICATION_OPTION_CUBICS_AND_LINES, nullptr, sink.get()));
                winrt::check_hresult(sink->Close());
                copy.as<ID2D1Geometry>().copy_to(result);
                return S_OK;
            } catch (...) { return winrt::to_hresult(); }
        }
    };
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_path_clip_make(SwiftOmniUIObjectRef element) {
    try {
        auto visual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(as<xaml::UIElement>(element));
        return detach(visual.Compositor().CreateGeometricClip(visual.Compositor().CreatePathGeometry()));
    } catch (...) { report("creating a path clip"); return nullptr; }
}

extern "C" void swiftomniui_winui_path_clip_update(
    SwiftOmniUIObjectRef clip, double const *commands, int32_t count, bool evenOdd
) {
    try {
        auto source = winrt::make<GeometrySource>(geometry(commands, count, evenOdd).as<ID2D1Geometry>(), evenOdd);
        as<composition::CompositionGeometricClip>(clip).Geometry().as<composition::CompositionPathGeometry>()
            .Path(composition::CompositionPath(source));
    } catch (...) { report("updating a path clip"); }
}

extern "C" void swiftomniui_winui_path_clip_attach(SwiftOmniUIObjectRef element, SwiftOmniUIObjectRef clip) {
    try {
        setElementCompositionClip(as<xaml::UIElement>(element),
                                  clip ? as<composition::CompositionGeometricClip>(clip) : nullptr);
    } catch (...) { report("attaching a path clip"); }
}
