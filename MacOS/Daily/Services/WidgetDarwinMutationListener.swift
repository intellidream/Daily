import Foundation
import DailyCore

@MainActor
public final class WidgetDarwinMutationListener {
    public static let shared = WidgetDarwinMutationListener()
    private var isListening = false
    
    private init() {}
    
    public func startListening() {
        guard !isListening else { return }
        isListening = true
        
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(WidgetDataCoordinator.darwinMutationNotificationName as CFString)
        
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    Task { @MainActor in
                        SmartLedgerStore.shared.reloadFromStorage()
                        HabitsService.shared.reloadFromLocalStorage()
                        await HabitsService.shared.flushOfflineQueue()
                        await HabitsService.shared.loadDataForSelectedDate()
                    }
                }
            },
            name.rawValue,
            nil,
            .deliverImmediately
        )
    }
}
