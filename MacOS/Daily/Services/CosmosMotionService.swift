import Foundation
import Combine

/// Graceful fallback motion tracker on macOS desktop where hardware IMU gyroscope is absent.
/// Keeps full API parity with iOS `CosmosMotionService` while cleanly reporting `isAvailable = false`
/// so desktop UI hides mobile-only AR controls.
@MainActor
public final class CosmosMotionService: ObservableObject {
    public static let shared = CosmosMotionService()

    @Published public private(set) var isTracking: Bool = false
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var isUsingTrueNorth: Bool = false
    @Published public private(set) var isRelativeGyroOnly: Bool = false
    @Published public private(set) var needsCompassCalibration: Bool = false

    @Published public private(set) var currentAzimuth: Double = 180.0
    @Published public private(set) var currentAltitude: Double = 45.0
    @Published public private(set) var currentRoll: Double = 0.0

    private init() {
        self.isAvailable = false
    }

    public func startTracking() {
        // Hardware AR sky tracking is intentionally unavailable on macOS desktop.
    }

    public func stopTracking() {
        isTracking = false
    }
}
