#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// Full-bleed, aspect-fill camera preview that stays upright as the interface rotates.
public struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    public init(session: AVCaptureSession, device: AVCaptureDevice?) {
        self.session = session
        self.device = device
    }

    public func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ view: PreviewView, context: Context) {
        view.attach(device: device)
    }

    public final class PreviewView: UIView {
        public override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        func attach(device: AVCaptureDevice?) {
            guard let device, coordinator?.device != device else { return }
            let c = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            coordinator = c
            observation = c.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] c, _ in
                let angle = c.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    guard let connection = self?.previewLayer.connection,
                          connection.isVideoRotationAngleSupported(angle) else { return }
                    connection.videoRotationAngle = angle
                }
            }
        }
    }
}
#endif
