import AppKit
import SwiftUI

enum TouchCommand: Equatable {
    case togglePlayback, nextLine, previousLine, replayLine, faster, slower, pause
    case enterTouchMode, exitTouchMode
}

/// A view-independent interpreter so momentum, direction and accidental gestures
/// can be checked without sending real input or producing haptics.
struct TouchGestureInterpreter {
    enum Phase { case none, mayBegin, began, changed, stationary, ended, cancelled }
    struct ScrollResult: Equatable {
        var command: TouchCommand?
        var shouldConsume: Bool
    }
    private enum Axis { case undecided, horizontal, vertical }
    private var axis: Axis = .undecided
    private var active = false
    private var delivered = false
    private var x: Double = 0
    private var y: Double = 0
    let navigationThreshold: Double = 48

    static func clickCommand(clickCount: Int, activationOnly: Bool = false) -> TouchCommand? {
        if activationOnly { return clickCount == 3 ? .enterTouchMode : nil }
        // The first click only focuses. A triple/quadruple click must not toggle
        // a second time; macOS's own double-click timing is respected.
        return clickCount == 2 ? .togglePlayback : nil
    }

    static func keyCommand(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags,
                           isRepeat: Bool) -> TouchCommand? {
        guard !isRepeat, modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return nil }
        switch keyCode {
        case 49: return .togglePlayback // Space
        case 123: return .previousLine
        case 124: return .nextLine
        case 125: return .slower
        case 126: return .faster
        case 53: return .exitTouchMode
        default: return characters?.lowercased() == "r" ? .replayLine : nil
        }
    }

    mutating func reset() { self = Self() }

    mutating func scroll(deltaX: Double, deltaY: Double, phase: Phase,
                         hasMomentum: Bool, precise: Bool, inverted: Bool,
                         allowsSpeedGestures: Bool = true) -> ScrollResult {
        // Coarse mouse wheels and unphased synthetic/legacy scrolling never
        // change lessons. Momentum belongs to the completed physical gesture.
        guard precise else { return ScrollResult(shouldConsume: false) }
        if hasMomentum { return ScrollResult(shouldConsume: axis != .vertical || allowsSpeedGestures) }
        if phase == .none { return ScrollResult(shouldConsume: false) }

        if phase == .mayBegin || phase == .began {
            axis = .undecided
            active = true
            delivered = false
            x = 0
            y = 0
        }
        guard active else { return ScrollResult(shouldConsume: false) }
        if phase == .cancelled {
            active = false
            return ScrollResult(shouldConsume: axis != .vertical || allowsSpeedGestures)
        }

        // AppKit inverts scrollingDeltaX/Y for Natural scrolling. Undo that
        // inversion to keep a physical left swipe = next line for both settings.
        // With inversion removed, positive horizontal scroll denotes left and
        // positive vertical scroll denotes up.
        let direction = inverted ? -1.0 : 1.0
        x += deltaX * direction
        y += deltaY * direction
        if axis == .undecided {
            if abs(y) >= 8 && abs(y) > abs(x) * 1.15 { axis = .vertical }
            else if abs(x) >= 8 && abs(x) > abs(y) * 1.5 { axis = .horizontal }
        }

        var command: TouchCommand?
        if axis == .horizontal, !delivered, abs(x) >= navigationThreshold {
            delivered = true
            command = x > 0 ? .nextLine : .previousLine
        } else if axis == .vertical, allowsSpeedGestures, !delivered, abs(y) >= navigationThreshold {
            delivered = true
            command = y > 0 ? .faster : .slower
        }
        if phase == .ended { active = false }
        return ScrollResult(command: command, shouldConsume: axis != .vertical || allowsSpeedGestures)
    }
}

/// Put this transparent view over the decorative touch panel, not over buttons
/// or text fields. Input stays local to this surface; there are no global hooks.
struct TouchControlSurface: NSViewRepresentable {
    var enabled: Bool = true
    var activationOnly: Bool = false
    var focusOnAppear: Bool = false
    var allowsSpeedGestures: Bool = true
    var accessibilityValue: String = ""
    var onCommand: (TouchCommand) -> Void

    func makeNSView(context: Context) -> TouchControlNSView {
        let view = TouchControlNSView()
        configure(view)
        return view
    }

