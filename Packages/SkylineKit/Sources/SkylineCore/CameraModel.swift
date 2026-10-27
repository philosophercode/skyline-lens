import Foundation

/// Pinhole intrinsics in *screen points* for the preview as it is displayed.
public struct CameraIntrinsics: Equatable, Sendable {
    public var focalX: Double
    public var focalY: Double
    public var center: Point2
    public var viewSize: Size2

    public init(focalX: Double, focalY: Double, center: Point2, viewSize: Size2) {
        self.focalX = focalX
        self.focalY = focalY
        self.center = center
        self.viewSize = viewSize
    }

    /// Intrinsics for an aspect-fill preview.
    ///
    /// - Parameters:
    ///   - horizontalFOV: the capture format's field of view across the sensor's
    ///     long side, in degrees (`AVCaptureDevice.Format.videoFieldOfView`).
    ///   - sensorSize: the capture format's pixel dimensions, long side first.
    ///   - viewSize: the preview view's size in points.
    ///   - orientation: interface orientation; in portrait the long side runs vertically.
    ///   - zoomFactor: digital/optical zoom relative to the format's native FOV.
    public static func aspectFill(
        horizontalFOV: Double,
        sensorSize: Size2,
        viewSize: Size2,
        orientation: InterfaceOrientation,
        zoomFactor: Double = 1
    ) -> CameraIntrinsics {
        let long = max(sensorSize.width, sensorSize.height)
        let short = min(sensorSize.width, sensorSize.height)
        let focalPixels = (long / 2) / tan(radians(horizontalFOV) / 2)
        // Image size as laid out on screen (before scaling).
        let imageW = orientation.isPortrait ? short : long
        let imageH = orientation.isPortrait ? long : short
        let scale = max(viewSize.width / imageW, viewSize.height / imageH)
        let f = focalPixels * scale * zoomFactor
        return CameraIntrinsics(
            focalX: f,
            focalY: f,
            center: Point2(x: viewSize.width / 2, y: viewSize.height / 2),
            viewSize: viewSize
        )
    }

    /// Horizontal field of view actually visible on screen, in degrees.
    public var visibleHorizontalFOV: Double { degrees(2 * atan(viewSize.width / 2 / focalX)) }
    public var visibleVerticalFOV: Double { degrees(2 * atan(viewSize.height / 2 / focalY)) }
}

/// Small corrections on top of the raw sensor attitude. Milestone 3's skyline
/// registration solves these; until then they are zero (or set from the debug HUD).
public struct PoseCorrection: Equatable, Codable, Sendable {
    /// Degrees to add to the sensor heading (positive = the true view is clockwise of
    /// what the magnetometer reports). Indoors this is typically within ±20°.
    public var yaw: Double
    /// Degrees to tilt the view up, applied in the camera frame.
    public var pitch: Double
    /// Degrees to roll the view clockwise, applied in the camera frame.
    public var roll: Double
    /// Multiplier on the focal length (lens model error, zoom mismatch).
    public var focalScale: Double

    public init(yaw: Double = 0, pitch: Double = 0, roll: Double = 0, focalScale: Double = 1) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
        self.focalScale = focalScale
    }

    public static let zero = PoseCorrection()
}

/// Projects reference-frame directions to screen points and back.
public struct Projector: Sendable {
    public let attitude: Attitude
    public let intrinsics: CameraIntrinsics
    public let orientation: InterfaceOrientation
    public let correction: PoseCorrection

    /// Rows are camera right, camera up, camera forward, in the reference frame
    /// after the yaw correction. `cameraFromReference * w` gives camera coords.
    private let cameraFromReference: Mat3

    public init(
        attitude: Attitude,
        intrinsics: CameraIntrinsics,
        orientation: InterfaceOrientation,
        correction: PoseCorrection = .zero
    ) {
        self.attitude = attitude
        self.intrinsics = intrinsics
        self.orientation = orientation
        self.correction = correction

        let axes = orientation.screenAxes
        let deviceToCamera = Mat3(rows: axes.right, axes.up, Vec3(0, 0, -1))
        // Camera coords are (right, up, forward), a left-handed basis, so these signs were
        // checked component-wise: positive pitch tilts the view up (scene points move down),
        // positive roll rolls the view clockwise (scene appears to rotate counter-clockwise).
        let residual = Mat3.rotationX(radians(correction.pitch)) * Mat3.rotationZ(radians(correction.roll))
        // Yaw about world up. A positive yaw means the true view is clockwise of the
        // sensor's; rotating world directions counter-clockwise by the same amount
        // (positive about +z, which points up) compensates.
        let yaw = Mat3.rotationZ(radians(correction.yaw))
        cameraFromReference = residual * deviceToCamera * attitude.deviceFromReference * yaw
    }

    private var focalX: Double { intrinsics.focalX * correction.focalScale }
    private var focalY: Double { intrinsics.focalY * correction.focalScale }

    /// Screen point for a reference-frame direction, or nil if it is behind the camera.
    public func project(_ direction: Vec3) -> Point2? {
        let c = cameraFromReference * direction
        guard c.z > 1e-6 else { return nil }
        return Point2(
            x: intrinsics.center.x + focalX * c.x / c.z,
            y: intrinsics.center.y - focalY * c.y / c.z
        )
    }

    public func project(bearing: Double, elevation: Double) -> Point2? {
        project(ReferenceFrame.direction(bearing: bearing, elevation: elevation))
    }

    /// Reference-frame unit direction through a screen point.
    public func unproject(_ point: Point2) -> Vec3 {
        let c = Vec3(
            (point.x - intrinsics.center.x) / focalX,
            -(point.y - intrinsics.center.y) / focalY,
            1
        )
        return (cameraFromReference.transposed * c).normalized
    }

    public func lookAngle(at point: Point2) -> (bearing: Double, elevation: Double) {
        ReferenceFrame.angles(of: unproject(point))
    }

    /// Bearing / elevation of the screen centre.
    public var centerAngles: (bearing: Double, elevation: Double) { lookAngle(at: intrinsics.center) }

    /// Camera roll in degrees: how far the true horizon is rotated clockwise on screen.
    public var horizonRoll: Double {
        // World up expressed in camera coords; when level it points straight up the screen.
        let up = cameraFromReference * Vec3(0, 0, 1)
        return degrees(atan2(up.x, up.y))
    }

    public func isOnScreen(_ p: Point2, margin: Double = 0) -> Bool {
        p.x >= -margin && p.y >= -margin
            && p.x <= intrinsics.viewSize.width + margin
            && p.y <= intrinsics.viewSize.height + margin
    }
}
