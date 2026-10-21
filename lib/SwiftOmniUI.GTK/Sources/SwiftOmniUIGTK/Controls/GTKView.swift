// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// A GTK widget Swift holds, and the number its signals name it by.
/// Design: docs/design/platforms/gtk/c-api.md#a-view-and-its-number
@MainActor
class GTKView {
    /// The widget, held until this is released.
    let widget: GTKWidget

    /// The number the widget's signals hand back.
    let number: Int64

    /// The layout that places this view, which a place written between passes asks to allocate again.
    weak var placingLayout: GTKLayoutView?

    /// Content-size invalidation belongs to this view, not to every row in its lazy parent.
    var measurementRevision = 0

    /// Logical ancestry survives native toolbar hosting.
    weak var sourceElement: MountedElement?
    var safeAreaContext: SafeAreaContext? {
        didSet { if safeAreaContext != oldValue { safeAreaChanged() } }
    }
    var rootSafeAreaContext: ((Rect) -> SafeAreaContext)?

    /// A native toolbar owns the widget, while the source modifier still owns
    /// its layout contribution, animation ancestry and parent-space report.
    weak var nativeSafeBarOwner: AnyObject?
    private(set) var safeBarDrawing: HostMatrix?

    func recordSafeBarPlace(_ place: Rect, context: SafeAreaContext) {
        placed = place
        safeAreaContext = context
        (nativeSafeBarOwner as? GTKSafeAreaBarHost)?.sourcePlaced(place)
        updateSafeBarDrawing()
    }

    func clearSafeBarDrawing() {
        safeBarDrawing = nil
        inheritedBlur = 0
        writeBlur()
        setPlacedDrawing(nil, opacity: 1)
    }

    func updateSafeBarDrawing() {
        guard nativeSafeBarOwner != nil else { return }
        (nativeSafeBarOwner as? GTKView)?.setIgnoresInput(sourceElement?.safeBarAllowsInput == false)
        (nativeSafeBarOwner as? GTKView)?.setEnabled(sourceElement?.safeBarIsEnabled ?? true)
        var matrix = HostMatrix.identity
        var opacity = 1.0
        var blurVariance = 0.0
        var x = placedFrame.x, y = placedFrame.y
        var totalX = 0.0, totalY = 0.0
        var next = sourceElement?.parent
        while let element = next {
            if let view = (element.native as? GTKElement)?.view {
                let frame = view.placedFrame
                var moved = HostMatrix.identity
                moved.m41 = x
                moved.m42 = y
                totalX += x
                totalY += y
                matrix = matrix * moved * view.transform.under(view.placedDrawing).matrix(width: frame.width, height: frame.height)
                opacity *= view.opacity * view.placedOpacity
                blurVariance += view.blur * view.blur
                x = frame.x
                y = frame.y
                if element.type == .page { break }
            }
            next = element.parent
        }
        var unmoved = HostMatrix.identity
        unmoved.m41 = -totalX
        unmoved.m42 = -totalY
        let drawing = matrix * unmoved
        let changed = safeBarDrawing != drawing
        safeBarDrawing = drawing
        inheritedBlur = blurVariance.squareRoot()
        writeBlur()
        setPlacedDrawing(placedDrawing, opacity: opacity)
        if changed, Self.allocating == 0, let host = nativeSafeBarOwner as? GTKLayoutView {
            gtk_widget_queue_allocate(host.widget)
        }
    }

    /// An ancestor opacity/offset animation need not cause layout. Mirror it
    /// to promoted descendants when drawing changes as well as when arranging.
    func refreshNativeSafeBarDrawing() {
        func visit(_ element: MountedElement) {
            for child in element.children {
                if let view = (child.native as? GTKElement)?.view, view.nativeSafeBarOwner != nil {
                    view.updateSafeBarDrawing()
                } else {
                    visit(child)
                }
            }
        }
        if let sourceElement { visit(sourceElement) }
    }

    func layoutSafeArea(in bounds: Rect) -> SafeAreaContext {
        (safeAreaContext ?? rootSafeAreaContext?(bounds) ?? SafeAreaContext(bounds: bounds))
            .ignoring(sourceElement?.ignoresSafeArea)
    }

