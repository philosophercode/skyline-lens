import Foundation

/// 3-vector of doubles. Kept dependency-free (no `simd`) so SkylineCore builds on Linux.
public typealias Vec3 = SIMD3<Double>

public extension SIMD3 where Scalar == Double {
    func dot(_ other: Vec3) -> Double { (self * other).sum() }

    func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    var length: Double { dot(self).squareRoot() }

    var normalized: Vec3 {
        let l = length
        return l > 0 ? self / l : self
    }
}

/// Row-major 3x3 matrix. `m * v` treats `v` as a column vector.
public struct Mat3: Equatable, Sendable {
    public var rows: (Vec3, Vec3, Vec3)

    public init(rows r0: Vec3, _ r1: Vec3, _ r2: Vec3) {
        rows = (r0, r1, r2)
    }

    public static let identity = Mat3(rows: Vec3(1, 0, 0), Vec3(0, 1, 0), Vec3(0, 0, 1))

    public var transposed: Mat3 {
        let (a, b, c) = rows
        return Mat3(rows: Vec3(a.x, b.x, c.x), Vec3(a.y, b.y, c.y), Vec3(a.z, b.z, c.z))
    }

    public static func * (m: Mat3, v: Vec3) -> Vec3 {
        Vec3(m.rows.0.dot(v), m.rows.1.dot(v), m.rows.2.dot(v))
    }

    public static func * (a: Mat3, b: Mat3) -> Mat3 {
        let bt = b.transposed
        func row(_ r: Vec3) -> Vec3 { Vec3(r.dot(bt.rows.0), r.dot(bt.rows.1), r.dot(bt.rows.2)) }
        return Mat3(rows: row(a.rows.0), row(a.rows.1), row(a.rows.2))
    }

    public static func == (a: Mat3, b: Mat3) -> Bool {
        a.rows.0 == b.rows.0 && a.rows.1 == b.rows.1 && a.rows.2 == b.rows.2
    }

    /// Right-handed rotation by `angle` radians about the x axis.
    public static func rotationX(_ angle: Double) -> Mat3 {
        let c = cos(angle), s = sin(angle)
        return Mat3(rows: Vec3(1, 0, 0), Vec3(0, c, -s), Vec3(0, s, c))
    }

    /// Right-handed rotation by `angle` radians about the y axis.
    public static func rotationY(_ angle: Double) -> Mat3 {
        let c = cos(angle), s = sin(angle)
        return Mat3(rows: Vec3(c, 0, s), Vec3(0, 1, 0), Vec3(-s, 0, c))
    }

    /// Right-handed rotation by `angle` radians about the z axis.
    public static func rotationZ(_ angle: Double) -> Mat3 {
        let c = cos(angle), s = sin(angle)
        return Mat3(rows: Vec3(c, -s, 0), Vec3(s, c, 0), Vec3(0, 0, 1))
    }

    /// Largest absolute element-wise difference, for tolerant comparisons.
    public func maxAbsDifference(_ o: Mat3) -> Double {
        let d0 = rows.0 - o.rows.0, d1 = rows.1 - o.rows.1, d2 = rows.2 - o.rows.2
        return [d0.x, d0.y, d0.z, d1.x, d1.y, d1.z, d2.x, d2.y, d2.z].map(abs).max() ?? 0
    }
}

public struct Point2: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Size2: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

@inlinable public func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
@inlinable public func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// Wraps an angle in degrees into [0, 360).
@inlinable public func wrap360(_ deg: Double) -> Double {
    let r = deg.truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

/// Wraps an angle in degrees into (-180, 180].
@inlinable public func wrap180(_ deg: Double) -> Double {
    let r = wrap360(deg)
    return r > 180 ? r - 360 : r
}
