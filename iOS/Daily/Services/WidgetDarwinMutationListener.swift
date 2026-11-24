import Foundation
import DailyCore
#if canImport(UIKit)
import UIKit
#endif

/// Cross-process Darwin notification observer on iOS that immediately synchronizes
/// widget-side App Group mutations (Smokes, Bubbles, Money, TagDoS) into the active
/// or backgrounded iOS app process and flushes queued habit mutations to Supabase.
@MainActor
public final class WidgetDarwinMutationListener {
    public static let shared = WidgetDarwinMutationListener()

    private var isListening = false
    #if canImport(UIKit)
    private var activeBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    private init() {}

    public func startListening() {
        guard !isListening else { return }
        isListening = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let name = WidgetDataCoordinator.darwinMutationNotificationName as CFString

        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, _, _, _, _ in
                DispatchQueue.main.async {
                    Task { @MainActor in
                        WidgetDarwinMutationListener.shared.handleRemoteMutation()
                    }
                }
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    private func handleRemoteMutation() {
        #if canImport(UIKit)
        if activeBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(activeBackgroundTask)
            activeBackgroundTask = .invalid
        }
        activeBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "DailyWidgetMutationSync") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.activeBackgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.activeBackgroundTask)
                    self.activeBackgroundTask = .invalid
                }
            }
        }
        #endif

        Task { @MainActor [weak self] in
            defer {
                #if canImport(UIKit)
                if let self, self.activeBackgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(self.activeBackgroundTask)
                    self.activeBackgroundTask = .invalid
                }
                #endif
            }
            WidgetDataCoordinator.shared.synchronizeDefaults()

            let previousLedgerText = SmartLedgerStore.shared.rawText
            SmartLedgerStore.shared.reloadFromStorage()
            let ledgerChanged = SmartLedgerStore.shared.rawText != previousLedgerText

            TagdosStore.shared.reloadFromWidgetMutation()

            HabitsService.shared.reloadFromLocalStorage()
            await HabitsService.shared.flushOfflineQueue()

            if ledgerChanged {
                await SmartLedgerStore.shared.syncWithSupabase()
            }
        }
    }
}