    /// Resolve arithmetic when a parent places this view, before native
    /// measurement reads its document. Native writes still wait until layout ends.
    func safeAreaChanged() {}

    /// Where the view was last placed in its parent; nil before its first place.
    var placed: Rect?

    /// How the view's own properties move, turn and scale it.
    var transform = HostDrawingTransform.identity

    /// How a placing layout's run draws the view over its own transform, and how opaque; nil while none does.
    var placedDrawing: HostDrawingTransform?
    private(set) var placedOpacity = 1.0

    /// How opaque the view's own property draws it, and whether it shows, as the host last wrote them.
    private(set) var opacity = 1.0
    private(set) var isShown = true

    /// Blur is drawing, in logical pixels. A local provider changes only this
    /// widget's filter; animated radii never grow the display-wide style sheet.
    private(set) var blur = 0.0
    private var inheritedBlur = 0.0
    private var writtenBlur = 0.0
    private var blurProvider: UnsafeMutablePointer<GtkCssProvider>?

    /// What assistive technology meets of the view, as the host last wrote it; nil before the element said any.
    var accessibility: AccessibilityWords?

    /// The `GtkDropTarget` the widget listens through, and the element its
    /// messages go to, weakly so the widget outliving its element loses them
    /// rather than dangling; nil while it takes no drops. The widget holds
    /// the target once attached.
    var drop: (target: OpaquePointer, recipient: () -> GTKElement?)?

    /// The words the view shows of itself, which name it where it is a heading; nil where it shows none.
    var shownWords: String? { nil }

    /// The controllers the view listens through, and what hears them; nil while it listens for nothing.
    private(set) var listening: GTKListening?
    private var onHeard: ((HeardInput) -> Void)?

    /// What hears the keyboard come into the view and leave it, and the controller telling it; nil while none does.
    /// Design: docs/design/platforms/gtk/input.md#the-keyboards-focus
    private var onFocusChanged: ((Bool) -> Void)?
    private var focusController: OpaquePointer?

    /// The menu the view offers where the user asks for one; nil for none.
    var contextMenu: GTKContextMenu? {
        didSet { if contextMenu !== oldValue { oldValue?.remove() } }
    }

    /// The style sheet's class giving the view its padding.
    private var paddingClass: String?

    private static let live = LiveViews<GTKView>()

    /// Takes the next number and holds the widget `make` makes, handed that number.
    init(_ make: (_ number: Int64) -> GTKWidget?) {
        number = Self.live.reserve()
        guard let widget = make(number) else { fatalError("GTK made no widget") }
        self.widget = widget
        g_object_ref_sink(widget)
        Self.live.hold(self, as: number)
    }

    /// Lets go of the widget, taking it out of a SwiftOmniUI panel; any other parent - a viewport, a window - is the
    /// owner of its child, and takes it out itself.
    isolated deinit {
        Self.live.release(number)
        contextMenu?.remove()
        if let blurProvider { g_object_unref(blurProvider) }
        if let parent = gtk_widget_get_parent(widget), GTKPanel.holds(parent) { gtk_widget_unparent(widget) }
        g_object_unref(widget)
    }

    /// The live view a signal names; nil once it has left.
    static func find(_ number: Int64) -> GTKView? {
        live.find(number)
    }

    /// How many views Swift holds - what a test counts to see every one let go.
    static var liveCount: Int { live.count }

    /// Connects `handler` to the widget's `signal`, handing it this view's number.
    func connect(_ signal: String, _ handler: GTKSignalHandler) {
        connectSignal(UnsafeMutableRawPointer(widget), signal, number: number, handler)
    }

    /// Connects `handler` to the widget's `notify::<property>`, handing it this view's number.
    func notify(_ property: String, _ handler: GTKArgumentHandler) {
        connectNotify(UnsafeMutableRawPointer(widget), property, number: number, handler)
    }

    /// Takes class `current` off `target` - the view's widget where nil - and puts `wanted` on it, where they differ.
    func swapClass(_ current: inout String?, to wanted: String?, on target: GTKWidget? = nil) {
        guard wanted != current else { return }
        let target = target ?? widget
        if let current { gtk_widget_remove_css_class(target, current) }
        if let wanted { gtk_widget_add_css_class(target, wanted) }
        current = wanted
    }

