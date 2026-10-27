#if os(iOS)
import SkylineCamera
import SkylineCore
import SwiftUI
import UIKit

/// Milestone 1 screen: full-screen rear camera with a compass overlay and debug HUD.
public struct LiveView: View {
    @State private var model = LiveViewModel()
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if model.demoMode {
                    DemoBackdrop().ignoresSafeArea()
                } else {
                    CameraPreview(session: model.camera.session, device: model.camera.captureDevice)
                        .ignoresSafeArea()
                }
                CompassOverlay(model: model)
                    .ignoresSafeArea()
                if model.showHUD {
                    DebugHUD(model: model, viewSize: Size2(width: geo.size.width, height: geo.size.height))
                        .padding(12)
                }
                statusBanner
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .topTrailing) {
                Button { showSettings = true } label: { roundIcon("slider.horizontal.3") }
                    .padding(12)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 6) {
                    Button { model.capture(viewSize: Size2(width: geo.size.width, height: geo.size.height)) } label: {
                        roundIcon("camera.circle")
                    }
                    if model.captureCount > 0 {
                        Text("\(model.captureCount)").font(.caption.bold()).foregroundStyle(.white)
                    }
                }
                .padding(12)
            }
            .background(InterfaceOrientationReader { model.orientation = $0 })
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .onAppear { model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.start()
            case .background: model.stop()
            default: break
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if model.demoMode {
            banner("Demo pose: synthetic view from Roosevelt Island, no camera", color: .blue)
        } else {
            cameraBanner
        }
    }

    @ViewBuilder private var cameraBanner: some View {
        switch model.camera.state {
        case .denied:
            banner("Camera access is off. Enable it in Settings › Skyline Lens.")
        case .unavailable(let reason):
            banner(reason)
        default:
            if let error = model.motion.errorMessage { banner(error) }
        }
    }

    private func roundIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title2)
            .padding(12)
            .background(.black.opacity(0.5), in: Circle())
            .foregroundStyle(.white)
    }

    private func banner(_ text: String, color: Color = .red) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color.opacity(0.75), in: Capsule())
    }
}

struct SettingsSheet: View {
    @Bindable var model: LiveViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Viewpoint") {
                    Stepper("Floor \(model.floor)  (≈\(Int(model.heightAboveGround)) m up)", value: $model.floor, in: 1...120)
                }
                Section {
                    TextField("Site label, e.g. Roosevelt Island 26F", text: $model.siteLabel)
                    if let msg = model.lastCaptureMessage { Text(msg).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Field capture (Milestone 0)")
                } footer: {
                    Text("The camera button saves a photo plus a JSON file of pose, lens and GPS. Find them in Files › On My iPad › Skyline Lens › captures.")
                }
                Section {
                    Toggle("Debug HUD", isOn: $model.showHUD)
                    Toggle("Landmark sanity markers", isOn: $model.showLandmarks)
                    Toggle("Demo pose (no camera)", isOn: $model.demoMode)
                    VStack(alignment: .leading) {
                        Text("Manual yaw bias: \(model.debugYawBias, specifier: "%.1f")°")
                        Slider(value: $model.debugYawBias, in: -30...30, step: 0.5)
                    }
                    Button("Reset yaw bias") { model.debugYawBias = 0 }
                } header: {
                    Text("Debug")
                } footer: {
                    Text("The yaw bias is only for checking Milestone 1 by eye. Milestone 3 solves it automatically from the skyline.")
                }
            }
            .navigationTitle("Skyline Lens")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Stand-in for the camera feed in demo mode: dusk sky over dark water.
struct DemoBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.10, green: 0.16, blue: 0.32), Color(red: 0.55, green: 0.45, blue: 0.55),
                     Color(red: 0.08, green: 0.10, blue: 0.16)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Reports the window scene's interface orientation (landscape left vs right matters
/// for the camera maths, and SwiftUI does not expose it directly).
struct InterfaceOrientationReader: UIViewRepresentable {
    let onChange: (ScreenOrientation) -> Void

    func makeUIView(context: Context) -> ReaderView { ReaderView(onChange: onChange) }
    func updateUIView(_ view: ReaderView, context: Context) { view.onChange = onChange }

    final class ReaderView: UIView {
        var onChange: (ScreenOrientation) -> Void
        private var last: ScreenOrientation?

        init(onChange: @escaping (ScreenOrientation) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private var geometryObservation: NSKeyValueObservation?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // A 180° turn (landscape left <-> right) does not change the size, so layout
            // alone misses it; the scene's effective geometry is key-value observable.
            geometryObservation = window?.windowScene?.observe(\.effectiveGeometry, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.report() }
            }
            report()
        }

        private func report() {
            guard let scene = window?.windowScene else { return }
            let o: ScreenOrientation
            switch scene.effectiveGeometry.interfaceOrientation {
            case .portrait: o = .portrait
            case .portraitUpsideDown: o = .portraitUpsideDown
            case .landscapeLeft: o = .landscapeLeft
            case .landscapeRight: o = .landscapeRight
            default: return
            }
            guard o != last else { return }
            last = o
            DispatchQueue.main.async { self.onChange(o) }
        }
    }
}
#endif
