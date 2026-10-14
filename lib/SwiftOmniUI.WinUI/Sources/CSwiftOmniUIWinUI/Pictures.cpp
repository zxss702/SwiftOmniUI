// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Pictures from the application's own folder: an Image showing one by file
// name, an SVG found under the PNG name it is asked for, at the size it
// declares, drawn at the size it shows at.
// Design: docs/design/platforms/winui/controls.md#pictures

#include "Relay.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <tuple>

#include <d2d1_3.h>
#include <d3d11.h>
#include <shcore.h>
#include <shlwapi.h>
#include <wincodec.h>

#include <optional>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>

using namespace swiftomniui;
namespace imaging = winrt::Microsoft::UI::Xaml::Media::Imaging;

namespace {
    /// The folder pictures are read from; empty for `Images` beside the executable.
    std::wstring folder;
    uint64_t folderRevision = 0;

    std::wstring pictures() {
        if (!folder.empty()) return folder;
        wchar_t path[MAX_PATH] = {};
        GetModuleFileNameW(nullptr, path, MAX_PATH);
        std::wstring executable(path);
        return executable.substr(0, executable.find_last_of(L"\\/") + 1) + L"Images\\";
    }

    bool exists(std::wstring const &path) {
        auto attributes = GetFileAttributesW(path.c_str());
        return attributes != INVALID_FILE_ATTRIBUTES && !(attributes & FILE_ATTRIBUTE_DIRECTORY);
    }

    /// Where attribute `name`'s value begins in an SVG's opening tag; npos for none.
    size_t attribute(std::string const &tag, std::string const &name) {
        for (auto at = tag.find(name); at != std::string::npos; at = tag.find(name, at + 1)) {
            if (at == 0 || !std::isspace(static_cast<unsigned char>(tag[at - 1]))) continue;
            auto next = tag.find_first_not_of(" \t\r\n", at + name.size());
            if (next == std::string::npos || tag[next] != '=') continue;
            next = tag.find_first_not_of(" \t\r\n", next + 1);
            if (next != std::string::npos && (tag[next] == '"' || tag[next] == '\'')) return next + 1;
        }
        return std::string::npos;
    }

    /// A length an SVG gives its picture, in DIPs; 0 for none, and for a share of a room it does not know.
    double length(std::string const &tag, std::string const &name) {
        auto at = attribute(tag, name);
        if (at == std::string::npos) return 0;
        char *end = nullptr;
        auto number = std::strtod(tag.c_str() + at, &end);
        std::string unit(end, std::strcspn(end, "\"' \t"));
        if (unit.empty() || unit == "px") return number;
        if (unit == "pt") return number * 96 / 72;
        if (unit == "pc") return number * 16;
        if (unit == "in") return number * 96;
        if (unit == "cm") return number * 96 / 2.54;
        if (unit == "mm") return number * 96 / 25.4;
        return 0;
    }

    /// Where an SVG's opening tag stands in its text, and how long it is; npos for none.
    std::pair<size_t, size_t> root(std::string const &text) {
        auto start = text.find("<svg");
        if (start == std::string::npos) return {start, 0};
        return {start, std::min(text.find('>', start), text.size()) - start};
    }

    /// The size an SVG declares, in DIPs: its width and height, the one missing taken from its viewBox's
    /// proportions, or its viewBox's; zero where it declares none.
    winrt::Windows::Foundation::Size declared(std::string const &text) {
        auto [start, span] = root(text);
        if (start == std::string::npos) return {};
        auto tag = text.substr(start, span);
        double width = length(tag, "width"), height = length(tag, "height");
        double box[4] = {};
        if (auto at = attribute(tag, "viewBox"); at != std::string::npos) {
            char const *cursor = tag.c_str() + at;
            for (auto &number : box) {
                char *end = nullptr;
                number = std::strtod(cursor, &end);
                cursor = end + std::strspn(end, ", \t\r\n");
            }
        }
        if (box[2] > 0 && box[3] > 0) {
            if (width <= 0 && height <= 0) width = box[2], height = box[3];
            else if (width <= 0) width = height * box[2] / box[3];
            else if (height <= 0) height = width * box[3] / box[2];
        }
        if (width <= 0 || height <= 0) return {};
        return {static_cast<float>(width), static_cast<float>(height)};
    }

