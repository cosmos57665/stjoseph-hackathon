import AppKit
import SwiftUI

enum DrawingCommand: Equatable {
    case dot, dash, finishLetter, space, undo, review, send, returnToPDF, exit
    case toggleAnswer, nextAnswer, previousAnswer, faster, slower, replayAnswer, newQuestion
}

struct MorseDrawingSurface: NSViewRepresentable {
    var handwriting = false
    let phase: AskAIModel.Phase
    let value: String
    let onStroke: ([CGPoint]) -> Void
    let onPreview: ([CGPoint]) -> Void
    let onCommand: (DrawingCommand) -> Void
    func makeNSView(context: Context) -> MorseDrawingNSView { let view = MorseDrawingNSView(); configure(view); return view }
    func updateNSView(_ view: MorseDrawingNSView, context: Context) { configure(view) }
    private func configure(_ view: MorseDrawingNSView) {
        view.handwriting = handwriting; view.phase = phase; view.onStroke = onStroke; view.onPreview = onPreview; view.onCommand = onCommand
        view.setAccessibilityValue(value)
        view.setAccessibilityLabel(handwriting ? "Write to communicate" : "Draw Morse to ask AI")
        if handwriting { view.setAccessibilityHelp("Print one letter using one finger. Lift between strokes. Two-finger swipe right saves the letter, up adds space, left undoes, down reviews recognized text. Physical click transcribes, then another click asks AI. Escape releases the pointer.") }
    }
}

