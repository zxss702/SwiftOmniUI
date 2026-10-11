// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import CSwiftOmniUIGTK
@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
@testable import SwiftOmniUIGTK
@_spi(Host) import SwiftOmniUIConformance

/// The GTK host as the conformance suite drives it: each user's act through the signal or the call GTK's own input
/// takes, and each read from the widget itself.
/// Design: docs/design/host/conformance.md#the-driver
@MainActor
final class GTKDriver: HostDriver {
    let host = "GTK 4"
    let cannot: [String: String] = [:]
    let platformHasNone = GTKDriver.none()

    /// What GTK holds none of: what SwiftOmniUI draws on GTK's snapshot, where SwiftOmniUI's layout places the children,
    /// what SwiftOmniUI measures and what the host cuts - each proven by its effect in another case.
    private static func none() -> [String: String] {
        var none = [
            "read growsWithText of TextEditor":
                "an editor's growing is SwiftOmniUI's measuring, which no property of GTK's holds; its frames prove it",
            "read maximumLength of TextEditor":
                "GTK's text view keeps no bound: the host cuts what is typed, and typing proves it",
            "read maximumLength of TextField":
                "GTK bounds code points, not characters, so the host cuts what is typed; typing proves it",
            "read maximumLength of SearchField":
                "GTK bounds code points, not characters, so the host cuts what is typed; typing proves it",
        ]
        let shapes = ["Ellipse", "Line", "Path", "Polygon", "Polyline", "Rectangle"]
        let shapePaint = [
            "aspect", "renderTransform", "fill", "stroke", "strokeWidth", "strokeDashOffset", "strokeDashPattern",
            "strokeLineCap", "strokeLineJoin", "strokeMiterLimit",
        ]
        for shape in shapes {
            for member in shapePaint {
                none["read \(member) of \(shape)"] =
                    "SwiftOmniUI draws a shape on GTK's snapshot, which holds none of its \(member); its drawing proves it"
            }
        }
        for layout in ["Grid", "HStack", "VStack", "ZStack", "ScrollView"] {
            for member in ["background", "stroke", "strokeWidth", "shape"] {
                none["read \(member) of \(layout)"] =
                    "SwiftOmniUI draws a layout's box on GTK's snapshot, which holds none of its \(member); its drawing proves it"
            }
            none["read padding of \(layout)"] =
                "GTK's panel places its children where SwiftOmniUI's layout says; their frames prove it"
        }
        for stack in ["HStack", "VStack"] {
            none["read spacing of \(stack)"] = "GTK's panel places its children where SwiftOmniUI's layout says; their frames prove it"
        }
        return none
    }

    /// What the families ask of a driver that GTK's has no path for yet says so, and stays empty in GTK's column
    /// with why, rather than failing: GTK's reads and acts are written on Linux (work-plan.md, ON LINUX).
    func reason(cannot ability: String) -> String? {
        cannot[ability] ?? "GTK's driver has no path for it yet"
    }

    /// What the driver reaches past GTK through a backend's own entry or record - the 🔌 mark's.
    func byHost(_ ability: String) -> String? {
        Self.backends.values.lazy.compactMap { $0.byHost[ability] }.first
    }

    var renderer: GTKRenderer?

    var register: HostRegister { GTKRealization.register.and(backendRecords) }

    func start(clock: TestClock?, reducesMotion: Bool, _ page: @escaping @MainActor @Sendable () -> any Page) -> MountedTree {
        let renderer = GTKRenderer.running(clock: clock, reducesMotion: reducesMotion, page)
        self.renderer = renderer
        return renderer.runtime.tree
    }

    func step() {
        renderer?.step()
    }

    func turn() {
        renderer?.runtime.pump.turn()
    }

    func frame() {
        renderer?.frame()
    }

    var liveViews: Int? {
        GTKView.liveCount
    }

    /// Whether the element holds the keyboard: its widget or one within it is the window's focus.
    func focused(_ element: MountedElement) throws -> Bool {
        guard let view = (element.native as? GTKElement)?.view else {
            throw DriverCannot("read the focus of \(element.type.name)")
        }
        guard let root = gtk_widget_get_root(view.widget), let focus = gtk_root_get_focus(root) else {
            return false
        }
        return focus == view.widget || gtk_widget_is_ancestor(focus, view.widget) != 0
    }