    // MARK: - What every view takes

    func setShown(_ shown: Bool) {
        isShown = shown
        gtk_widget_set_visible(widget, shown ? 1 : 0)
    }

    /// How opaque the view's own property draws it, under a placing run's opacity; written only where it differs.
    func setOpacity(_ opacity: Double) {
        guard opacity != self.opacity else { return }
        self.opacity = opacity
        gtk_widget_set_opacity(widget, opacity * placedOpacity)
        refreshNativeSafeBarDrawing()
    }

    func setBlur(_ radius: Double) {
        let radius = radius.isFinite ? max(0, radius) : 0
        guard radius != blur else { return }
        blur = radius
        writeBlur()
        refreshNativeSafeBarDrawing()
    }

    private func writeBlur() {
        // Successive Gaussian filters add their variances. A promoted bar has
        // left its native ancestors, so reproduce their filter on its own root.
        let radius = (blur * blur + inheritedBlur * inheritedBlur).squareRoot()
        guard radius != writtenBlur else { return }
        writtenBlur = radius
        let context = gtk_widget_get_style_context(widget)!
        if radius == 0 {
            if let blurProvider {
                gtk_style_context_remove_provider(context, blurProvider.opaque)
                g_object_unref(blurProvider)
                self.blurProvider = nil
            }
            gtk_widget_queue_draw(widget)
            return
        }
        let provider = blurProvider ?? gtk_css_provider_new()!
        // GTK implements CSS blur as a GSK blur node around the entire widget
        // snapshot, including native controls and the custom panel's children.
        gtk_css_provider_load_from_string(provider, "* { filter: blur(\(radius)px); }")
        if blurProvider == nil {
            gtk_style_context_add_provider(context, provider.opaque, guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION + 1))
            blurProvider = provider
        }
        gtk_widget_queue_draw(widget)
    }

    /// How a placing layout's run draws the view, and how opaque, over its own; nil draws it as its own say.
    func setPlacedDrawing(_ drawing: HostDrawingTransform?, opacity: Double) {
        guard drawing != placedDrawing || opacity != placedOpacity else { return }
        placedDrawing = drawing
        placedOpacity = opacity
        gtk_widget_set_opacity(widget, self.opacity * opacity)
        refreshNativeSafeBarDrawing()
        if Self.allocating == 0, let layout = (nativeSafeBarOwner as? GTKLayoutView) ?? placingLayout {
            gtk_widget_queue_allocate(layout.widget)
        }
    }

    /// Whether clicks and touches go through the view to what is behind it.
    func setIgnoresInput(_ ignores: Bool) {
        gtk_widget_set_can_target(widget, ignores ? 0 : 1)
    }

    /// Lays the view out, and writes its words, in `direction` - a field's and a stepper's through the text they
    /// edit by.
    /// Design: docs/design/platforms/gtk/layout.md#right-to-left
    func setDirection(_ direction: GtkTextDirection) {
        gtk_widget_set_direction(widget, direction)
        guard g_type_check_instance_is_a(widget.of(GTypeInstance.self), gtk_editable_get_type()) != 0,
              let words = gtk_editable_get_delegate(widget.opaque) else { return }
        gtk_widget_set_direction(UnsafeMutablePointer(words), direction)
    }

    /// The room between the view's edge and its content, as a class of the host's style sheet; nil for none.
    func setPadding(_ insets: EdgeInsets?) {
        let wanted = insets.flatMap { $0 == EdgeInsets(0) ? nil : GTKStyleSheet.padding($0) }
        guard wanted != paddingClass else { return }
        if let paddingClass { gtk_widget_remove_css_class(widget, paddingClass) }
        if let wanted { gtk_widget_add_css_class(widget, wanted) }
        paddingClass = wanted
    }

    func setEnabled(_ enabled: Bool) {
        gtk_widget_set_sensitive(widget, enabled ? 1 : 0)
    }

    /// Asks GTK to measure this widget again, and every widget above it.
    func invalidateMeasure() {
        measurementRevision &+= 1
        gtk_widget_queue_resize(widget)
    }

    /// Where the view's place travels (`PlacedView`); nothing of most views' follows it.
    func travels(to destination: Rect?) {}

    /// The room the view's words stand in while its place travels; nil where they stand in its place.
    var wordsRoom: Rect? { nil }

    /// The widget's size for the room offered, in logical pixels; nil offers any. Its natural width, no wider
    /// than offered nor narrower than its least, and its natural height for that width.
    /// Design: docs/design/platforms/gtk/layout.md#measuring-a-widget
    func measure(width: Double?, height: Double?) -> LayoutSize {
        var least: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &least, &natural, nil, nil)
        var measuredWidth = Double(natural)
        if let width { measuredWidth = max(Double(least), min(measuredWidth, width.rounded(.down))) }

        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, Int32(measuredWidth), &least, &natural, nil, nil)
        return LayoutSize(width: measuredWidth, height: Double(natural))
    }

    /// Local allocated dimensions, without ancestor traversal or coordinate transforms.
    func drawingSize() -> Size? {
        guard gtk_widget_get_root(widget) != nil, isLaidOut else { return nil }
        return Size(Double(gtk_widget_get_width(widget)), Double(gtk_widget_get_height(widget)))
    }

    /// Where the view stands, in logical pixels: its frame in its parent, its place in the window, and the frame
    /// of its page's content - beneath the page's header bar - there, the window's whole bounds for a view whose
    /// page keeps no bar; nil while it stands in no window or no layout has placed it yet.
    /// Design: docs/design/platforms/gtk/layout.md#where-a-view-stands
    func frameReport() -> [Double]? {
        guard let root = gtk_widget_get_root(widget).map(GTKWidget.init), isLaidOut else { return nil }
        var safeArea = Rect(
            x: 0, y: 0,
            width: Double(gtk_widget_get_width(root)), height: Double(gtk_widget_get_height(root)))
        var ancestor = gtk_widget_get_parent(widget)
        while let each = ancestor {
            if g_type_check_instance_is_a(each.of(GTypeInstance.self), adw_toolbar_view_get_type()) != 0,
               let content = adw_toolbar_view_get_content(each.opaque) {
                var bounds = graphene_rect_t()
                if gtk_widget_compute_bounds(content, root, &bounds) != 0 {
                    safeArea = Rect(
                        x: Double(bounds.origin.x), y: Double(bounds.origin.y),
                        width: Double(bounds.size.width), height: Double(bounds.size.height))
                }
                break
            }
            ancestor = gtk_widget_get_parent(each)
        }
        let corner = Self.origin(of: widget, in: root)
        if let local = safeAreaContext?.safe {
            safeArea = Rect(corner.x + local.x, corner.y + local.y, local.width, local.height)
        }
        var frame = placedFrame
        frame.width = Double(gtk_widget_get_width(widget))
        frame.height = Double(gtk_widget_get_height(widget))
        return MountedElement.frameNumbers(place: frame, corner: corner, safeArea: safeArea)
    }

    /// The widget's frame in its window, in logical pixels; nil in no window.
    func windowRect() -> Rect? {
        guard let root = gtk_widget_get_root(widget).map(GTKWidget.init) else { return nil }
        let origin = Self.origin(of: widget, in: root)
        return Rect(
            x: origin.x, y: origin.y,
            width: Double(gtk_widget_get_width(widget)), height: Double(gtk_widget_get_height(widget)))
    }

    /// Whether a layout has placed the view: SwiftOmniUI's, or GTK's allocation giving it a size.
    private var isLaidOut: Bool {
        placed != nil || gtk_widget_get_width(widget) > 0 || gtk_widget_get_height(widget) > 0
    }

    private static func origin(of widget: GTKWidget, in root: GTKWidget) -> Point {
        var from = graphene_point_t(x: 0, y: 0)
        var to = graphene_point_t()
        guard gtk_widget_compute_point(widget, root, &from, &to) != 0 else { return Point(x: 0, y: 0) }
        return Point(x: Double(to.x), y: Double(to.y))
    }

    /// Where GTK laid the widget out in its parent, in logical pixels, its CSS box and transform included.
    var laidOutFrame: Rect {
        var bounds = graphene_rect_t()
        guard let parent = gtk_widget_get_parent(widget), gtk_widget_compute_bounds(widget, parent, &bounds) != 0
        else { return Rect(x: 0, y: 0, width: 0, height: 0) }
        return Rect(
            x: Double(bounds.origin.x), y: Double(bounds.origin.y),
            width: Double(bounds.size.width), height: Double(bounds.size.height))
    }

    /// What the view listens for of the user's input.
    var hearing: Hearing { listening?.hearing ?? [] }

    /// Listens for what `hearing` names, `heard` hearing it; a panel listening for taps is pressable by
    /// assistive technology.
    /// Design: docs/design/platforms/gtk/input.md#listening
    func hear(_ hearing: Hearing, _ heard: @escaping (HeardInput) -> Void) {
        onHeard = hearing.isEmpty ? nil : heard
        guard hearing != self.hearing else { return }

        if GTKPanel.holds(widget) { GTKPanel.setPressable(widget, hearing.contains(.taps)) }
        let listening = listening ?? GTKListening(widget: widget, number: number)
        listening.listen(for: hearing)
        self.listening = hearing.isEmpty ? nil : listening
    }

    /// What the view heard, handed to what hears it.
    ///
    /// A popup standing over the pointer takes the pointer to a surface of its own, so GTK tells the views under it
    /// that the pointer left - which it did not. That exit is withheld while a popup stands over the view; a pointer
    /// coming back on the view drops what was withheld, since the view's hover never left either. A popup standing
    /// over one layer is no popup over the layer it opens in: what stands in the popup itself - its own card's
    /// content, where the pointer is - hears the pointer's own exits.
    /// Design: docs/design/platforms/gtk/input.md#a-popup-over-the-pointer
    func heard(_ heard: HeardInput) {
        if case .pointer(let event, _) = heard {
            if event == .pointerEntered {
                GTKHoverHold.resumed(self)
            } else if event == .pointerExited, GTKHoverHold.standsOver(self) {
                GTKHoverHold.withhold(heard, for: self)
                return
            }
        }
        deliver(heard)
    }

    /// What the view heard, past the hold above - what the hold itself uses when a popup's going settles it.
    func deliver(_ heard: HeardInput) {
        if case .drag(let phase, let x, let y, let at, let from) = heard,
           let root = gtk_widget_get_root(widget).map(GTKWidget.init) {
            func local(_ point: Point) -> Point {
                var input = graphene_point_t(x: Float(point.x), y: Float(point.y))
                var output = graphene_point_t()
                guard gtk_widget_compute_point(root, widget, &input, &output) != 0 else { return point }
                return Point(Double(output.x), Double(output.y))
            }
            onHeard?(.drag(phase, x: x, y: y, at: local(at), from: local(from)))
        } else { onHeard?(heard) }
    }

    /// Tells `action` when the keyboard comes into the view or a part of it, and when it leaves; nil tells no one.
    /// Design: docs/design/platforms/gtk/input.md#the-keyboards-focus
    func setFocusChanged(_ action: ((Bool) -> Void)?) {
        onFocusChanged = action
        if action == nil, let focusController {
            gtk_widget_remove_controller(widget, focusController)
            self.focusController = nil
        } else if action != nil, focusController == nil {
            let focus = gtk_event_controller_focus_new()!
            connectSignal(UnsafeMutableRawPointer(focus), "enter", number: number) { (_: UnsafeMutableRawPointer?, data) in
                MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.onFocusChanged?(true) }
            }
            connectSignal(UnsafeMutableRawPointer(focus), "leave", number: number) { (_: UnsafeMutableRawPointer?, data) in
                MainActor.assumeIsolated { GTKView.find(viewNumber(data))?.onFocusChanged?(false) }
            }
            gtk_widget_add_controller(widget, focus)
            focusController = focus
        }
    }

    /// The user clicked the view.
    func clicked() {}

    /// The element left the tree: the view lets go of everything that would call back into it. An override
    /// calls this first.
    func detach() {
        GTKHoverHold.letGo(of: self)
        hear([]) { _ in }
        setFocusChanged(nil)
        contextMenu = nil
    }
}
