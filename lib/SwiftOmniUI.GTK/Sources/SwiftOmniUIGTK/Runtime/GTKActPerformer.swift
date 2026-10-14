// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// Performs the acts the application calls on the host, and answers each - a reply with its values, or a failure
/// with the reason - so a caller never waits on an act nobody performs. A question for the user answers when the
/// user does.
/// Design: docs/design/platforms/gtk/runtime.md#acts
@MainActor
final class GTKActPerformer {
    private let core: CoreLink

    /// What the dialogs ask, one showing at a time; each answers under its ticket.
    private let questions = QuestionQueue<GTKQuestion>()

    init(core: CoreLink) {
        self.core = core
    }

    /// Performs one act, and answers it; `window` is where a question, a word to a screen reader and the keyboard
    /// stand.
    func perform(_ call: HostActCall, in tree: MountedTree, window: GTKWindow?, applicationID: String) {
        switch call.act {
        case .currentTime:
            reply(call, [currentTime().propValue])
        case .currentTimeZone:
            let zone = g_time_zone_new_local()!
            reply(call, [.string(String(cString: g_time_zone_get_identifier(zone)))])
            g_time_zone_unref(zone)
        case .utcOffset:
            utcOffset(call)
        case .alert, .confirm, .chooseAction, .prompt:
            guard let window, let question = HostQuestion(call) else {
                return fail(call, "there is no window to ask the user in")
            }
            let asked = GTKQuestion(call, question, window: window)
            let (ticket, showsNow) = questions.ask(asked)
            asked.ticket = ticket
            if showsNow { asked.show() }
        case .chooseFiles:
            chooseFiles(call, window: window)
        case .openFolders:
            openFolders(call, window: window)
        case .revealFile, .launchFile, .launchLink:
            launch(call, window: window)
        case .copyText:
            let text = call.arguments.first?.string ?? ""
            text.withCString { gdk_clipboard_set_text(gdk_display_get_clipboard(gdk_display_get_default()), $0) }
            reply(call, [])
        case .announce:
            if let window, Self.reachesAScreenReader(window.widget) {
                gtk_accessible_announce(
                    window.widget.opaque, call.arguments.first?.string ?? "", GTK_ACCESSIBLE_ANNOUNCEMENT_PRIORITY_MEDIUM)
            }
            reply(call, [])
        case .hideOnScreenKeyboard:
            // The keyboard GNOME shows on a touch screen stands for the field holding the focus: the field lets
            // the focus go, and the keyboard goes down. Whether a field held it.
            reply(call, [.bool(hideKeyboard(from: window))])
        case .focus, .unfocus:
            focus(call, in: tree)
        case .persistValue:
            GTKKeptValues.keep(call, core: core, applicationID: applicationID)
            reply(call, [])
        case .scrollTo:
            guard let view = aimed(call, in: tree) else { return }
            guard let items = view as? GTKItemsView else { return fail(call, "scrollTo is an act of an List") }
            items.scroll(
                to: call.arguments.value(1)?.string ?? "",
                anchor: call.arguments.value(2).flatMap(ScrollAnchor.init(propValue:)) ?? .nearest)
            reply(call, [])
        case .scrollToDescendant:
            scrollToDescendant(call, in: tree)
        case .measureText:
            measureText(call, in: tree)
        case .handlerFailed:
            GTKRenderer.log.error("a handler failed: \(call.arguments.first?.string ?? "")")
            reply(call, [])
        default:
            perform(registered: call, in: tree)
        }
    }

    /// Performs an act the application registered, by the host layer's rule: its own, or one aimed at its own element,
    /// handed that element's control; an act nobody registered is refused by name.
    private func perform(registered call: HostActCall, in tree: MountedTree) {
        guard !GTKInterop.acts.perform(
            call, in: tree, core: core, view: { ($0.native as? GTKElement)?.view }, log: { GTKRenderer.log.error($0) })
        else { return }
        fail(call, "the GTK host does not perform the act '\(call.act.name)'")
    }

    /// Native asynchronous launchers keep the UI responsive while the desktop opens the item.
    private func launch(_ call: HostActCall, window: GTKWindow?) {
        let operation = Launch(call: call, core: core)
        let data = Unmanaged.passRetained(operation).toOpaque()
        let ready: GAsyncReadyCallback = { _, result, data in
            guard let data else { return }
            let operation = Unmanaged<GTKActPerformer.Launch>.fromOpaque(data).takeRetainedValue()
            nonisolated(unsafe) let result = result
            MainActor.assumeIsolated { operation.finish(result) }
        }
        let parent = window?.widget.of(GtkWindow.self)
        if call.act == .launchLink {
            gtk_uri_launcher_launch(operation.launcher, parent, nil, ready, data)
        } else if call.act == .revealFile {
            gtk_file_launcher_open_containing_folder(operation.launcher, parent, nil, ready, data)
        } else {
            gtk_file_launcher_launch(operation.launcher, parent, nil, ready, data)
        }
    }