    /// Makes the picture `text` draws give up its proportions, filling whatever room it is drawn in.
    void letGoOfProportions(std::string &text) {
        auto [start, span] = root(text);
        if (start == std::string::npos) return;
        auto tag = text.substr(start, span);
        if (auto at = attribute(tag, "preserveAspectRatio"); at != std::string::npos)
            text.replace(start + at, tag.find(tag[at - 1], at) - at, "none");
        else
            text.insert(start + 4, " preserveAspectRatio=\"none\"");
    }

    std::string contents(std::wstring const &path) {
        std::string text;
        FILE *file = nullptr;
        if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || !file) return text;
        char buffer[16384];
        for (size_t read; (read = std::fread(buffer, 1, sizeof buffer, file)) > 0;) text.append(buffer, read);
        std::fclose(file);
        return text;
    }

    /// A bitmap's pixels, decoded once: premultiplied RGBA rows, shared by native Image and PicturePixels.
    struct DecodedPixels {
        UINT width = 0, height = 0;
        std::vector<uint8_t> rgba;
    };

    /// The pixels of the picture at `path`, decoded to premultiplied RGBA by the platform's imaging component;
    /// nil where the file is no bitmap it reads - an SVG, or a format it does not know.
    DecodedPixels const *decodedPixels(std::wstring const &path) {
        static std::map<std::wstring, std::optional<DecodedPixels>> decoded;
        if (auto kept = decoded.find(path); kept != decoded.end())
            return kept->second ? &*kept->second : nullptr;
        std::optional<DecodedPixels> result;
        winrt::com_ptr<IWICImagingFactory> factory;
        winrt::com_ptr<IWICBitmapDecoder> decoder;
        winrt::com_ptr<IWICBitmapFrameDecode> frame;
        winrt::com_ptr<IWICFormatConverter> converted;
        if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                      IID_PPV_ARGS(factory.put())))
            && SUCCEEDED(factory->CreateDecoderFromFilename(
                path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad, decoder.put()))
            && SUCCEEDED(decoder->GetFrame(0, frame.put()))
            && SUCCEEDED(factory->CreateFormatConverter(converted.put()))
            && SUCCEEDED(converted->Initialize(frame.get(), GUID_WICPixelFormat32bppPRGBA,
                WICBitmapDitherTypeNone, nullptr, 0.0, WICBitmapPaletteTypeCustom))) {
            DecodedPixels out;
            if (SUCCEEDED(converted->GetSize(&out.width, &out.height)) && out.width > 0 && out.height > 0) {
                out.rgba.resize(static_cast<size_t>(out.width) * out.height * 4);
                if (SUCCEEDED(converted->CopyPixels(
                        nullptr, out.width * 4, static_cast<UINT>(out.rgba.size()), out.rgba.data())))
                    result = std::move(out);
            }
        }
        auto placed = decoded.emplace(path, std::move(result));
        return placed.first->second ? &*placed.first->second : nullptr;
    }

    /// The system WIC decoder finishes reading the bitmap before XAML receives
    /// its pixels. No URI, stream-source setter or later ImageOpened is involved.
    imaging::WriteableBitmap bitmapSource(std::wstring const &path) {
        static std::map<std::wstring, imaging::WriteableBitmap> decoded;
        if (auto kept = decoded.find(path); kept != decoded.end()) return kept->second;
        auto pixels = decodedPixels(path);
        if (!pixels) winrt::throw_hresult(WINCODEC_ERR_BADIMAGE);
        imaging::WriteableBitmap source(pixels->width, pixels->height);
        auto buffer = source.PixelBuffer().data();
        for (size_t at = 0; at < pixels->rgba.size(); at += 4) {
            buffer[at] = pixels->rgba[at + 2];
            buffer[at + 1] = pixels->rgba[at + 1];
            buffer[at + 2] = pixels->rgba[at];
            buffer[at + 3] = pixels->rgba[at + 3];
        }
        source.Invalidate();
        decoded.emplace(path, source);
        return source;
    }

    /// SvgImageSource itself uses Direct2D, but its load and rerasterization are
    /// asynchronous. Ordinary Image instead parses and draws with that same system
    /// SVG engine before assigning a ready WriteableBitmap to the native Image.
    struct SvgDevice {
        winrt::com_ptr<ID2D1DeviceContext5> context;
        uint64_t generation = 0;

        void prepare() {
            if (context) return;
            winrt::com_ptr<ID3D11Device> direct3D;
            auto make = [&](D3D_DRIVER_TYPE driver) {
                direct3D = nullptr;
                return D3D11CreateDevice(nullptr, driver, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0,
                                         D3D11_SDK_VERSION, direct3D.put(), nullptr, nullptr);
            };
            if (FAILED(make(D3D_DRIVER_TYPE_HARDWARE))) winrt::check_hresult(make(D3D_DRIVER_TYPE_WARP));
            winrt::com_ptr<ID2D1Device> device;
            winrt::check_hresult(D2D1CreateDevice(direct3D.as<IDXGIDevice>().get(), nullptr, device.put()));
            winrt::com_ptr<ID2D1DeviceContext> base;
            winrt::check_hresult(device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, base.put()));
            context = base.as<ID2D1DeviceContext5>();
            ++generation;
        }
    } svgDevice;

    struct SvgPicture {
        std::string text;
        winrt::Windows::Foundation::Size size{};
        winrt::com_ptr<ID2D1SvgDocument> document;
        uint64_t generation = 0;
    };

    SvgPicture &svgPicture(std::wstring const &path, bool stretch) {
        static std::map<std::pair<std::wstring, bool>, SvgPicture> pictures;
        auto key = std::make_pair(path, stretch);
        auto found = pictures.find(key);
        if (found == pictures.end()) {
            SvgPicture picture;
            picture.text = contents(path);
            picture.size = declared(picture.text);
            if (stretch) letGoOfProportions(picture.text);
            found = pictures.emplace(std::move(key), std::move(picture)).first;
        }
        return found->second;
    }

    using SvgRasterKey = std::tuple<std::wstring, bool, int32_t, int32_t>;
    struct SvgRaster {
        imaging::WriteableBitmap bitmap{nullptr};
        uint64_t used = 0;
    };
    std::map<SvgRasterKey, SvgRaster> svgRasters;
    uint64_t svgRasterBytes = 0, svgRasterUse = 0;
    constexpr uint64_t svgRasterBudget = 64 * 1024 * 1024;

    /// Keeps decoded CPU pixels, independent of the graphics device. Evicting a
    /// cache entry never removes a bitmap still held by a visible native Image.
    void keepRaster(SvgRasterKey const &key, imaging::WriteableBitmap const &bitmap) {
        auto bytes = static_cast<uint64_t>(bitmap.PixelWidth()) * bitmap.PixelHeight() * 4;
        if (bytes > svgRasterBudget) return;
        while (!svgRasters.empty() && svgRasterBytes + bytes > svgRasterBudget) {
            auto oldest = std::min_element(svgRasters.begin(), svgRasters.end(),
                [](auto const &a, auto const &b) { return a.second.used < b.second.used; });
            auto held = oldest->second.bitmap;
            svgRasterBytes -= static_cast<uint64_t>(held.PixelWidth()) * held.PixelHeight() * 4;
            svgRasters.erase(oldest);
        }
        svgRasters.emplace(key, SvgRaster{bitmap, ++svgRasterUse});
        svgRasterBytes += bytes;
    }

    imaging::WriteableBitmap svgSource(std::wstring const &path, bool stretch, int32_t width, int32_t height) {
        SvgRasterKey key{path, stretch, width, height};
        if (auto kept = svgRasters.find(key); kept != svgRasters.end()) {
            kept->second.used = ++svgRasterUse;
            return kept->second.bitmap;
        }
        auto &picture = svgPicture(path, stretch);
        auto own = picture.size;
        // SVGs without intrinsic dimensions use the SVG initial viewport.
        auto across = own.Width > 0 ? own.Width : 300.0f;
        auto down = own.Height > 0 ? own.Height : 150.0f;
        for (int attempt = 0; attempt < 2; ++attempt) {
            svgDevice.prepare();
            auto context = svgDevice.context;
            if (!picture.document || picture.generation != svgDevice.generation) {
                winrt::com_ptr<IStream> memory;
                memory.attach(SHCreateMemStream(reinterpret_cast<BYTE const *>(picture.text.data()),
                                              static_cast<UINT>(picture.text.size())));
                if (!memory) winrt::throw_hresult(E_OUTOFMEMORY);
                picture.document = nullptr;
                winrt::check_hresult(context->CreateSvgDocument(memory.get(), D2D1::SizeF(across, down),
                                                               picture.document.put()));
                picture.generation = svgDevice.generation;
            }
            D2D1_BITMAP_PROPERTIES1 properties{};
            properties.pixelFormat = {DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED};
            properties.dpiX = properties.dpiY = 96;
            properties.bitmapOptions = D2D1_BITMAP_OPTIONS_TARGET;
            winrt::com_ptr<ID2D1Bitmap1> target;
            winrt::check_hresult(context->CreateBitmap(D2D1::SizeU(width, height), nullptr, 0, &properties, target.put()));
            context->SetTarget(target.get());
            context->SetTransform(D2D1::Matrix3x2F::Scale(width / across, height / down));
            context->BeginDraw();
            context->Clear(D2D1::ColorF(0, 0, 0, 0));
            context->DrawSvgDocument(picture.document.get());
            auto result = context->EndDraw();
            context->SetTarget(nullptr);
            if (result == DXGI_ERROR_DEVICE_REMOVED || result == DXGI_ERROR_DEVICE_RESET || result == D2DERR_RECREATE_TARGET) {
                svgDevice.context = nullptr;
                continue;
            }
            winrt::check_hresult(result);

            // Copy the finished system rendering into XAML's CPU pixel buffer.
            // No dispatcher pump, async source, or ImageOpened callback is needed.
            properties.bitmapOptions = static_cast<D2D1_BITMAP_OPTIONS>(
                D2D1_BITMAP_OPTIONS_CPU_READ | D2D1_BITMAP_OPTIONS_CANNOT_DRAW);
            winrt::com_ptr<ID2D1Bitmap1> readable;
            winrt::check_hresult(context->CreateBitmap(D2D1::SizeU(width, height), nullptr, 0, &properties, readable.put()));
            winrt::check_hresult(readable->CopyFromBitmap(nullptr, target.get(), nullptr));
            imaging::WriteableBitmap bitmap(width, height);
            auto pixels = bitmap.PixelBuffer().data();
            D2D1_MAPPED_RECT mapped{};
            winrt::check_hresult(readable->Map(D2D1_MAP_OPTIONS_READ, &mapped));
            for (int32_t row = 0; row < height; ++row)
                std::memcpy(pixels + static_cast<size_t>(row) * width * 4,
                            mapped.bits + static_cast<size_t>(row) * mapped.pitch, static_cast<size_t>(width) * 4);
            winrt::check_hresult(readable->Unmap());
            bitmap.Invalidate();
            keepRaster(key, bitmap);
            return bitmap;
        }
        winrt::throw_hresult(D2DERR_RECREATE_TARGET);
    }

    imaging::WriteableBitmap svgSource(std::wstring const &path, bool stretch = false) {
        auto own = svgPicture(path, stretch).size;
        return svgSource(path, stretch, std::max(1, static_cast<int32_t>(std::ceil(own.Width > 0 ? own.Width : 300))),
                         std::max(1, static_cast<int32_t>(std::ceil(own.Height > 0 ? own.Height : 150))));
    }
}

