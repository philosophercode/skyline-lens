import XCTest
@testable import SkylineCore

/// An attitude with the rear camera level, pointing at `heading`, in the given UI orientation.
func levelAttitude(heading: Double, orientation: InterfaceOrientation) -> Attitude {
    let forward = ReferenceFrame.direction(bearing: heading, elevation: 0)
    let right = ReferenceFrame.direction(bearing: heading + 90, elevation: 0)
    let up = Vec3(0, 0, 1)
    // Device axes in the reference frame: z is opposite the camera; x and y follow
    // from the screen axes for this orientation.
    let z = -forward
    let axes = orientation.screenAxes
    // Screen right/up are given in device coords; invert that mapping.
    // device axis i in reference = sum over screen axes of component * world axis.
    func deviceAxis(_ i: Int) -> Vec3 {
        let r = [axes.right.x, axes.right.y, axes.right.z][i]
        let u = [axes.up.x, axes.up.y, axes.up.z][i]
        return right * r + up * u
    }
    return Attitude(deviceX: deviceAxis(0), deviceY: deviceAxis(1), deviceZ: z)
}

let viewSize = Size2(width: 1180, height: 820)

func intrinsics(_ orientation: InterfaceOrientation) -> CameraIntrinsics {
    CameraIntrinsics.aspectFill(
        horizontalFOV: 64,
        sensorSize: Size2(width: 1920, height: 1080),
        viewSize: orientation.isPortrait ? Size2(width: 820, height: 1180) : viewSize,
        orientation: orientation
    )
}

final class GeodesyTests: XCTestCase {
    func testECEFRoundTrip() {
        let p = GeodeticCoordinate(latitude: 40.7625, longitude: -73.9495, altitude: 90)
        let q = Geodesy.geodetic(fromECEF: Geodesy.ecef(p))
        XCTAssertEqual(q.latitude, p.latitude, accuracy: 1e-9)
        XCTAssertEqual(q.longitude, p.longitude, accuracy: 1e-9)
        XCTAssertEqual(q.altitude, p.altitude, accuracy: 1e-3)
    }

    func testENURoundTrip() {
        let o = GeodeticCoordinate(latitude: 40.75, longitude: -73.98, altitude: 10)
        let offset = Vec3(1234, -5678, 90)
        let back = Geodesy.enu(of: Geodesy.coordinate(atENU: offset, from: o), from: o)
        XCTAssertEqual((back - offset).length, 0, accuracy: 1e-4)
    }

    func testDueNorthAndEast() {
        let o = GeodeticCoordinate(latitude: 40.75, longitude: -73.98)
        let north = Geodesy.lookAngle(from: o, to: GeodeticCoordinate(latitude: 40.76, longitude: -73.98), refraction: 0)
        XCTAssertEqual(wrap180(north.bearing), 0, accuracy: 1e-6) // may come back as 359.999…
        XCTAssertEqual(north.distance, 1111, accuracy: 3) // ~111.0 km per degree of latitude
        let east = Geodesy.lookAngle(from: o, to: GeodeticCoordinate(latitude: 40.75, longitude: -73.97), refraction: 0)
        XCTAssertEqual(east.bearing, 90, accuracy: 0.01)
    }

    func testCurvatureAndRefraction() {
        // A target at the same altitude 10 km away sits below horizontal by ~d/2R.
        let o = GeodeticCoordinate(latitude: 40.75, longitude: -73.98, altitude: 0)
        let t = Geodesy.coordinate(atENU: Vec3(0, 10_000, 0), from: o)
        let level = GeodeticCoordinate(latitude: t.latitude, longitude: t.longitude, altitude: 0)
        let geometric = Geodesy.lookAngle(from: o, to: level, refraction: 0)
        XCTAssertEqual(geometric.elevation, -degrees(10_000 / (2 * WGS84.meanRadius)), accuracy: 0.003)
        let apparent = Geodesy.lookAngle(from: o, to: level)
        XCTAssertGreaterThan(apparent.elevation, geometric.elevation)
    }

    func testHorizonDip() {
        // ~84 m up: dip ≈ 0.27° with standard refraction.
        XCTAssertEqual(Geodesy.horizonDip(height: 84), 0.275, accuracy: 0.01)
    }

    func testEmpireStateFromRooseveltIsland() {
        // Sanity check of the whole chain: ESB is west-south-west of Roosevelt Island
        // (~243° by a flat-earth estimate) and well above the horizon from the 26th floor.
        let a = Viewpoint.rooseveltIslandReference.lookAngle(to: LandmarkCatalog.starter[0])
        XCTAssertEqual(a.bearing, 242.9, accuracy: 0.3)
        XCTAssert((3_000...4_500).contains(a.distance), "distance \(a.distance)")
        XCTAssert((3...8).contains(a.elevation), "elevation \(a.elevation)")
    }
}