    @MainActor private final class Launch {
        let call: HostActCall
        let core: CoreLink
        let launcher: OpaquePointer

        init(call: HostActCall, core: CoreLink) {
            self.call = call
            self.core = core
            if call.act == .launchLink {
                launcher = gtk_uri_launcher_new(call.arguments.first?.string ?? "")!
            } else {
                let path = call.act == .revealFile ? call.arguments.first?.string
                    : call.arguments.first.flatMap(ChosenFile.init(propValue:))?.address
                let file = g_file_new_for_path(path ?? "")!
                launcher = gtk_file_launcher_new(file)!
                g_object_unref(UnsafeMutableRawPointer(file))
            }
        }

        isolated deinit { g_object_unref(UnsafeMutableRawPointer(launcher)) }

        func finish(_ result: OpaquePointer?) {
            guard let result else { core.reply(call, [.bool(false)]); return }
            var error: UnsafeMutablePointer<GError>?
            let took: gboolean
            if call.act == .launchLink {
                took = gtk_uri_launcher_launch_finish(launcher, result, &error)
            } else if call.act == .revealFile {
                took = gtk_file_launcher_open_containing_folder_finish(launcher, result, &error)
            } else {
                took = gtk_file_launcher_launch_finish(launcher, result, &error)
            }
            if let error { g_error_free(error) }
            core.reply(call, [.bool(took != 0)])
        }
    }

    /// The platform's file dialog for `chooseFiles` - the picked paths answer
    /// it, an empty list a cancel; a `Choice` keeps the dialog and the call
    /// until GTK is heard.
    private func chooseFiles(_ call: HostActCall, window: GTKWindow?) {
        let dialog = gtk_file_dialog_new()!
        let multiple = call.arguments.value(0)?.bool ?? false
        let types = call.arguments.value(1)?.strings ?? []
        if !types.isEmpty {
            let filter = gtk_file_filter_new()!
            for type in types { gtk_file_filter_add_suffix(filter, type) }
            let filters = g_list_store_new(gtk_file_filter_get_type())!
            g_list_store_append(filters, UnsafeMutableRawPointer(filter))
            gtk_file_dialog_set_filters(dialog, filters)
            g_object_unref(UnsafeMutableRawPointer(filter))
            g_object_unref(UnsafeMutableRawPointer(filters))
        }

        let choice = Choice(call: call, dialog: dialog, multiple: multiple, core: core)
        let data = Unmanaged.passRetained(choice).toOpaque()
        let ready: GAsyncReadyCallback = { _, result, data in
            guard let data, let result else { return }
            let choice = Unmanaged<GTKActPerformer.Choice>.fromOpaque(data).takeRetainedValue()
            MainActor.assumeIsolated { choice.finish(result) }
        }
        if multiple {
            gtk_file_dialog_open_multiple(dialog, window?.widget.of(GtkWindow.self), nil, ready, data)
        } else {
            gtk_file_dialog_open(dialog, window?.widget.of(GtkWindow.self), nil, ready, data)
        }
    }

    /// The platform's folder dialog for `openFolders` - the picked folders
    /// answer it as `ChosenFile`s, an empty list a cancel; a `FolderChoice`
    /// keeps the dialog and the call until GTK is heard.
    private func openFolders(_ call: HostActCall, window: GTKWindow?) {
        let dialog = gtk_file_dialog_new()!
        let multiple = call.arguments.value(0)?.bool ?? false
        let choice = FolderChoice(call: call, dialog: dialog, multiple: multiple, core: core)
        let data = Unmanaged.passRetained(choice).toOpaque()
        let ready: GAsyncReadyCallback = { _, result, data in
            guard let data, let result else { return }
            let choice = Unmanaged<GTKActPerformer.FolderChoice>.fromOpaque(data).takeRetainedValue()
            MainActor.assumeIsolated { choice.finish(result) }
        }
        if multiple {
            gtk_file_dialog_select_multiple_folders(dialog, window?.widget.of(GtkWindow.self), nil, ready, data)
        } else {
            gtk_file_dialog_select_folder(dialog, window?.widget.of(GtkWindow.self), nil, ready, data)
        }
    }

    /// An `openFolders` act waiting on its dialog: the dialog keeps living
    /// under it, and its `finish` answers the call with the folders GTK
    /// heard - or an empty list, which is how a cancel reads.
    final class FolderChoice {
        let call: HostActCall
        let dialog: OpaquePointer
        let multiple: Bool
        let core: CoreLink

        init(call: HostActCall, dialog: OpaquePointer, multiple: Bool, core: CoreLink) {
            self.call = call
            self.dialog = dialog
            self.multiple = multiple
            self.core = core
        }

