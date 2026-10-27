#if os(iOS)
import SkylineCore
import SwiftUI

/// Pose and lens readout. Milestone 3 adds the rendered-vs-detected skyline panel
/// and alignment residual here.
struct DebugHUD: View {
    let model: LiveViewModel
    let viewSize: Size2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines, id: \.self) { Text($0) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 8))
    }

    private var lines: [String] {
        var out: [String] = []
        let f1 = { (v: Double) in String(format: "%.1f", v) }
        let f2 = { (v: Double) in String(format: "%.2f", v) }

        if let p = model.projector(viewSize: viewSize) {
            let c = p.centerAngles
            out.append("view   bearing \(f1(c.bearing))°  elev \(f2(c.elevation))°  roll \(f1(p.horizonRoll))°")
            out.append("fov    \(f1(p.intrinsics.visibleHorizontalFOV))° × \(f1(p.intrinsics.visibleVerticalFOV))°  f \(f1(p.intrinsics.focalX)) pt")
        } else {
            out.append("view   (no pose yet)")
        }
        if let s = model.motion.latest {
            out.append("motion \(s.referenceFrame), mag \(s.magneticAccuracy), CM heading \(s.reportedHeading.map(f1) ?? "–")°")
        }
        out.append("matrix \(model.motion.convention.rawValue)\(model.motion.conventionVerified ? " ✓" : " (unverified)")")
        out.append("lens   \(model.camera.deviceName) native \(f1(model.camera.fieldOfView))° zoom \(f2(model.camera.zoomFactor))× \(Int(model.camera.formatSize.width))×\(Int(model.camera.formatSize.height))")
        if let loc = model.location.location {
            out.append("gps    \(String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)) ±\(Int(loc.horizontalAccuracy)) m  alt \(Int(loc.altitude)) ±\(Int(loc.verticalAccuracy)) m")
        } else {
            out.append("gps    no fix: using Roosevelt Island fallback")
        }
        if let rel = model.location.relativeAltitude { out.append("baro   Δalt \(f2(rel)) m") }
        out.append("height floor \(model.floor) → \(f1(model.heightAboveGround)) m  dip \(f2(Geodesy.horizonDip(height: model.heightAboveGround)))°")
        if case .tooLow(let h) = OperatingEnvelope.evaluate(model.viewpoint) {
            out.append("⚠︎ \(f1(h)) m above ground: below the \(Int(OperatingEnvelope.minimumHeight)) m envelope")
        }
        out.append("yaw    debug bias \(f1(model.debugYawBias))°  (auto-registration: Milestone 3)")
        out.append("ui     \(model.orientation.rawValue)")
        return out
    }
}
#endif
