import AppKit
import SwiftUI
import DailyCore

/// Manages independent multi-monitor floating macOS windows for Prism Studio ("Pop-Out Window").
@MainActor
public final class PrismWindowManager: NSObject, NSWindowDelegate {
    public static let shared = PrismWindowManager()

    private var popoutController: NSWindowController?

    private override init() {
        super.init()
    }

    public func openPopOutWindow() {
        if let existing = popoutController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        window.title = "Prism — Assisted Web Studio"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self

        let root = LiquidGlassBackground {
            PrismMainView(
                isInPopOutWindow: true,
                defaultResearchSplit: true,
                onNavigateBack: { [weak window] in
                    window?.close()
                }
            )
        }
        window.contentView = NSHostingView(rootView: root)

        let controller = NSWindowController(window: window)
        popoutController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === popoutController?.window {
            popoutController = nil
        }
    }
}
