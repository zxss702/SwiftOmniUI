// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What a window lays over its page and every page presented over it: views
/// under their keys, one over another.
///
///     window.overlays[.offline] = OfflineBanner()
///     window.overlays[.saving] = SavingToast().zIndex(1)
///     window.overlays[.offline] = nil
///
/// A layer written later stands over the ones before it, and `.zIndex` on its
/// view reorders them without moving anything. A docked inspector stands over
/// every layer.
public struct WindowOverlays {
    /// The layers, in the order each key was first written.
    private(set) var layers: [(key: OverlayKey, view: any View)] = []

    /// The keyed environment each layer was written under - the layer mounts
    /// at the window but resolves as though written where it was.
    private(set) var environments: [OverlayKey: EnvironmentValues] = [:]

    /// None.
    public init() {}

    /// The view standing under `key`; writing one lays it, or replaces the one
    /// there in its place, and nil takes it away.
    public subscript(key: OverlayKey) -> (any View)? {
        get { layers.first { $0.key == key }?.view }
        set {
            let index = layers.firstIndex { $0.key == key }

            switch (index, newValue) {
            case let (index?, view?):
                layers[index].view = view
                environments[key] = DispatchContext.envValues
            case let (index?, nil):
                layers.remove(at: index)
                environments.removeValue(forKey: key)
            case let (nil, view?):
                layers.append((key, view))
                environments[key] = DispatchContext.envValues
            case (nil, nil): break
            }
        }
    }

    /// The keys, in the order their layers stand before any `.zIndex`.
    public var keys: [OverlayKey] { layers.map(\.key) }
}
