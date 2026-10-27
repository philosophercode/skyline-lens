import Foundation

/// A WGS84 position. `altitude` is metres above the ellipsoid; in NYC the geoid
/// sits about 32 m below the ellipsoid, so treat it as "height in the model's
/// datum" and keep observer and targets in the same datum.
public struct GeodeticCoordinate: Equatable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double

    public init(latitude: Double, longitude: Double, altitude: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }
}

/// Bearing / elevation / range from an observer to a target.
public struct LookAngle: Equatable, Sendable {
    /// Degrees clockwise from true north, in [0, 360).
    public var bearing: Double
    /// Degrees above the observer's local horizontal plane (apparent, i.e. after refraction).
    public var elevation: Double
    /// Straight-line distance in metres.
    public var distance: Double

    public init(bearing: Double, elevation: Double, distance: Double) {
        self.bearing = bearing
        self.elevation = elevation
        self.distance = distance
    }
}

public enum WGS84 {
    public static let a = 6_378_137.0
    public static let f = 1 / 298.257_223_563
    public static let e2 = f * (2 - f)
    /// Mean Earth radius, for curvature and refraction corrections.
    public static let meanRadius = 6_371_008.8
}

public enum Geodesy {
    /// Standard terrestrial refraction coefficient (ratio of Earth radius to ray radius).
    public static let defaultRefraction = 0.13

    public static func ecef(_ p: GeodeticCoordinate) -> Vec3 {
        let lat = radians(p.latitude), lon = radians(p.longitude)
        let sinLat = sin(lat)
        let n = WGS84.a / (1 - WGS84.e2 * sinLat * sinLat).squareRoot()
        return Vec3(
            (n + p.altitude) * cos(lat) * cos(lon),
            (n + p.altitude) * cos(lat) * sin(lon),
            (n * (1 - WGS84.e2) + p.altitude) * sinLat
        )
    }

    /// East-North-Up offset of `target` relative to `observer`, in metres.
    /// Earth curvature is included automatically (the target's "up" drops away).
    public static func enu(of target: GeodeticCoordinate, from observer: GeodeticCoordinate) -> Vec3 {
        let d = ecef(target) - ecef(observer)
        let lat = radians(observer.latitude), lon = radians(observer.longitude)
        let east = Vec3(-sin(lon), cos(lon), 0)
        let north = Vec3(-sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat))
        let up = Vec3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
        return Vec3(d.dot(east), d.dot(north), d.dot(up))
    }

    /// Inverse of `enu`: the coordinate at an ENU offset from `origin`.
    public static func coordinate(atENU offset: Vec3, from origin: GeodeticCoordinate) -> GeodeticCoordinate {
        let lat = radians(origin.latitude), lon = radians(origin.longitude)
        let east = Vec3(-sin(lon), cos(lon), 0)
        let north = Vec3(-sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat))
        let up = Vec3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
        let p = ecef(origin) + east * offset.x + north * offset.y + up * offset.z
        return geodetic(fromECEF: p)
    }

    /// ECEF to geodetic (Bowring's iteration; converges to sub-millimetre in a few steps).
    public static func geodetic(fromECEF p: Vec3) -> GeodeticCoordinate {
        let lon = atan2(p.y, p.x)
        let r = (p.x * p.x + p.y * p.y).squareRoot()
        var lat = atan2(p.z, r * (1 - WGS84.e2))
        var alt = 0.0
        for _ in 0..<6 {
            let sinLat = sin(lat)
            let n = WGS84.a / (1 - WGS84.e2 * sinLat * sinLat).squareRoot()
            alt = r / cos(lat) - n
            lat = atan2(p.z, r * (1 - WGS84.e2 * n / (n + alt)))
        }
        return GeodeticCoordinate(latitude: degrees(lat), longitude: degrees(lon), altitude: alt)
    }

    /// Bearing, apparent elevation and range from `observer` to `target`.
    /// `refraction` lifts distant targets slightly (k ≈ 0.13 near the ground);
    /// pass 0 for the purely geometric angle.
    public static func lookAngle(
        from observer: GeodeticCoordinate,
        to target: GeodeticCoordinate,
        refraction: Double = defaultRefraction
    ) -> LookAngle {
        let v = enu(of: target, from: observer)
        let horizontal = (v.x * v.x + v.y * v.y).squareRoot()
        let distance = v.length
        let geometric = degrees(atan2(v.z, horizontal))
        // Refraction bends the ray along an arc of radius R/k; the apparent lift
        // seen from the observer is half the subtended angle, k * d / (2R).
        let lift = degrees(refraction * horizontal / (2 * WGS84.meanRadius))
        return LookAngle(
            bearing: wrap360(degrees(atan2(v.x, v.y))),
            elevation: geometric + lift,
            distance: distance
        )
    }

    /// Dip of the sea-level horizon below horizontal for an eye `height` metres up, in degrees.
    public static func horizonDip(height: Double, refraction: Double = defaultRefraction) -> Double {
        guard height > 0 else { return 0 }
        return degrees((2 * height * (1 - refraction) / WGS84.meanRadius).squareRoot())
    }
}