/// Raw short touches enter dots; strokes enter dashes. Only a mouse click
/// accompanied by an actual Force Touch pressure event can submit, so macOS
/// Tap to click cannot turn a Morse dot into a network request.
final class MorseDrawingNSView: NSView {
    var handwriting = false
    var phase: AskAIModel.Phase = .composing { didSet { if oldValue != phase { resetStroke(); interpreter.reset() } } }
    var onStroke: (([CGPoint]) -> Void)?
    var onPreview: (([CGPoint]) -> Void)?
    var onCommand: ((DrawingCommand) -> Void)?
    private var identity: (NSCopying & NSObjectProtocol)?
    private var points: [CGPoint] = []
    private var gestureBlocked = false
    private var buttonDown = false
    private var validSendClick = false
    private var contactStarted: TimeInterval = 0
    private var pressureSeen = false
    private var contactWasPressed = false
    private var pressHadMovement = false
    private var touchCount = 0
    private var interpreter = TouchGestureInterpreter()

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = true
        pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryClick)
        focusRingType = .none
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("Draw Morse to ask AI")
        setAccessibilityHelp("Tap lightly for dot or draw a horizontal stroke for dash. Two-finger swipe right finishes a letter, up adds a space, left undoes, down reviews. Physically press to click once and send. Secondary click returns to the PDF. Escape releases the pointer.")
        let commands: [(String, DrawingCommand)] = [("Dot", .dot), ("Dash", .dash), ("Finish letter", .finishLetter), ("Word space", .space), ("Undo", .undo), ("Review question", .review), ("Send question", .send), ("Return to PDF", .returnToPDF)]
        setAccessibilityCustomActions(commands.map { label, command in
            NSAccessibilityCustomAction(name: label) { [weak self] in self?.onCommand?(command); return self != nil }
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self) }
    }

    private func resetStroke() {
        identity = nil; points = []; gestureBlocked = false; buttonDown = false; validSendClick = false
        pressureSeen = false; contactWasPressed = false; pressHadMovement = false
        touchCount = 0
    }
    private var strokeMoved: Bool { points.first.map { first in points.contains { hypot($0.x - first.x, $0.y - first.y) > 0.02 } } ?? false }
    private func activeTouches(_ event: NSEvent) -> Set<NSTouch> {
        let touches = event.touches(matching: .touching, in: self).filter { $0.type == .indirect }
        touchCount = touches.count
        return touches
    }
    private func point(_ touch: NSTouch) -> CGPoint {
        // Preserve the physical aspect ratio for circles and horizontal strokes.
        CGPoint(x: touch.normalizedPosition.x, y: touch.normalizedPosition.y * touch.deviceSize.height / max(1, touch.deviceSize.width))
    }
    private func append(_ point: CGPoint) {
        guard points.count < 2000 else { return }
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 0.001 { return }
        points.append(point); onPreview?(points)
    }
    private func blockGesture() { identity = nil; points = []; gestureBlocked = true; validSendClick = false; onPreview?([]) }

    override func touchesBegan(with event: NSEvent) {
        guard phase == .composing else { return }
        let touches = activeTouches(event)
        if touches.count > 1 { blockGesture(); return }
        guard !gestureBlocked, !contactWasPressed, identity == nil, let touch = touches.first else { return }
        contactStarted = event.timestamp
        identity = touch.identity; points = []; append(point(touch))
    }
    override func touchesMoved(with event: NSEvent) {
        guard phase == .composing else { return }
        let touches = activeTouches(event)
        if touches.count > 1 { blockGesture(); return }
        guard !gestureBlocked, !contactWasPressed, let identity,
              let touch = touches.first(where: { $0.identity.isEqual(identity) }) else { return }
        append(point(touch))
    }
    override func touchesEnded(with event: NSEvent) {
        guard phase == .composing else { return }
        if !gestureBlocked, !contactWasPressed, let identity,
           let touch = event.touches(matching: .ended, in: self).first(where: { $0.identity.isEqual(identity) }) {
            append(point(touch))
            let finished = points
            self.identity = nil; points = []
            if handwriting { onStroke?(finished) }
            else if DrawnMorse.isTap(finished, duration: event.timestamp - contactStarted) { onCommand?(.dot) }
            else if let first = finished.first, finished.contains(where: { hypot($0.x - first.x, $0.y - first.y) > 0.02 }) { onStroke?(finished) }
        }
        if activeTouches(event).isEmpty {
            identity = nil; points = []; gestureBlocked = false
            contactWasPressed = false; pressHadMovement = false
        }
    }
    override func touchesCancelled(with event: NSEvent) { blockGesture(); if activeTouches(event).isEmpty { gestureBlocked = false } }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { super.mouseDown(with: event); return }
        window?.makeFirstResponder(self)
        if phase == .answer {
            if event.clickCount == 2 { onCommand?(.toggleAnswer) }
            if event.clickCount == 3 { onCommand?(.newQuestion) }
            return
        }
        guard phase == .composing else { return }
        // Pressing in the middle of drawing cancels that stroke, never submits it.
        validSendClick = !strokeMoved && !pressHadMovement && !gestureBlocked
        buttonDown = true
    }
    override func mouseUp(with event: NSEvent) {
        let send = buttonDown && validSendClick && pressureSeen && phase == .composing
        buttonDown = false; validSendClick = false; pressureSeen = false
        if touchCount == 0 { gestureBlocked = false; contactWasPressed = false; pressHadMovement = false }
        if send { onCommand?(.send) }
    }
    override func pressureChange(with event: NSEvent) { receivedPressure(stage: event.stage) }

    // Kept separate so event-order cases can be tested without driving hardware.
    func receivedPressure(stage: Int) {
        guard phase == .composing, stage >= 1 else { return }
        if !contactWasPressed { pressHadMovement = strokeMoved || gestureBlocked }
        pressureSeen = true; contactWasPressed = true
        if pressHadMovement { validSendClick = false }
        identity = nil; points = []; onPreview?([])
    }
    override func rightMouseDown(with event: NSEvent) {
        guard event.clickCount == 1 else { return }
        blockGesture(); onCommand?(.returnToPDF)
    }

    static func command(for gesture: TouchCommand, phase: AskAIModel.Phase) -> DrawingCommand? {
        switch (phase, gesture) {
        case (.composing, .previousLine): return .finishLetter // physical right
        case (.composing, .nextLine): return .undo
        case (.composing, .faster): return .space
        case (.composing, .slower): return .review
        case (.answer, .previousLine): return .previousAnswer
        case (.answer, .nextLine): return .nextAnswer
        case (.answer, .faster): return .faster
        case (.answer, .slower): return .slower
        default: return nil
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return }
        // A swipe always cancels the incidental one-finger stroke that preceded it.
        if !event.phase.isEmpty { blockGesture() }
        let p: TouchGestureInterpreter.Phase
        if event.phase.contains(.cancelled) { p = .cancelled }
        else if event.phase.contains(.began) { p = .began }
        else if event.phase.contains(.ended) { p = .ended }
        else if event.phase.contains(.changed) { p = .changed }
        else if event.phase.contains(.mayBegin) { p = .mayBegin }
        else { p = .none }
        let result = interpreter.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, phase: p,
                                        hasMomentum: !event.momentumPhase.isEmpty, precise: event.hasPreciseScrollingDeltas,
                                        inverted: event.isDirectionInvertedFromDevice)
        if let gesture = result.command, let command = Self.command(for: gesture, phase: phase) { onCommand?(command) }
        if p == .ended || p == .cancelled { gestureBlocked = touchCount > 0 }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
        if event.keyCode == 53 { onCommand?(.exit); return }
        if phase == .composing {
            switch event.keyCode {
            case 36, 76: onCommand?(.send)
            case 124, 49: onCommand?(.finishLetter)
            case 126: onCommand?(.space)
            case 123, 51: onCommand?(.undo)
            case 125: onCommand?(.review)
            default:
                if event.characters == "." { onCommand?(.dot) }
                else if event.characters == "-" { onCommand?(.dash) }
                else { super.keyDown(with: event) }
            }
        } else if phase == .answer {
            switch event.keyCode {
            case 49: onCommand?(.toggleAnswer)
            case 124: onCommand?(.nextAnswer)
            case 123: onCommand?(.previousAnswer)
            case 126: onCommand?(.faster)
            case 125: onCommand?(.slower)
            default:
                if event.charactersIgnoringModifiers?.lowercased() == "r" { onCommand?(.replayAnswer) }
                else if event.charactersIgnoringModifiers?.lowercased() == "a" { onCommand?(.newQuestion) }
                else { super.keyDown(with: event) }
            }
        }
    }
}
