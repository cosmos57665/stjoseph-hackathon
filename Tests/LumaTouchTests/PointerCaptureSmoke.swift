// Standalone runtime smoke test. Compilation does not capture the pointer.
// Run only when ready: .build/pointer-capture-smoke --run-capture
import AppKit
import Darwin

private struct SmokeFailure: Error { let message: String }

@MainActor private final class SmokeDelegate: NSObject, NSApplicationDelegate {
    private let capture = PointerCapture()
    private var window: NSWindow!
    private var secondWindow: NSWindow!
    private var surface: TouchControlNSView!
    private var interruptions = 0
    private var escapeCommands = 0
    private var checks = 0
    private var finished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 160, y: 180, width: 650, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Luma pointer capture smoke test — Escape releases"
        surface = TouchControlNSView(frame: window.contentView!.bounds)
        surface.autoresizingMask = [.width, .height]
        surface.onCommand = { [weak self] command in
            guard let self, command == .exitTouchMode else { return }
            self.escapeCommands += 1
            self.capture.release()
        }
        window.contentView = surface
        secondWindow = NSWindow(contentRect: NSRect(x: 210, y: 220, width: 300, height: 180),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        secondWindow.title = "Focus change check"
        capture.onInterruption = { [weak self] in self?.interruptions += 1 }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(surface)
        NSApp.activate(ignoringOtherApps: true)

        // Cleanup still happens if the scripted sequence fails to finish.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.finished else { return }
            self.finish("FAIL: watchdog released capture after 12 seconds.")
        }
        Task { @MainActor in
            do { try await runChecks(); finish("PASS: \(checks) pointer lifecycle assertions.") }
            catch { finish("FAIL: \((error as? SmokeFailure)?.message ?? error.localizedDescription)") }
        }
    }

    private func require(_ value: Bool, _ message: String) throws {
        guard value else { throw SmokeFailure(message: message) }
        checks += 1
    }

    private func settle() async throws { try await Task.sleep(nanoseconds: 200_000_000) }

    private func foreground() async throws {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(surface)
        NSApp.activate(ignoringOtherApps: true)
        for _ in 0..<15 {
            if NSApp.isActive && window.isKeyWindow && window.isMainWindow { break }
            try await settle()
        }
        try require(NSApp.isActive && window.isKeyWindow && window.isMainWindow, "Smoke window did not become active.")
        try await settle()
    }

    private func runChecks() async throws {
        try await foreground()
        try require(capture.centerPointer(in: window), capture.failureMessage ?? "Initial positioning failed.")
        try require(!capture.isCaptured, "Positioning alone captured the pointer.")

        try require(capture.capture(in: window), capture.failureMessage ?? "Capture failed.")
        try require(capture.isCaptured, "Capture did not set its state.")
        // Exercise the real native touch surface's Escape routing, not a mock.
        guard let escape = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                           modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil,
                                           characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                           isARepeat: false, keyCode: 53) else {
            throw SmokeFailure(message: "Could not make the local Escape event.")
        }
        window.sendEvent(escape)
        try require(escapeCommands == 1 && !capture.isCaptured, "Escape did not release through touch input.")
        capture.release()
        try require(!capture.isCaptured, "Repeated release changed capture state.")

        try require(capture.capture(in: window), capture.failureMessage ?? "Recapture failed.")
        let beforeWindowFocus = interruptions
        secondWindow.makeKeyAndOrderFront(nil)
        try await settle()
        try require(!capture.isCaptured && interruptions == beforeWindowFocus + 1,
                    "Changing key windows did not release and notify once.")
        secondWindow.orderOut(nil)

        try await foreground()
        try require(capture.capture(in: window), capture.failureMessage ?? "Capture before movement failed.")
        let beforeMove = interruptions
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + 25, y: window.frame.origin.y))
        try await settle()
        try require(!capture.isCaptured && interruptions == beforeMove + 1,
                    "Moving the captured window did not release and notify once.")

        try await foreground()
        try require(capture.capture(in: window), capture.failureMessage ?? "Capture before deactivation failed.")
        let beforeDeactivate = interruptions
        NSApp.deactivate()
        try await settle()
        try require(!capture.isCaptured && interruptions == beforeDeactivate + 1,
                    "Application deactivation did not release and notify once.")
    }

    private func finish(_ result: String) {
        guard !finished else { return }
        finished = true
        capture.release()
        window?.orderOut(nil)
        secondWindow?.orderOut(nil)
        print(result)
        print("Synthetic native-event/lifecycle checks only; physical cursor movement and tactile feel still need human testing.")
        // Cleanup is complete; expose failure to shell runners as well as logs.
        fflush(stdout)
        exit(result.hasPrefix("PASS:") ? 0 : 1)
    }

    func applicationWillTerminate(_ notification: Notification) { capture.release() }
}

@main private struct PointerCaptureSmoke {
    @MainActor static func main() {
        guard CommandLine.arguments.contains("--run-capture") else {
            print("Not run. Add --run-capture only when ready for a brief foreground pointer capture test.")
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = SmokeDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