        deinit { g_object_unref(UnsafeMutableRawPointer(dialog)) }

        /// The answer: every picked folder as a `ChosenFile`, an empty list
        /// for a cancel.
        func finish(_ result: OpaquePointer) {
            var error: UnsafeMutablePointer<GError>?
            var folders: [ChosenFile] = []
            func take(_ file: OpaquePointer) {
                guard let path = g_file_get_path(file) else { return }
                let address = String(cString: path)
                g_free(path)
                folders.append(ChosenFile(address: address, name: String(address.split(separator: "/").last ?? "")))
            }
            if multiple {
                if let files = gtk_file_dialog_select_multiple_folders_finish(dialog, result, &error) {
                    for index in 0 ..< g_list_model_get_n_items(files) {
                        guard let file = g_list_model_get_item(files, index) else { continue }
                        take(OpaquePointer(file))
                        g_object_unref(UnsafeMutableRawPointer(file))
                    }
                    g_object_unref(UnsafeMutableRawPointer(files))
                }
            } else if let file = gtk_file_dialog_select_folder_finish(dialog, result, &error) {
                take(file)
                g_object_unref(UnsafeMutableRawPointer(file))
            }
            if let error { g_error_free(error) }
            core.reply(call, [folders.propValue])
        }
    }

    /// A `chooseFiles` act waiting on its dialog: the dialog keeps living
    /// under it, and its `finish` answers the call with the paths GTK heard -
    /// or an empty list, which is how a cancel reads.
    final class Choice {
        let call: HostActCall
        let dialog: OpaquePointer
        let multiple: Bool
        let core: CoreLink

        init(call: HostActCall, dialog: OpaquePointer, multiple: Bool, core: CoreLink) {
            self.call = call
            self.dialog = dialog
            self.multiple = multiple
            self.core = core
        }

        deinit { g_object_unref(UnsafeMutableRawPointer(dialog)) }

        /// The answer: every picked file's path, an empty list for a cancel.
        func finish(_ result: OpaquePointer) {
            var error: UnsafeMutablePointer<GError>?
            var paths: [String] = []
            if multiple {
                if let files = gtk_file_dialog_open_multiple_finish(dialog, result, &error) {
                    for index in 0 ..< g_list_model_get_n_items(files) {
                        guard let file = g_list_model_get_item(files, index) else { continue }
                        if let path = g_file_get_path(OpaquePointer(file)) {
                            paths.append(String(cString: path))
                            g_free(path)
                        }
                        g_object_unref(UnsafeMutableRawPointer(file))
                    }
                    g_object_unref(UnsafeMutableRawPointer(files))
                }
            } else if let file = gtk_file_dialog_open_finish(dialog, result, &error) {
                if let path = g_file_get_path(file) {
                    paths.append(String(cString: path))
                    g_free(path)
                }
                g_object_unref(UnsafeMutableRawPointer(file))
            }
            if let error { g_error_free(error) }
            core.reply(call, [.strings(paths)])
        }
    }

    /// The question under `ticket` was answered by the response `id`; the next question shows.
    func respond(_ ticket: Int64, _ id: String) {
        guard let (asked, next) = questions.answered(ticket) else { return }
        let (accepted, words) = asked.answer(id)
        reply(asked.call, asked.question.answer(accepted: accepted, words: words))
        next?.show()
    }

    /// The local time of day: hour, minute, second, millisecond.
    private func currentTime() -> [Double] {
        let now = g_date_time_new_now_local()!
        defer { g_date_time_unref(now) }
        return [
            Double(g_date_time_get_hour(now)), Double(g_date_time_get_minute(now)),
            Double(g_date_time_get_second(now)), Double(g_date_time_get_microsecond(now) / 1000),
        ]
    }

    /// How far a zone is from UTC on a day, in minutes, taken at the day's noon; a zone GLib does not know fails the
    /// act.
    private func utcOffset(_ call: HostActCall) {
        let name = call.arguments.value(0)?.string
        guard let zone = name.map({ g_time_zone_new_identifier($0) }) ?? g_time_zone_new_local() else {
            return fail(call, "no time zone '\(name ?? "")' is known")
        }
        defer { g_time_zone_unref(zone) }

        let today = g_date_time_new_now(zone)!
        let day = call.arguments.value(1).flatMap { CalendarDate(propValue: $0) }
        let noon = g_date_time_new(
            zone, Int32(day?.year ?? Int(g_date_time_get_year(today))),
            Int32(day?.month ?? Int(g_date_time_get_month(today))),
            Int32(day?.day ?? Int(g_date_time_get_day_of_month(today))), 12, 0, 0)
        g_date_time_unref(today)
        guard let noon else { return fail(call, "no such day") }
        defer { g_date_time_unref(noon) }

        reply(call, [.number(Double(g_date_time_get_utc_offset(noon) / 60_000_000))])
    }

