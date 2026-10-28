import Foundation
import Combine

/// Graceful fallback motion tracker on macOS where hardware gyroscope is not present.
@MainActor
public final class CosmosMotionService: ObservableObject {
    public static let shared = CosmosMotionService()

    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var currentAzimuth: Double = 180.0
    @Published public private(set) var currentAltitude: Double = 45.0
    @Published public private(set) var currentRoll: Double = 0.0

    private init() {
        self.isAvailable = false
    }

    public func startTracking() {
        // Gyroscope tracking is not supported on macOS desktop
    }

    public func stopTracking() {
        isTracking = false
    }
}