final class FrameTests: XCTestCase {
    func testDirectionRoundTrip() {
        for (b, e) in [(0.0, 0.0), (45.0, 10.0), (200.0, -5.0), (359.0, 30.0)] {
            let (b2, e2) = ReferenceFrame.angles(of: ReferenceFrame.direction(bearing: b, elevation: e))
            XCTAssertEqual(b2, b, accuracy: 1e-9)
            XCTAssertEqual(e2, e, accuracy: 1e-9)
        }
    }

    func testReferenceAxes() {
        XCTAssertEqual((ReferenceFrame.direction(bearing: 0, elevation: 0) - Vec3(1, 0, 0)).length, 0, accuracy: 1e-12)
        // East is -y because +y is west.
        XCTAssertEqual((ReferenceFrame.direction(bearing: 90, elevation: 0) - Vec3(0, -1, 0)).length, 0, accuracy: 1e-12)
        XCTAssertEqual((ReferenceFrame.fromENU(Vec3(1, 0, 0)) - Vec3(0, -1, 0)).length, 0, accuracy: 1e-12)
    }

    func testScreenAxesAreRightHanded() {
        for o in InterfaceOrientation.allCases {
            let (r, u) = o.screenAxes
            XCTAssertEqual((r.cross(u) - Vec3(0, 0, 1)).length, 0, accuracy: 1e-12, "\(o)")
        }
    }

    func testLevelAttitudeIsRotation() {
        for o in InterfaceOrientation.allCases {
            let m = levelAttitude(heading: 37, orientation: o).deviceFromReference
            XCTAssertLessThan((m * m.transposed).maxAbsDifference(.identity), 1e-12, "\(o)")
            let r = m.rows
            XCTAssertEqual(r.0.cross(r.1).dot(r.2), 1, accuracy: 1e-12, "det \(o)")
        }
    }

    func testConventionDetection() {
        // Camera pointing north, iPad upright in landscape: the two readings disagree strongly.
        let att = levelAttitude(heading: 20, orientation: .landscapeRight)
        let g = att.expectedGravity
        let m = att.deviceFromReference
        XCTAssertEqual(AttitudeConvention.detect(matrix: m, gravity: g), .deviceFromReference)
        XCTAssertEqual(AttitudeConvention.detect(matrix: m.transposed, gravity: g), .referenceFromDevice)
        // In landscapeRight the device's +x edge points up, so gravity is along -x.
        XCTAssertEqual((g - Vec3(-1, 0, 0)).length, 0, accuracy: 1e-12)
    }
}

final class ProjectorTests: XCTestCase {
    func testCenterAndOffsetsInEveryOrientation() throws {
        for o in InterfaceOrientation.allCases {
            let k = intrinsics(o)
            let p = Projector(attitude: levelAttitude(heading: 225, orientation: o), intrinsics: k, orientation: o)
            let c = try XCTUnwrap(p.project(bearing: 225, elevation: 0))
            XCTAssertEqual(c.x, k.center.x, accuracy: 1e-6, "\(o)")
            XCTAssertEqual(c.y, k.center.y, accuracy: 1e-6, "\(o)")

            let right = try XCTUnwrap(p.project(bearing: 235, elevation: 0))
            XCTAssertEqual(right.x - k.center.x, k.focalX * tan(radians(10)), accuracy: 1e-6, "\(o)")
            XCTAssertEqual(right.y, k.center.y, accuracy: 1e-6, "\(o)")

            let up = try XCTUnwrap(p.project(bearing: 225, elevation: 5))
            XCTAssertEqual(k.center.y - up.y, k.focalY * tan(radians(5)), accuracy: 1e-6, "\(o)")

            XCTAssertNil(p.project(bearing: 45, elevation: 0), "behind camera \(o)")
            XCTAssertEqual(p.horizonRoll, 0, accuracy: 1e-9)
        }
    }

    func testUnprojectInvertsProject() throws {
        let o = InterfaceOrientation.landscapeLeft
        let p = Projector(
            attitude: levelAttitude(heading: 200, orientation: o),
            intrinsics: intrinsics(o),
            orientation: o,
            correction: PoseCorrection(yaw: 7, pitch: 2, roll: -3, focalScale: 1.05)
        )
        for (b, e) in [(200.0, 0.0), (215.0, 4.0), (185.0, -2.0)] {
            let s = try XCTUnwrap(p.project(bearing: b, elevation: e))
            let back = p.lookAngle(at: s)
            XCTAssertEqual(back.bearing, b, accuracy: 1e-9)
            XCTAssertEqual(back.elevation, e, accuracy: 1e-9)
        }
    }

    func testYawCorrection() throws {
        // Sensor says the camera faces 200°, but it really faces 210° (yaw +10).
        let o = InterfaceOrientation.landscapeRight
        let k = intrinsics(o)
        let p = Projector(attitude: levelAttitude(heading: 200, orientation: o), intrinsics: k, orientation: o,
                          correction: PoseCorrection(yaw: 10))
        let c = try XCTUnwrap(p.project(bearing: 210, elevation: 0))
        XCTAssertEqual(c.x, k.center.x, accuracy: 1e-6)
        XCTAssertEqual(p.centerAngles.bearing, 210, accuracy: 1e-9)
    }

