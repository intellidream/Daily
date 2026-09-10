import Foundation
import CoreLocation

/// Thread-safe CoreLocation coordinator supporting async/await location queries.
@MainActor
public final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    public static let shared = LocationManager()

    private let clManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<(latitude: Double, longitude: Double), Error>?
    private var timeoutTask: Task<Void, Never>?

    @Published public private(set) var authorizationStatus: CLAuthorizationStatus

    public override init() {
        self.authorizationStatus = clManager.authorizationStatus
        super.init()
        self.clManager.delegate = self
        self.clManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Returns the immediate cached location from hardware, if recently available.
    public var lastKnownLocation: (latitude: Double, longitude: Double)? {
        guard let location = clManager.location else { return nil }
        // Verify location isn't older than 15 minutes
        if abs(location.timestamp.timeIntervalSinceNow) < 900 {
            return (location.coordinate.latitude, location.coordinate.longitude)
        }
        return nil
    }

    /// Requests current GPS location with a strict timeout (default 10s).
    public func requestCurrentLocation(timeoutSeconds: TimeInterval = 10) async throws -> (latitude: Double, longitude: Double) {
        // Check authorization
        if clManager.authorizationStatus == .notDetermined {
            clManager.requestWhenInUseAuthorization()
        }

        // Return last known if fresh
        if let lastKnown = lastKnownLocation {
            return lastKnown
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation

            // Setup timeout
            self.timeoutTask?.cancel()
            self.timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                guard let self = self else { return }
                self.handleTimeout()
            }

            self.clManager.requestLocation()
        }
    }

    private func handleTimeout() {
        if let continuation = locationContinuation {
            locationContinuation = nil
            clManager.stopUpdatingLocation()
            continuation.resume(throwing: LocationError.timeout)
        }
    }

    private func didUpdateLocation(_ coords: (latitude: Double, longitude: Double)) {
        timeoutTask?.cancel()
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(returning: coords)
        }
    }

    private func didFail(_ error: Error) {
        timeoutTask?.cancel()
        if let continuation = locationContinuation {
            locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coords = (latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor in
            self.didUpdateLocation(coords)
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.didFail(error)
        }
    }
}

public enum LocationError: LocalizedError {
    case unauthorized
    case timeout
    case unableToDetermine

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Location permissions are not granted."
        case .timeout:
            return "Location request timed out."
        case .unableToDetermine:
            return "Unable to determine current coordinates."
        }
    }
}
