#if os(iOS)
import SkylineCore
import SwiftUI

/// Draws the 0° elevation line, bearing ticks, the visible-horizon dip line,
/// a centre reticle and landmark sanity markers.
struct CompassOverlay: View {
    let model: LiveViewModel

    var body: some View {
        GeometryReader { geo in
            let size = Size2(width: geo.size.width, height: geo.size.height)
            if let projector = model.projector(viewSize: size) {
                let ticks = CompassTicks.ticks(for: projector)
                let markers = model.showLandmarks ? model.landmarkMarkers(projector: projector) : []
                let dip = Geodesy.horizonDip(height: model.heightAboveGround)
                Canvas { ctx, _ in
                    drawLevelLine(ctx, projector, elevation: 0, color: .white.opacity(0.55), dash: [])
                    drawLevelLine(ctx, projector, elevation: -dip, color: .cyan.opacity(0.5), dash: [6, 6])
                    for tick in ticks { draw(tick, in: ctx) }
                    for m in markers { draw(m, in: ctx) }
                    drawReticle(ctx, center: projector.intrinsics.center)
                }
                .allowsHitTesting(false)
            } else {
                Text("Waiting for camera and motion…")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 10))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func cg(_ p: Point2) -> CGPoint { CGPoint(x: p.x, y: p.y) }

    private func drawLevelLine(_ ctx: GraphicsContext, _ projector: Projector, elevation: Double, color: Color, dash: [CGFloat]) {
        guard let line = CompassTicks.levelLine(for: projector, elevation: elevation) else { return }
        let (a, b) = line
        var path = Path()
        path.move(to: cg(a))
        path.addLine(to: cg(b))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: dash))
    }

    private func draw(_ tick: CompassTick, in ctx: GraphicsContext) {
        let (length, width): (Double, CGFloat) = switch tick.kind {
        case .minor: (6, 1)
        case .major: (14, 1.5)
        case .cardinal: (22, 2.5)
        }
        let end = Point2(x: tick.point.x + tick.up.x * length, y: tick.point.y + tick.up.y * length)
        var path = Path()
        path.move(to: cg(tick.point))
        path.addLine(to: cg(end))
        ctx.stroke(path, with: .color(tick.kind == .cardinal ? .yellow : .white), lineWidth: width)

        if let label = tick.label {
            let at = Point2(x: tick.point.x + tick.up.x * (length + 12), y: tick.point.y + tick.up.y * (length + 12))
            let text = Text(label)
                .font(tick.kind == .cardinal ? .system(size: 16, weight: .bold) : .system(size: 12, weight: .medium))
                .foregroundColor(tick.kind == .cardinal ? .yellow : .white)
            ctx.draw(text, at: cg(at))
        }
    }

    private func draw(_ marker: LiveViewModel.LandmarkMarker, in ctx: GraphicsContext) {
        let p = cg(marker.point)
        var diamond = Path()
        diamond.move(to: CGPoint(x: p.x, y: p.y - 6))
        diamond.addLine(to: CGPoint(x: p.x + 6, y: p.y))
        diamond.addLine(to: CGPoint(x: p.x, y: p.y + 6))
        diamond.addLine(to: CGPoint(x: p.x - 6, y: p.y))
        diamond.closeSubpath()
        ctx.stroke(diamond, with: .color(.orange), lineWidth: 2)
        let km = marker.look.distance / 1000
        let text = Text("\(marker.landmark.name) · \(km, specifier: "%.1f") km")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.orange)
        ctx.draw(text, at: CGPoint(x: p.x, y: p.y - 16), anchor: .bottom)
    }

    private func drawReticle(_ ctx: GraphicsContext, center: Point2) {
        let c = cg(center)
        var path = Path()
        path.move(to: CGPoint(x: c.x - 10, y: c.y)); path.addLine(to: CGPoint(x: c.x + 10, y: c.y))
        path.move(to: CGPoint(x: c.x, y: c.y - 10)); path.addLine(to: CGPoint(x: c.x, y: c.y + 10))
        ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1)
    }
}
#endif