    func updateNSView(_ view: TouchControlNSView, context: Context) { configure(view) }

    private func configure(_ view: TouchControlNSView) {
        view.inputEnabled = enabled
        view.activationOnly = activationOnly
        view.focusOnAppear = focusOnAppear
        view.allowsSpeedGestures = allowsSpeedGestures
        view.onCommand = onCommand
        view.setAccessibilityEnabled(enabled)
        view.setAccessibilityValue(accessibilityValue)
        view.setAccessibilityLabel(activationOnly ? "Enter touch mode" : "Touch controls")
        view.setAccessibilityHelp(activationOnly
            ? "Triple-click to enter touch mode. Escape opens the standard interface."
            : "Double-click to play or pause. Swipe two fingers left for the next line or right for the previous line. Swipe up for faster playback or down for slower playback. Right-click to replay. When focused: Space plays or pauses, left and right arrows change lines, R replays, up and down arrows change speed, and Escape pauses and exits touch mode.")
    }
}

final class TouchControlNSView: NSView {
    var onCommand: ((TouchCommand) -> Void)?
    var activationOnly = false {
        didSet { if oldValue != activationOnly { interpreter.reset() } }
    }
    var focusOnAppear = false
    var allowsSpeedGestures = true
    var inputEnabled = true {
        didSet {
            if !inputEnabled { interpreter.reset() }
            if oldValue != inputEnabled { needsDisplay = true }
        }
    }
    private var interpreter = TouchGestureInterpreter()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Touch controls")
        let actions: [(String, TouchCommand)] = [
            ("Next line", .nextLine), ("Previous line", .previousLine),
            ("Replay line", .replayLine), ("Faster", .faster),
            ("Slower", .slower), ("Pause", .pause)
        ]
        setAccessibilityCustomActions(actions.map { name, command in
            NSAccessibilityCustomAction(name: name) { [weak self] in
                guard let self, self.inputEnabled, !self.activationOnly else { return false }
                self.onCommand?(command)
                return true
            }
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { inputEnabled }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { inputEnabled }
    override var focusRingMaskBounds: NSRect { bounds }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if focusOnAppear, inputEnabled {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.focusOnAppear, self.inputEnabled else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 18, yRadius: 18).fill()
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        guard inputEnabled, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        if let command = TouchGestureInterpreter.clickCommand(clickCount: event.clickCount, activationOnly: activationOnly) { onCommand?(command) }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard inputEnabled, !activationOnly, event.modifierFlags.intersection([.command, .option, .shift]).isEmpty else {
            super.rightMouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        // Only the first event in a repeated secondary-click sequence replays.
        if event.clickCount == 1 { onCommand?(.replayLine) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard inputEnabled, !activationOnly, event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            super.scrollWheel(with: event)
            return
        }
        let phase: TouchGestureInterpreter.Phase
        if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.changed) { phase = .changed }
        else if event.phase.contains(.mayBegin) { phase = .mayBegin }
        else if event.phase.contains(.stationary) { phase = .stationary }
        else { phase = .none }
        let result = interpreter.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                        phase: phase, hasMomentum: !event.momentumPhase.isEmpty,
                                        precise: event.hasPreciseScrollingDeltas,
                                        inverted: event.isDirectionInvertedFromDevice,
                                        allowsSpeedGestures: allowsSpeedGestures)
        if let command = result.command {
            window?.makeFirstResponder(self)
            onCommand?(command)
        }
        if !result.shouldConsume { super.scrollWheel(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        guard inputEnabled else { super.keyDown(with: event); return }
        if let command = TouchGestureInterpreter.keyCommand(keyCode: event.keyCode,
                                                            characters: event.charactersIgnoringModifiers,
                                                            modifiers: event.modifierFlags,
                                                            isRepeat: event.isARepeat) {
            if !activationOnly || command == .exitTouchMode { onCommand?(command) }
        } else {
            // Leave tab navigation, VoiceOver shortcuts and application commands
            // on the normal responder chain. No key monitor touches text fields.
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard inputEnabled else { return false }
        onCommand?(activationOnly ? .enterTouchMode : .togglePlayback)
        return true
    }
}
