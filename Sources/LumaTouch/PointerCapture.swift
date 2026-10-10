import AppKit
import CoreGraphics

/// Keeps pointer movement out of the way only while the active reading window
/// owns the keyboard. The event interpreter stays local to that window.
@MainActor final class PointerCapture: NSObject {
    private(set) var isCaptured = false
    private(set) var failureMessage: String?
    var onInterruption: (() -> Void)?

    private weak var capturedWindow: NSWindow?
    private var mouseDisconnected = false
    private var cursorHidden = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        for name in [NSApplication.willResignActiveNotification,
                     NSApplication.willHideNotification,
                     NSApplication.didChangeScreenParametersNotification,
                     NSApplication.willTerminateNotification] {
            center.addObserver(self, selector: #selector(applicationUnavailable(_:)), name: name, object: nil)
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                     NSWindow.willMiniaturizeNotification, NSWindow.willBeginSheetNotification,
                     NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didChangeScreenNotification] {
            center.addObserver(self, selector: #selector(windowUnavailable(_:)), name: name, object: nil)
        }
    }

    /// Places the cursor over the welcome surface without locking or hiding it.
    /// Call once after the reading window becomes active at launch.
    @discardableResult
    func centerPointer(in window: NSWindow) -> Bool {
        failureMessage = nil
        guard let point = centerPoint(in: window) else { return false }
        guard CGWarpMouseCursorPosition(point) == .success else {
            failureMessage = "macOS could not position the pointer over the reading window."
            return false
        }
        return true
    }

    /// Returns false without hiding or disconnecting the cursor if macOS cannot
    /// activate capture. Callers should keep ordinary controls available.
    @discardableResult
    func capture(in window: NSWindow) -> Bool {
        if isCaptured, capturedWindow === window { return true }
        release()
        failureMessage = nil
        guard let center = centerPoint(in: window) else { return false }
        let associationResult = CGAssociateMouseAndMouseCursorPosition(0)
        guard associationResult == .success else {
            failureMessage = "macOS could not hold the pointer for touch mode. Use the visible controls and try again."
            return false
        }
        mouseDisconnected = true
        guard CGWarpMouseCursorPosition(center) == .success else {
            release()
            failureMessage = "macOS could not position the pointer for touch mode. Use the visible controls and try again."
            return false
        }

        NSCursor.hide()
        cursorHidden = true
        capturedWindow = window
        isCaptured = true
        return true
    }

    private func centerPoint(in window: NSWindow) -> CGPoint? {
        guard NSApp.isActive, window.isVisible, window.isMainWindow,
              window.isKeyWindow, !window.isMiniaturized,
              window.attachedSheet == nil, let content = window.contentView else {
            failureMessage = "Activate the Luma Touch reading window before entering touch mode."
            return nil
        }
        let contentRect = window.convertToScreen(content.convert(content.bounds, to: nil))
        // AppKit's screen origin is below the primary display; Quartz's is above
        // it. This also preserves off-primary display offsets.
        return CGPoint(x: contentRect.midX,
                       y: CGDisplayBounds(CGMainDisplayID()).height - contentRect.midY)
    }

    /// Safe to call repeatedly, including from Escape and view teardown.
    func release() {
        if mouseDisconnected {
            let result = CGAssociateMouseAndMouseCursorPosition(1)
            // Keep the flag on failure so a subsequent teardown retries release.
            mouseDisconnected = result != .success
            if mouseDisconnected {
                failureMessage = "macOS could not restore pointer movement yet. Switch to another app to leave touch mode."
            }
        }
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
        isCaptured = false
        capturedWindow = nil
    }

    @objc private func applicationUnavailable(_ notification: Notification) {
        interruptCapture()
    }

    @objc private func windowUnavailable(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === capturedWindow else { return }
        interruptCapture()
    }

    private func interruptCapture() {
        guard isCaptured || mouseDisconnected || cursorHidden else { return }
        release()
        onInterruption?()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Destruction normally happens on the main actor. Preserve a safe
        // cleanup path even if a future owner releases its last reference off it.
        let reconnect = mouseDisconnected
        let unhide = cursorHidden
        guard reconnect || unhide else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                if reconnect { CGAssociateMouseAndMouseCursorPosition(1) }
                if unhide { NSCursor.unhide() }
            }
        } else {
            DispatchQueue.main.async {
                if reconnect { CGAssociateMouseAndMouseCursorPosition(1) }
                if unhide { NSCursor.unhide() }
            }
        }
    }
}
