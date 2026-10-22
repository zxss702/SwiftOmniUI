// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// How words look, on a text block or on any control showing them: their font,
// their colour and the room around them; and a label's lines, alignment,
// spacing and decorations.
// Design: docs/design/platforms/winui/controls.md#words

#include "Relay.h"

#include <algorithm>
#include <cmath>
#include <cwchar>
#include <cwctype>
#include <functional>
#include <memory>
#include <map>
#include <tuple>
#include <string>
#include <vector>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Microsoft.UI.Text.h>
#include <winrt/Microsoft.UI.Input.h>
#include <winrt/Microsoft.UI.Xaml.Documents.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>

using namespace swiftomniui;
namespace media = winrt::Microsoft::UI::Xaml::Media;
namespace documents = winrt::Microsoft::UI::Xaml::Documents;

extern "C" void swiftomniui_winui_set_pointer_style(SwiftOmniUIObjectRef handle, int32_t style) {
    try {
        auto target = as<xaml::FrameworkElement>(handle);
        auto currentKey = winrt::box_value(L"SwiftOmniUIPointerStyle");
        auto pendingKey = winrt::box_value(L"SwiftOmniUIPointerStylePending");
        target.Resources().Insert(currentKey, winrt::box_value(style));
        auto apply = [currentKey](xaml::FrameworkElement const &target) {
            auto style = winrt::unbox_value<int32_t>(target.Resources().Lookup(currentKey));
            using winrt::Microsoft::UI::Input::InputSystemCursorShape;
            auto shape = InputSystemCursorShape::Arrow;
            switch (style) {
            case 1: case 2: case 3: case 11: shape = InputSystemCursorShape::IBeam; break;
            case 4: case 5: case 6: case 7: case 8: shape = InputSystemCursorShape::Hand; break;
            case 9: shape = InputSystemCursorShape::UniversalNo; break;
            case 10: shape = InputSystemCursorShape::Cross; break;
            case 12: shape = InputSystemCursorShape::SizeWestEast; break;
            case 13: shape = InputSystemCursorShape::SizeNorthSouth; break;
            case 14: shape = InputSystemCursorShape::SizeNorthwestSoutheast; break;
            }
            auto element = target.as<xaml::IUIElementProtected>();
            if (style < 0) element.ProtectedCursor(nullptr);
            else element.ProtectedCursor(winrt::Microsoft::UI::Input::InputSystemCursor::Create(shape));
        };
        if (target.IsLoaded()) apply(target);
        else if (!target.Resources().HasKey(pendingKey)) {
            // ProtectedCursor requires a live XamlRoot. Unsubscribe before
            // applying the latest value: style can change several times before
            // attachment, and an earlier Loaded callback must not restore it.
            target.Resources().Insert(pendingKey, winrt::box_value(true));
            auto token = std::make_shared<winrt::event_token>();
            *token = target.Loaded([weak = winrt::make_weak(target), token, pendingKey, apply](auto const &, auto const &) {
                try {
                    if (auto target = weak.get()) {
                        target.Loaded(*token);
                        target.Resources().Remove(pendingKey);
                        apply(target);
                    }
                } catch (...) { report("loaded pointer style"); }
            });
        }
    } catch (...) { report("pointer style"); }
}

extern "C" void swiftomniui_winui_text_set_selectable(SwiftOmniUIObjectRef handle, bool selectable) {
    try { labelWords(handle).IsTextSelectionEnabled(selectable); syncRichWords(handle); }
    catch (...) { report("text selectable"); }
}

namespace {
    uint64_t fontProbes = 0;

    // WinUI takes an Image/Panel's bottom edge as its inline baseline; only a
    // TextBlock/RichTextBlock can report a separate baseline and descent. Keep
    // the image in a native paragraph whose baseline comes from its margin,
    // and whose minimum height retains the pixels below that baseline. Without
    // this host a negative baseline offset shortens the line's measured height.
    controls::RichTextBlock inlineHost(xaml::UIElement const &child, double height) {
        controls::RichTextBlock host;
        host.UseLayoutRounding(false);
        host.IsTextSelectionEnabled(false);
        host.IsHitTestVisible(false);
        host.FontSize(0.01);
        host.Padding({0, 0, 0, 0});
        host.TextWrapping(xaml::TextWrapping::NoWrap);
        host.MinHeight(std::max(0.0, height));
        host.Tag(child);
        documents::Paragraph paragraph;
        documents::InlineUIContainer content;
        content.Child(child);
        paragraph.Inlines().Append(content);
        host.Blocks().Append(paragraph);
        return host;
    }

    xaml::FrameworkElement inlineContent(documents::InlineUIContainer const &holder) {
        auto child = holder.Child();
        if (auto host = child.try_as<controls::RichTextBlock>())
            if (auto content = host.Tag().try_as<xaml::FrameworkElement>()) return content;
        return child.try_as<xaml::FrameworkElement>();
    }

    winrt::Windows::UI::Color color(uint32_t argb) {
        return {static_cast<uint8_t>(argb >> 24), static_cast<uint8_t>(argb >> 16), static_cast<uint8_t>(argb >> 8),
                static_cast<uint8_t>(argb)};
    }

    /// A solid brush's colour as 0xAARRGGBB; 0 for any other.
    double argb(media::Brush const &brush) {
        auto solid = brush.try_as<media::SolidColorBrush>();
        if (!solid) return 0;
        auto c = solid.Color();
        return static_cast<double>(static_cast<uint32_t>(c.A) << 24 | static_cast<uint32_t>(c.R) << 16
                                   | static_cast<uint32_t>(c.G) << 8 | c.B);
    }

