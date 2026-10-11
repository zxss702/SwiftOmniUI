import SwiftOmniUI

/// The platform's own map, and the region an act away.
struct MapSample: SampleContent, ExampleContent {
    @Aim(Map.self) private var map

    static let id = "map"
    static let title = "Map"
    static let summary = "The platform's own map - the region it shows is an act away."

    /// Held still: a map PANS, and the page's scroller would claim the drag -
    /// the rule every gesture sample follows.
    static let scrolls = false

    static let code = """
        @Aim(Map.self) private var map

        VStack {
            // Where it OPENS is the initializer's - kept until the platform's
            // map has connected. Moving later is the act the buttons perform.
            Map(latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                .aim(map)
                .frame(height: 300)

            HStack {
                Button("Old Town", action: {
                        try await map.moveToRegion(
                            latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                    })
                    

                Button("Poland", action: {
                        try await map.moveToRegion(
                            latitude: 52.1, longitude: 19.4, radiusMeters: 350_000)
                    })
                    
            }
        }
        """

    var body: some View {
        VStack {

            // The opening region is the INITIALIZER's, not an `.onAppear` act:
            // written here it is kept until the platform's map has connected,
            // while an act can land an instant too early and be overwritten
            // by the map's own opening view.
            Map(latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                .aim(map)
                .frame(height: 300)

            HStack {
                Button("Old Town", action: {
                        try await map.moveToRegion(
                            latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                    })
                    .padding(EdgeInsets(14, 8))
                    

                Button("Poland", action: {
                        try await map.moveToRegion(
                            latitude: 52.1, longitude: 19.4, radiusMeters: 350_000)
                    })
                    .padding(EdgeInsets(14, 8))
                    
            }
            .spacing(8)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`Map` is an optional provider, drawn by the platform's own map where a "
                + "host provides one. A host depends on a map library and a map service "
                + "of its own, and some platforms have no map element at all.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("Where the map opens is the initializer's: that region is kept until the "
                + "platform's map has connected, while the same move from `.onAppear` can "
                + "land an instant too early and be overwritten. Moving later is the act "
                + "the buttons perform - `moveToRegion` through the map's `@Aim`, with the "
                + "radius in meters.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