std::wstring swiftomniui::pictureFile(char const *names) {
    std::string_view left(names ? names : "");
    while (!left.empty()) {
        auto end = left.find('\n');
        auto name = left.substr(0, end);
        std::wstring each(winrt::to_hstring(name).c_str());
        if (!each.empty() && exists(pictures() + each)) return each;
        if (end == std::string_view::npos) break;
        left.remove_prefix(end + 1);
    }
    return {};
}

xaml::Media::ImageSource swiftomniui::pictureSource(std::wstring const &file) {
    auto path = pictures() + file;
    auto dot = file.find_last_of(L'.');
    if (dot != std::wstring::npos && file.substr(dot) == L".svg") return svgSource(path);
    return bitmapSource(path);
}

extern "C" void swiftomniui_winui_set_pictures(char const *utf8) {
    try {
        std::wstring next = winrt::to_hstring(std::string_view(utf8 ? utf8 : "")).c_str();
        if (!next.empty() && next.back() != L'\\' && next.back() != L'/') next += L'\\';
        if (folder != next) { folder = std::move(next); ++folderRevision; }
    } catch (...) {
        report("naming the pictures' folder");
    }
}

extern "C" uint64_t swiftomniui_winui_pictures_revision(void) { return folderRevision; }

extern "C" bool swiftomniui_winui_picture_pixels(
    char const *const *names, int32_t count, int32_t *size, uint8_t *rgba, int64_t capacity
) {
    size[0] = size[1] = 0;
    try {
        std::string listed;
        for (int32_t index = 0; index < count; ++index)
            listed += std::string(names[index] ? names[index] : "") + "\n";
        auto file = pictureFile(listed.c_str());
        if (file.empty()) return false;
        if (auto dot = file.find_last_of(L'.'); dot != std::wstring::npos && file.substr(dot) == L".svg") {
            auto source = svgSource(pictures() + file);
            size[0] = source.PixelWidth();
            size[1] = source.PixelHeight();
            auto bytes = static_cast<int64_t>(size[0]) * size[1] * 4;
            if (rgba && capacity >= bytes) {
                auto pixels = source.PixelBuffer().data();
                for (int64_t at = 0; at < bytes; at += 4) {
                    rgba[at] = pixels[at + 2];
                    rgba[at + 1] = pixels[at + 1];
                    rgba[at + 2] = pixels[at];
                    rgba[at + 3] = pixels[at + 3];
                }
            }
            return true;
        }
        auto found = decodedPixels(pictures() + file);
        if (!found) return false;
        size[0] = static_cast<int32_t>(found->width);
        size[1] = static_cast<int32_t>(found->height);
        if (rgba && capacity >= static_cast<int64_t>(found->rgba.size()))
            std::memcpy(rgba, found->rgba.data(), found->rgba.size());
        return true;
    } catch (...) {
        report("reading a picture's pixels");
        return false;
    }
}

