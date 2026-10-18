// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A canvas: SwiftOmniUI's drawing replayed with Direct2D, which WinUI itself draws
// with, into the SurfaceImageSource the canvas is painted with - again for each
// size and scale it is shown at, and for a surface that lost what it held. A
// press on it is followed from down to up, the pointer held.
// Design: docs/design/platforms/winui/drawing.md#a-canvas

#include "Figure.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <string>
#include <utility>
#include <vector>

#include <d2d1_1.h>
#include <d3d11.h>
#include <dwrite.h>
#include <microsoft.ui.xaml.media.dxinterop.h>

#include <winrt/Windows.UI.h>
#include <winrt/Microsoft.UI.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>

using namespace swiftomniui;
using winrt::Windows::Foundation::Point;
using winrt::Windows::Foundation::Size;
namespace input = winrt::Microsoft::UI::Xaml::Input;
namespace media = winrt::Microsoft::UI::Xaml::Media;

namespace {
    /// The instructions' kinds, as SwiftOmniUI numbers them.
    enum Kind : int32_t {
        FillColor, StrokeColor, TextColor, StrokeWidth, FontSize, Alpha, DrawLine, DrawRectangle, DrawRoundedRectangle,
        DrawEllipse, DrawArc, DrawPath, FillRectangle, FillRoundedRectangle, FillEllipse, FillArc, FillPath, DrawText,
        Translate, Rotate, Scale, SaveState, RestoreState, StrokeStyle, FillStyle,
        CompleteStrokeStyle = 27,
    };

    /// What every canvas draws with: Direct2D's device, made at the first drawing and again after Windows takes it
    /// away, and how many there have been; what writes text, in the system's family and the user's language.
    struct Devices {
        winrt::com_ptr<ID2D1Factory1> factory;
        winrt::com_ptr<IDWriteFactory> words;
        winrt::com_ptr<ID2D1Device> device;
        uint32_t made = 0;
        std::wstring family;
        wchar_t language[LOCALE_NAME_MAX_LENGTH] = L"";
    } devices;

