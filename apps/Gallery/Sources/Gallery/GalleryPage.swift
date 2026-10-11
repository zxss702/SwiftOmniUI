// What every page of the gallery has in common.

import SwiftOmniUI

extension PageSession {
    /// Dresses a page the way every page of the gallery is dressed: its title,
    /// the inspector and the way home in the corner, and the tinted ground
    /// behind the content.
    ///
    ///     VStack { … }
    ///         .onAppear { page.gallery("Level 2", scene: scene, nav: nav) }
    ///
    /// Said once here instead of on every page. **What is NOT here is the
    /// bar**: a `NavigationStack` owns its bar, so its appearance is written
    /// once in `MainWindow.detail`. What a
    /// PAGE can still ask of the stack it is on is the `navigationStack`
    /// properties - whether there is a bar at all, whether there is a way back,
    /// what the back button reads - and `LevelPage` shows those.
    ///
    /// The title is the page's own, drawn by each platform's bar in its own
    /// type. A page with actions of its own puts them before these from its
    /// `.onAppear`; see `ToolbarSample`.
    ///
    /// - Parameters:
    ///   - title: what the page is called.
    ///   - scene: the gallery the page is in - the scene its ⓘ opens the
    ///     inspector of.
    ///   - nav: where the gallery is, which the way home moves - nil on the
    ///     home page, which is where it goes.
    @MainActor func gallery(_ title: String, scene: SceneSession, nav: Navigation?) {
        self.title = title
        // The inspector's ⓘ and Home's house are the two buttons every page
        // carries; their captions remain available to accessibility and to
        // platforms that show text.
        toolbarItems = [
            .inspector(scene),
        ] + (nav.map { [.home($0)] } ?? [])

        // Tinted rather than white, which is what lets a card lift off it with
        // a fill instead of a shadow - see `Palette.surface`.
        background = Palette.surface
    }
}
