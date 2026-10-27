import Foundation

/// Sidecar written next to every field capture. Milestone 0's offline solver reads
/// these, so field: everything the app believed about pose and lens at that instant.
public struct CaptureMetadata: Codable, Equatable, Sendable {
    public struct Lens: Codable, Equatable, Sendable {
        public var deviceName: String
        /// Native horizontal FOV of the capture format, degrees.
        public var horizontalFOV: Double
        public var formatWidth: Int
        public var formatHeight: Int
        public var zoomFactor: Double
        public var photoWidth: Int
        public var photoHeight: Int

        public init(deviceName: String, horizontalFOV: Double, formatWidth: Int, formatHeight: Int,
                    zoomFactor: Double, photoWidth: Int, photoHeight: Int) {
            self.deviceName = deviceName
            self.horizontalFOV = horizontalFOV
            self.formatWidth = formatWidth
            self.formatHeight = formatHeight
            self.zoomFactor = zoomFactor
            self.photoWidth = photoWidth
            self.photoHeight = photoHeight
        }
    }

    public struct Motion: Codable, Equatable, Sendable {
        /// Rows of `Attitude.deviceFromReference` (reference frame: x north, y west, z up).
        public var deviceFromReference: [[Double]]
        public var gravity: [Double]
        public var referenceFrame: String
        public var magneticAccuracy: String
        public var reportedHeading: Double?
        public var convention: String
        /// Core Motion timestamp of this sample (seconds of system uptime).
        public var sampleTimestamp: Double?
        /// Camera centre bearing / elevation / roll as the app computed them.
        public var cameraBearing: Double?
        public var cameraElevation: Double?
        public var horizonRoll: Double?

        public init(deviceFromReference: [[Double]], gravity: [Double], referenceFrame: String,
                    magneticAccuracy: String, reportedHeading: Double?, convention: String, sampleTimestamp: Double? = nil,
                    cameraBearing: Double?, cameraElevation: Double?, horizonRoll: Double?) {
            self.deviceFromReference = deviceFromReference
            self.gravity = gravity
            self.referenceFrame = referenceFrame
            self.magneticAccuracy = magneticAccuracy
            self.reportedHeading = reportedHeading
            self.convention = convention
            self.sampleTimestamp = sampleTimestamp
            self.cameraBearing = cameraBearing
            self.cameraElevation = cameraElevation
            self.horizonRoll = horizonRoll
        }
    }

    public struct Location: Codable, Equatable, Sendable {
        public var latitude: Double?
        public var longitude: Double?
        public var horizontalAccuracy: Double?
        public var altitude: Double?
        public var verticalAccuracy: Double?
        public var relativeBarometricAltitude: Double?
        public var floor: Int
        public var heightAboveGround: Double

        public init(latitude: Double?, longitude: Double?, horizontalAccuracy: Double?, altitude: Double?,
                    verticalAccuracy: Double?, relativeBarometricAltitude: Double?, floor: Int, heightAboveGround: Double) {
            self.latitude = latitude
            self.longitude = longitude
            self.horizontalAccuracy = horizontalAccuracy
            self.altitude = altitude
            self.verticalAccuracy = verticalAccuracy
            self.relativeBarometricAltitude = relativeBarometricAltitude
            self.floor = floor
            self.heightAboveGround = heightAboveGround
        }
    }

    public var schemaVersion = 1
    public var capturedAt: Date
    /// Exposure time on the same clock as `Motion.sampleTimestamp`; their difference is
    /// how stale the recorded pose is.
    public var exposureTimestamp: Double?
    public var interfaceOrientation: String
    public var siteLabel: String
    public var lens: Lens
    public var motion: Motion?
    public var location: Location
    public var correction: PoseCorrection

    public init(capturedAt: Date, interfaceOrientation: String, siteLabel: String, lens: Lens,
                motion: Motion?, location: Location, correction: PoseCorrection) {
        self.capturedAt = capturedAt
        self.interfaceOrientation = interfaceOrientation
        self.siteLabel = siteLabel
        self.lens = lens
        self.motion = motion
        self.location = location
        self.correction = correction
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// File stem like `2026-10-27T05-49-01Z_roosevelt-island` (safe on every filesystem).
    public var fileStem: String {
        let f = ISO8601DateFormatter()
        // Millisecond precision so rapid captures never share a filename.
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = f.string(from: capturedAt).replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: ".", with: "-")
        let slug = siteLabel.lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { s, c in if !(c == "-" && s.last == "-") { s.append(c) } }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? stamp : "\(stamp)_\(slug)"
    }
}

public extension Mat3 {
    var rowArrays: [[Double]] {
        [rows.0, rows.1, rows.2].map { [$0.x, $0.y, $0.z] }
    }
}
