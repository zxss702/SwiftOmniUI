import SwiftOmniUI

/// The platform's own map, with pins, a region to move to, and what it draws.
struct MapSample: SampleContent, ExampleContent {
    @State private var said = "tap the map, a pin, or its details"

    @Aim(Map.self) private var map
    @State private var kind = MapType.street
    @State private var traffic = false
    @State private var showsMe = false
    @State private var locked = false

    static let id = "map"
    static let title = "Map"
    static let summary = "The platform's own map, with pins on it - and the region an act away."

    /// Held still: a map PANS, and the page's scroller would claim the drag -
    /// the rule every gesture sample follows.
    static let scrolls = false

    static let code = """
        @State private var said = "tap the map, a pin, or its details"

        @Aim(Map.self) private var map
        @State private var kind = MapType.street
        @State private var traffic = false
        @State private var showsMe = false
        @State private var locked = false

        VStack {
            // What the map last said is read here, so every tap on it builds
            // this closure.
            DebugInfoLabel()

            HStack {
                Button("Old Town", action: {
                        try await map.moveToRegion(
                            latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                    })
                    

                Button("Poland", action: {
                        try await map.moveToRegion(
                            latitude: 52.1, longitude: 19.4, radiusMeters: 350_000)
                    })
                    

                // What it DRAWS, cycled so all three can be seen.
                Button(kind == .street ? "Street" : kind == .satellite ? "Satellite" : "Hybrid", action: {
                        kind = kind == .street ? .satellite
                            : kind == .satellite ? .hybrid : .street
                    })
                    
            }

            HStack {
                SwitchRow("Traffic", $traffic)

                SwitchRow("Show me", $showsMe)

                // Both at once, which is what "locked" means to a user.
                SwitchRow("Locked", $locked)
            }

            // Where it OPENS is the initializer's - kept until the platform's
            // map has connected. Moving later is the act the buttons perform.
            Map(latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                .aim(map)
                // What the map draws, and whether the user may move it.
                .mapType(kind)
                .isTrafficEnabled(traffic)
                .showsUserLocation(showsMe)
                .isZoomEnabled(!locked)
                .isScrollEnabled(!locked)
                .pins {
                    Pin("Wawel Castle")
                        .address("Wawel 5")
                        // What the pin stands for, which is what decides the
                        // icon the platform draws for it.
                        .type(.place)
                        .location(latitude: 50.0540, longitude: 19.9354)
                        .onPinClicked { said = "pin: Wawel Castle" }
                        .onPinDetailsClicked { said = "details: Wawel Castle" }

                    Pin("Main Market Square")
                        .address("Main Market Square 1/3")
                        .type(.searchResult)
                        .location(latitude: 50.0617, longitude: 19.9373)
                        .onPinClicked { said = "pin: Main Market Square" }
                }
                .onMapClicked { location in
                    said = "map: \\(location.latitude), \\(location.longitude)"
                }
                .frame(height: 300)

            Text(said)
        }
        """

    var body: some View {
        VStack {
            DebugInfoLabel()

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
                    

                Button(kind == .street ? "Street" : kind == .satellite ? "Satellite" : "Hybrid", action: {
                        kind =
                            kind == .street
                            ? .satellite
                            : kind == .satellite ? .hybrid : .street
                    })
                    .padding(EdgeInsets(14, 8))
                    
            }
            .spacing(8)
            .horizontalAlignment(.center)

            HStack {
                SwitchRow("Traffic", $traffic)

                SwitchRow("Show me", $showsMe)

                SwitchRow("Locked", $locked)
            }

            // The opening region is the INITIALIZER's, not an `.onAppear` act:
            // written here it is kept until the platform's map has connected,
            // while an act can land an instant too early and be overwritten
            // by the map's own opening view.
            Map(latitude: 50.0617, longitude: 19.9373, radiusMeters: 1500)
                .aim(map)
                // What the map draws, and whether the user may move it.
                .mapType(kind)
                .isTrafficEnabled(traffic)
                .showsUserLocation(showsMe)
                .isZoomEnabled(!locked)
                .isScrollEnabled(!locked)
                .pins {
                    Pin("Wawel Castle")
                        .address("Wawel 5")
                        .type(.place)
                        .location(latitude: 50.0540, longitude: 19.9354)
                        .onPinClicked { said = "pin: Wawel Castle" }
                        .onPinDetailsClicked { said = "details: Wawel Castle" }

                    Pin("Main Market Square")
                        .address("Main Market Square 1/3")
                        .type(.searchResult)
                        .location(latitude: 50.0617, longitude: 19.9373)
                        .onPinClicked { said = "pin: Main Market Square" }
                }
                .onMapClicked { location in
                    said = "map: \(rounded(location.latitude)), \(rounded(location.longitude))"
                }
                .frame(height: 300)

            Text(said)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.accent)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("`Map` is an optional provider, drawn by the platform's own map where a "
                + "host provides one - `MKMapView` on Apple. Elsewhere a host depends on a "
                + "map library and a map service, and the Web has no map element.")
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

    /// Four decimal places - about eleven meters - so a tapped point reads as
    /// a coordinate rather than a river of digits.
    private func rounded(_ degrees: Double) -> Double {
        (degrees * 10_000).rounded() / 10_000
    }
}
