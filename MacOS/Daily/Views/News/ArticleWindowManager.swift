import AppKit
import SwiftUI
import DailyCore

/// Manager responsible for opening, focusing, and managing independent native macOS windows for reading articles.
@MainActor
public final class ArticleWindowManager: NSObject, NSWindowDelegate {
    public static let shared = ArticleWindowManager()
    
    private var openControllers: [String: NSWindowController] = [:]
    
    private override init() {
        super.init()
    }
    
    /// Opens an article in a dedicated, resizable, floating macOS window.
    public func open(article: NewsArticle, candidatePool: [NewsArticle]) {
        // If window already exists for this article, bring it to the front
        if let existing = openControllers[article.id], let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1050, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 680, height: 520)
        window.center()
        window.title = article.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        let readerView = NewsReaderView(
            article: article,
            candidatePool: candidatePool,
            isInSeparateWindow: true,
            onDismiss: { [weak window] in
                window?.close()
            }
        )
        window.contentView = NSHostingView(rootView: readerView)
        
        let controller = NSWindowController(window: window)
        openControllers[article.id] = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow {
            openControllers = openControllers.filter { $0.value.window !== closingWindow }
        }
    }
}