    void prepare() {
        if (!devices.factory) {
            D2D1_FACTORY_OPTIONS options{};
            winrt::check_hresult(D2D1CreateFactory(
                D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory1), &options, devices.factory.put_void()));
            winrt::check_hresult(DWriteCreateFactory(
                DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), reinterpret_cast<IUnknown **>(devices.words.put())));
            // Segoe UI Variable where Windows has it, Segoe UI before.
            winrt::com_ptr<IDWriteFontCollection> fonts;
            UINT32 index = 0;
            BOOL found = FALSE;
            if (SUCCEEDED(devices.words->GetSystemFontCollection(fonts.put())))
                fonts->FindFamilyName(L"Segoe UI Variable Text", &index, &found);
            devices.family = found ? L"Segoe UI Variable Text" : L"Segoe UI";
            GetUserDefaultLocaleName(devices.language, LOCALE_NAME_MAX_LENGTH);
        }
        if (devices.device) return;

        winrt::com_ptr<ID3D11Device> direct3D;
        auto make = [&](D3D_DRIVER_TYPE driver) {
            direct3D = nullptr;
            return D3D11CreateDevice(nullptr, driver, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                     D3D11_SDK_VERSION, direct3D.put(), nullptr, nullptr);
        };
        // Where the graphics card gives no device, Windows' own rasterizer draws.
        if (FAILED(make(D3D_DRIVER_TYPE_HARDWARE))) winrt::check_hresult(make(D3D_DRIVER_TYPE_WARP));
        winrt::check_hresult(devices.factory->CreateDevice(direct3D.as<IDXGIDevice>().get(), devices.device.put()));
        devices.made += 1;
    }

    /// Whether drawing failed for a device Windows took away: a driver updated or reset, the card removed.
    bool lost(HRESULT result) {
        return result == DXGI_ERROR_DEVICE_REMOVED || result == DXGI_ERROR_DEVICE_RESET || result == D2DERR_RECREATE_TARGET;
    }

    /// A drawing as the host lays it out: kinds and whole numbers, numbers, and text.
    struct Drawing {
        std::vector<int32_t> ints;
        std::vector<double> numbers;
        std::vector<std::wstring> words;
    };

    // These objects describe commands, not a surface. Keep one of each per
    // command while the drawing is unchanged; a different drawing, device, or
    // rasterization scale discards them together.
    struct PathResource {
        winrt::com_ptr<ID2D1PathGeometry> geometry;
        size_t numbers = 0;
    };

    struct TextResource {
        winrt::com_ptr<IDWriteTextFormat> format;
        winrt::com_ptr<IDWriteTextLayout> layout;
        winrt::com_ptr<ID2D1RectangleGeometry> edges;
    };

    struct ReplayResources {
        std::vector<PathResource> paths;
        std::vector<TextResource> texts;

        void clear() {
            paths.clear();
            texts.clear();
        }
    };

    /// Reads a drawing's lists in order, and stops for good at a record either list cannot finish.
    struct Reader {
        Drawing const &drawing;
        size_t at = 0, number = 0;
        bool whole = true;

        bool more() const { return whole && at < drawing.ints.size(); }

        int32_t integer() {
            if (at < drawing.ints.size()) return drawing.ints[at++];
            whole = false;
            return 0;
        }

        /// The next `count` numbers; null once the list runs out.
        double const *numbers(size_t count) {
            if (!whole || number + count > drawing.numbers.size()) {
                whole = false;
                return nullptr;
            }
            number += count;
            return drawing.numbers.data() + number - count;
        }
    };

    /// What an instruction may change, kept by saveState and put back by restoreState.
    struct Pen {
        D2D1_COLOR_F fill = D2D1::ColorF(D2D1::ColorF::Black);
        D2D1_COLOR_F stroke = D2D1::ColorF(D2D1::ColorF::Black);
        D2D1_COLOR_F text = D2D1::ColorF(D2D1::ColorF::Black);
        float width = 1, size = 14, alpha = 1;
        D2D1_CAP_STYLE cap = D2D1_CAP_STYLE_FLAT;
        D2D1_LINE_JOIN join = D2D1_LINE_JOIN_MITER;
        bool evenOdd = false;
        float miter = 10, phase = 0;
        std::vector<float> dashes;
        winrt::com_ptr<ID2D1StrokeStyle> style;
        D2D1_CAP_STYLE madeCap = D2D1_CAP_STYLE_FLAT;
        D2D1_LINE_JOIN madeJoin = D2D1_LINE_JOIN_MITER;
        D2D1::Matrix3x2F transform = D2D1::Matrix3x2F::Identity();

        /// The stroke style `cap` and `join` say, remade where they moved on.
        ID2D1StrokeStyle *strokeStyle() {
            if (!style || madeCap != cap || madeJoin != join) {
                madeCap = cap;
                madeJoin = join;
                style = nullptr;
                std::vector<float> relative;
                for (auto dash : dashes) relative.push_back(dash / std::max(width, 0.000001f));
                auto dashed = std::any_of(relative.begin(), relative.end(), [](float length) { return length > 0; });
                auto properties = D2D1::StrokeStyleProperties(cap, cap, cap, join, miter * 2,
                    dashed ? D2D1_DASH_STYLE_CUSTOM : D2D1_DASH_STYLE_SOLID, phase / std::max(width, 0.000001f));
                winrt::check_hresult(devices.factory->CreateStrokeStyle(properties,
                    dashed ? relative.data() : nullptr, dashed ? static_cast<uint32_t>(relative.size()) : 0, style.put()));
            }
            return style.get();
        }
    };

    D2D1_COLOR_F colour(int32_t argb) {
        auto value = static_cast<uint32_t>(argb);
        return D2D1::ColorF(((value >> 16) & 0xFF) / 255.0f, ((value >> 8) & 0xFF) / 255.0f, (value & 0xFF) / 255.0f,
                            (value >> 24) / 255.0f);
    }

    D2D1_POINT_2F point(double x, double y) {
        return D2D1::Point2F(static_cast<float>(x), static_cast<float>(y));
    }

    /// The box four numbers give: its left, top, width and height.
    D2D1_RECT_F box(double const *at) {
        return D2D1::RectF(static_cast<float>(at[0]), static_cast<float>(at[1]), static_cast<float>(at[0] + at[2]),
                           static_cast<float>(at[1] + at[3]));
    }

    /// The next `count` curves - each its kind, 0 move, 1 line, 2 cubic, 3 quadratic, 4 close, then its points -
    /// filled by the rule `evenOdd` says; null where the numbers run out first.
    winrt::com_ptr<ID2D1PathGeometry> curves(Reader &reader, int32_t count, bool evenOdd) {
        winrt::com_ptr<ID2D1PathGeometry> geometry;
        winrt::com_ptr<ID2D1GeometrySink> sink;
        winrt::check_hresult(devices.factory->CreatePathGeometry(geometry.put()));
        winrt::check_hresult(geometry->Open(sink.put()));
        sink->SetFillMode(evenOdd ? D2D1_FILL_MODE_ALTERNATE : D2D1_FILL_MODE_WINDING);
        bool open = false;
        auto start = point(0, 0);
        // A curve drawn with no figure open begins one where the last began: at the origin before any.
        auto begin = [&] {
            if (open) return;
            sink->BeginFigure(start, D2D1_FIGURE_BEGIN_FILLED);
            open = true;
        };
        for (int32_t index = 0; index < count; ++index) {
            auto const *kind = reader.numbers(1);
            if (!kind) break;
            double const *p = nullptr;
            switch (static_cast<int>(*kind)) {
            case 0:
                if (!(p = reader.numbers(2))) break;
                if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
                open = false;
                start = point(p[0], p[1]);
                begin();
                break;
            case 1:
                if (!(p = reader.numbers(2))) break;
                begin();
                sink->AddLine(point(p[0], p[1]));
                break;
            case 2:
                if (!(p = reader.numbers(6))) break;
                begin();
                sink->AddBezier(D2D1::BezierSegment(point(p[0], p[1]), point(p[2], p[3]), point(p[4], p[5])));
                break;
            case 3:
                if (!(p = reader.numbers(4))) break;
                begin();
                sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(point(p[0], p[1]), point(p[2], p[3])));
                break;
            default:
                if (open) sink->EndFigure(D2D1_FIGURE_END_CLOSED);
                open = false;
            }
        }
        if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
        winrt::check_hresult(sink->Close());
        return reader.whole ? geometry : nullptr;
    }

    /// `text` wrapped in the box `at`, set across it and down it as `across` and `down` say, cut at its edges.
    void write(ID2D1DeviceContext *context, ID2D1Brush *brush, float size, double const *at, int32_t across,
               int32_t down, std::wstring const &text, TextResource &resource) {
        if (size <= 0) return;
        if (!resource.layout) {
            TextResource next;
            if (FAILED(devices.words->CreateTextFormat(devices.family.c_str(), nullptr, DWRITE_FONT_WEIGHT_NORMAL,
                                                       DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, size,
                                                       devices.language, next.format.put())))
                return;
            next.format->SetTextAlignment(across == 1   ? DWRITE_TEXT_ALIGNMENT_CENTER
                                          : across == 2 ? DWRITE_TEXT_ALIGNMENT_TRAILING
                                                        : DWRITE_TEXT_ALIGNMENT_LEADING);
            next.format->SetParagraphAlignment(down == 1   ? DWRITE_PARAGRAPH_ALIGNMENT_CENTER
                                               : down == 2 ? DWRITE_PARAGRAPH_ALIGNMENT_FAR
                                                           : DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
            if (FAILED(devices.words->CreateTextLayout(text.c_str(), static_cast<UINT32>(text.size()), next.format.get(),
                                                       static_cast<float>(std::max(0.0, at[2])),
                                                       static_cast<float>(std::max(0.0, at[3])), next.layout.put()))
                || FAILED(devices.factory->CreateRectangleGeometry(box(at), next.edges.put())))
                return;
            resource = std::move(next);
        }
        // A layer cut by the box, where a clip would take the box's bounds once the canvas is turned.
        context->PushLayer(D2D1::LayerParameters1(D2D1::InfiniteRect(), resource.edges.get()), nullptr);
        context->DrawTextLayout(point(at[0], at[1]), resource.layout.get(), brush);
        context->PopLayer();
    }

    /// Replays `drawing` on `context`, over `base`, which places the canvas on its surface.
    void replay(ID2D1DeviceContext *context, D2D1::Matrix3x2F const &base, Drawing const &drawing,
                ReplayResources &resources) {
        winrt::com_ptr<ID2D1SolidColorBrush> brush;
        winrt::check_hresult(context->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::Black), brush.put()));
        Pen pen;
        std::vector<Pen> kept;
        auto paint = [&](D2D1_COLOR_F const &colour) {
            brush->SetColor(colour);
            brush->SetOpacity(pen.alpha);
            return brush.get();
        };
        auto place = [&] { context->SetTransform(pen.transform * base); };
        auto shape = [&](ID2D1Geometry *geometry, bool filled) {
            if (!geometry) return;
            if (filled) context->FillGeometry(geometry, paint(pen.fill));
            else if (pen.width > 0) context->DrawGeometry(geometry, paint(pen.stroke), pen.width, pen.strokeStyle());
        };

        Reader reader{drawing};
        size_t pathIndex = 0, textIndex = 0;
        while (reader.more()) {
            auto kind = reader.integer();
            double const *at = nullptr;
            switch (kind) {
            case FillColor: pen.fill = colour(reader.integer()); break;
            case StrokeColor: pen.stroke = colour(reader.integer()); break;
            case TextColor: pen.text = colour(reader.integer()); break;
            case StrokeWidth:
                if ((at = reader.numbers(1))) pen.width = static_cast<float>(std::max(0.0, *at));
                pen.style = nullptr;
                break;
            case FontSize:
                if ((at = reader.numbers(1))) pen.size = static_cast<float>(std::max(0.0, *at));
                break;
            case Alpha:
                if ((at = reader.numbers(1))) pen.alpha = static_cast<float>(std::clamp(*at, 0.0, 1.0));
                break;
            case DrawLine:
                if ((at = reader.numbers(4)) && pen.width > 0)
                    context->DrawLine(point(at[0], at[1]), point(at[2], at[3]), paint(pen.stroke), pen.width,
                                      pen.strokeStyle());
                break;
            case DrawRectangle:
                if ((at = reader.numbers(4)) && pen.width > 0)
                    context->DrawRectangle(box(at), paint(pen.stroke), pen.width, pen.strokeStyle());
                break;
            case FillRectangle:
                if ((at = reader.numbers(4))) context->FillRectangle(box(at), paint(pen.fill));
                break;
            case DrawRoundedRectangle:
            case FillRoundedRectangle: {
                if (!(at = reader.numbers(5))) break;
                auto radius = static_cast<float>(std::max(0.0, at[4]));
                auto rounded = D2D1::RoundedRect(box(at), radius, radius);
                if (kind == FillRoundedRectangle) context->FillRoundedRectangle(rounded, paint(pen.fill));
                else if (pen.width > 0) context->DrawRoundedRectangle(rounded, paint(pen.stroke), pen.width, pen.strokeStyle());
                break;
            }
            case DrawEllipse:
            case FillEllipse: {
                if (!(at = reader.numbers(4))) break;
                auto oval = D2D1::Ellipse(point(at[0] + at[2] / 2, at[1] + at[3] / 2), static_cast<float>(at[2] / 2),
                                          static_cast<float>(at[3] / 2));
                if (kind == FillEllipse) context->FillEllipse(oval, paint(pen.fill));
                else if (pen.width > 0) context->DrawEllipse(oval, paint(pen.stroke), pen.width, pen.strokeStyle());
                break;
            }
            case DrawPath:
            case FillPath: {
                auto count = reader.integer();
                if (resources.paths.size() <= pathIndex) resources.paths.resize(pathIndex + 1);
                auto &resource = resources.paths[pathIndex++];
                if (!resource.geometry) {
                    auto before = reader.number;
                    resource.geometry = curves(reader, count, kind == FillPath && pen.evenOdd);
                    if (resource.geometry) resource.numbers = reader.number - before;
                } else if (resource.numbers > 0) {
                    reader.numbers(resource.numbers);
                }
                shape(resource.geometry.get(), kind == FillPath);
                break;
            }
            case DrawText: {
                auto across = reader.integer(), down = reader.integer(), word = reader.integer();
                if (!(at = reader.numbers(4)) || word < 0 || static_cast<size_t>(word) >= drawing.words.size()) return;
                if (resources.texts.size() <= textIndex) resources.texts.resize(textIndex + 1);
                write(context, paint(pen.text), pen.size, at, across, down, drawing.words[word],
                      resources.texts[textIndex++]);
                break;
            }
            case Translate:
                if (!(at = reader.numbers(2))) break;
                pen.transform = D2D1::Matrix3x2F::Translation(static_cast<float>(at[0]), static_cast<float>(at[1])) * pen.transform;
                place();
                break;
            case Rotate:
                if (!(at = reader.numbers(1))) break;
                pen.transform = D2D1::Matrix3x2F::Rotation(static_cast<float>(*at)) * pen.transform;
                place();
                break;
            case Scale:
                if (!(at = reader.numbers(2))) break;
                pen.transform = D2D1::Matrix3x2F::Scale(static_cast<float>(at[0]), static_cast<float>(at[1])) * pen.transform;
                place();
                break;
            case SaveState:
                kept.push_back(pen);
                break;
            case RestoreState:
                if (kept.empty()) break;
                pen = kept.back();
                kept.pop_back();
                place();
                break;
            case StrokeStyle: {
                auto cap = reader.integer(), join = reader.integer();
                if (!(at = reader.numbers(1))) break;
                pen.width = static_cast<float>(std::max(0.0, *at));
                pen.style = nullptr;
                // The vocabulary: flat, round, square; miter, bevel, round.
                pen.cap = cap == 1   ? D2D1_CAP_STYLE_ROUND
                          : cap == 2 ? D2D1_CAP_STYLE_SQUARE
                                     : D2D1_CAP_STYLE_FLAT;
                pen.join = join == 1   ? D2D1_LINE_JOIN_BEVEL
                           : join == 2 ? D2D1_LINE_JOIN_ROUND
                                       : D2D1_LINE_JOIN_MITER;
                break;
            }
            case CompleteStrokeStyle: {
                auto cap = reader.integer(), join = reader.integer(), count = reader.integer();
                if (count < 0 || !(at = reader.numbers(3))) break;
                pen.width = static_cast<float>(std::max(0.0, at[0]));
                pen.miter = static_cast<float>(std::max(1.0, at[1]));
                pen.phase = static_cast<float>(at[2]);
                pen.cap = cap == 1 ? D2D1_CAP_STYLE_ROUND : cap == 2 ? D2D1_CAP_STYLE_SQUARE : D2D1_CAP_STYLE_FLAT;
                pen.join = join == 1 ? D2D1_LINE_JOIN_BEVEL : join == 2 ? D2D1_LINE_JOIN_ROUND : D2D1_LINE_JOIN_MITER;
                pen.dashes.clear();
                if (count > 0) {
                    if (!(at = reader.numbers(static_cast<size_t>(count)))) break;
                    for (int32_t index = 0; index < count; ++index) pen.dashes.push_back(static_cast<float>(std::max(0.0, at[index])));
                }
                pen.style = nullptr;
                break;
            }
            case FillStyle:
                pen.evenOdd = reader.integer() == 1;
                break;
            default:
                return;
            }
        }
    }

    /// How many canvases there are.
    int32_t canvases = 0;

    /// A canvas: a panel with no size of its own, painted with the surface its drawing is replayed on.
    struct SwiftOmniUICanvas : controls::PanelT<SwiftOmniUICanvas> {
        // Internal regression inspection, alongside the native lifetime count.
        uint64_t paints = 0;
        explicit SwiftOmniUICanvas(int64_t view) : view(view) {
            canvases += 1;
            // A clear background: the whole canvas is hit, drawn on or not.
            Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
            PointerPressed({this, &SwiftOmniUICanvas::pressed});
            PointerMoved({this, &SwiftOmniUICanvas::moved});
            PointerReleased({this, &SwiftOmniUICanvas::released});
            PointerCaptureLost({this, &SwiftOmniUICanvas::lostPress});
            PointerCanceled({this, &SwiftOmniUICanvas::lostPress});
            // A canvas put in a tree draws; WinUI's unloading is not heard: it can come after the canvas is loaded
            // again elsewhere, and would stop the drawing that waits.
            Loaded([this](auto &&, auto &&) { invalidate(); });
        }

        ~SwiftOmniUICanvas() {
            canvases -= 1;
        }

        winrt::Microsoft::UI::Xaml::Automation::Peers::AutomationPeer OnCreateAutomationPeer() {
            IInspectable self = *this;
            return figurePeer(self.as<xaml::FrameworkElement>(), view);
        }

        Size MeasureOverride(Size) {
            return {0, 0};
        }

        Size ArrangeOverride(Size final) {
            if (final != size) {
                size = final;
                // Swift supplies the renderer's commands before Arrange. A new
                // lazy row has no previous surface to display while waiting for
                // Rendering (which may already have fired in this frame).
                if (!surface && size.Width > 0 && size.Height > 0 && XamlRoot()) {
                    rendering.revoke();
                    paint();
                    return final;
                }
                // Rendering follows layout. Several arrangements and command
                // updates in this turn publish only their final surface.
                invalidate();
            }
            return final;
        }

        /// Keep the latest commands until the rendering phase knows their room.
        void show(Drawing next) {
            if (drawing.ints == next.ints && drawing.numbers == next.numbers && drawing.words == next.words) return;
            drawing = std::move(next);
            resources.clear();
            stale = true;
            invalidate();
        }

    private:
        /// Draws on the next frame, however often it is asked before then.
        void invalidate() {
            if (!rendering) rendering = media::CompositionTarget::Rendering(winrt::auto_revoke, {get_weak(), &SwiftOmniUICanvas::render});
        }

        void render(IInspectable const &, IInspectable const &) {
            rendering.revoke();
            paint();
        }

        /// Draws what stands, now: the drawing again where it, the room, the scale or the device moved. False
        /// where there is no root to draw in - nothing is asked for, and the drawing waits for the next notice.
        bool paint() {
            auto root = XamlRoot();
            if (!root) return false;
            watch(root);
            auto scale = static_cast<float>(root.RasterizationScale());
            auto across = static_cast<int32_t>(std::ceil(size.Width * scale));
            auto down = static_cast<int32_t>(std::ceil(size.Height * scale));
            if (!stale && across == drawnAcross && down == drawnDown && scale == drawnScale
                && made == devices.made) return true;

            try {
                // Clear even when the new room is empty: a later nonempty
                // surface at this scale must not reuse the old scale's data.
                if (scale != drawnScale || made != devices.made) resources.clear();
                if (across <= 0 || down <= 0) {
                    surface = nullptr;
                    drawnAcross = drawnDown = 0;
                    drawnScale = scale;
                    stale = false;
                    Background(media::SolidColorBrush(winrt::Windows::UI::Color{0, 0, 0, 0}));
                    return true;
                }
                for (int attempt = 0; attempt < 2; ++attempt) {
                    prepare();
                    if (made != devices.made) resources.clear();
                    auto target = surface;
                    bool replacement = false;
                    if (!surface || across != drawnAcross || down != drawnDown || made != devices.made) {
                        target = media::Imaging::SurfaceImageSource(across, down, false);
                        winrt::check_hresult(target.as<ISurfaceImageSourceNativeWithD2D>()->SetDevice(devices.device.get()));
                        replacement = true;
                    }
                    auto result = draw(target, across, down, scale);
                    if (!lost(result)) {
                        winrt::check_hresult(result);
                        // Publish a completed surface. A resized or newly realized
                        // row must never expose a new transparent backing while
                        // its drawing is still being replayed.
                        if (replacement) {
                            media::ImageBrush painted;
                            painted.ImageSource(target);
                            painted.Stretch(media::Stretch::Fill);
                            Background(painted);
                            surface = target;
                        }
                        drawnAcross = across;
                        drawnDown = down;
                        drawnScale = scale;
                        made = devices.made;
                        stale = false;
                        ++paints;
                        return true;
                    }
                    // Windows took the device away: a new one, a new surface, and the drawing again.
                    resources.clear();
                    devices.device = nullptr;
                }
            } catch (...) {
                report("drawing a canvas");
            }
            return false;
        }

        /// Replays the drawing on the whole surface, cleared first: the canvas's DIPs at `scale` pixels each.
        HRESULT draw(media::Imaging::SurfaceImageSource const &target, int32_t across, int32_t down, float scale) {
            auto native = target.as<ISurfaceImageSourceNativeWithD2D>();
            winrt::com_ptr<ID2D1DeviceContext> context;
            POINT offset{};
            auto began = native->BeginDraw(RECT{0, 0, across, down}, __uuidof(ID2D1DeviceContext),
                                           context.put_void(), &offset);
            if (FAILED(began)) return began;

            // The surface may be part of a larger one: the drawing starts where it does.
            context->SetDpi(96 * scale, 96 * scale);
            context->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
            auto base = D2D1::Matrix3x2F::Translation(offset.x / scale, offset.y / scale);
            context->SetTransform(base);
            context->PushAxisAlignedClip(D2D1::RectF(0, 0, across / scale, down / scale), D2D1_ANTIALIAS_MODE_ALIASED);
            context->Clear(D2D1::ColorF(0, 0, 0, 0));
            HRESULT replayed = S_OK;
            try {
                replay(context.get(), base, drawing, resources);
            } catch (...) {
                replayed = winrt::to_hresult();
                report("replaying a drawing");
            }
            context->PopAxisAlignedClip();
            auto ended = native->EndDraw();
            return FAILED(ended) ? ended : replayed;
        }

        void pressed(IInspectable const &sender, input::PointerRoutedEventArgs const &args) {
            auto element = sender.as<xaml::UIElement>();
            auto at = args.GetCurrentPoint(element);
            if (holding || !at.Properties().IsLeftButtonPressed() || !element.CapturePointer(args.Pointer())) return;
            holding = true;
            pointer = args.Pointer().PointerId();
            args.Handled(true);
            tell(0, at.Position());
        }

        void moved(IInspectable const &sender, input::PointerRoutedEventArgs const &args) {
            if (!holding || args.Pointer().PointerId() != pointer) return;
            args.Handled(true);
            tell(1, args.GetCurrentPoint(sender.as<xaml::UIElement>()).Position());
        }

        void released(IInspectable const &sender, input::PointerRoutedEventArgs const &args) {
            if (!holding || args.Pointer().PointerId() != pointer) return;
            args.Handled(true);
            auto element = sender.as<xaml::UIElement>();
            auto at = args.GetCurrentPoint(element).Position();
            holding = false;
            element.ReleasePointerCapture(args.Pointer());
            tell(2, at);
        }

        /// The press ends where it last was: its pointer taken away, or the input cancelled.
        void lostPress(IInspectable const &, input::PointerRoutedEventArgs const &args) {
            if (!holding || args.Pointer().PointerId() != pointer) return;
            holding = false;
            tell(2, last);
        }

        void tell(int32_t phase, Point at) {
            last = at;
            callbacks.canvasPressed(view, phase, at.X, at.Y);
        }

        /// Drawn again when the scale of the root it draws in changes, and whenever WinUI's surfaces lose what
        /// they held: both heard for as long as the canvas lives, and neither holds it.
        void watch(xaml::XamlRoot const &root) {
            if (watched.get() != root) {
                watched = winrt::make_weak(root);
                rootChanged = root.Changed(winrt::auto_revoke, {get_weak(), &SwiftOmniUICanvas::rootChange});
            }
            if (!contentsLost)
                contentsLost = media::CompositionTarget::SurfaceContentsLost(winrt::auto_revoke, {get_weak(), &SwiftOmniUICanvas::surfaceLost});
        }

        void rootChange(xaml::XamlRoot const &root, xaml::XamlRootChangedEventArgs const &) {
            if (static_cast<float>(root.RasterizationScale()) != drawnScale) invalidate();
        }

        void surfaceLost(IInspectable const &, IInspectable const &) {
            stale = true;
            invalidate();
        }

        int64_t view;
        Drawing drawing;
        ReplayResources resources;
        Size size{};
        bool stale = false;

        media::Imaging::SurfaceImageSource surface{nullptr};
        int32_t drawnAcross = 0, drawnDown = 0;
        float drawnScale = 0;
        uint32_t made = 0;

        bool holding = false;
        uint32_t pointer = 0;
        Point last{};

        media::CompositionTarget::Rendering_revoker rendering;
        media::CompositionTarget::SurfaceContentsLost_revoker contentsLost;
        winrt::weak_ref<xaml::XamlRoot> watched;
        xaml::XamlRoot::Changed_revoker rootChanged;
    };

    /// The canvas a handle holds, reached through an interface the canvas implements itself: the panel it is made
    /// on answers the rest.
    SwiftOmniUICanvas *canvas(SwiftOmniUIObjectRef handle) {
        return winrt::get_self<SwiftOmniUICanvas>(as<xaml::IFrameworkElementOverrides>(handle));
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_canvas_make(int64_t view) {
    try {
        return detach(winrt::make<SwiftOmniUICanvas>(view).as<controls::Panel>());
    } catch (...) {
        report("making a canvas");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_canvas_draw(
    SwiftOmniUIObjectRef handle, int32_t const *ints, int32_t intCount, double const *numbers, int32_t numberCount,
    char const *words, int32_t const *lengths, int32_t wordCount
) {
    try {
        Drawing drawing;
        drawing.ints.assign(ints, ints + intCount);
        drawing.numbers.assign(numbers, numbers + numberCount);
        for (int32_t index = 0, at = 0; index < wordCount; at += lengths[index++])
            drawing.words.emplace_back(winrt::to_hstring(std::string_view(words + at, lengths[index])));
        canvas(handle)->show(std::move(drawing));
    } catch (...) {
        report("handing a canvas its drawing");
    }
}

extern "C" int32_t swiftomniui_winui_measure_text(
    char const *utf8, char const *family, double size, int32_t weight, int32_t italic, double width, double *out
) {
    try {
        prepare();
        winrt::com_ptr<IDWriteTextFormat> format;
        auto face = family && *family ? text(family) : winrt::hstring(devices.family);
        if (FAILED(devices.words->CreateTextFormat(
                face.c_str(), nullptr,
                weight > 0 ? static_cast<DWRITE_FONT_WEIGHT>(std::min<int32_t>(weight, 999))
                           : DWRITE_FONT_WEIGHT_NORMAL,
                italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
                size > 0 ? static_cast<float>(size) : 14.0f, devices.language, format.put())))
            return 0;
        auto words = text(utf8);
        // The room the canvas gives it, or endless where none is asked; GetMetrics answers the laid-out extent.
        winrt::com_ptr<IDWriteTextLayout> layout;
        if (FAILED(devices.words->CreateTextLayout(
                words.c_str(), static_cast<UINT32>(words.size()), format.get(),
                width > 0 ? static_cast<float>(width) : std::numeric_limits<float>::max(),
                std::numeric_limits<float>::max(), layout.put())))
            return 0;
        DWRITE_TEXT_METRICS metrics;
        if (FAILED(layout->GetMetrics(&metrics))) return 0;
        out[0] = metrics.width;
        out[1] = metrics.height;
        return 1;
    } catch (...) {
        report("measuring a canvas's text");
        return 0;
    }
}

extern "C" int32_t swiftomniui_winui_canvases(void) {
    try {
        return canvases;
    } catch (...) {
        report("counting the canvases");
        return 0;
    }
}

extern "C" uint64_t swiftomniui_winui_canvas_paints(SwiftOmniUIObjectRef handle) {
    try { return canvas(handle)->paints; } catch (...) { return 0; }
}
