// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// The properties a host moves frame by frame, element by element: those its views present and whose values travel.
/// Every other pair arrives at once, rather than keeping a animation alive that nothing shows.
/// Design: docs/design/host/animation.md#what-travels
@_spi(Host) public enum TransitionSurface {
    /// Drawing shared by every actual native view, including a page, a lazy
    /// container or an application-registered control. The caller checks
    /// that this instance presents a view; type tables still govern its
    /// layout, text and control-specific properties.
    public static func presentsDrawing(_ property: Prop) -> Bool {
        drawingProperties.contains(property)
    }

    /// Whether a host moves `property` of an element of `type` frame by frame; `atRest` names, element type by
    /// element type, what the host's toolkit paints only at rest, which arrives at once there.
    public static func presents(_ property: Prop, on type: NodeType, atRest: [NodeType: Set<Prop>] = [:]) -> Bool {
        if atRest[type]?.contains(property) == true {
            return false
        }

        if nativeViewTypes.contains(type), sharedViewProperties.contains(property) {
            return true
        }

        if shapeTypes.contains(type), shapeProperties.contains(property) {
            return true
        }

        switch type {
        case .page:
            return contentPageProperties.contains(property)

        case .vStack, .hStack:
            return stackProperties.contains(property) || layoutBoxProperties.contains(property)

        case .grid:
            return gridProperties.contains(property) || layoutBoxProperties.contains(property)

        case .zStack:
            return property == .contentPadding || layoutBoxProperties.contains(property)

        case .scrollView:
            return property == .contentPadding || layoutBoxProperties.contains(property)

        case .text:
            return labelProperties.contains(property)

        case .span:
            return spanProperties.contains(property)

        case .button:
            return buttonProperties.contains(property)


        case .textField, .textEditor, .searchField:
            return fieldProperties.contains(property)

        case .radioButton:
            return radioProperties.contains(property)

        case .picker:
            return pickerProperties.contains(property)

        case .datePicker, .timePicker:
            return textControlProperties.contains(property)

        case .colorPicker:
            return boxProperties.contains(property)

        case .checkBox:
            return property == .tint

        case .slider:
            return sliderProperties.contains(property)

        case .progressBar:
            return property == .progress

        case .navigationStack:
            return navigationProperties.contains(property)

        case .tabView:
            return property == .barBackgroundColor

        case .titleBar:
            return titleBarProperties.contains(property)

        case .rectangle:
            return property == .cornerRadius

        case .line:
            return lineProperties.contains(property)

        case .canvas:
            return property == .drawable

        case .windowScene:
            return windowProperties.contains(property)

        default:
            return false
        }
    }

    private static let nativeViewTypes: Set<NodeType> = [
        .activityIndicator, .colorPicker, .button,
        .checkBox, .datePicker, .textEditor, .ellipse, .textField, .canvas,
        .grid, .hStack, .image, .list, .text, .line,
        .path, .picker, .polygon, .polyline, .progressBar, .radioButton,
        .rectangle, .scrollView, .searchField, .slider,
        .stepper, .switch, .timePicker, .vStack, .zStack,
    ]

    private static let shapeTypes: Set<NodeType> = [
        .ellipse, .line, .path, .polygon, .polyline, .rectangle,
    ]

    private static let sharedViewProperties: Set<Prop> = [
        .opacity, .background,
        .width, .height,
        .minimumWidth, .minimumHeight,
        .maximumWidth, .maximumHeight,
        .rotation, .scale, .scaleX, .scaleY, .translationX, .translationY,
        .pivotX, .pivotY,
        .padding,
    ]

    private static let drawingProperties: Set<Prop> = [
        .opacity, .translationX, .translationY, .rotation, .rotationX, .rotationY,
        .scale, .scaleX, .scaleY, .pivotX, .pivotY,
    ]

    private static let contentPageProperties: Set<Prop> = [
        .background, .contentPadding,
    ]

    private static let stackProperties: Set<Prop> = [.contentPadding, .spacing]

    /// What a layout draws of its own box.
    private static let layoutBoxProperties: Set<Prop> = [.background, .stroke, .strokeWidth, .shape]

    private static let gridProperties: Set<Prop> = [
        .contentPadding, .rowSpacing, .columnSpacing, .rows, .columns,
    ]

    private static let labelProperties: Set<Prop> = [
        .contentPadding, .fontSize, .foregroundStyle, .characterSpacing, .lineHeight,
    ]

    private static let spanProperties: Set<Prop> = [
        .background, .fontSize, .foregroundStyle, .characterSpacing, .lineHeight,
    ]

    private static let textControlProperties: Set<Prop> = [.fontSize, .foregroundStyle]

    private static let buttonProperties: Set<Prop> = [
        .contentPadding, .fontSize, .foregroundStyle, .stroke, .strokeWidth, .shape,
    ]


    private static let fieldProperties: Set<Prop> = [
        .fontSize, .foregroundStyle, .placeholderColor,
    ]

    private static let radioProperties: Set<Prop> = [.contentPadding, .fontSize, .foregroundStyle]

    private static let pickerProperties: Set<Prop> = [.fontSize, .foregroundStyle, .tint]

    private static let boxProperties: Set<Prop> = [.color, .cornerRadius]

    private static let sliderProperties: Set<Prop> = [.value, .tint]

    private static let navigationProperties: Set<Prop> = [
        .barBackgroundColor, .barForegroundColor,
    ]

    private static let titleBarProperties: Set<Prop> = [
        .background, .barForegroundColor,
    ]

    private static let shapeProperties: Set<Prop> = [
        .fill, .stroke, .strokeWidth, .strokeDashOffset, .strokeMiterLimit,
        .renderTransform,
    ]

    private static let lineProperties: Set<Prop> = [.x1, .y1, .x2, .y2]

    private static let windowProperties: Set<Prop> = [.x, .y, .width, .height]
}
