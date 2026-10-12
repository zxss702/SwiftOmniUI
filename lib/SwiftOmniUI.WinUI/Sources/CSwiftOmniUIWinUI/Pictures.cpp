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

#include <shcore.h>
#include <shlwapi.h>
#include <wincodec.h>

#include <optional>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>

using namespace swiftomniui;
namespace imaging = winrt::Microsoft::UI::Xaml::Media::Imaging;

namespace {
    /// The folder pictures are read from; empty for `Images` beside the executable.
    std::wstring folder;

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

    /// A local bitmap decoded before it is attached to the visible tree, once per file: a row realized again - a
    /// list scrolled back and forth - takes the bitmap the first read left, not another decode of the same file.
    imaging::BitmapImage bitmapSource(std::wstring const &path) {
        static std::map<std::wstring, imaging::BitmapImage> decoded;
        auto kept = decoded.find(path);
        if (kept != decoded.end()) return kept->second;
        winrt::com_ptr<IStream> file;
        winrt::check_hresult(SHCreateStreamOnFileEx(path.c_str(), STGM_READ | STGM_SHARE_DENY_NONE,
                                                  FILE_ATTRIBUTE_NORMAL, FALSE, nullptr, file.put()));
        winrt::Windows::Storage::Streams::IRandomAccessStream stream{nullptr};
        winrt::check_hresult(CreateRandomAccessStreamOverStream(
            file.get(), BSOS_DEFAULT, winrt::guid_of<decltype(stream)>(), winrt::put_abi(stream)));
        imaging::BitmapImage source;
        source.SetSource(stream);
        decoded.emplace(path, source);
        return source;
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

    /// A bitmap's pixels, decoded once: premultiplied RGBA rows, kept by path like `bitmapSource`'s bitmaps.
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

    /// An SVG source drawing `text`, read from memory.
    imaging::SvgImageSource drawing(std::string const &text) {
        winrt::com_ptr<IStream> memory;
        memory.attach(SHCreateMemStream(reinterpret_cast<BYTE const *>(text.data()), static_cast<UINT>(text.size())));
        if (!memory) winrt::throw_hresult(E_OUTOFMEMORY);
        winrt::Windows::Storage::Streams::IRandomAccessStream stream{nullptr};
        winrt::check_hresult(CreateRandomAccessStreamOverStream(
            memory.get(), BSOS_DEFAULT, winrt::guid_of<decltype(stream)>(), winrt::put_abi(stream)));
        imaging::SvgImageSource source;
        source.SetSourceAsync(stream);
        return source;
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
    if (dot != std::wstring::npos && file.substr(dot) == L".svg") return drawing(contents(path));
    return bitmapSource(path);
}

extern "C" void swiftomniui_winui_set_pictures(char const *utf8) {
    try {
        folder = winrt::to_hstring(std::string_view(utf8 ? utf8 : "")).c_str();
        if (!folder.empty() && folder.back() != L'\\' && folder.back() != L'/') folder += L'\\';
    } catch (...) {
        report("naming the pictures' folder");
    }
}

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
    /// The element `handle` made by `swiftomniui_winui_image_make` holds: a grid
    /// with the picture at [0] and a Viewbox with a FontIcon at [1], one
    /// visible at a time.
    controls::Grid imageGrid(SwiftOmniUIObjectRef handle) {
        return borrow<controls::Grid>(handle);
    }

    controls::Image imageChild(controls::Grid const &grid) {
        return grid.Children().GetAt(0).as<controls::Image>();
    }

    controls::Viewbox symbolBox(controls::Grid const &grid) {
        return grid.Children().GetAt(1).as<controls::Viewbox>();
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_image_make(void) {
    try {
        controls::Grid grid;
        grid.Children().Append(controls::Image());
        controls::Viewbox box;
        controls::FontIcon icon;
        icon.FontFamily(xaml::Media::FontFamily(L"Segoe Fluent Icons"));
        icon.FontSize(16);
        box.Child(icon);
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
        auto image = imageChild(grid);
        auto box = symbolBox(grid);
        image.Source(nullptr);
        image.Visibility(xaml::Visibility::Collapsed);
        auto icon = box.Child().as<controls::FontIcon>();
        controls::TextBlock font;
        if (textStyle >= 0 && textStyle < 11) {
            wchar_t const *styles[] = {L"TitleLargeTextBlockStyle", L"TitleTextBlockStyle", L"SubtitleTextBlockStyle",
                L"BodyLargeTextBlockStyle", L"BodyStrongTextBlockStyle", L"CaptionTextBlockStyle", L"BodyTextBlockStyle",
                L"BodyTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle"};
            if (auto application = xaml::Application::Current()) {
                auto resource = application.Resources().TryLookup(winrt::box_value(styles[textStyle]));
                if (auto style = resource.try_as<xaml::Style>()) font.Style(style);
            }
        }
        icon.FontSize(fontSize > 0 ? fontSize : textStyle >= 0 ? font.FontSize() : 16);
        icon.FontWeight(fontWeight > 0 ? winrt::Windows::UI::Text::FontWeight{
            static_cast<uint16_t>(std::clamp(fontWeight, 1.0, 1000.0))} : font.FontWeight());
        icon.Glyph(winrt::to_hstring(glyph));
        size[0] = size[1] = icon.FontSize();
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
            return !named;
        }
        auto path = pictures() + file;
        auto dot = file.find_last_of(L'.');
        auto extension = dot == std::wstring::npos ? std::wstring() : file.substr(dot);
        if (extension != L".svg") {
            // Decode before the first layout: both pixels and their size are ready when the source is attached.
            image.Source(nullptr);
            auto bitmap = bitmapSource(path);
            size[0] = bitmap.PixelWidth();
            size[1] = bitmap.PixelHeight();
            image.Source(bitmap);
            return true;
        }

        auto text = contents(path);
        auto own = declared(text);
        size[0] = own.Width;
        size[1] = own.Height;
        if (aspect == 2) letGoOfProportions(text);
        // WinUI takes an SVG's pixels for DIPs: centred, it is drawn at its own size by the image's.
        if (centred && own.Width > 0) {
            image.Stretch(xaml::Media::Stretch::Uniform);
            image.Width(own.Width);
            image.Height(own.Height);
        }
        image.Source(drawing(text));
        return true;
    } catch (...) {
        report("showing a picture");
        return false;
    }
}

extern "C" void swiftomniui_winui_image_size(SwiftOmniUIObjectRef handle, double *size) {
    size[0] = size[1] = 0;
    try {
        auto bitmap = imageChild(imageGrid(handle)).Source().try_as<imaging::BitmapImage>();
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
        auto image = imageChild(imageGrid(handle));
        auto drawn = image.Source().try_as<imaging::SvgImageSource>();
        if (!drawn) return;
        auto scale = image.XamlRoot() ? image.XamlRoot().RasterizationScale() : 1.0;
        drawn.RasterizePixelWidth(std::ceil(width * scale));
        drawn.RasterizePixelHeight(std::ceil(height * scale));
    } catch (...) {
        report("drawing a picture");
    }
}