    /// Runs `block` on a label's text block, or `control` on a control; the element is one or the other.
    template <typename OnBlock, typename OnControl>
    void either(SwiftOmniUIObjectRef handle, OnBlock block, OnControl control) {
        auto object = as<IInspectable>(handle);
        if (auto text = wordsOf(object)) { block(text); syncRichWords(handle); }
        else if (auto other = object.try_as<controls::Control>()) control(other);
    }

    // OptimizeApplyStyles defers applying a Style until an element enters the
    // live tree. Font lookup also serves off-tree measurement and symbol sizing:
    // read the native setters instead of depending on a detached probe's Style.
    // BasedOn is applied first, as it is by XAML; StaticResource values have
    // already been resolved by the native resource dictionary.
    bool fontSizeValue(winrt::Windows::Foundation::IInspectable const &value, double &size) {
        if (!value) return false;
        try {
            auto boxed = value.as<winrt::Windows::Foundation::IPropertyValue>();
            double resolved = 0;
            switch (boxed.Type()) {
            case winrt::Windows::Foundation::PropertyType::Double: resolved = boxed.GetDouble(); break;
            case winrt::Windows::Foundation::PropertyType::Single: resolved = boxed.GetSingle(); break;
            case winrt::Windows::Foundation::PropertyType::Int32: resolved = boxed.GetInt32(); break;
            case winrt::Windows::Foundation::PropertyType::UInt32: resolved = boxed.GetUInt32(); break;
            case winrt::Windows::Foundation::PropertyType::String: {
                auto string = boxed.GetString();
                wchar_t *end = nullptr;
                resolved = std::wcstod(string.c_str(), &end);
                if (end == string.c_str() || *end != 0) return false;
                break;
            }
            default: return false;
            }
            if (!std::isfinite(resolved) || resolved <= 0) return false;
            size = resolved;
            return true;
        } catch (...) {
            return false;
        }
    }

    bool fontWeightValue(winrt::Windows::Foundation::IInspectable const &value, uint16_t &weight) {
        if (!value) return false;
        // XAML styles can expose a boxed FontWeight, a number, or an unresolved
        // string. Query each representation separately: a mismatched WinRT
        // interface must not prevent the glyph or text from being shown.
        try {
            auto resolved = winrt::unbox_value<winrt::Windows::UI::Text::FontWeight>(value).Weight;
            if (resolved > 0 && resolved <= 1000) {
                weight = resolved;
                return true;
            }
        } catch (...) {}
        try {
            auto boxed = value.as<winrt::Windows::Foundation::IPropertyValue>();
            double resolved = 0;
            switch (boxed.Type()) {
            case winrt::Windows::Foundation::PropertyType::UInt16: resolved = boxed.GetUInt16(); break;
            case winrt::Windows::Foundation::PropertyType::Int32: resolved = boxed.GetInt32(); break;
            case winrt::Windows::Foundation::PropertyType::UInt32: resolved = boxed.GetUInt32(); break;
            case winrt::Windows::Foundation::PropertyType::String: {
                auto string = boxed.GetString();
                std::wstring name(string.c_str());
                std::transform(name.begin(), name.end(), name.begin(), [](wchar_t c) { return std::towlower(c); });
                if (name == L"thin") resolved = 100;
                else if (name == L"extralight" || name == L"ultralight") resolved = 200;
                else if (name == L"light") resolved = 300;
                else if (name == L"normal" || name == L"regular") resolved = 400;
                else if (name == L"medium") resolved = 500;
                else if (name == L"semibold" || name == L"demibold") resolved = 600;
                else if (name == L"bold") resolved = 700;
                else if (name == L"extrabold" || name == L"ultrabold") resolved = 800;
                else if (name == L"black" || name == L"heavy") resolved = 900;
                else {
                    wchar_t *end = nullptr;
                    resolved = std::wcstod(name.c_str(), &end);
                    if (end == name.c_str() || *end != 0) return false;
                }
                break;
            }
            default: return false;
            }
            if (!std::isfinite(resolved) || resolved < 1 || resolved > 1000) return false;
            weight = static_cast<uint16_t>(resolved);
            return true;
        } catch (...) {
            return false;
        }
    }

    void fontSetters(xaml::Style const &style, TextFontDefaults &font) {
        if (!style) return;
        fontSetters(style.BasedOn(), font);
        for (auto const &item : style.Setters()) {
            try {
                auto setter = item.try_as<xaml::Setter>();
                if (!setter) continue;
                if (setter.Property() == controls::TextBlock::FontSizeProperty())
                    fontSizeValue(setter.Value(), font.size);
                else if (setter.Property() == controls::TextBlock::FontWeightProperty())
                    fontWeightValue(setter.Value(), font.weight);
            } catch (...) {
                // One malformed setter must not discard the rest of the style.
            }
        }
    }
}

