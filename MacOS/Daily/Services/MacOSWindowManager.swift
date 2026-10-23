import SwiftUI
import AppKit
import DailyCore

@MainActor
public final class MacOSWindowManager: ObservableObject {
    public static let shared = MacOSWindowManager()
    
    public var openWindowAction: OpenWindowAction? = nil
    
    private init() {}
    
    /// Activates the primary DayOne window:
    /// - If minimized in the Dock, de-miniaturizes it.
    /// - If already open, brings it to front and focuses it.
    /// - If closed, reopens the single instance.
    /// - If a tab is specified, switches the existing window to that tab without spawning new windows.
    public func activateMainWindow(selectingTab tab: NavigationTab? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        
        let mainWindow = NSApp.windows.first { window in
            let title = window.title
            return (title == "DayOne" || title.isEmpty || window.identifier?.rawValue == "main") && !title.contains("Glance")
        }
        
        if let window = mainWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openWindowAction?(id: "main")
        }
        
        if let tab = tab {
            NotificationCenter.default.post(name: .dailySelectTab, object: tab)
        }
    }
    
    /// Summons or focuses the DayOne Glance HUD floating window.
    public func activateGlanceWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        let glanceWindow = NSApp.windows.first { window in
            window.title.contains("Glance") || window.identifier?.rawValue == "glance"
        }
        
        if let window = glanceWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            openWindowAction?(id: "glance")
        }
    }
    
    /// Smoothly animates the main window frame width between compact single-column (480pt)
    /// and expanded dual-pane workspace (1040pt).
    public func setMainWindowDualPane(enabled: Bool) {
        guard let window = NSApp.windows.first(where: {
            let title = $0.title
            return (title == "DayOne" || title.isEmpty || $0.identifier?.rawValue == "main") && !title.contains("Glance")
        }) else { return }
        
        var currentFrame = window.frame
        let targetWidth: CGFloat = enabled ? 1040 : 480
        
        if enabled && currentFrame.width < 860 {
            let delta = targetWidth - currentFrame.width
            let newX = max(currentFrame.origin.x - delta / 2, 20)
            currentFrame.origin.x = newX
            currentFrame.size.width = targetWidth
            window.setFrame(currentFrame, display: true, animate: true)
        } else if !enabled && currentFrame.width > 650 {
            let delta = currentFrame.width - targetWidth
            currentFrame.origin.x += delta / 2
            currentFrame.size.width = targetWidth
            window.setFrame(currentFrame, display: true, animate: true)
        }
    }
}

extension Notification.Name {
    public static let dailySelectTab = Notification.Name("dailySelectTab")
}
