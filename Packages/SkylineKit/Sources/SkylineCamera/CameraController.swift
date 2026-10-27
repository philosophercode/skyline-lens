#if os(iOS)
import AVFoundation
import Foundation
import Observation
import SkylineCore

/// Owns the rear-camera capture session and reports the lens geometry the overlay needs.
@Observable
public final class CameraController {
    public enum State: Equatable {
        case idle, running, denied, unavailable(String)
    }

    public private(set) var state: State = .idle
    /// Horizontal FOV of the active format across the sensor's long side, degrees.
    public private(set) var fieldOfView: Double = 0
    /// Active format dimensions, long side first.
    public private(set) var formatSize = Size2(width: 1920, height: 1080)
    public private(set) var zoomFactor: Double = 1
    public private(set) var deviceName = ""

    public let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "SkylineLens.camera")
    private var device: AVCaptureDevice?
    @ObservationIgnored private var zoomObservation: NSKeyValueObservation?
    private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var photoDelegates: [Int64: PhotoDelegate] = [:]

    public init() {}

    public func start() {
        guard state != .running else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.configureAndRun() } else { self.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    public func stop() {
        sessionQueue.async { self.session.stopRunning() }
        state = .idle
    }

    /// Sets zoom, clamped to what the device supports. Smooth ramps come in Milestone 5.
    public func setZoom(_ factor: Double) {
        guard let device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10)
                device.videoZoomFactor = CGFloat(min(max(factor, device.minAvailableVideoZoomFactor), maxZoom))
                device.unlockForConfiguration()
            } catch {}
        }
    }

    private func configureAndRun() {
        sessionQueue.async {
            // The wide camera has the best low-light performance and a well-characterised FOV.
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async { self.state = .unavailable("No rear wide-angle camera.") }
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) { self.session.addInput(input) }
                if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            } catch {
                self.session.commitConfiguration()
                DispatchQueue.main.async { self.state = .unavailable(error.localizedDescription) }
                return
            }
            self.session.commitConfiguration()
            self.session.startRunning()

            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let fov = Double(device.activeFormat.videoFieldOfView)
            let size = Size2(width: Double(max(dims.width, dims.height)), height: Double(min(dims.width, dims.height)))
            let name = device.localizedName

            let observation = device.observe(\.videoZoomFactor, options: [.initial, .new]) { d, _ in
                let z = Double(d.videoZoomFactor)
                DispatchQueue.main.async { self.zoomFactor = z }
            }
            DispatchQueue.main.async {
                self.device = device
                self.zoomObservation = observation
                self.fieldOfView = fov
                self.formatSize = size
                self.deviceName = name
                self.state = .running
            }
        }
    }

    /// Captures a still (JPEG) for Milestone 0 field data. `rotationAngle` should match the
    /// preview so the saved image is upright. `onExposure` fires as the exposure starts, so
    /// callers can snapshot the pose then rather than at tap time. `completion` gets the JPEG,
    /// its pixel size and the exposure's host-clock time in seconds (the clock Core Motion
    /// timestamps use). Both call back on the main queue.
    public func capturePhoto(
        rotationAngle: CGFloat?,
        onExposure: @escaping () -> Void,
        completion: @escaping (Data?, Size2?, Double?) -> Void
    ) {
        sessionQueue.async {
            guard self.session.isRunning else {
                DispatchQueue.main.async { completion(nil, nil, nil) }
                return
            }
            if let angle = rotationAngle, let connection = self.photoOutput.connection(with: .video),
               connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            let id = settings.uniqueID
            let delegate = PhotoDelegate(
                exposing: { DispatchQueue.main.async(execute: onExposure) },
                done: { [weak self] data, size, time in
                    self?.sessionQueue.async { self?.photoDelegates[id] = nil }
                    DispatchQueue.main.async { completion(data, size, time) }
                }
            )
            self.photoDelegates[id] = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    /// Device handle for the preview's rotation coordinator.
    public var captureDevice: AVCaptureDevice? { device }
}

private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let exposing: () -> Void
    let done: (Data?, Size2?, Double?) -> Void

    init(exposing: @escaping () -> Void, done: @escaping (Data?, Size2?, Double?) -> Void) {
        self.exposing = exposing
        self.done = done
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        exposing()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let dims = photo.resolvedSettings.photoDimensions
        let time = photo.timestamp.isValid ? photo.timestamp.seconds : nil
        done(photo.fileDataRepresentation(), Size2(width: Double(dims.width), height: Double(dims.height)), time)
    }
}
#endif