    /// Puts the focus on the view the act names - or the first control in it that takes it - or takes it off;
    /// `focus` answers whether the view took it.
    private func focus(_ call: HostActCall, in tree: MountedTree) {
        guard let view = aimed(call, in: tree) else { return }

        if call.act == .focus {
            // GTK hands a container's keyboard to a part of it - a list to its row - and may answer that it took
            // none: where the focus stands answers.
            gtk_widget_grab_focus(view.widget)
            reply(call, [.bool(Self.holdsTheKeyboard(view.widget))])
            return
        }
        if Self.holdsTheKeyboard(view.widget), let root = gtk_widget_get_root(view.widget) {
            gtk_root_set_focus(root, nil)
        }
        reply(call, [])
    }

    /// Takes the focus off the text widget holding it in `window`, where one does - the keyboard the widget
    /// brought up goes with it. Whether one held it.
    private func hideKeyboard(from window: GTKWindow?) -> Bool {
        guard let window, let root = gtk_widget_get_root(window.widget),
              let held = gtk_root_get_focus(root),
              [gtk_text_get_type(), gtk_text_view_get_type()].contains(where: {
                  g_type_check_instance_is_a(held.of(GTypeInstance.self), $0) != 0
              })
        else { return false }
        gtk_root_set_focus(root, nil)
        return true
    }

    /// Whether the keyboard's focus stands on `widget` or a part of it.
    private static func holdsTheKeyboard(_ widget: GTKWidget) -> Bool {
        guard let root = gtk_widget_get_root(widget), let focus = gtk_root_get_focus(root) else { return false }
        return focus == widget || gtk_widget_is_ancestor(focus, widget) != 0
    }

    /// Scrolls until the aimed ScrollView's descendant `.id()` names stands
    /// where the anchor says.
    private func scrollToDescendant(_ call: HostActCall, in tree: MountedTree) {
        do {
            let element = try tree.aimed(call)
            guard let scroller = (element.native as? GTKElement)?.view as? GTKScrollView else {
                return fail(call, "scrollToDescendant is an act of a ScrollView")
            }
            let name = call.arguments.value(1)?.string ?? ""
            guard let target = element.first(id: .manual(name)),
                  let descendant = (target.native as? GTKElement)?.view else {
                return fail(call, "there is no view '\(name)' inside the scroll view")
            }
            scroller.scroll(
                toDescendant: descendant.widget,
                anchorX: call.arguments.value(2)?.number,
                anchorY: call.arguments.value(3)?.number)
            reply(call, [])
        } catch {
            fail(call, error.reason)
        }
    }

    /// A canvas's `measureText`: its words in the font the act carries, measured by a Pango layout on the aimed
    /// canvas - Pango being the engine GTK draws words with.
    private func measureText(_ call: HostActCall, in tree: MountedTree) {
        guard let view = aimed(call, in: tree) else { return }
        guard let canvas = view as? GTKCanvasView else { return fail(call, "measureText is an act of a Canvas") }
        guard let asked = HostTextMeasure(call) else { return fail(call, "measureText is asked malformed") }
        reply(call, [canvas.measureText(asked.text, font: asked.font, maximumWidth: asked.maximumWidth).propValue])
    }

    /// The view the act is aimed at (`MountedTree.aimed`); nil, the act failed, where there is none.
    private func aimed(_ call: HostActCall, in tree: MountedTree) -> GTKView? {
        do {
            let element = try tree.aimed(call)
            if let view = (element.native as? GTKElement)?.view { return view }
            fail(call, "\(element.id) has no view")
        } catch {
            fail(call, error.reason)
        }
        return nil
    }

    private func reply(_ call: HostActCall, _ values: [HostValue]) {
        core.reply(call, values)
    }

    private func fail(_ call: HostActCall, _ reason: String) {
        core.fail(call, reason, log: { GTKRenderer.log.error($0) })
    }
}

extension GTKActPerformer {
    /// Whether what `widget` announces reaches a screen reader: through GTK's AT-SPI context alone. Without the
    /// accessibility bus GTK stands a context of no assistive technology, which GTK 4.14 announces through a call it
    /// lacks - a crash.
    /// Design: docs/design/platforms/gtk/controls.md#what-assistive-technology-meets
    static func reachesAScreenReader(_ widget: GTKWidget) -> Bool {
        let atSpi = g_type_from_name("GtkAtSpiContext")
        guard atSpi != 0, let context = gtk_accessible_get_at_context(widget.opaque) else { return false }
        defer { g_object_unref(UnsafeMutableRawPointer(context)) }
        return g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(context), atSpi) != 0
    }
}
