#if os(iOS)
import Foundation
import Observation
import SkylineCamera
import SkylineCore
import SkylineSensors

/// Glue between sensors, camera and overlay for the live view.
@Observable
public final class LiveViewModel {
    public let camera = CameraController()
    public let motion = MotionTracker()
    public let location = LocationProvider()

    public var orientation: ScreenOrientation = .landscapeRight
    public var showHUD = true
    public var showLandmarks = true

    /// Floor the iPad is on; drives height above ground until the resection solve exists.
    public var floor: Int {
        didSet { UserDefaults.standard.set(floor, forKey: Keys.floor) }
    }

    /// Debug-only manual heading bias. Milestone 3's skyline registration replaces this
    /// with a solved correction; it exists so Milestone 1 can be checked by eye.
    public var debugYawBias: Double {
        didSet { UserDefaults.standard.set(debugYawBias, forKey: Keys.yawBias) }
    }

    /// Free-text label written into capture sidecars, e.g. "Roosevelt Island 26F".
    public var siteLabel: String {
        didSet { UserDefaults.standard.set(siteLabel, forKey: Keys.siteLabel) }
    }

    public private(set) var lastCaptureMessage: String?
    public private(set) var captureCount = 0

    private enum Keys {
        static let floor = "skyline.floor"
        static let yawBias = "skyline.debugYawBias"
        static let siteLabel = "skyline.siteLabel"
    }

    public init() {
        let stored = UserDefaults.standard.integer(forKey: Keys.floor)
        floor = stored > 0 ? stored : 26
        debugYawBias = UserDefaults.standard.double(forKey: Keys.yawBias)
        siteLabel = UserDefaults.standard.string(forKey: Keys.siteLabel) ?? ""
    }

    public func start() {
        camera.start()
        motion.start()
        location.start()
    }

    public func stop() {
        camera.stop()
        motion.stop()
        location.stop()
    }

    public var heightAboveGround: Double { Viewpoint.heightAboveGround(floor: floor) }

    /// GPS viewpoint, or the reference viewpoint when there is no fix yet.
    public var viewpoint: Viewpoint {
        location.viewpoint(heightAboveGround: heightAboveGround)
            ?? Viewpoint(
                latitude: Viewpoint.rooseveltIslandReference.latitude,
                longitude: Viewpoint.rooseveltIslandReference.longitude,
                groundElevation: Viewpoint.rooseveltIslandReference.groundElevation,
                heightAboveGround: heightAboveGround
            )
    }

    public var usingFallbackPosition: Bool { location.location == nil }

    public var correction: PoseCorrection { PoseCorrection(yaw: debugYawBias) }

    public func projector(viewSize: Size2) -> Projector? {
        guard let sample = motion.latest, camera.fieldOfView > 0, viewSize.width > 0 else { return nil }
        let k = CameraIntrinsics.aspectFill(
            horizontalFOV: camera.fieldOfView,
            sensorSize: camera.formatSize,
            viewSize: viewSize,
            orientation: orientation,
            zoomFactor: camera.zoomFactor
        )
        return Projector(attitude: sample.attitude, intrinsics: k, orientation: orientation, correction: correction)
    }

    public struct LandmarkMarker: Identifiable {
        public var id: String { landmark.id }
        public var landmark: Landmark
        public var look: LookAngle
        public var point: Point2
    }

    public func landmarkMarkers(projector: Projector) -> [LandmarkMarker] {
        let vp = viewpoint
        return LandmarkCatalog.starter.compactMap { lm in
            let look = vp.lookAngle(to: lm)
            guard look.distance > 300,
                  let p = projector.project(bearing: look.bearing, elevation: look.elevation),
                  projector.isOnScreen(p, margin: 20)
            else { return nil }
            return LandmarkMarker(landmark: lm, look: look, point: p)
        }
    }

    // MARK: Milestone 0 field capture

