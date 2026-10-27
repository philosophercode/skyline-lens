import Foundation

/// A recognisable structure with a known position, used for sanity markers now and
/// for landmark-based registration (Milestone 7) later.
public struct Landmark: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// Ground elevation at the base, metres (NAVD88-ish; datum error is a few metres).
    public var groundElevation: Double
    /// Height of the visual top (spire/antenna if that is what you see), metres above ground.
    public var topHeight: Double

    public var top: GeodeticCoordinate {
        GeodeticCoordinate(latitude: latitude, longitude: longitude, altitude: groundElevation + topHeight)
    }
}

public enum LandmarkCatalog {
    /// Starter citywide catalogue for Milestone 1 sanity markers.
    ///
    /// Coordinates are approximate (typed from public sources, roughly ±30 m) and
    /// must be replaced by footprint-centroid values from the NYC building dataset
    /// in Milestone 2. Do not tune these per site; the full catalogue is 50+ entries.
    public static let starter: [Landmark] = [
        Landmark(id: "esb", name: "Empire State Building", latitude: 40.74844, longitude: -73.98566, groundElevation: 15, topHeight: 443),
        Landmark(id: "chrysler", name: "Chrysler Building", latitude: 40.75165, longitude: -73.97531, groundElevation: 12, topHeight: 319),
        Landmark(id: "one-vanderbilt", name: "One Vanderbilt", latitude: 40.75300, longitude: -73.97870, groundElevation: 14, topHeight: 427),
        Landmark(id: "432-park", name: "432 Park Avenue", latitude: 40.76163, longitude: -73.97191, groundElevation: 20, topHeight: 426),
        Landmark(id: "citigroup", name: "Citigroup Center", latitude: 40.75845, longitude: -73.97040, groundElevation: 18, topHeight: 279),
        Landmark(id: "one-wtc", name: "One World Trade Center", latitude: 40.71274, longitude: -74.01338, groundElevation: 3, topHeight: 541),
        Landmark(id: "central-park-tower", name: "Central Park Tower", latitude: 40.76658, longitude: -73.98095, groundElevation: 22, topHeight: 472),
        Landmark(id: "steinway", name: "Steinway Tower (111 W 57th)", latitude: 40.76462, longitude: -73.97770, groundElevation: 22, topHeight: 435),
        Landmark(id: "boa-tower", name: "Bank of America Tower", latitude: 40.75545, longitude: -73.98446, groundElevation: 15, topHeight: 366),
        Landmark(id: "un-secretariat", name: "UN Secretariat", latitude: 40.74892, longitude: -73.96803, groundElevation: 5, topHeight: 155),
        Landmark(id: "30-hudson-yards", name: "30 Hudson Yards", latitude: 40.75380, longitude: -74.00090, groundElevation: 8, topHeight: 387),
        Landmark(id: "metlife", name: "MetLife Building", latitude: 40.75335, longitude: -73.97648, groundElevation: 14, topHeight: 246),
    ]
}

/// Where the iPad is. Milestone 1 uses GPS plus an optional floor number;
/// Milestone 0/3 replace this with a resection solve.
public struct Viewpoint: Equatable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var groundElevation: Double
    public var heightAboveGround: Double

    public init(latitude: Double, longitude: Double, groundElevation: Double, heightAboveGround: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.groundElevation = groundElevation
        self.heightAboveGround = heightAboveGround
    }

    public var coordinate: GeodeticCoordinate {
        GeodeticCoordinate(latitude: latitude, longitude: longitude, altitude: groundElevation + heightAboveGround)
    }

    /// Rough eye height for a residential floor number (ground floor = 1).
    public static func heightAboveGround(floor: Int, floorHeight: Double = 3.2) -> Double {
        Double(max(floor - 1, 0)) * floorHeight + 1.5
    }

    /// Default reference viewpoint: about the 26th floor of 430 Main St, Roosevelt Island.
    /// Only a fallback for when there is no GPS fix; nothing downstream depends on it.
    public static let rooseveltIslandReference = Viewpoint(
        latitude: 40.7625, longitude: -73.9495,
        groundElevation: 5, heightAboveGround: heightAboveGround(floor: 26)
    )

    public func lookAngle(to landmark: Landmark) -> LookAngle {
        Geodesy.lookAngle(from: coordinate, to: landmark.top)
    }
}

/// The pure-rotation model needs height and distance. Warn outside the envelope.
public enum OperatingEnvelope {
    public static let minimumHeight = 15.0

    public enum Status: Equatable, Sendable {
        case ok
        case tooLow(height: Double)
    }

    public static func evaluate(_ viewpoint: Viewpoint) -> Status {
        viewpoint.heightAboveGround < minimumHeight ? .tooLow(height: viewpoint.heightAboveGround) : .ok
    }
}
