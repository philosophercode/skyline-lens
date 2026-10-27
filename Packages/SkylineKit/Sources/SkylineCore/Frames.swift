import Foundation

/// The world reference frame used everywhere in Skyline Lens.
///
/// It matches Core Motion's `.xTrueNorthZVertical`: +x points to true north,
/// +z points up (against gravity), so +y points west. Keeping our maths in the
/// same frame as Core Motion means the attitude matrix can be used directly.
public enum ReferenceFrame {
    /// Unit direction for a compass bearing (degrees clockwise from north) and
    /// elevation (degrees above horizontal).
    public static func direction(bearing: Double, elevation: Double) -> Vec3 {
        let b = radians(bearing), e = radians(elevation)
        let north = cos(e) * cos(b)
        let east = cos(e) * sin(b)
        return Vec3(north, -east, sin(e))
    }

    /// Inverse of `direction(bearing:elevation:)`.
    public static func angles(of direction: Vec3) -> (bearing: Double, elevation: Double) {
        let d = direction.normalized
        let north = d.x, east = -d.y
        let horizontal = (north * north + east * east).squareRoot()
        return (wrap360(degrees(atan2(east, north))), degrees(atan2(d.z, horizontal)))
    }

    /// Converts an ENU offset (east, north, up) into this frame (north, west, up).
    public static func fromENU(_ v: Vec3) -> Vec3 { Vec3(v.y, -v.x, v.z) }
}

/// The device's attitude as a rotation from the reference frame into the device frame:
/// `deviceVector = deviceFromReference * referenceVector`.
///
/// Device frame (Apple convention, independent of UI rotation): +x towards the
/// right edge in portrait, +y towards the top edge in portrait, +z out of the
/// screen towards the viewer. The rear camera therefore looks along -z.
public struct Attitude: Equatable, Sendable {
    public var deviceFromReference: Mat3

    public init(deviceFromReference: Mat3) {
        self.deviceFromReference = deviceFromReference
    }

    /// Builds an attitude from the device axes expressed in the reference frame
    /// (these are the rows of `deviceFromReference`).
    public init(deviceX: Vec3, deviceY: Vec3, deviceZ: Vec3) {
        deviceFromReference = Mat3(rows: deviceX.normalized, deviceY.normalized, deviceZ.normalized)
    }

    /// Gravity as the accelerometer would see it in the device frame (units of g).
    public var expectedGravity: Vec3 { deviceFromReference * Vec3(0, 0, -1) }

    /// Rear-camera optical axis in the reference frame.
    public var cameraForward: Vec3 { deviceFromReference.transposed * Vec3(0, 0, -1) }
}

/// Core Motion documents its rotation matrix loosely, and its transpose is an easy
/// mistake to make. Instead of trusting one reading of the docs, we check against
/// the measured gravity vector at runtime and pick whichever reading agrees.
public enum AttitudeConvention: String, Sendable {
    /// The raw matrix maps reference vectors into the device frame (expected).
    case deviceFromReference
    /// The raw matrix maps device vectors into the reference frame; transpose it.
    case referenceFromDevice

    /// Picks the convention under which `matrix` predicts `gravity` (device frame, in g).
    /// Returns nil when the device is close to flat and the two readings can't be told apart.
    public static func detect(matrix: Mat3, gravity: Vec3) -> AttitudeConvention? {
        let g = gravity.normalized
        let asIs = (matrix * Vec3(0, 0, -1)).dot(g)
        let flipped = (matrix.transposed * Vec3(0, 0, -1)).dot(g)
        guard abs(asIs - flipped) > 0.2 else { return nil }
        return asIs > flipped ? .deviceFromReference : .referenceFromDevice
    }

    public func attitude(from matrix: Mat3) -> Attitude {
        switch self {
        case .deviceFromReference: return Attitude(deviceFromReference: matrix)
        case .referenceFromDevice: return Attitude(deviceFromReference: matrix.transposed)
        }
    }
}

/// UI orientation of the interface, mirroring `UIInterfaceOrientation` without UIKit.
public enum InterfaceOrientation: String, CaseIterable, Sendable {
    case portrait
    case portraitUpsideDown
    /// `UIInterfaceOrientation.landscapeLeft`: the device's top edge points right.
    case landscapeLeft
    /// `UIInterfaceOrientation.landscapeRight`: the device's top edge points left.
    case landscapeRight

    public var isPortrait: Bool { self == .portrait || self == .portraitUpsideDown }

    /// Screen "right" and "up" directions in the device frame.
    public var screenAxes: (right: Vec3, up: Vec3) {
        switch self {
        case .portrait: return (Vec3(1, 0, 0), Vec3(0, 1, 0))
        case .portraitUpsideDown: return (Vec3(-1, 0, 0), Vec3(0, -1, 0))
        case .landscapeLeft: return (Vec3(0, 1, 0), Vec3(-1, 0, 0))
        case .landscapeRight: return (Vec3(0, -1, 0), Vec3(1, 0, 0))
        }
    }
}