swiftomniui::TextFontDefaults swiftomniui::textFontDefaults(int32_t textStyle) {
    struct Probe {
        controls::TextBlock block{nullptr};
        xaml::Style style{nullptr};
        TextFontDefaults defaults{};
        TextFontDefaults font{};
    };
    static Probe probes[12];
    auto valid = textStyle >= 0 && textStyle < 11;
    auto &probe = probes[valid ? textStyle + 1 : 0];
    if (!probe.block) {
        probe.block = controls::TextBlock();
        probe.defaults = {probe.block.FontSize(), probe.block.FontWeight().Weight};
        probe.font = probe.defaults;
        ++fontProbes;
    }
    xaml::Style style{nullptr};
    if (valid) {
        wchar_t const *styles[] = {L"TitleLargeTextBlockStyle", L"TitleTextBlockStyle", L"SubtitleTextBlockStyle",
            L"BodyLargeTextBlockStyle", L"BodyStrongTextBlockStyle", L"CaptionTextBlockStyle", L"BodyTextBlockStyle",
            L"BodyTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle", L"CaptionTextBlockStyle"};
        try {
            if (auto application = xaml::Application::Current())
                style = application.Resources().TryLookup(winrt::box_value(styles[textStyle])).try_as<xaml::Style>();
        } catch (...) {
            // An unavailable theme style falls back to the native TextBlock's
            // defaults; icon rendering must not depend on a resource lookup.
        }
    }
    // Styles can be replaced while the application runs. Resolve sealed styles
    // once per native identity. A still-editable application style must reflect
    // setter changes too, even before it has entered a tree.
    if (style != probe.style || (style && !style.IsSealed())) {
        auto font = probe.defaults;
        try { fontSetters(style, font); } catch (...) {}
        probe.font = font;
        probe.style = style;
    }
    return probe.font;
}

extern "C" uint64_t swiftomniui_winui_font_probes(void) { return fontProbes; }

extern "C" void swiftomniui_winui_set_font(SwiftOmniUIObjectRef handle, double size, bool bold, bool italic,
                                         char const *family, int32_t textStyle, double requestedWeight) {
    try {
        auto font = textFontDefaults(textStyle);
        auto weight = requestedWeight > 0 ? winrt::Windows::UI::Text::FontWeight{
            static_cast<uint16_t>(std::clamp(requestedWeight, 1.0, 1000.0))}
            : bold ? winrt::Microsoft::UI::Text::FontWeights::Bold() : winrt::Windows::UI::Text::FontWeight{font.weight};
        auto style = italic ? winrt::Windows::UI::Text::FontStyle::Italic : winrt::Windows::UI::Text::FontStyle::Normal;
        auto named = family && *family ? media::FontFamily(text(family)) : media::FontFamily{nullptr};
        auto apply = [&](auto const &element, auto sizeProperty, auto familyProperty) {
            if (size > 0) element.FontSize(size);
            else if (textStyle >= 0) element.FontSize(font.size);
            else element.ClearValue(sizeProperty);
            element.FontWeight(weight);
            element.FontStyle(style);
            if (named) element.FontFamily(named);
            else element.ClearValue(familyProperty);
        };
        either(handle,
            [&](controls::TextBlock const &block) {
                apply(block, controls::TextBlock::FontSizeProperty(), controls::TextBlock::FontFamilyProperty());
            },
            [&](controls::Control const &control) {
                apply(control, controls::Control::FontSizeProperty(), controls::Control::FontFamilyProperty());
            });
    } catch (...) {
        report("setting a font");
    }
}

extern "C" void swiftomniui_winui_set_foreground(SwiftOmniUIObjectRef handle, bool has, uint32_t argb) {
    try {
        auto brush = has ? media::SolidColorBrush(color(argb)) : media::SolidColorBrush{nullptr};
        either(handle,
            [&](controls::TextBlock const &block) {
                auto previous = block.Foreground();
                if (has) block.Foreground(brush);
                else block.ClearValue(controls::TextBlock::ForegroundProperty());
                // A background run without its own colour shares the label's
                // brush. Keep that inheritance when the label changes colour;
                // an explicit run owns a different brush, even for the same ARGB.
                auto foreground = block.Foreground();
                for (auto const &highlighter : block.TextHighlighters()) {
                    if (highlighter.Foreground() == previous) highlighter.Foreground(foreground);
                }
                if (auto rich = richWords(handle)) {
                    for (auto const &highlighter : rich.TextHighlighters())
                        if (highlighter.Foreground() == previous) highlighter.Foreground(foreground);
                    for (auto const &value : rich.Blocks()) if (auto paragraph = value.try_as<documents::Paragraph>())
                        for (auto const &inlineValue : paragraph.Inlines())
                            if (auto holder = inlineValue.try_as<documents::InlineUIContainer>())
                                if (auto child = inlineContent(holder).try_as<controls::TextBlock>()) {
                                    auto key = winrt::box_value(L"SwiftOmniUIInlineInheritsForeground");
                                    if (child.Resources().HasKey(key) && winrt::unbox_value<bool>(child.Resources().Lookup(key)))
                                        child.Foreground(foreground);
                                }
                }
            },
            [&](controls::Control const &control) {
                if (has) control.Foreground(brush);
                else control.ClearValue(controls::Control::ForegroundProperty());
                // A button's template draws its words in its own colour under the pointer and pressed.
                auto resources = control.Resources();
                auto keep = [&](wchar_t const *key) {
                    auto name = winrt::box_value(key);
                    if (resources.HasKey(name)) resources.Remove(name);
                    if (has) resources.Insert(name, brush);
                };
                if (control.try_as<controls::Primitives::ToggleButton>()) {
                    // A toggle names every state it can sit in.
                    for (auto state : {L"", L"PointerOver", L"Pressed", L"Checked", L"CheckedPointerOver",
                                       L"CheckedPressed", L"Indeterminate", L"IndeterminatePointerOver",
                                       L"IndeterminatePressed"}) {
                        keep((std::wstring(L"ToggleButtonForeground") + state).c_str());
                    }
                    return;
                }
                if (!control.try_as<controls::Button>()) return;
                for (auto key : {L"ButtonForeground", L"ButtonForegroundPointerOver", L"ButtonForegroundPressed"}) {
                    keep(key);
                }
            });
    } catch (...) {
        report("colouring words");
    }
}