    func testPitchAndRollCorrectionSigns() throws {
        let o = InterfaceOrientation.landscapeRight
        let k = intrinsics(o)
        let att = levelAttitude(heading: 0, orientation: o)

        // View tilted up: the horizon drops below centre.
        let up = Projector(attitude: att, intrinsics: k, orientation: o, correction: PoseCorrection(pitch: 3))
        XCTAssertGreaterThan(try XCTUnwrap(up.project(bearing: 0, elevation: 0)).y, k.center.y)
        XCTAssertEqual(up.centerAngles.elevation, 3, accuracy: 1e-9)

        // View rolled clockwise: a point right of centre on the horizon moves up the screen.
        let rolled = Projector(attitude: att, intrinsics: k, orientation: o, correction: PoseCorrection(roll: 5))
        XCTAssertLessThan(try XCTUnwrap(rolled.project(bearing: 10, elevation: 0)).y, k.center.y)
        XCTAssertEqual(rolled.horizonRoll, -5, accuracy: 1e-9)
    }

    func testAspectFillFOV() {
        // 16:9 sensor in a 1180x820 landscape view: width is the binding side... the view is
        // taller relative to 16:9, so height fills and width is cropped.
        let k = intrinsics(.landscapeRight)
        XCTAssertLessThan(k.visibleHorizontalFOV, 64)
        let vfov = degrees(2 * atan(tan(radians(32)) * 1080 / 1920))
        XCTAssertEqual(k.visibleVerticalFOV, vfov, accuracy: 1e-9)
    }
}

final class CompassTickTests: XCTestCase {
    func testTicksCoverVisibleBearings() {
        let o = InterfaceOrientation.landscapeRight
        let k = intrinsics(o)
        let p = Projector(attitude: levelAttitude(heading: 225, orientation: o), intrinsics: k, orientation: o)
        let ticks = CompassTicks.ticks(for: p, margin: 0)
        let half = k.visibleHorizontalFOV / 2
        XCTAssertEqual(Double(ticks.count), (2 * half).rounded(.down) + 1, accuracy: 1)
        XCTAssert(ticks.contains { $0.label == "SW" && abs($0.point.x - k.center.x) < 1e-6 })
        XCTAssert(ticks.allSatisfy { abs($0.up.x) < 1e-9 && abs($0.up.y + 1) < 1e-9 })
        XCTAssertNotNil(CompassTicks.levelLine(for: p))
    }

    func testTicksWrapThroughNorth() {
        let o = InterfaceOrientation.landscapeLeft
        let p = Projector(attitude: levelAttitude(heading: 2, orientation: o), intrinsics: intrinsics(o), orientation: o)
        let bearings = Set(CompassTicks.ticks(for: p).map(\.bearing))
        XCTAssert(bearings.contains(0) && bearings.contains(350) && bearings.contains(10))
    }
}

final class ViewpointTests: XCTestCase {
    func testFloorHeightAndEnvelope() {
        XCTAssertEqual(Viewpoint.heightAboveGround(floor: 26), 81.5, accuracy: 1e-9)
        var v = Viewpoint.rooseveltIslandReference
        XCTAssertEqual(OperatingEnvelope.evaluate(v), .ok)
        v.heightAboveGround = 6
        XCTAssertEqual(OperatingEnvelope.evaluate(v), .tooLow(height: 6))
    }
}

final class CaptureMetadataTests: XCTestCase {
    func testRoundTripAndFileStem() throws {
        let meta = CaptureMetadata(
            capturedAt: Date(timeIntervalSince1970: 1_793_080_141),
            interfaceOrientation: "landscapeRight",
            siteLabel: "Roosevelt Island / 26F",
            lens: .init(deviceName: "Back Camera", horizontalFOV: 64, formatWidth: 1920, formatHeight: 1080,
                        zoomFactor: 1, photoWidth: 1920, photoHeight: 1080),
            motion: .init(deviceFromReference: Mat3.identity.rowArrays, gravity: [0, -1, 0],
                          referenceFrame: "true north", magneticAccuracy: "high", reportedHeading: 240,
                          convention: "deviceFromReference", cameraBearing: 240, cameraElevation: 1, horizonRoll: 0),
            location: .init(latitude: 40.76, longitude: -73.95, horizontalAccuracy: 35, altitude: 80,
                            verticalAccuracy: 10, relativeBarometricAltitude: nil, floor: 26, heightAboveGround: 81.5),
            correction: .zero
        )
        let data = try meta.jsonData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(CaptureMetadata.self, from: data), meta)
        XCTAssertTrue(meta.fileStem.hasSuffix("_roosevelt-island-26f"), meta.fileStem)
        XCTAssertFalse(meta.fileStem.contains(":"))
        XCTAssertFalse(meta.fileStem.contains("."))
        var later = meta
        later.capturedAt = meta.capturedAt.addingTimeInterval(0.25)
        XCTAssertNotEqual(later.fileStem, meta.fileStem)
    }
}