    /// Folder (visible in the Files app) where captures land.
    public static var capturesDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
    }

    /// Pose state frozen for one capture.
    private struct PoseSnapshot {
        var sample: MotionSample?
        var convention: AttitudeConvention
        var projector: Projector?
        var capturedAt: Date
    }

    private final class SnapshotBox { var value: PoseSnapshot? }

    private func poseSnapshot(viewSize: Size2) -> PoseSnapshot {
        PoseSnapshot(sample: motion.latest, convention: motion.convention,
                     projector: projector(viewSize: viewSize), capturedAt: Date())
    }

    /// Saves a JPEG plus a JSON sidecar with everything the app knows about pose and lens.
    /// The pose is snapshotted when the exposure starts, not at tap time, and both clocks
    /// are recorded so the offline solver can measure any remaining lag.
    public func capture(viewSize: Size2) {
        let tapSnapshot = poseSnapshot(viewSize: viewSize)
        let exposureSnapshot = SnapshotBox()
        let loc = location.location
        let rotation: CGFloat = switch self.orientation {
        case .landscapeRight: 0
        case .portrait: 90
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        }
        let orientation = self.orientation
        let site = siteLabel
        let floor = self.floor
        let height = heightAboveGround
        let correction = self.correction
        let relAlt = location.relativeAltitude
        let lensName = camera.deviceName, fov = camera.fieldOfView, format = camera.formatSize, zoom = camera.zoomFactor

        camera.capturePhoto(
            rotationAngle: rotation,
            onExposure: { [weak self] in exposureSnapshot.value = self?.poseSnapshot(viewSize: viewSize) },
            completion: { [weak self] data, size, exposureTime in
                guard let self else { return }
                guard let data else {
                    self.lastCaptureMessage = "Capture failed"
                    return
                }
                let snap = exposureSnapshot.value ?? tapSnapshot
                let motionMeta = snap.sample.map { s in
                    CaptureMetadata.Motion(
                        deviceFromReference: s.attitude.deviceFromReference.rowArrays,
                        gravity: [s.gravity.x, s.gravity.y, s.gravity.z],
                        referenceFrame: s.referenceFrame,
                        magneticAccuracy: s.magneticAccuracy,
                        reportedHeading: s.reportedHeading,
                        convention: snap.convention.rawValue,
                        sampleTimestamp: s.timestamp,
                        cameraBearing: snap.projector?.centerAngles.bearing,
                        cameraElevation: snap.projector?.centerAngles.elevation,
                        horizonRoll: snap.projector?.horizonRoll
                    )
                }
                var meta = CaptureMetadata(
                    capturedAt: snap.capturedAt,
                    interfaceOrientation: orientation.rawValue,
                    siteLabel: site,
                    lens: .init(deviceName: lensName, horizontalFOV: fov,
                                formatWidth: Int(format.width), formatHeight: Int(format.height), zoomFactor: zoom,
                                photoWidth: Int(size?.width ?? 0), photoHeight: Int(size?.height ?? 0)),
                    motion: motionMeta,
                    location: .init(latitude: loc?.coordinate.latitude, longitude: loc?.coordinate.longitude,
                                    horizontalAccuracy: loc?.horizontalAccuracy, altitude: loc?.altitude,
                                    verticalAccuracy: loc?.verticalAccuracy, relativeBarometricAltitude: relAlt,
                                    floor: floor, heightAboveGround: height),
                    correction: correction
                )
                meta.exposureTimestamp = exposureTime
                do {
                    let dir = Self.capturesDirectory
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try data.write(to: dir.appendingPathComponent(meta.fileStem + ".jpg"))
                    try meta.jsonData().write(to: dir.appendingPathComponent(meta.fileStem + ".json"))
                    self.captureCount += 1
                    self.lastCaptureMessage = "Saved \(meta.fileStem)"
                } catch {
                    self.lastCaptureMessage = "Save failed: \(error.localizedDescription)"
                }
            }
        )
    }
}
#endif