    /// Where the element stands in its window, as GTK places its widget - laid out first, as a frame lays out
    /// what the user sees before it is read.
    func place(of element: MountedElement) throws -> Rect {
        guard let view = (element.native as? GTKElement)?.view, let root = gtk_widget_get_root(view.widget) else {
            throw DriverCannot("read where \(element.type.name) stands")
        }
        renderer?.layOut()
        var bounds = graphene_rect_t()
        let window = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWidget.self)
        guard gtk_widget_compute_bounds(view.widget, window, &bounds) != 0 else {
            throw DriverCannot("read where \(element.type.name) stands")
        }
        return Rect(
            x: Double(bounds.origin.x), y: Double(bounds.origin.y), width: Double(bounds.size.width),
            height: Double(bounds.size.height))
    }

    func perform(_ act: UserAct, on element: MountedElement) throws {
        if try backendPerforms(act, on: element) { return }
        if act == .goBack {
            guard renderer?.goBack() == true else { throw DriverCannot(act, on: element) }
            return
        }
        let view = (element.native as? GTKElement)?.view
        if act == .activate, let items = element.enclosing(type: .list), try activateItem(element, in: items) {
            return
        }
        switch (act, view) {
        case (.activate, let button as GTKButtonView): button.click()
        case (.toggle, let toggle as GTKSwitchView): gtk_switch_set_active(toggle.widget.opaque, toggle.isOn ? 0 : 1)
        case (.toggle, let check as GTKCheckView): gtk_widget_activate(check.widget)
        case (.slide(let value), let slider as GTKSliderView): gtk_range_set_value(slider.widget.of(GtkRange.self), value)
        case (.step(let up), let stepper as GTKStepperView):
            gtk_spin_button_spin(stepper.widget.opaque, up ? GTK_SPIN_STEP_FORWARD : GTK_SPIN_STEP_BACKWARD, 0)
        case (.enterWords(let words), let stepper as GTKStepperView):
            gtk_editable_set_text(stepper.widget.opaque, words)
            gtk_spin_button_update(stepper.widget.opaque)
        case (.type(let words), let field as GTKTextFieldView):
            type(words, into: field, keys: gtk_editable_get_delegate(field.widget.opaque))
        case (.type(let words), let editor as GTKTextEditorView):
            type(words, into: editor, keys: OpaquePointer(gtk_scrolled_window_get_child(editor.widget.opaque)))
        case (.submit, let field as GTKTextFieldView): GTKTestHost.emit(field.widget.opaque, "activate")
        case (.focus, let view?): gtk_widget_grab_focus(view.widget)
        case (.choose(let place), let picker as GTKPickerView): gtk_drop_down_set_selected(picker.widget.opaque, guint(place))
        case (.scroll(let offset), let items as GTKItemsView): try scroll(items, to: offset, on: element, act)
        case (.scroll(let offset), let scrollView as GTKScrollView): try scroll(scrollView, to: offset, on: element, act)
        case (.choose(let place), let items as GTKItemsView): try choose(place, in: items, on: element)
        case (.open, let picker as GTKPopoverPickerView): gtk_menu_button_popup(picker.widget.opaque)
        case (.close, let picker as GTKPopoverPickerView): gtk_popover_popdown(picker.popover.of(GtkPopover.self))
        case (.pickDate(let day), let dates as GTKDatePickerView):
            guard let native = g_date_time_new_local(Int32(day.year), Int32(day.month), Int32(day.day), 12, 0, 0) else {
                throw DriverCannot(act, on: element)
            }
            gtk_calendar_select_day(dates.calendar.opaque, native)
            g_date_time_unref(native)
        // The user moves the hour and the minute each; the clock is set at once, and its minute's wheel tells it.
        case (.pickTime(let time), let times as GTKTimePickerView):
            ProgramWrite.perform { times.setTime(time) }
            GTKTestHost.emit(times.minutes.opaque, "value-changed")
        case (.activate, _) where element.type == .menuItem: try chooseMenuItem(element)
        case (.dropFiles(let paths), _):
            // The system's files let go on the element, at its middle: what a drop out of Files raises.
            guard let target = element.native as? GTKElement else { throw DriverCannot(act, on: element) }
            let place = try place(of: element)
            target.send(.dropPaths, [.strings(paths), .numbers([place.width / 2, place.height / 2])])
        case (.openLink(let link), _):
            // The platform handing the application a link, as opening one from Files or a browser raises it.
            guard let runtime = renderer?.runtime else { throw DriverCannot(act, on: element) }
            runtime.core.raise(AppContract.urlOpened, link)
        default: throw DriverCannot(act, on: element)
        }
    }

    func held(_ property: Prop, on element: MountedElement) throws -> HostValue? {
        if element.type == .menuItem { return try menuItemHolds(property, element) }
        if let value = backendHolds(property, on: element) { return value }
        let view = (element.native as? GTKElement)?.view
        switch (property, view) {
        case (.isOn, let toggle as GTKToggleView): return toggle.isOn.propValue
        case (.value, let slider as GTKSliderView): return slider.value.propValue
        case (.minimum, let slider as GTKSliderView):
            return gtk_adjustment_get_lower(gtk_range_get_adjustment(slider.widget.of(GtkRange.self))).propValue
        case (.maximum, let slider as GTKSliderView):
            return gtk_adjustment_get_upper(gtk_range_get_adjustment(slider.widget.of(GtkRange.self))).propValue
        case (.value, let stepper as GTKStepperView): return stepper.value.propValue
        case (.progress, let bar as GTKProgressBarView): return bar.progress.propValue
        case (.isRunning, let spinner as GTKActivityIndicatorView): return spinner.isRunning.propValue
        case (.text, let label as GTKTextView): return label.text.propValue
        case (.text, let field as GTKTextFieldView): return field.text.propValue
        case (.text, let editor as GTKTextEditorView): return editor.text.propValue
        case (.text, let button as GTKButtonView): return button.text.propValue
        case (.text, let check as GTKCheckView): return check.text.propValue
        case (.selectedIndex, let picker as GTKPickerView): return picker.chosen.map(\.propValue)
        case (.options, let picker as GTKPickerView):
            guard let model = gtk_drop_down_get_model(picker.widget.opaque) else { return [String]().propValue }
            return (0..<g_list_model_get_n_items(model)).map { String(cString: gtk_string_list_get_string(model, $0)) }
                .propValue
        case (.isOpen, let picker as GTKPopoverPickerView): return picker.isOpen.propValue
        case (.date, let dates as GTKDatePickerView): return dates.date.propValue
        case (.minimumDate, let dates as GTKDatePickerView): return dates.range.earliest?.propValue
        case (.maximumDate, let dates as GTKDatePickerView): return dates.range.latest?.propValue
        case (.format, let dates as GTKDatePickerView):
            return (Self.words(of: dates) == Self.shortForm(of: dates) ? "d" : "D").propValue
        case (.time, let times as GTKTimePickerView): return times.time.propValue
        case (.scrollOffset, let scroll as GTKScrollView),
             (.horizontalScrollIndicators, let scroll as GTKScrollView),
             (.verticalScrollIndicators, let scroll as GTKScrollView):
            return try scrollHolds(property, scroll, on: element)
        case (.selectionMode, let items as GTKItemsView): return items.choiceMode.map { $0.propValue }
        case (.selectedItems, let items as GTKItemsView): return items.chosenIdentities.propValue
        case (.isVisible, let view?): return (gtk_widget_get_visible(view.widget) != 0).propValue
        case (.opacity, let view?): return gtk_widget_get_opacity(view.widget).propValue
        case (.isEnabled, let view?): return (gtk_widget_get_sensitive(view.widget) != 0).propValue
        default: throw DriverCannot(reading: property, of: element)
        }
    }

    /// What a ScrollView's scrolled window holds: where it stands, and the bars its policies say - laid out first,
    /// as a frame lays out what the user sees before it is read.
    private func scrollHolds(_ property: Prop, _ scroll: GTKScrollView, on element: MountedElement) throws -> HostValue? {
        renderer?.layOut()
        guard let scrolled = GTKTestHost.descendants(of: scroll.widget).first(where: {
            GTKTestHost.holds($0, gtk_scrolled_window_get_type())
        })?.opaque else { throw DriverCannot(reading: property, of: element) }
        var policies = (horizontal: GTK_POLICY_AUTOMATIC, vertical: GTK_POLICY_AUTOMATIC)
        gtk_scrolled_window_get_policy(scrolled, &policies.horizontal, &policies.vertical)
        let visibility = { (policy: GtkPolicyType) -> ScrollIndicatorVisibility in
            policy == GTK_POLICY_ALWAYS ? .visible
                : policy == GTK_POLICY_NEVER || policy == GTK_POLICY_EXTERNAL ? .hidden : .automatic
        }
        switch property {
        case .scrollOffset:
            return [gtk_adjustment_get_value(gtk_scrolled_window_get_hadjustment(scrolled)),
                    gtk_adjustment_get_value(gtk_scrolled_window_get_vadjustment(scrolled))].propValue
        case .horizontalScrollIndicators: return visibility(policies.horizontal).propValue
        case .verticalScrollIndicators: return visibility(policies.vertical).propValue
        default: throw DriverCannot(reading: property, of: element)
        }
    }

    /// The words a picker's button shows.
    private static func words(of picker: GTKPopoverPickerView) -> String {
        String(cString: gtk_label_get_text(picker.label.opaque))
    }

    /// The day a DatePicker holds, in its short form.
    private static func shortForm(of picker: GTKDatePickerView) -> String {
        let day = gtk_calendar_get_date(picker.calendar.opaque)!
        defer { g_date_time_unref(day) }
        let words = g_date_time_format(day, "%x")!
        defer { g_free(words) }
        return String(cString: words)
    }

    /// Moves the scrolled window in `view` to `offset`, as a wheel does: through its adjustments, which hold it
    /// within what it shows - laid out first, as a frame lays out what the user sees before they scroll it.
    private func scroll(_ view: GTKView, to offset: Point, on element: MountedElement, _ act: UserAct) throws {
        renderer?.layOut()
        var child = gtk_widget_get_first_child(view.widget)
        while let each = child, g_type_check_instance_is_a(each.of(GTypeInstance.self), gtk_scrolled_window_get_type()) == 0 {
            child = gtk_widget_get_first_child(each)
        }
        guard let scrolled = child?.opaque else { throw DriverCannot(act, on: element) }
        gtk_adjustment_set_value(gtk_scrolled_window_get_hadjustment(scrolled), offset.x)
        gtk_adjustment_set_value(gtk_scrolled_window_get_vadjustment(scrolled), offset.y)
    }

    /// Types `words` into `input` as the keyboard leaves them - what does not lead to them chosen and deleted, the
    /// rest typed after what does - through the key bindings' signals of `keys`, which a read-only field refuses.
    private func type(_ words: String, into input: any GTKInputView, keys: OpaquePointer) {
        let kept = words.hasPrefix(input.text) ? input.text : ""
        if kept.isEmpty && !input.text.isEmpty {
            input.select(start: 0, length: input.text.unicodeScalars.count)
            GTKTestHost.emit(keys, "delete-from-cursor", [Double(GTK_DELETE_CHARS.rawValue), 1])
        } else {
            input.select(start: kept.unicodeScalars.count, length: 0)
        }
        GTKTestHost.emit(keys, "insert-at-cursor", words: String(words.dropFirst(kept.count)))
    }

    /// Chooses the item at `place` as the user's click does, through the list's own `list.select-item`: alone where
    /// one may be chosen, beside those chosen - as a Ctrl click - where many may.
    private func choose(_ place: Int, in items: GTKItemsView, on element: MountedElement) throws {
        guard let list = items.list, let mode = items.choiceMode, mode != .none else {
            throw DriverCannot(.choose(place), on: element)
        }
        var parts = [g_variant_new_uint32(guint32(place)), g_variant_new_boolean(mode == .multiple ? 1 : 0),
                     g_variant_new_boolean(0)]
        _ = gtk_widget_activate_action_variant(list, "list.select-item", g_variant_new_tuple(&parts, 3))
    }

    /// Activates the item `element` stands in, as a double click or Return on its row does: the list's own
    /// `activate`; false where it stands in no item.
    func activateItem(_ element: MountedElement, in items: MountedElement) throws -> Bool {
        guard let view = (items.native as? GTKElement)?.view as? GTKItemsView, let list = view.list else {
            return false
        }
        var item = element
        while let parent = item.parent, parent !== items { item = parent }
        guard let identity = view.cells.identity(of: item), let place = view.cells.identities.firstIndex(of: identity)
        else { return false }
        GTKTestHost.emit(list.opaque, "activate", [Double(place)])
        return true
    }
}

extension GTKItemsView {
    /// How many items GTK's choice model lets the user choose, by its kind; nil before there is a list.
    var choiceMode: SelectionMode? {
        guard let selection else { return nil }
        let held = UnsafeMutablePointer<GTypeInstance>(selection)
        if g_type_check_instance_is_a(held, gtk_single_selection_get_type()) != 0 { return .single }
        if g_type_check_instance_is_a(held, gtk_multi_selection_get_type()) != 0 { return .multiple }
        return SelectionMode.none
    }

    /// The identities GTK's choice model holds chosen, in the order the list shows them.
    var chosenIdentities: [String] {
        guard let selection else { return [] }
        let count = g_list_model_get_n_items(selection)
        return (0..<count).filter { gtk_selection_model_is_selected(selection, $0) != 0 }.map { identity(at: $0) }
    }
}
