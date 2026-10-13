// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// Which of an element's properties its layouts read, the same on every host.
/// Design: docs/design/host/layout.md#measured-once
extension MountedElement {
    /// The properties a parent reads into its child's place: a change arranges the parent again.
    public static let arrangedProperties: Set<Prop> = [
        .padding, .horizontalAlignment, .verticalAlignment,
        .width, .height,
        .minimumWidth, .minimumHeight,
        .maximumWidth, .maximumHeight,
        .isVisible,
        .isGeometryReader, .safeAreaInsetEdge, .ignoresSafeArea, Prop("safeAreaPadding"),
        .gridRow, .gridColumn, .gridRowSpan, .gridColumnSpan,
        .area,
    ]

    /// The properties drawn without changing any measurement; any other one measures the element again.
    public static let unmeasuredProperties = Set<Prop>([
        .opacity, .blur, .background, .foregroundStyle, .placeholderColor, .tint, .color, .isEnabled,
        .isOn, .value, .minimum, .maximum, .progress, .cursorPosition, .selectionLength,
        .stroke, .fill, .strokeWidth, .strokeDashPattern, .strokeDashOffset, .strokeLineCap, .strokeLineJoin,
        .strokeMiterLimit, .shape, .cornerRadius, .renderTransform, .barBackgroundColor, .barForegroundColor,
        .drawable, .scrollOffset, .clipsContent, .ignoresInput, .letsInputThrough,
        .horizontalContentAlignment, .verticalContentAlignment,
    ]).union(transformProperties).union(accessibilityProperties)
}
