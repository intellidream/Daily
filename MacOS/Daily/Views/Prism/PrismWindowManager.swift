import AppKit
import SwiftUI
import DailyCore

/// Manages independent multi-monitor floating macOS windows for Prism Studio ("Pop-Out Window").
@MainActor
public final class PrismWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = PrismWindowManager()

    @Published public private(set) var isPopOutWindowActive: Bool = false

    private var popoutController: NSWindowController?

    private override init() {
        super.init()
    }

    public func openPopOutWindow() {
        if let existing = popoutController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            isPopOutWindowActive = true
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
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
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
        .ignoresSafeArea(.all)

        window.contentView = NSHostingView(rootView: root)

        let controller = NSWindowController(window: window)
        popoutController = controller
        isPopOutWindowActive = true
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func focusPopOutWindow() {
        if let window = popoutController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public func closePopOutWindow() {
        popoutController?.window?.close()
        popoutController = nil
        isPopOutWindowActive = false
    }

    public func windowWillClose(_ notification: Notification) {
        if let closing = notification.object as? NSWindow, closing === popoutController?.window {
            popoutController = nil
            isPopOutWindowActive = false
        }
    }
}