extern "C" void swiftomniui_winui_set_padding(SwiftOmniUIObjectRef handle, double left, double top, double right, double bottom) {
    try {
        xaml::Thickness room{left, top, right, bottom};
        either(handle,
            [&](controls::TextBlock const &block) { block.Padding(room); },
            [&](controls::Control const &control) { control.Padding(room); });
    } catch (...) {
        report("setting the room around words");
    }
}

extern "C" void swiftomniui_winui_text_set_lines(SwiftOmniUIObjectRef handle, bool wraps, int32_t lines, bool trims) {
    try {
        auto block = labelWords(handle);
        block.TextWrapping(wraps ? xaml::TextWrapping::Wrap : xaml::TextWrapping::NoWrap);
        block.TextTrimming(trims ? xaml::TextTrimming::CharacterEllipsis : xaml::TextTrimming::None);
        block.MaxLines(std::max(0, lines));
        syncRichWords(handle);
    } catch (...) {
        report("setting a label's lines");
    }
}

extern "C" void swiftomniui_winui_text_set_alignment(SwiftOmniUIObjectRef handle, int32_t horizontal) {
    try {
        auto aligned = horizontal == 1 ? xaml::TextAlignment::Center
            : horizontal == 2 ? xaml::TextAlignment::End : xaml::TextAlignment::Start;
        labelWords(handle).TextAlignment(aligned);
        syncRichWords(handle);
    } catch (...) {
        report("aligning a label's words");
    }
}

extern "C" double swiftomniui_winui_text_natural_line_height(SwiftOmniUIObjectRef handle) {
    try {
        auto block = labelWords(handle);
        using Key = std::tuple<std::wstring, double, uint16_t, int32_t, int32_t>;
        static std::map<Key, double> heights;
        auto family = block.FontFamily().Source();
        Key key{std::wstring(family.c_str(), family.size()), block.FontSize(), block.FontWeight().Weight,
                static_cast<int32_t>(block.FontStyle()), static_cast<int32_t>(block.FontStretch())};
        if (auto found = heights.find(key); found != heights.end()) return found->second;
        controls::TextBlock probe;
        probe.FontFamily(block.FontFamily());
        probe.FontSize(block.FontSize());
        probe.FontWeight(block.FontWeight());
        probe.FontStyle(block.FontStyle());
        probe.FontStretch(block.FontStretch());
        probe.Text(L"Mg");
        probe.Measure({10000, 10000});
        auto height = probe.DesiredSize().Height;
        if (height > 0) heights.emplace(std::move(key), height);
        return height;
    } catch (...) { report("reading natural line height"); return 0; }
}

extern "C" void swiftomniui_winui_text_set_spacing(SwiftOmniUIObjectRef handle, int32_t characterSpacing, double minimumLineHeight) {
    try {
        auto block = labelWords(handle);
        block.CharacterSpacing(characterSpacing);
        // Native BaselineToBaseline assigns a fixed advance even when a line
        // contains a taller font or inline image. MaxHeight keeps the native
        // line's complete ascent/descent and treats LineHeight as a minimum.
        // WinUI exposes no additive spacing for individually varying line
        // heights; this preserves the content instead of shrinking its line.
        // See WinUI ParagraphNode::ApplyLineStackingStrategy.
        block.LineStackingStrategy(xaml::LineStackingStrategy::MaxHeight);
        block.LineHeight(std::isfinite(minimumLineHeight) && minimumLineHeight > 0 ? minimumLineHeight : 0);
        syncRichWords(handle);
    } catch (...) {
        report("spacing a label's words");
    }
}

