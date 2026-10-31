//
//  LayoutEngineTestSupport.swift
//  ModernTests
//
//  Terminal windows are laid out by hand, and engaging AppKit's layout engine
//  in one has made windows impossible to shrink (issue 13118). These helpers
//  engage the engine on purpose, read the minimum size it enforces, and record
//  constraints it has to break, so tests can check that nothing in a window
//  depends on the engine staying off.
//

import XCTest
@testable import iTerm2SharedARC

enum LayoutEngineTestSupport {
    // Marks the view that engages the engine so layout comparisons can skip it.
    static let engagingViewIdentifier = NSUserInterfaceItemIdentifier("LayoutEngineTestSupport.engagingView")

    // Whether to engage the engine in every window TerminalWindowTestFixture
    // opens. Set ITERM2_ENGAGE_LAYOUT_ENGINE=1 in the test process:
    //
    //   TEST_RUNNER_ITERM2_ONSCREEN_TESTS=1 TEST_RUNNER_ITERM2_ENGAGE_LAYOUT_ENGINE=1 tools/run_tests.expect ...
    static var engageInEveryFixtureWindow: Bool {
        return ProcessInfo.processInfo.environment["ITERM2_ENGAGE_LAYOUT_ENGINE"] == "1"
    }

    // The minimum size AppKit derives from constraints and clamps resizes to,
    // programmatic ones included. It is not reflected in -minSize.
    static func constrainedMinSize(of window: NSWindow) -> NSSize {
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSSize>, UnsafeMutablePointer<NSSize>) -> Void
        let sel = NSSelectorFromString("_getConstrainedWindowMinSize:maxSize:")
        guard let method = class_getInstanceMethod(type(of: window), sel) else {
            it_fatalError("No \(sel)")
        }
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        var minSize = NSSize.zero
        var maxSize = NSSize.zero
        window.layoutIfNeeded()
        fn(window, sel, &minSize, &maxSize)
        return minSize
    }

    // The title bar and anything AppKit puts in it, such as a tab bar
    // accessory. A window cannot be shorter than this with or without the
    // engine.
    static func titleBarHeight(of window: NSWindow) -> CGFloat {
        return NSHeight(window.frame) - NSHeight(window.contentLayoutRect)
    }

    static func engineEngaged(in window: NSWindow) -> Bool {
        return window.value(forKey: "_layoutEngineIfAvailable") != nil
    }

    // Engages the engine the way a real feature would: a hidden glass view
    // where it exists (it uses constraints internally), otherwise a view with
    // constraints of its own.
    static func engage(in window: NSWindow) {
        guard let contentView = window.contentView else {
            it_fatalError("No content view")
        }
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            glass.identifier = engagingViewIdentifier
            glass.isHidden = true
            contentView.addSubview(glass)
        } else {
            let probe = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            probe.identifier = engagingViewIdentifier
            probe.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(probe)
            NSLayoutConstraint.activate([
                probe.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                probe.topAnchor.constraint(equalTo: contentView.topAnchor),
                probe.widthAnchor.constraint(equalToConstant: 1),
                probe.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        window.layoutIfNeeded()
        it_assert(engineEngaged(in: window), "Failed to engage the layout engine")
    }

    // Records constraints the layout engine breaks because they cannot all be
    // satisfied, by wrapping the engine delegate methods on NSWindow and NSView
    // (the engine is hosted by one or the other). AppKit reports each
    // constraint only the first time it breaks.
    final class BrokenConstraintRecorder {
        private static var current: BrokenConstraintRecorder?
        private(set) var constraints = [String]()
        private var restorers = [() -> Void]()

        init() {
            let sel = NSSelectorFromString("engine:willBreakConstraint:dueToMutuallyExclusiveConstraints:")
            typealias Fn = @convention(c) (AnyObject, Selector, AnyObject, NSLayoutConstraint, NSArray) -> Void
            Self.current = self
            for cls in [NSWindow.self, NSView.self] as [AnyClass] {
                guard let method = class_getInstanceMethod(cls, sel) else {
                    it_fatalError("No \(sel) on \(cls)")
                }
                let original = unsafeBitCast(method_getImplementation(method), to: Fn.self)
                let block: @convention(block) (AnyObject, AnyObject, NSLayoutConstraint, NSArray) -> Void = { receiver, engine, constraint, others in
                    BrokenConstraintRecorder.current?.constraints.append(constraint.description)
                    original(receiver, sel, engine, constraint, others)
                }
                let previous = method_setImplementation(method, imp_implementationWithBlock(block))
                restorers.append {
                    method_setImplementation(method, previous)
                }
            }
        }

        func reset() {
            constraints.removeAll()
        }

        func stop() {
            restorers.forEach { $0() }
            restorers.removeAll()
            if Self.current === self {
                Self.current = nil
            }
        }

        deinit {
            stop()
        }
    }
}