namespace {
    /// The source's immutable file metadata belongs to the Image, including the
    /// full path; changing the application's picture folder cannot redirect an
    /// already visible image's next size or DPI adjustment.
    struct PicturePanel : controls::PanelT<PicturePanel> {
        std::wstring path;
        bool svg = false;
        int32_t aspect = -1;
        winrt::Windows::Foundation::Size size{};

        winrt::Windows::Foundation::Size MeasureOverride(winrt::Windows::Foundation::Size) {
            // Swift owns the image's intrinsic size and its frame. A native
            // desired size would enlarge or clip an unresizable image whose
            // frame is smaller than its glyph (for example a disclosure arrow).
            for (auto const &child : Children()) child.Measure({INFINITY, INFINITY});
            return {0, 0};
        }

        winrt::Windows::Foundation::Size ArrangeOverride(winrt::Windows::Foundation::Size final) {
            for (auto const &child : Children()) {
                auto element = child.as<xaml::FrameworkElement>();
                auto desired = child.DesiredSize();
                auto width = std::isfinite(element.Width()) ? static_cast<float>(element.Width()) : desired.Width;
                auto height = std::isfinite(element.Height()) ? static_cast<float>(element.Height()) : desired.Height;
                child.Arrange({(final.Width - width) / 2, (final.Height - height) / 2, width, height});
            }
            return final;
        }
    };