extern "C" void swiftomniui_winui_text_set_runs(SwiftOmniUIObjectRef handle, SwiftOmniUIWordsRun const *runs, int32_t count) {
    try {
        if (count < 0 || (count > 0 && !runs)) return;
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        using winrt::Windows::UI::Text::TextDecorations;
        auto block = labelWords(handle);
        bool needsRich = false;
        for (int32_t i = 0; i < count; ++i)
            needsRich = needsRich || runs[i].imagePixelWidth > 0 || (runs[i].image && *runs[i].image) || runs[i].baseline != 0;
        auto rich = richWords(handle);
        if (needsRich && !rich) {
            rich = controls::RichTextBlock(); rich.UseLayoutRounding(false);
            auto border = borrow<controls::Border>(handle); border.Tag(block); border.Child(rich);
            syncRichWords(handle);
        } else if (!needsRich && rich) {
            auto border = borrow<controls::Border>(handle); border.Child(block); border.Tag(nullptr); rich = nullptr;
        }
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        if (rich) {
            rich.Blocks().Clear(); documents::Paragraph paragraph;
            paragraph.TextDecorations(block.TextDecorations());
            rich.Blocks().Append(paragraph); inlines = paragraph.Inlines(); highlighters = rich.TextHighlighters();
        }
        inlines.Clear();
        highlighters.Clear();
        int32_t at = 0;
        winrt::hstring plainText;
        auto paintBackground = [&](SwiftOmniUIWordsRun const &run, int32_t length) {
            if (!run.hasBackground || length <= 0) return;
            documents::TextHighlighter highlighter;
            highlighter.Background(media::SolidColorBrush(color(run.background)));
            highlighter.Foreground(run.hasColor ? media::SolidColorBrush(color(run.color)) : block.Foreground());
            highlighter.Ranges().Append(documents::TextRange{at, length});
            highlighters.Append(highlighter);
        };
        for (int32_t index = 0; index < count; ++index) {
            auto const &run = runs[index];
            // Symbols are font glyphs, so retain TextBlock's native Run path.
            // Image-bearing text uses RichTextBlock's native paragraph layout.
            if (run.glyph && *run.glyph && run.baseline == 0) {
                documents::Run mark;
                auto glyph = text(run.glyph);
                mark.Text(glyph);
                mark.FontFamily(media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
                if (run.size > 0) mark.FontSize(run.size);
                if (run.hasColor) mark.Foreground(media::SolidColorBrush(color(run.color)));
                inlines.Append(mark);
                auto length = static_cast<int32_t>(glyph.size());
                paintBackground(run, length);
                at += length;
                plainText = plainText + glyph;
                continue;
            }
            auto hasImage = run.imagePixelWidth > 0 || (run.image && *run.image);
            if (hasImage || run.baseline != 0) {
                documents::InlineUIContainer holder;
                if (hasImage) {
                    controls::Image picture;
                    if (run.imagePixelWidth > 0) {
                        if (!std::isfinite(run.imageWidth) || !std::isfinite(run.imageHeight)
                            || run.imageWidth <= 0 || run.imageHeight <= 0) winrt::throw_hresult(E_INVALIDARG);
                        auto source = memoryPicture(run.imageRGBA, run.imagePixelWidth, run.imagePixelHeight);
                        if (!source) winrt::throw_hresult(E_INVALIDARG);
                        picture.Source(source);
                        picture.Width(run.imageWidth); picture.Height(run.imageHeight);
                    } else {
                        auto file = pictureFile(run.image);
                        if (!file.empty()) picture.Source(pictureSource(file));
                    }
                    picture.Stretch(media::Stretch::Fill);
                    picture.Margin({0, 0, 0, run.baseline});
                    picture.Measure({INFINITY, INFINITY});
                    auto height = std::max(0.0, static_cast<double>(picture.DesiredSize().Height) - run.baseline);
                    if (run.baseline == 0) holder.Child(picture);
                    else holder.Child(inlineHost(picture, height));
                    plainText = plainText + L"\uFFFC";
                } else {
                    controls::TextBlock part;
                    auto symbol = run.glyph && *run.glyph;
                    part.Text(text(symbol ? run.glyph : run.text));
                    // InlineUIContainer does not inherit text formatting into
                    // its child. Apply the label's resolved look first.
                    part.FontFamily(block.FontFamily()); part.FontSize(block.FontSize());
                    part.FontWeight(block.FontWeight()); part.FontStyle(block.FontStyle());
                    part.FontStretch(block.FontStretch()); part.Foreground(block.Foreground());
                    part.UseLayoutRounding(false);
                    part.Resources().Insert(winrt::box_value(L"SwiftOmniUIInlineInheritsForeground"), winrt::box_value(!run.hasColor));
                    if (symbol) part.FontFamily(media::FontFamily(L"Segoe Fluent Icons, Segoe MDL2 Assets"));
                    if (run.hasColor) part.Foreground(media::SolidColorBrush(color(run.color)));
                    if (run.size > 0) part.FontSize(run.size);
                    if (run.bold) part.FontWeight(winrt::Microsoft::UI::Text::FontWeights::Bold());
                    if (run.italic) part.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);
                    if (!symbol && run.family && *run.family) part.FontFamily(media::FontFamily(text(run.family)));
                    part.CharacterSpacing(run.spacing);
                    auto decorations = TextDecorations::None;
                    if (run.underline) decorations = decorations | TextDecorations::Underline;
                    if (run.strikethrough) decorations = decorations | TextDecorations::Strikethrough;
                    part.TextDecorations(decorations);
                    part.Measure({INFINITY, INFINITY});
                    auto height = static_cast<double>(part.DesiredSize().Height);
                    controls::Border room;
                    room.Child(part);
                    // A Border uses its desired bottom edge as its baseline.
                    // Its native margin supplies the requested ascent while
                    // the RichTextBlock keeps the complete text height.
                    room.Margin({0, 0, 0, part.BaselineOffset() + run.baseline - height});
                    auto host = inlineHost(room, height);
                    host.Tag(part);
                    holder.Child(host);
                    plainText = plainText + part.Text();
                }
                inlines.Append(holder);
                auto length = (run.glyph && *run.glyph) || hasImage ? 1
                    : static_cast<int32_t>(text(run.text).size());
                paintBackground(run, length);
                at += length;
                continue;
            }
            documents::Run piece;
            auto words = text(run.text);
            piece.Text(words);
            plainText = plainText + words;
            if (run.hasColor) piece.Foreground(media::SolidColorBrush(color(run.color)));
            if (run.size > 0) piece.FontSize(run.size);
            if (run.bold) piece.FontWeight(winrt::Microsoft::UI::Text::FontWeights::Bold());
            if (run.italic) piece.FontStyle(winrt::Windows::UI::Text::FontStyle::Italic);
            auto lines = TextDecorations::None;
            if (run.underline) lines = lines | TextDecorations::Underline;
            if (run.strikethrough) lines = lines | TextDecorations::Strikethrough;
            if (lines != TextDecorations::None) piece.TextDecorations(lines);
            if (run.family && *run.family) piece.FontFamily(media::FontFamily(text(run.family)));
            piece.CharacterSpacing(run.spacing);
            inlines.Append(piece);

            // A run's background is a highlighter over its part of the words; its own colour stays on them.
            auto length = static_cast<int32_t>(words.size());
            paintBackground(run, length);
            at += length;
        }
        // The detached TextBlock remains the label's style/readback object.
        // Do not leave its previous document alive when RichTextBlock owns the
        // visible inlines, or generic text/automation reads see stale words.
        if (rich) block.Text(plainText);
    } catch (...) {
        report("setting a label's runs of words");
    }
}

