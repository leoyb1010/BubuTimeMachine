import Foundation
import CoreLocation
import MapKit
import Observation

struct CapturedLocation: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var name: String?
}

private struct CapturedCoordinate: Sendable {
    var latitude: Double
    var longitude: Double
}

@Observable
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    private var locationContinuation: CheckedContinuation<CapturedCoordinate?, Never>?

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionIfNeeded() async -> Bool {
        authorizationStatus = manager.authorizationStatus

        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                permissionContinuation?.resume(returning: false)
                permissionContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func currentPlacemark() async -> CapturedLocation? {
        guard await requestPermissionIfNeeded() else { return nil }
        guard let coordinate = await requestOneShotLocation() else { return nil }

        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let name = await reverseGeocode(location)
        return CapturedLocation(latitude: coordinate.latitude,
                                longitude: coordinate.longitude,
                                name: name)
    }

    private func requestOneShotLocation() async -> CapturedCoordinate? {
        await withCheckedContinuation { continuation in
            locationContinuation?.resume(returning: nil)
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        request.preferredLocale = Locale(identifier: "zh_Hans_CN")
        guard let item = try? await request.mapItems.first else { return nil }
        let representations = item.addressRepresentations
        let candidates = [
            item.address?.shortAddress,
            representations?.cityName,
            representations?.cityWithContext,
            item.name,
            item.address?.fullAddress,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            Task { @MainActor [weak self] in self?.finishLocation(nil) }
            return
        }
        let coordinate = CapturedCoordinate(latitude: location.coordinate.latitude,
                                           longitude: location.coordinate.longitude)
        Task { @MainActor [weak self] in
            self?.finishLocation(coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finishLocation(nil)
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        guard let continuation = permissionContinuation else { return }
        permissionContinuation = nil
        continuation.resume(returning: status == .authorizedAlways || status == .authorizedWhenInUse)
    }

    private func finishLocation(_ coordinate: CapturedCoordinate?) {
        let continuation = locationContinuation
        locationContinuation = nil
        continuation?.resume(returning: coordinate)
    }
}