    /// The element `handle` made by `swiftomniui_winui_image_make` holds: a panel
    /// with the picture at [0] and a Viewbox with a system glyph at [1], one
    /// visible at a time.
    controls::Panel imageGrid(SwiftOmniUIObjectRef handle) {
        return borrow<controls::Panel>(handle);
    }

    PicturePanel *imageState(controls::Panel const &grid) {
        return winrt::get_self<PicturePanel>(grid.as<xaml::IFrameworkElementOverrides>());
    }

    controls::Image imageChild(controls::Panel const &grid) {
        return grid.Children().GetAt(0).as<controls::Image>();
    }

    controls::Viewbox symbolBox(controls::Panel const &grid) {
        return grid.Children().GetAt(1).as<controls::Viewbox>();
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_image_make(void) {
    try {
        auto grid = winrt::make<PicturePanel>().as<controls::Panel>();
        grid.Children().Append(controls::Image());
        controls::Viewbox box;
        controls::TextBlock glyph;
        glyph.FontFamily(xaml::Media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
        glyph.FontSize(16);
        glyph.TextAlignment(xaml::TextAlignment::Center);
        box.Child(glyph);
        box.Stretch(xaml::Media::Stretch::None);
        box.Visibility(xaml::Visibility::Collapsed);
        grid.Children().Append(box);
        return detach(grid);
    } catch (...) {
        report("making an image");
        return nullptr;
    }
}

extern "C" bool swiftomniui_winui_image_set_symbol(
    SwiftOmniUIObjectRef handle, char const *glyph, int32_t aspect, double fontSize, double fontWeight,
    int32_t textStyle, double *size
) {
    size[0] = size[1] = 0;
    try {
        if (!glyph || !*glyph) return false;
        auto grid = imageGrid(handle);
        auto state = imageState(grid);
        state->path.clear();
        state->svg = false;
        state->aspect = -1;
        auto image = imageChild(grid);
        auto box = symbolBox(grid);
        image.Source(nullptr);
        image.Visibility(xaml::Visibility::Collapsed);
        auto symbol = box.Child().as<controls::TextBlock>();
        auto font = textFontDefaults(textStyle);
        symbol.FontSize(fontSize > 0 ? fontSize : textStyle >= 0 ? font.size : 16);
        symbol.FontWeight(fontWeight > 0 ? winrt::Windows::UI::Text::FontWeight{
            static_cast<uint16_t>(std::clamp(fontWeight, 1.0, 1000.0))} : winrt::Windows::UI::Text::FontWeight{font.weight});
        symbol.Text(winrt::to_hstring(glyph));
        size[0] = size[1] = symbol.FontSize();
        auto centred = aspect == 3;
        box.Stretch(aspect == 2 ? xaml::Media::Stretch::Fill
                    : centred ? xaml::Media::Stretch::None : xaml::Media::Stretch::Uniform);
        box.HorizontalAlignment(centred ? xaml::HorizontalAlignment::Center : xaml::HorizontalAlignment::Stretch);
        box.VerticalAlignment(centred ? xaml::VerticalAlignment::Center : xaml::VerticalAlignment::Stretch);
        box.ClearValue(xaml::FrameworkElement::WidthProperty());
        box.ClearValue(xaml::FrameworkElement::HeightProperty());
        box.Visibility(xaml::Visibility::Visible);
        return true;
    } catch (...) {
        report("showing a symbol");
        return false;
    }
}

extern "C" void swiftomniui_winui_image_set_tint(SwiftOmniUIObjectRef handle, bool has, uint32_t argb) {
    try {
        auto glyph = symbolBox(imageGrid(handle)).Child().as<controls::TextBlock>();
        if (has) glyph.Foreground(xaml::Media::SolidColorBrush(winrt::Windows::UI::Color{
            static_cast<uint8_t>(argb >> 24), static_cast<uint8_t>(argb >> 16),
            static_cast<uint8_t>(argb >> 8), static_cast<uint8_t>(argb)}));
        else glyph.ClearValue(controls::TextBlock::ForegroundProperty());
    } catch (...) {
        report("tinting a symbol");
    }
}

extern "C" bool swiftomniui_winui_image_set(
    SwiftOmniUIObjectRef handle, char const *const *names, int32_t count, int32_t aspect, double *size
) {
    size[0] = size[1] = 0;
    try {
        auto grid = imageGrid(handle);
        symbolBox(grid).Visibility(xaml::Visibility::Collapsed);
        auto image = imageChild(grid);
        image.Visibility(xaml::Visibility::Visible);
        // SwiftOmniUI's Aspect: fit, fill, stretch, centre - at the picture's own size, in the middle of the room.
        auto centred = aspect == 3;
        image.Stretch(aspect == 2 ? xaml::Media::Stretch::Fill
                      : centred ? xaml::Media::Stretch::None : xaml::Media::Stretch::Uniform);
        image.HorizontalAlignment(centred ? xaml::HorizontalAlignment::Center : xaml::HorizontalAlignment::Stretch);
        image.VerticalAlignment(centred ? xaml::VerticalAlignment::Center : xaml::VerticalAlignment::Stretch);
        image.ClearValue(xaml::FrameworkElement::WidthProperty());
        image.ClearValue(xaml::FrameworkElement::HeightProperty());

        // The first of the files the name stands for that the pictures hold.
        std::string listed;
        for (int32_t index = 0; index < count; ++index) listed += std::string(names[index] ? names[index] : "") + "\n";
        auto file = pictureFile(listed.c_str());
        auto named = count > 0 && names[0] && *names[0];
        image.Tag(winrt::box_value(winrt::hstring(file)));
        if (file.empty()) {
            image.Source(nullptr);
            auto state = imageState(grid);
            state->path.clear();
            state->svg = false;
            state->aspect = -1;
            state->size = {};
            return !named;
        }
        auto path = pictures() + file;
        auto dot = file.find_last_of(L'.');
        auto extension = dot == std::wstring::npos ? std::wstring() : file.substr(dot);
        if (extension != L".svg") {
            // Decode before the first layout: both pixels and their size are ready when the source is attached.
            auto bitmap = bitmapSource(path);
            size[0] = bitmap.PixelWidth();
            size[1] = bitmap.PixelHeight();
            if (image.Source() != bitmap) image.Source(bitmap);
            auto state = imageState(grid);
            state->path = path;
            state->svg = false;
            state->aspect = aspect;
            state->size = {static_cast<float>(size[0]), static_cast<float>(size[1])};
            return true;
        }

        auto own = svgPicture(path, aspect == 2).size;
        size[0] = own.Width;
        size[1] = own.Height;
        // WinUI takes an SVG's pixels for DIPs: centred, it is drawn at its own size by the image's.
        if (centred && own.Width > 0) {
            image.Stretch(xaml::Media::Stretch::Uniform);
            image.Width(own.Width);
            image.Height(own.Height);
        }
        auto state = imageState(grid);
        if (state->path != path || state->aspect != aspect || !state->svg) {
            image.Source(svgSource(path, aspect == 2));
        }
        state->path = path;
        state->svg = true;
        state->aspect = aspect;
        state->size = own;
        return true;
    } catch (...) {
        report("showing a picture");
        return false;
    }
}

extern "C" void swiftomniui_winui_image_size(SwiftOmniUIObjectRef handle, double *size) {
    size[0] = size[1] = 0;
    try {
        auto grid = imageGrid(handle);
        auto state = imageState(grid);
        if (state->svg) {
            size[0] = state->size.Width;
            size[1] = state->size.Height;
            return;
        }
        auto bitmap = imageChild(grid).Source().try_as<imaging::BitmapSource>();
        if (!bitmap) return;
        size[0] = bitmap.PixelWidth();
        size[1] = bitmap.PixelHeight();
    } catch (...) {
        report("reading a picture's size");
    }
}

extern "C" void swiftomniui_winui_image_place(SwiftOmniUIObjectRef handle, double width, double height) {
    try {
        auto grid = imageGrid(handle);
        auto box = symbolBox(grid);
        auto child = box.Visibility() == xaml::Visibility::Visible
            ? box.as<xaml::FrameworkElement>() : imageChild(grid).as<xaml::FrameworkElement>();
        child.Width(width);
        child.Height(height);
        child.HorizontalAlignment(xaml::HorizontalAlignment::Center);
        child.VerticalAlignment(xaml::VerticalAlignment::Center);
    } catch (...) {
        report("placing a picture");
    }
}

extern "C" void swiftomniui_winui_image_draw(SwiftOmniUIObjectRef handle, double width, double height) {
    try {
        auto grid = imageGrid(handle);
        auto state = imageState(grid);
        if (!state->svg || width <= 0 || height <= 0 || !std::isfinite(width) || !std::isfinite(height)) return;
        auto image = imageChild(grid);
        auto scale = image.XamlRoot() ? image.XamlRoot().RasterizationScale() : 1.0;
        auto across = static_cast<int32_t>(std::ceil(width * scale));
        auto down = static_cast<int32_t>(std::ceil(height * scale));
        auto current = image.Source().try_as<imaging::WriteableBitmap>();
        if (current && current.PixelWidth() >= across && current.PixelHeight() >= down) return;
        image.Source(svgSource(state->path, state->aspect == 2, across, down));
    } catch (...) {
        report("drawing a picture");
    }
}

extern "C" bool swiftomniui_winui_images_share_source(SwiftOmniUIObjectRef left, SwiftOmniUIObjectRef right) {
    try {
        auto a = imageChild(imageGrid(left)).Source();
        return a && a == imageChild(imageGrid(right)).Source();
    } catch (...) {
        report("comparing decoded image sources");
        return false;
    }
}

extern "C" bool swiftomniui_winui_image_decoded_pixels(
    SwiftOmniUIObjectRef handle, int32_t *size, uint8_t *rgba, int64_t capacity
) {
    size[0] = size[1] = 0;
    try {
        auto source = imageChild(imageGrid(handle)).Source().try_as<imaging::WriteableBitmap>();
        if (!source) return false;
        size[0] = source.PixelWidth();
        size[1] = source.PixelHeight();
        auto bytes = static_cast<int64_t>(size[0]) * size[1] * 4;
        if (rgba && capacity >= bytes) {
            auto pixels = source.PixelBuffer().data();
            for (int64_t at = 0; at < bytes; at += 4) {
                rgba[at] = pixels[at + 2];
                rgba[at + 1] = pixels[at + 1];
                rgba[at + 2] = pixels[at];
                rgba[at + 3] = pixels[at + 3];
            }
        }
        return true;
    } catch (...) {
        report("reading a synchronously decoded image's pixels");
        return false;
    }
}
