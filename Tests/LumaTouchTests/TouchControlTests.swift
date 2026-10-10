import AppKit

@MainActor final class TouchControlTests {
    func run() {
        testClickAndActivationCommands()
        testKeyboardCommandsRespectModifiers()
        testSwipeDirectionIgnoresNaturalScrollingPreference()
        testOneCommandPerPhysicalGesture()
        testAccidentalInputAndCancellation()
        testNativeSurfaceRoutesWithoutGlobalInput()
    }

    private func testClickAndActivationCommands() {
        expectNil(TouchGestureInterpreter.clickCommand(clickCount: 1))
        expectEqual(TouchGestureInterpreter.clickCommand(clickCount: 2), .togglePlayback)
        expectNil(TouchGestureInterpreter.clickCommand(clickCount: 3))
        expectNil(TouchGestureInterpreter.clickCommand(clickCount: 4))
        for count in [0, 1, 2, 4] {
            expectNil(TouchGestureInterpreter.clickCommand(clickCount: count, activationOnly: true))
        }
        expectEqual(TouchGestureInterpreter.clickCommand(clickCount: 3, activationOnly: true), .enterTouchMode)
    }

    private func testKeyboardCommandsRespectModifiers() {
        let commands: [(UInt16, String?, TouchCommand)] = [
            (49, " ", .togglePlayback), (123, nil, .previousLine), (124, nil, .nextLine),
            (125, nil, .slower), (126, nil, .faster), (53, nil, .exitTouchMode), (15, "r", .replayLine)
        ]
        for (code, characters, command) in commands {
            expectEqual(TouchGestureInterpreter.keyCommand(keyCode: code, characters: characters,
                                                           modifiers: [], isRepeat: false), command)
            expectNil(TouchGestureInterpreter.keyCommand(keyCode: code, characters: characters,
                                                         modifiers: [], isRepeat: true))
            for modifier: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
                expectNil(TouchGestureInterpreter.keyCommand(keyCode: code, characters: characters,
                                                             modifiers: modifier, isRepeat: false))
            }
        }
        // Arrow events can legitimately carry function/numeric-pad flags.
        expectEqual(TouchGestureInterpreter.keyCommand(keyCode: 124, characters: nil,
                                                       modifiers: [.function, .numericPad], isRepeat: false), .nextLine)
        expectNil(TouchGestureInterpreter.keyCommand(keyCode: 0, characters: "a", modifiers: [], isRepeat: false))
        expectEqual(TouchGestureInterpreter.keyCommand(keyCode: 15, characters: "R", modifiers: .capsLock, isRepeat: false), .replayLine)
    }

    private func testSwipeDirectionIgnoresNaturalScrollingPreference() {
        for inverted in [false, true] {
            let sign = inverted ? -1.0 : 1.0
            let swipes: [(Double, Double, TouchCommand)] = [
                (60, 0, .nextLine), (-60, 0, .previousLine), (0, 60, .faster), (0, -60, .slower)
            ]
            for (x, y, expected) in swipes {
                var input = TouchGestureInterpreter()
                let result = input.scroll(deltaX: x * sign, deltaY: y * sign, phase: .began,
                                          hasMomentum: false, precise: true, inverted: inverted)
                expectEqual(result.command, expected)
                expectTrue(result.shouldConsume)
            }
        }
    }

    private func testOneCommandPerPhysicalGesture() {
        var input = TouchGestureInterpreter()
        expectNil(input.scroll(deltaX: 20, deltaY: 2, phase: .began,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectEqual(input.scroll(deltaX: 30, deltaY: 0, phase: .changed,
                                 hasMomentum: false, precise: true, inverted: false).command, .nextLine)
        expectNil(input.scroll(deltaX: 200, deltaY: 0, phase: .changed,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: -500, deltaY: 0, phase: .changed,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: 0, deltaY: 0, phase: .ended,
                               hasMomentum: false, precise: true, inverted: false).command)
        let momentum = input.scroll(deltaX: 500, deltaY: 0, phase: .none,
                                    hasMomentum: true, precise: true, inverted: false)
        expectNil(momentum.command)
        expectTrue(momentum.shouldConsume)
        expectEqual(input.scroll(deltaX: -60, deltaY: 0, phase: .began,
                                 hasMomentum: false, precise: true, inverted: false).command, .previousLine)

        var speed = TouchGestureInterpreter()
        expectEqual(speed.scroll(deltaX: 0, deltaY: 60, phase: .began,
                                 hasMomentum: false, precise: true, inverted: false).command, .faster)
        expectNil(speed.scroll(deltaX: 0, deltaY: 200, phase: .changed,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(speed.scroll(deltaX: 0, deltaY: 0, phase: .ended,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(speed.scroll(deltaX: 0, deltaY: 300, phase: .none,
                               hasMomentum: true, precise: true, inverted: false).command)
    }

    private func testAccidentalInputAndCancellation() {
        var input = TouchGestureInterpreter()
        let wheel = input.scroll(deltaX: 100, deltaY: 0, phase: .none,
                                 hasMomentum: false, precise: false, inverted: false)
        expectNil(wheel.command)
        expectFalse(wheel.shouldConsume)
        expectNil(input.scroll(deltaX: 100, deltaY: 0, phase: .none,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: 100, deltaY: 0, phase: .changed,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: 3, deltaY: 2, phase: .began,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: 100, deltaY: 0, phase: .cancelled,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: 100, deltaY: 0, phase: .changed,
                               hasMomentum: false, precise: true, inverted: false).command)
        expectNil(input.scroll(deltaX: 100, deltaY: 100, phase: .began,
                               hasMomentum: false, precise: true, inverted: false).command)

        var vertical = TouchGestureInterpreter()
        let start = vertical.scroll(deltaX: 2, deltaY: 15, phase: .began,
                                    hasMomentum: false, precise: true, inverted: false,
                                    allowsSpeedGestures: false)
        expectNil(start.command)
        expectFalse(start.shouldConsume)
        let continued = vertical.scroll(deltaX: 100, deltaY: 80, phase: .changed,
                                        hasMomentum: false, precise: true, inverted: false,
                                        allowsSpeedGestures: false)
        expectNil(continued.command)
        expectFalse(continued.shouldConsume)
        vertical.reset()
        expectEqual(vertical.scroll(deltaX: 60, deltaY: 0, phase: .began,
                                    hasMomentum: false, precise: true, inverted: false).command, .nextLine)
    }

    private func testNativeSurfaceRoutesWithoutGlobalInput() {
        let view = TouchControlNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        var commands: [TouchCommand] = []
        view.onCommand = { commands.append($0) }
        for count in 1...4 { view.mouseDown(with: mouseEvent(.leftMouseDown, count: count)) }
        expectEqual(commands, [.togglePlayback])
        view.rightMouseDown(with: mouseEvent(.rightMouseDown, count: 1))
        view.rightMouseDown(with: mouseEvent(.rightMouseDown, count: 2))
        expectEqual(commands, [.togglePlayback, .replayLine])
        view.keyDown(with: keyEvent(49, characters: " "))
        expectEqual(commands.last, .togglePlayback)

        commands = []
        view.activationOnly = true
        for count in 1...4 { view.mouseDown(with: mouseEvent(.leftMouseDown, count: count)) }
        expectEqual(commands, [.enterTouchMode])
        view.keyDown(with: keyEvent(49, characters: " "))
        expectEqual(commands, [.enterTouchMode, .enterTouchMode])
        view.keyDown(with: keyEvent(53, characters: "\u{1B}"))
        expectEqual(commands.last, .exitTouchMode)
        expectTrue(view.accessibilityPerformPress())
        expectEqual(commands.last, .enterTouchMode)
        commands = []
        view.inputEnabled = false
        expectFalse(view.accessibilityPerformPress())
        expectTrue(commands.isEmpty)
        expectFalse(view.acceptsFirstResponder)
    }

    private func mouseEvent(_ type: NSEvent.EventType, count: Int) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: count, clickCount: count, pressure: 0)!
    }

    private func keyEvent(_ code: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: 0, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }
}