extern "C" bool swiftomniui_winui_text_recolor_runs(
    SwiftOmniUIObjectRef handle, SwiftOmniUIWordsRun const *runs, int32_t count
) {
    try {
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        auto block = labelWords(handle);
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        if (auto rich = richWords(handle)) {
            if (rich.Blocks().Size() != 1) return false;
            inlines = rich.Blocks().GetAt(0).as<documents::Paragraph>().Inlines();
            highlighters = rich.TextHighlighters();
        }
        if (count < 0 || inlines.Size() != static_cast<uint32_t>(count)) return false;
        std::vector<documents::Run> pieces;
        std::vector<controls::TextBlock> children;
        std::vector<int32_t> lengths;
        pieces.reserve(count);
        children.reserve(count);
        lengths.reserve(count);
        // Validate before changing anything. A paint-only update keeps native
        // paragraphs and image objects, including their already uploaded pixels.
        for (int32_t index = 0; index < count; ++index) {
            auto piece = inlines.GetAt(index).try_as<documents::Run>();
            auto const &run = runs[index];
            auto symbol = run.glyph && *run.glyph;
            auto image = run.imagePixelWidth > 0 || (run.image && *run.image);
            auto words = text(symbol ? run.glyph : run.text);
            controls::TextBlock child{nullptr};
            if (piece) {
                if (image || run.baseline != 0 || piece.Text() != words) return false;
            } else {
                auto holder = inlines.GetAt(index).try_as<documents::InlineUIContainer>();
                if (!holder) return false;
                auto content = inlineContent(holder);
                child = content.try_as<controls::TextBlock>();
                if (image) {
                    if (!content.try_as<controls::Image>()) return false;
                } else if (!child || child.Text() != words) return false;
            }
            pieces.push_back(piece);
            children.push_back(child);
            lengths.push_back(image ? 1 : static_cast<int32_t>(words.size()));
        }
        uint32_t painted = 0;
        int32_t at = 0;
        for (int32_t index = 0; index < count; ++index) {
            auto const &piece = pieces[index];
            auto const &run = runs[index];
            if (piece) {
                auto property = documents::TextElement::ForegroundProperty();
                auto local = piece.ReadLocalValue(property) != xaml::DependencyProperty::UnsetValue();
                if (run.hasColor) {
                    if (!local || argb(piece.Foreground()) != run.color)
                        piece.Foreground(media::SolidColorBrush(color(run.color)));
                } else if (local) {
                    piece.ClearValue(property);
                }
            } else if (auto child = children[index]) {
                child.Foreground(run.hasColor ? media::SolidColorBrush(color(run.color)) : block.Foreground());
                child.Resources().Insert(winrt::box_value(L"SwiftOmniUIInlineInheritsForeground"), winrt::box_value(!run.hasColor));
            }
            auto length = lengths[index];
            if (run.hasBackground && length > 0) {
                auto highlighter = painted < highlighters.Size()
                    ? highlighters.GetAt(painted) : documents::TextHighlighter();
                if (!highlighter.Background() || argb(highlighter.Background()) != run.background)
                    highlighter.Background(media::SolidColorBrush(color(run.background)));
                if (run.hasColor) {
                    // An explicit colour must own its brush even if it equals
                    // the inherited colour, so later parent changes leave it alone.
                    if (!highlighter.Foreground() || highlighter.Foreground() == block.Foreground()
                        || argb(highlighter.Foreground()) != run.color)
                        highlighter.Foreground(media::SolidColorBrush(color(run.color)));
                } else if (highlighter.Foreground() != block.Foreground()) {
                    highlighter.Foreground(block.Foreground());
                }
                auto ranges = highlighter.Ranges();
                if (ranges.Size() != 1 || ranges.GetAt(0).StartIndex != at || ranges.GetAt(0).Length != length) {
                    ranges.Clear();
                    ranges.Append(documents::TextRange{at, length});
                }
                if (painted == highlighters.Size()) highlighters.Append(highlighter);
                ++painted;
            }
            at += length;
        }
        while (highlighters.Size() > painted) highlighters.RemoveAtEnd();
        return true;
    } catch (...) {
        // The caller retains a complete description and can restore it.
        return false;
    }
}

