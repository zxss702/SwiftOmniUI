// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#include "CompositionClips.h"
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Windows.UI.Xaml.Interop.h>

namespace composition = winrt::Microsoft::UI::Composition;

namespace swiftomniui {
    namespace {
        xaml::DependencyProperty const &clipProperty() {
            // An attached value keeps ownership on the actual XAML element,
            // without a process-wide map of addresses or extra event handlers.
            static auto property = xaml::DependencyProperty::RegisterAttached(
                L"SwiftOmniUICompositionClip", winrt::xaml_typename<IInspectable>(),
                winrt::xaml_typename<xaml::UIElement>(), xaml::PropertyMetadata{IInspectable{nullptr}});
            return property;
        }
    }

    composition::CompositionClip elementCompositionClip(xaml::UIElement const &element) {
        return element.GetValue(clipProperty()).try_as<composition::CompositionClip>();
    }

    void setElementCompositionClip(xaml::UIElement const &element, composition::CompositionClip const &clip) {
        // Clearing an unauthored clip is a no-op. Even obtaining a handout
        // Visual here would permanently change the native element's API mode.
        if (!clip && !elementCompositionClip(element)) return;
        auto visual = xaml::Hosting::ElementCompositionPreview::GetElementVisual(element);
        visual.Clip(clip);
        // Publish only after the native write succeeds. Queries observe the
        // current authored clip without touching native template visuals.
        if (clip) element.SetValue(clipProperty(), clip);
        else element.ClearValue(clipProperty());
    }
}
