// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "Relay.h"
#include <winrt/Microsoft.UI.Composition.h>
#include <memory>
#include <functional>
#include <vector>

namespace swiftomniui {
    struct AcrylicScene;
    // All material strips in a window sample this content-only scene in the
    // same coordinates. Neither local material nor fixed bar controls enter it.
    std::shared_ptr<AcrylicScene> acrylicScene(xaml::FrameworkElement const &source,
                                             xaml::FrameworkElement const &target);
    xaml::FrameworkElement acrylicSceneRoot(std::shared_ptr<AcrylicScene> const &scene);
    winrt::Microsoft::UI::Composition::Visual acrylicSceneVisual(std::shared_ptr<AcrylicScene> const &scene);
    winrt::Windows::Foundation::Rect acrylicVisibleBounds(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    float acrylicPresentationOpacity(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    bool acrylicUsesLocalPresentation(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    winrt::Windows::Foundation::Numerics::float4x4 acrylicPresentationMatrix(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    winrt::Windows::Foundation::Rect acrylicLocalClip(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root,
        winrt::Windows::Foundation::Rect const &visible);
    void presentAcrylicScenes();
    std::vector<xaml::FrameworkElement> acrylicWindowRoots();
    bool acrylicSceneIsWindow(std::shared_ptr<AcrylicScene> const &scene);
    std::vector<xaml::FrameworkElement> acrylicSceneBars(std::shared_ptr<AcrylicScene> const &scene);
    std::vector<winrt::Windows::Foundation::Rect> acrylicSceneRegions(std::shared_ptr<AcrylicScene> const &scene);
    xaml::Media::SystemBackdrop acrylicFoundationBackdrop(xaml::FrameworkElement const &target);
    xaml::Media::Brush acrylicFoundationFill(xaml::FrameworkElement const &target);
    void setAcrylicWindowBackdrop(xaml::FrameworkElement const &root, xaml::Media::SystemBackdrop const &backdrop);
    // Weak subscribers return false after disposal; a geometry commit updates
    // every crop only after the scene's final native coordinates are available.
    void observeAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, std::function<bool()> observer);
    void registerAcrylicScroller(xaml::FrameworkElement const &scroller);
    void setAcrylicContentRoot(xaml::FrameworkElement const &root, xaml::FrameworkElement const &content);
    void acrylicStructureChanged(xaml::FrameworkElement const &element) noexcept;
}