extern "C" int32_t swiftomniui_winui_text_runs(SwiftOmniUIObjectRef handle, double *values, int32_t capacity) {
    try {
        namespace documents = winrt::Microsoft::UI::Xaml::Documents;
        using winrt::Windows::UI::Text::TextDecorations;
        auto block = labelWords(handle);
        auto inlines = block.Inlines();
        auto highlighters = block.TextHighlighters();
        if (auto rich = richWords(handle); rich && rich.Blocks().Size() == 1) {
            inlines = rich.Blocks().GetAt(0).as<documents::Paragraph>().Inlines();
            highlighters = rich.TextHighlighters();
        }
        int32_t count = 0, at = 0;
        for (auto const &piece : inlines) {
            auto run = piece.try_as<documents::Run>();
            controls::TextBlock child{nullptr};
            if (auto holder = piece.try_as<documents::InlineUIContainer>())
                child = inlineContent(holder).try_as<controls::TextBlock>();
            auto length = run ? static_cast<int32_t>(run.Text().size())
                : child ? static_cast<int32_t>(child.Text().size()) : 1;
            double background = 0;
            for (auto const &highlighter : highlighters)
                for (auto const &range : highlighter.Ranges())
                    if (range.StartIndex == at && range.Length == length) background = argb(highlighter.Background());
            if (6 * (count + 1) <= capacity) {
                auto *slot = values + 6 * count;
                slot[0] = run ? (run.ReadLocalValue(documents::TextElement::ForegroundProperty()) == xaml::DependencyProperty::UnsetValue()
                    ? 0 : argb(run.Foreground())) : child ? argb(child.Foreground()) : 0;
                slot[1] = run ? (run.ReadLocalValue(documents::TextElement::FontSizeProperty()) == xaml::DependencyProperty::UnsetValue()
                    ? 0 : run.FontSize()) : child ? child.FontSize() : 0;
                slot[2] = run ? run.FontWeight().Weight : child ? child.FontWeight().Weight : block.FontWeight().Weight;
                auto style = run ? run.FontStyle() : child ? child.FontStyle() : block.FontStyle();
                slot[3] = style == winrt::Windows::UI::Text::FontStyle::Italic ? 1 : 0;
                auto lines = run ? run.TextDecorations() : child ? child.TextDecorations() : TextDecorations::None;
                slot[4] = ((lines & TextDecorations::Underline) == TextDecorations::Underline ? 1 : 0)
                    + ((lines & TextDecorations::Strikethrough) == TextDecorations::Strikethrough ? 2 : 0);
                slot[5] = background;
            }
            ++count;
            at += length;
        }
        return count;
    } catch (...) {
        report("reading a label's runs");
        return 0;
    }
}

extern "C" void swiftomniui_winui_text_set_decorations(SwiftOmniUIObjectRef handle, bool underline, bool strikethrough) {
    try {
        using winrt::Windows::UI::Text::TextDecorations;
        auto lines = TextDecorations::None;
        if (underline) lines = lines | TextDecorations::Underline;
        if (strikethrough) lines = lines | TextDecorations::Strikethrough;
        labelWords(handle).TextDecorations(lines);
        if (auto rich = richWords(handle))
            for (auto const &value : rich.Blocks())
                if (auto paragraph = value.try_as<documents::Paragraph>()) paragraph.TextDecorations(lines);
    } catch (...) {
        report("decorating a label's words");
    }
}

extern "C" void swiftomniui_winui_text_style(SwiftOmniUIObjectRef handle, double *style) {
    try {
        either(handle,
            [&](controls::TextBlock const &block) {
                style[0] = block.FontSize();
                style[1] = block.FontWeight().Weight;
                style[2] = block.MaxLines();
                style[3] = static_cast<double>(block.TextAlignment());
                style[4] = argb(block.Foreground());
            },
            [&](controls::Control const &control) {
                style[0] = control.FontSize();
                style[1] = control.FontWeight().Weight;
                style[2] = 0;
                style[3] = 0;
                style[4] = argb(control.Foreground());
            });
    } catch (...) {
        report("reading how words look");
    }
}

extern "C" double swiftomniui_winui_text_baseline(SwiftOmniUIObjectRef handle, double height) {
    try {
        auto block = labelWords(handle);
        if (auto rich = richWords(handle)) {
            auto extra = std::max(0.0, height - static_cast<double>(rich.DesiredSize().Height));
            auto shift = rich.VerticalAlignment() == xaml::VerticalAlignment::Center ? extra / 2
                : rich.VerticalAlignment() == xaml::VerticalAlignment::Bottom ? extra : 0;
            return rich.BaselineOffset() + shift;
        }
        auto extra = std::max(0.0, height - static_cast<double>(block.DesiredSize().Height));
        auto shift = block.VerticalAlignment() == xaml::VerticalAlignment::Center ? extra / 2
            : block.VerticalAlignment() == xaml::VerticalAlignment::Bottom ? extra : 0;
        return block.BaselineOffset() + shift;
    } catch (...) { report("reading the first text baseline"); return -1; }
}

