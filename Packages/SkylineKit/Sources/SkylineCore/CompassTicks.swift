import Foundation

/// A bearing tick to draw along the horizon.
public struct CompassTick: Equatable, Sendable {
    public enum Kind: Sendable { case minor, major, cardinal }

    public var bearing: Double
    public var kind: Kind
    public var label: String?
    /// Where the tick meets the horizontal (0° elevation) line.
    public var point: Point2
    /// Screen direction of "up" at this point, as a unit vector (y down), so ticks
    /// stay perpendicular to the horizon when the iPad is rolled.
    public var up: Point2
}

public enum CompassTicks {
    static let cardinals: [Int: String] = [
        0: "N", 45: "NE", 90: "E", 135: "SE", 180: "S", 225: "SW", 270: "W", 315: "NW",
    ]

    /// Ticks every `step` degrees along the 0° elevation line, labelled every
    /// `labelEvery` degrees, keeping only those on screen.
    public static func ticks(
        for projector: Projector,
        step: Int = 1,
        labelEvery: Int = 10,
        elevation: Double = 0,
        margin: Double = 40
    ) -> [CompassTick] {
        var result: [CompassTick] = []
        for b in stride(from: 0, to: 360, by: max(step, 1)) {
            let bearing = Double(b)
            guard let p = projector.project(bearing: bearing, elevation: elevation),
                  projector.isOnScreen(p, margin: margin),
                  let above = projector.project(bearing: bearing, elevation: elevation + 0.5)
            else { continue }
            let dx = above.x - p.x, dy = above.y - p.y
            let len = (dx * dx + dy * dy).squareRoot()
            let up = len > 0 ? Point2(x: dx / len, y: dy / len) : Point2(x: 0, y: -1)

            let kind: CompassTick.Kind
            let label: String?
            if let c = cardinals[b] {
                kind = .cardinal
                label = c
            } else if b % labelEvery == 0 {
                kind = .major
                label = "\(b)°"
            } else {
                kind = .minor
                label = nil
            }
            result.append(CompassTick(bearing: bearing, kind: kind, label: label, point: p, up: up))
        }
        return result
    }

    /// Two screen points spanning the line at `elevation` across the view (a level
    /// line in the world is a straight line under a pinhole camera), or nil if the
    /// line is not visible.
    public static func levelLine(for projector: Projector, elevation: Double = 0) -> (Point2, Point2)? {
        let center = projector.centerAngles.bearing
        let half = projector.intrinsics.visibleHorizontalFOV / 2 + 30
        let points = stride(from: -half, through: half, by: 2).compactMap {
            projector.project(bearing: center + $0, elevation: elevation)
        }
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        return (first, last)
    }
}
