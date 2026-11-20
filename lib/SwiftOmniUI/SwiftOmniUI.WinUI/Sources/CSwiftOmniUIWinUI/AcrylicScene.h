// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "Relay.h"
#include <winrt/Microsoft.UI.Composition.h>
#include <memory>
#include <functional>
#include <optional>
#include <vector>

namespace swiftomniui {
    struct AcrylicScene;
    // Material strips share a content-only scene in their native column's
    // coordinates. Neighbouring columns, animated template ancestors and fixed
    // chrome are outside its captured input.
    std::shared_ptr<AcrylicScene> acrylicScene(xaml::FrameworkElement const &source,
                                             xaml::FrameworkElement const &target);
    xaml::FrameworkElement acrylicSceneRoot(std::shared_ptr<AcrylicScene> const &scene);
    winrt::Microsoft::UI::Composition::Visual acrylicSceneVisual(std::shared_ptr<AcrylicScene> const &scene);
    struct AcrylicPartGeometry {
        winrt::Windows::Foundation::Rect visible{};
        winrt::Windows::Foundation::Rect localClip{};
        winrt::Windows::Foundation::Numerics::float4x4 matrix{};
        float opacity = 0;
    };
    winrt::Windows::Foundation::Rect acrylicVisibleBounds(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    AcrylicPartGeometry acrylicPartGeometry(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    float acrylicPresentationOpacity(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    bool acrylicUsesLocalPresentation(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    winrt::Windows::Foundation::Numerics::float4x4 acrylicPresentationMatrix(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    winrt::Windows::Foundation::Rect acrylicLocalClip(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root,
        winrt::Windows::Foundation::Rect const &visible);
    void setAcrylicLocalPresentation(IInspectable const &element, bool active) noexcept;
    bool hasAcrylicScrollerInsets() noexcept;
    void markAcrylicMaterialDirty() noexcept;
    bool takeAcrylicMaterialDirty() noexcept;
    void presentAcrylicScenes();
    std::vector<xaml::FrameworkElement> acrylicWindowRoots();
    bool acrylicSceneIsWindow(std::shared_ptr<AcrylicScene> const &scene);
    // Navigation columns never share captures or filters. Bounds are native
    // slot-local, including the column's slice of window chrome.
    std::vector<xaml::FrameworkElement> acrylicWindowColumns(xaml::FrameworkElement const &root);
    controls::Panel acrylicColumnOwner(xaml::FrameworkElement const &column, xaml::FrameworkElement const &root);
    winrt::Windows::Foundation::Rect acrylicSceneBounds(std::shared_ptr<AcrylicScene> const &scene);
    winrt::Windows::Foundation::Rect acrylicLayoutBounds(xaml::FrameworkElement const &element, xaml::FrameworkElement const &root);
    bool acrylicSceneContains(std::shared_ptr<AcrylicScene> const &scene, xaml::FrameworkElement const &element);
    std::vector<xaml::FrameworkElement> acrylicSceneBars(std::shared_ptr<AcrylicScene> const &scene);
    enum class AcrylicEdge { fixed, top, bottom };
    struct AcrylicBand {
        winrt::Windows::Foundation::Rect rect{};
        bool active = true;
    };
    std::vector<AcrylicBand> acrylicSceneRegions(std::shared_ptr<AcrylicScene> const &scene);
    std::vector<winrt::Windows::Foundation::Rect> acrylicMaterialRegions(std::vector<AcrylicBand> const &bands);
    std::vector<AcrylicBand> acrylicLocalRegions(std::shared_ptr<AcrylicScene> const &scene,
        xaml::FrameworkElement const &marker, winrt::Windows::Foundation::Rect const &bounds);
    enum class AcrylicChromeMode { safeBar, automatic, visible, hidden };
    AcrylicChromeMode acrylicTitleBarMode(xaml::FrameworkElement const &titleBar);
    void setAcrylicTitleBarMode(xaml::FrameworkElement const &titleBar, AcrylicChromeMode mode);
    std::vector<AcrylicBand> acrylicChromeRegions(std::shared_ptr<AcrylicScene> const &scene,
        winrt::Windows::Foundation::Rect const &bounds, AcrylicChromeMode mode);
    xaml::Media::SystemBackdrop acrylicFoundationBackdrop(xaml::FrameworkElement const &target);
    xaml::Media::Brush acrylicFoundationFill(xaml::FrameworkElement const &target);
    void setAcrylicWindowBackdrop(xaml::FrameworkElement const &root, xaml::Media::SystemBackdrop const &backdrop);
    // Weak subscribers return false after disposal; a geometry commit updates
    // every crop only after the scene's final native coordinates are available.
    void observeAcrylicScene(std::shared_ptr<AcrylicScene> const &scene, std::function<bool()> observer);
    void registerAcrylicScroller(xaml::FrameworkElement const &scroller);
    void updateAcrylicScroller(xaml::FrameworkElement const &scroller, std::optional<xaml::Thickness> insets = {});
    void setAcrylicContentRoot(xaml::FrameworkElement const &root, xaml::FrameworkElement const &content);
    void acrylicStructureChanged(xaml::FrameworkElement const &element) noexcept;
}