extern "C" double swiftomniui_winui_text_whitespace_width(SwiftOmniUIObjectRef handle) {
    try {
        auto block = labelWords(handle);
        auto words = block.Text();
        auto family = block.FontFamily().Source();
        auto size = block.FontSize();
        auto weight = block.FontWeight().Weight;
        auto style = block.FontStyle();
        auto spacing = block.CharacterSpacing();
        if (block.Inlines().Size()) {
            // Attributed Text stores even a standalone space in a Run.
            if (block.Inlines().Size() != 1) return 0;
            auto run = block.Inlines().GetAt(0).try_as<documents::Run>();
            if (!run) return 0;
            words = run.Text();
            family = run.FontFamily().Source(); size = run.FontSize();
            weight = run.FontWeight().Weight; style = run.FontStyle(); spacing = run.CharacterSpacing();
        }
        if (words.empty() || !std::all_of(words.begin(), words.end(), [](wchar_t ch) { return ch == L' ' || ch == L'\t'; }))
            return 0;
        auto key = std::make_tuple(std::wstring(family.c_str(), family.size()), size, weight,
                                   static_cast<int32_t>(style), spacing,
                                   std::wstring(words.c_str(), words.size()));
        static std::map<decltype(key), double> widths;
        if (auto found = widths.find(key); found != widths.end()) return found->second;
        double extent[2] = {};
        if (!swiftomniui_winui_measure_text(winrt::to_string(words).c_str(), winrt::to_string(family).c_str(),
                size, weight, style != winrt::Windows::UI::Text::FontStyle::Normal, 0, extent)) return 0;
        auto width = extent[0] + std::max<int32_t>(0, static_cast<int32_t>(words.size()) - 1)
            * spacing * size / 1000;
        if (widths.size() >= 256) widths.clear();
        widths.emplace(key, width);
        return width;
    } catch (...) { report("measuring whitespace in a text flow"); return 0; }
}

extern "C" int32_t swiftomniui_winui_text_character_rects(
    SwiftOmniUIObjectRef handle, double *rectangles, int32_t capacity
) {
    try {
        auto block = labelWords(handle);
        auto coordinates = as<xaml::UIElement>(handle);
        int32_t at = 0;
        auto rich = richWords(handle);
        auto visual = rich ? rich.as<xaml::UIElement>() : block.as<xaml::UIElement>();
        auto transform = visual.TransformToVisual(coordinates);
        auto append = [&](documents::TextPointer const &start, std::wstring_view string,
                          xaml::UIElement const &owner = nullptr) {
            auto position = start;
            auto local = owner ? owner.TransformToVisual(visual) : nullptr;
            for (int32_t i = 0; i < static_cast<int32_t>(string.size()) && at < capacity; ++i, ++at) {
                if (!position) return;
                auto rect = position.GetCharacterRect(documents::LogicalDirection::Forward);
                auto next = position.GetPositionAtOffset(1, documents::LogicalDirection::Forward);
                // GetCharacterRect is a caret rectangle: XAML leaves Width
                // zero. The backward affinity at the trailing boundary keeps
                // the final glyph on its own row at a soft wrap.
                if (next) {
                    auto end = next.GetCharacterRect(documents::LogicalDirection::Backward);
                    if (rect.Height > 0 && end.Height > 0 &&
                        std::abs(rect.Y - end.Y) < 0.5f) {
                        auto left = std::min(rect.X, end.X);
                        rect.Width = std::abs(end.X - rect.X);
                        rect.X = left;
                    }
                }
                if (local) rect = local.TransformBounds(rect);
                rect = transform.TransformBounds(rect);
                rectangles[at * 4] = rect.X;
                rectangles[at * 4 + 1] = rect.Y;
                rectangles[at * 4 + 2] = rect.Width;
                rectangles[at * 4 + 3] = rect.Height;
                position = next;
            }
        };
        if (!rich && block.Inlines().Size() == 0) {
            auto words = block.Text();
            append(block.ContentStart(), std::wstring_view(words.c_str(), words.size()));
        } else {
            std::function<void(documents::Inline const &)> visit = [&](documents::Inline const &inlineValue) {
                if (auto run = inlineValue.try_as<documents::Run>()) {
                    auto words = run.Text();
                    append(run.ContentStart(), std::wstring_view(words.c_str(), words.size()));
                } else if (auto span = inlineValue.try_as<documents::Span>()) {
                    for (auto const &child : span.Inlines()) visit(child);
                } else if (auto holder = inlineValue.try_as<documents::InlineUIContainer>()) {
                    auto content = inlineContent(holder);
                    if (auto child = content.try_as<controls::TextBlock>()) {
                        auto words = child.Text();
                        append(child.ContentStart(), std::wstring_view(words.c_str(), words.size()), child);
                    } else if (content && at < capacity) {
                        // InlineUIContainer has structural open/close positions,
                        // not a character with two ordinary caret boundaries.
                        // Use the native arranged image itself for the single
                        // replacement character in SOUI's source text.
                        auto rect = content.TransformToVisual(coordinates).TransformBounds(
                            {0, 0, static_cast<float>(content.ActualWidth()), static_cast<float>(content.ActualHeight())});
                        rectangles[at * 4] = rect.X;
                        rectangles[at * 4 + 1] = rect.Y;
                        rectangles[at * 4 + 2] = rect.Width;
                        rectangles[at * 4 + 3] = rect.Height;
                        ++at;
                    } else if (at < capacity) {
                        append(inlineValue.ContentStart(), L"\uFFFC");
                    }
                } else {
                    // Embedded glyphs occupy one replacement character.
                    append(inlineValue.ContentStart(), L"\uFFFC");
                }
            };
            if (rich) {
                for (auto const &value : rich.Blocks()) if (auto paragraph = value.try_as<documents::Paragraph>())
                    for (auto const &inlineValue : paragraph.Inlines()) visit(inlineValue);
            } else {
                for (auto const &inlineValue : block.Inlines()) visit(inlineValue);
            }
        }
        return at;
    } catch (...) { report("reading native text geometry"); return 0; }
}
