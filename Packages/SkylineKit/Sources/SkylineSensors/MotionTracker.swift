#if os(iOS)
import CoreMotion
import Foundation
import Observation
import SkylineCore

/// One Core Motion sample, already converted into SkylineCore types.
public struct MotionSample: Sendable {
    public var attitude: Attitude
    /// Measured gravity in the device frame (units of g).
    public var gravity: Vec3
    /// Core Motion's heading of the device's +y axis (not the camera), degrees, or nil.
    public var reportedHeading: Double?
    public var referenceFrame: String
    public var magneticAccuracy: String
    public var timestamp: TimeInterval
}

/// Streams device attitude in the true-north, z-up reference frame.
///
/// Falls back to magnetic north when true north is unavailable (no location yet);
/// in NYC magnetic declination is about 13° W, which the yaw correction absorbs.
@Observable
public final class MotionTracker {
    public private(set) var latest: MotionSample?
    public private(set) var convention: AttitudeConvention = .deviceFromReference
    public private(set) var conventionVerified = false
    public private(set) var isRunning = false
    public private(set) var errorMessage: String?

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "SkylineLens.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    /// Convention as seen by the motion queue; only touched on `queue`.
    @ObservationIgnored private var queueConvention: AttitudeConvention = .deviceFromReference

    public init() {}

    public func start(updateHz: Double = 60) {
        guard !isRunning else { return }
        guard manager.isDeviceMotionAvailable else {
            errorMessage = "Device motion is not available on this device."
            return
        }
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame =
            available.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        manager.deviceMotionUpdateInterval = 1 / updateHz
        manager.showsDeviceMovementDisplay = true
        isRunning = true
        manager.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] motion, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                return
            }
            guard let motion else { return }
            let sample = self.makeSample(motion, frame: frame)
            DispatchQueue.main.async { self.latest = sample }
        }
    }

    public func stop() {
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    // Runs on the motion queue.
    private func makeSample(_ motion: CMDeviceMotion, frame: CMAttitudeReferenceFrame) -> MotionSample {
        let r = motion.attitude.rotationMatrix
        let raw = Mat3(
            rows: Vec3(r.m11, r.m12, r.m13),
            Vec3(r.m21, r.m22, r.m23),
            Vec3(r.m31, r.m32, r.m33)
        )
        let g = Vec3(motion.gravity.x, motion.gravity.y, motion.gravity.z)

        // Re-check the matrix convention whenever the device is far from flat (an
        // upright iPad on a window always is). See AttitudeConvention.
        if let detected = AttitudeConvention.detect(matrix: raw, gravity: g) {
            queueConvention = detected
            DispatchQueue.main.async {
                self.convention = detected
                self.conventionVerified = true
            }
        }

        return MotionSample(
            attitude: queueConvention.attitude(from: raw),
            gravity: g,
            reportedHeading: motion.heading >= 0 ? motion.heading : nil,
            referenceFrame: frame == .xTrueNorthZVertical ? "true north" : "magnetic north",
            magneticAccuracy: Self.describe(motion.magneticField.accuracy),
            timestamp: motion.timestamp
        )
    }

    private static func describe(_ a: CMMagneticFieldCalibrationAccuracy) -> String {
        switch a {
        case .uncalibrated: return "uncalibrated"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        @unknown default: return "unknown"
        }
    }
}
#endif
