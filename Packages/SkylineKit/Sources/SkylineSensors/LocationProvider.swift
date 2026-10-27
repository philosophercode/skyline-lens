#if os(iOS)
import CoreLocation
import CoreMotion
import Foundation
import Observation
import SkylineCore

/// GPS fix plus barometric relative altitude.
///
/// Indoors the GPS fix is weak (20–50 m). Milestone 1 only uses it to place compass
/// ticks and sanity markers; the resection solve in Milestone 0/3 refines it.
@Observable
public final class LocationProvider: NSObject, CLLocationManagerDelegate {
    public private(set) var location: CLLocation?
    public private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// Barometric altitude change since start, metres.
    public private(set) var relativeAltitude: Double?

    private let manager = CLLocationManager()
    private let altimeter = CMAltimeter()

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
    }

    public func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                self?.relativeAltitude = data?.relativeAltitude.doubleValue
            }
        }
    }

    public func stop() {
        manager.stopUpdatingLocation()
        altimeter.stopRelativeAltitudeUpdates()
    }

    /// Current viewpoint. Height above ground comes from the floor the user entered
    /// (GPS altitude indoors is too noisy to be useful on its own).
    public func viewpoint(heightAboveGround: Double, groundElevation: Double = 5) -> Viewpoint? {
        guard let c = location?.coordinate else { return nil }
        return Viewpoint(
            latitude: c.latitude, longitude: c.longitude,
            groundElevation: groundElevation, heightAboveGround: heightAboveGround
        )
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Keep the most accurate recent fix rather than the latest, since indoor fixes jump.
        guard let new = locations.last, new.horizontalAccuracy >= 0 else { return }
        if let old = location,
           old.horizontalAccuracy < new.horizontalAccuracy,
           new.timestamp.timeIntervalSince(old.timestamp) < 30 {
            return
        }
        location = new
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
#endif
