// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

// File drops: `allowDrop` attaches a `GtkDropTarget` to the widget, offering
// the session `GFile` and `GdkFileList`, and its `enter`/`leave`/`drop`
// signals become the tree's `dragOver`/`dragLeave`/`dropPaths` through the
// view's recipient element.

extension GTKElement {
    /// Whether `view` takes file drops: its drop target and recipient, both
    /// ways.
    func configureDropTarget(for view: GTKView) {
        if value(.allowDrop)?.bool == true {
            if view.drop == nil {
                var types: [GType] = [g_file_get_type(), gdk_file_list_get_type()]
                if let target = gtk_drop_target_new(g_file_get_type(), GDK_ACTION_COPY) {
                    gtk_drop_target_set_gtypes(target, &types, 2)
                    listen(target, to: view)
                    gtk_widget_add_controller(view.widget, target)
                    view.drop = (target, { nil })
                }
            }
            if let target = view.drop?.target {
                view.drop = (target, { [weak self] in self })
            }
        } else {
            if let drop = view.drop {
                gtk_widget_remove_controller(view.widget, drop.target)
            }
            view.drop = nil
        }
    }

    /// Wires the target's three signals to the view's number.
    private func listen(_ target: OpaquePointer, to view: GTKView) {
        let entered: @convention(c) (OpaquePointer?, Double, Double, gpointer?) -> GdkDragAction = { _, _, _, data in
            guard let element = GTKView.find(viewNumber(data))?.drop?.recipient() else { return GdkDragAction(rawValue: 0) }
            element.send(.dragOver, [])
            return GDK_ACTION_COPY
        }
        g_signal_connect_data(
            UnsafeMutableRawPointer(target), "enter", unsafeBitCast(entered, to: GCallback.self),
            UnsafeMutableRawPointer(bitPattern: Int(view.number)), nil, GConnectFlags(0))

        let left: GTKSignalHandler = { _, data in
            GTKView.find(viewNumber(data))?.drop?.recipient()?.send(.dragLeave, [])
        }
        g_signal_connect_data(
            UnsafeMutableRawPointer(target), "leave", unsafeBitCast(left, to: GCallback.self),
            UnsafeMutableRawPointer(bitPattern: Int(view.number)), nil, GConnectFlags(0))

        let dropped: @convention(c) (OpaquePointer?, UnsafeMutablePointer<GValue>?, Double, Double, gpointer?) -> Bool = {
            _, value, x, y, data in
            guard let element = GTKView.find(viewNumber(data))?.drop?.recipient(),
                  let value else { return false }
            let paths = GTKElement.dropPaths(in: value)
            guard !paths.isEmpty else { return false }
            element.send(.dropPaths, [.strings(paths), .numbers([x, y])])
            return true
        }
        g_signal_connect_data(
            UnsafeMutableRawPointer(target), "drop", unsafeBitCast(dropped, to: GCallback.self),
            UnsafeMutableRawPointer(bitPattern: Int(view.number)), nil, GConnectFlags(0))
    }

    /// The paths a drop's value carries - one `GFile`, or a `GdkFileList`'s
    /// whole run.
    static func dropPaths(in value: UnsafeMutablePointer<GValue>) -> [String] {
        var paths: [String] = []
        let held = value.pointee.g_type
        if held == g_file_get_type(), let file = g_value_get_object(value) {
            if let path = g_file_get_path(OpaquePointer(file)) {
                paths.append(String(cString: path))
                g_free(path)
            }
        } else if held == gdk_file_list_get_type(), let boxed = g_value_get_boxed(value) {
            var node = gdk_file_list_get_files(OpaquePointer(boxed))
            while let item = node {
                if let path = g_file_get_path(OpaquePointer(item.pointee.data)) {
                    paths.append(String(cString: path))
                    g_free(path)
                }
                node = item.pointee.next
            }
        }
        return paths
    }
}
