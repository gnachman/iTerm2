//
//  iTermSessionNameControllerFormattingTests.swift
//  ModernTests
//
//  iTermSessionNameController applies the tmux decoration in -formattedName: when
//  it evaluates, and publishes the formatted result. So when the formatting
//  descriptor changes but the base name does not -- which is exactly what happens
//  when a session acquires a tmux controller -- there is nothing to notice it. The
//  only route that would republish is a re-evaluation, and -setNeedsReevaluation
//  hops through the main queue, so the tab keeps the undecorated title until then.
//  -formattingDescriptorDidChange closes that window synchronously. Issue 13072.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermSessionNameControllerFormattingTests: XCTestCase {
    private let windowName = "editor"
    private let clientName = "default"

    private var prefix: String {
        return iTermAdvancedSettingsModel.tmuxTitlePrefix() ?? ""
    }

    /// Records what the controller publishes and lets a test change the formatting
    /// descriptor out from under it, the way -[PTYSession setTmuxController:] does.
    ///
    /// By default the delegate reports no title provider, which makes the controller
    /// evaluate to @"" without calling into the expression machinery. That keeps
    /// these tests synchronous and independent of the built-in title function. Set
    /// `uniqueIdentifier` to a provider that resolves to no invocation to get a
    /// non-empty cached base name instead (the controller caches `…` for one).
    private final class Delegate: NSObject, iTermSessionNameControllerDelegate, iTermObject {
        let scope = iTermVariableScope()
        var descriptor = iTermSessionFormattingDescriptor()
        var uniqueIdentifier: String?
        var onNameWillChange: (() -> Void)?
        private(set) var publishedPresentationNames = [String]()
        private(set) var publishedNames = [String]()

        override init() {
            super.init()
            scope.add(iTermVariables(context: [], owner: self), toScopeNamed: nil)
        }

        func sessionNameControllerNameWillChange(to newName: String!) {
            publishedNames.append(newName ?? "")
            onNameWillChange?()
        }

        func sessionNameControllerPresentationNameDidChange(to newName: String!) {
            publishedPresentationNames.append(newName ?? "")
        }

        func sessionNameControllerDidChangeWindowTitle() {
        }

        func sessionNameControllerFormattingDescriptor() -> iTermSessionFormattingDescriptor! {
            return descriptor
        }

        func sessionNameControllerScope() -> iTermVariableScope! {
            return scope
        }

        func sessionNameControllerUniqueIdentifier() -> String! {
            return uniqueIdentifier
        }

        func sessionNameControllerShouldSuppressEmptyTitle() -> Bool {
            return false
        }

        // MARK: - iTermObject

        func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
        func objectScope() -> iTermVariableScope? { nil }
    }

    private var controller: iTermSessionNameController!
    private var delegate: Delegate!

    /// Leaves the controller in the state a tmux window's sessions are in when
    /// +[PTYTab tabWithArrangement:] finishes: a title has been evaluated and
    /// published with no tmux formatting, because the tmux controllers are only
    /// installed afterwards, by -[PseudoTerminal loadTmuxLayout:...].
    override func setUp() {
        super.setUp()
        delegate = Delegate()
        controller = iTermSessionNameController()
        // -setDelegate: evaluates and publishes.
        controller.delegate = delegate
        XCTAssertEqual(controller.presentationSessionTitle, "",
                       "test setup: a title has been evaluated, with no tmux formatting")
        XCTAssertFalse(delegate.publishedPresentationNames.isEmpty,
                       "test setup: that title has been published")
    }

    private func tmuxDescriptor() -> iTermSessionFormattingDescriptor {
        let descriptor = iTermSessionFormattingDescriptor()
        descriptor.haveTmuxController = true
        descriptor.tmuxWindowName = windowName
        return descriptor
    }

    /// What a test's own call published, ignoring whatever setUp left behind.
    private func publishedSinceSetup(_ body: () -> Void) -> [String] {
        let before = delegate.publishedPresentationNames.count
        body()
        return Array(delegate.publishedPresentationNames.dropFirst(before))
    }

    // MARK: - Tests

    /// The regression. Acquiring a tmux controller changes the descriptor, and the
    /// already-published presentation name has to be reissued with the decoration --
    /// synchronously, or the tab bar draws the bare name first.
    func testDescriptorChangePublishesDecoratedName() {
        delegate.descriptor = tmuxDescriptor()

        let published = publishedSinceSetup {
            controller.formattingDescriptorDidChange()
        }

        XCTAssertEqual(published, ["\(prefix)\(windowName)"],
                       "exactly one decorated title, published without a runloop hop")
        XCTAssertEqual(controller.presentationSessionTitle, "\(prefix)\(windowName)",
                       "what was published must be what the controller now reports")
    }

    /// A tmux gateway session decorates differently. The republish has to use
    /// whatever -formattedName: produces now, not a hardcoded tmux shape.
    func testDescriptorChangeUsesGatewayFormatting() {
        let descriptor = iTermSessionFormattingDescriptor()
        descriptor.isTmuxGateway = true
        descriptor.tmuxClientName = clientName
        delegate.descriptor = descriptor

        let published = publishedSinceSetup {
            controller.formattingDescriptorDidChange()
        }

        XCTAssertEqual(published, ["[\(prefix) \(clientName)]"])
    }

    /// Detaching is the same problem in reverse: the decoration has to come back off.
    func testDescriptorChangeBackToPlainPublishesUndecoratedName() {
        delegate.descriptor = tmuxDescriptor()
        controller.formattingDescriptorDidChange()
        XCTAssertEqual(controller.presentationSessionTitle, "\(prefix)\(windowName)")

        delegate.descriptor = iTermSessionFormattingDescriptor()
        let published = publishedSinceSetup {
            controller.formattingDescriptorDidChange()
        }

        XCTAssertEqual(published, [""],
                       "losing the tmux controller must republish the undecorated title")
    }

    /// A synchronous evaluation must publish the same way the asynchronous one
    /// does. The async arm of -evaluateInvocationSynchronously:sideEffectsAllowed:
    /// completion: calls -didEvaluateInvocationWithResult:, which applies
    /// -formattedName: and sets the session's name variable; the sync arm used to
    /// hand the raw cached evaluation straight to the delegate instead, so a tmux
    /// session lost its decoration and session.name went stale until an async
    /// evaluation landed. -setNeedsUpdate does one synchronous pass and then hops
    /// through the main queue, so nothing here spins the runloop: what is asserted
    /// is purely the synchronous pass.
    func testSynchronousEvaluationPublishesFormattedNameAndSetsSessionName() {
        // The built-in provider resolves to a real invocation, which is what gets
        // the sync pass past the early returns and into the arm under test. The
        // call fails here (no such session), and the failure placeholder is what
        // gets published -- the exact text doesn't matter, only that it is
        // formatted and mirrored onto the name variable.
        let delegate = Delegate()
        delegate.uniqueIdentifier = iTermSessionNameControllerSystemTitleUniqueIdentifier
        let descriptor = iTermSessionFormattingDescriptor()
        descriptor.isTmuxGateway = true
        descriptor.tmuxClientName = clientName
        delegate.descriptor = descriptor

        let controller = iTermSessionNameController()
        controller.delegate = delegate

        // -updateIfNeeded runs the synchronous pass and then the asynchronous one,
        // and the asynchronous one completes inline here because the failing
        // lookup returns without ever leaving the stack. So the FIRST publish is
        // the synchronous pass -- the one under test. Asserting on the last would
        // pass either way, since the asynchronous arm has always formatted
        // correctly and would paper over an unformatted first publish.
        guard let first = delegate.publishedPresentationNames.first else {
            XCTFail("the synchronous evaluation published nothing")
            return
        }
        XCTAssertTrue(first.hasPrefix("[") && first.hasSuffix("]"),
                      "the gateway decoration must be applied by the synchronous pass too: \(first)")
        XCTAssertTrue(first.contains(clientName),
                      "the gateway decoration names the client: \(first)")
        XCTAssertEqual(first, controller.presentationSessionTitle,
                       "what the synchronous pass published must be what the controller reports")

        // Every publish must also mirror the undecorated base name onto the
        // session's name variable; the synchronous pass used to skip that.
        XCTAssertEqual(delegate.publishedNames.count,
                       delegate.publishedPresentationNames.count,
                       "each published presentation name must come with a name-variable update")
        XCTAssertFalse(delegate.publishedNames[0].hasPrefix("["),
                       "the name variable takes the undecorated base name")
    }

    /// With a title provider configured -- which is every real session, since the
    /// built-in provider has one too -- -formattedName: decorates the *cached base
    /// name* rather than the tmux window name. That is the branch production takes,
    /// so pin that the republish goes through it and leaves the base name alone.
    func testDecorationIsAppliedToTheCachedBaseName() {
        // A provider id that resolves to no invocation, so the controller caches its
        // unregistered-provider placeholder as the base name without any RPC.
        let unregisteredProviderPlaceholder = "\u{2026}"
        let delegate = Delegate()
        delegate.uniqueIdentifier = "com.example.no-such-title-provider"
        let controller = iTermSessionNameController()
        controller.delegate = delegate
        XCTAssertEqual(controller.presentationSessionTitle, unregisteredProviderPlaceholder,
                       "test setup: a non-empty base name is cached")

        delegate.descriptor = tmuxDescriptor()
        controller.formattingDescriptorDidChange()

        XCTAssertEqual(delegate.publishedPresentationNames.last,
                       "\(prefix)\(unregisteredProviderPlaceholder)",
                       "the prefix must decorate the cached base name, not replace it")
        XCTAssertNotEqual(delegate.publishedPresentationNames.last, "\(prefix)\(windowName)",
                          "the tmux-window-name branch is only for sessions with no title provider")
    }

    /// The completion of an evaluation whose base name did not change used to
    /// return before publishing, so a reevaluation scheduled by an observed tmux
    /// variable (the route the recording scope already provides) could not carry a
    /// descriptor change to the tab. It has to republish when only the formatting
    /// changed, without anyone calling -formattingDescriptorDidChange.
    ///
    /// This needs the built-in provider: with no provider at all the controller
    /// short-circuits through -didEvaluateInvocationWithResult: and never reaches
    /// the completion's unchanged arm.
    func testReevaluationWithUnchangedBaseNamePublishesNewFormatting() {
        let delegate = Delegate()
        delegate.uniqueIdentifier = iTermSessionNameControllerSystemTitleUniqueIdentifier
        let controller = iTermSessionNameController()
        controller.delegate = delegate
        let baseName = controller.presentationSessionTitle ?? ""
        XCTAssertFalse(baseName.isEmpty, "test setup: a base name is cached")

        let tmux = tmuxDescriptor()
        tmux.tmuxWindowName = nil   // the built-in provider decorates the base name
        delegate.descriptor = tmux

        let presentationCountBefore = delegate.publishedPresentationNames.count
        let nameCountBefore = delegate.publishedNames.count
        controller.setNeedsUpdate()

        XCTAssertEqual(Array(delegate.publishedPresentationNames.dropFirst(presentationCountBefore)),
                       ["\(prefix)\(baseName)"],
                       "the synchronous pass must publish the decorated name once")
        XCTAssertEqual(delegate.publishedNames.count, nameCountBefore,
                       "the base name did not change, so the name variable is not rewritten")
    }

    /// An observer of the session's name variable may read a title accessor from
    /// inside the publish callback (the window title format does). That read must
    /// not start a nested evaluation: the cache is current, and a flagged
    /// reevaluation belongs to the main-queue hop.
    func testTitleReadDuringPublishDoesNotNestAnEvaluation() {
        let delegate = Delegate()
        delegate.uniqueIdentifier = iTermSessionNameControllerSystemTitleUniqueIdentifier
        let controller = iTermSessionNameController()
        // -setNeedsUpdate below evaluates synchronously while the reevaluation
        // flagged by the registration is still pending, so this read would find
        // -updateIfNeeded willing to evaluate again.
        delegate.onNameWillChange = { [unowned controller] in
            _ = controller.presentationSessionTitle
        }
        controller.delegate = delegate
        controller.perform(NSSelectorFromString("didRegisterSessionTitleFunc:"), with: nil)

        let presentationCountBefore = delegate.publishedPresentationNames.count
        let nameCountBefore = delegate.publishedNames.count
        controller.setNeedsUpdate()

        XCTAssertEqual(delegate.publishedPresentationNames.count - presentationCountBefore, 1,
                       "a title read from inside the publish must not publish again: \(delegate.publishedPresentationNames)")
        XCTAssertEqual(delegate.publishedNames.count - nameCountBefore, 1)
    }

    /// Republishing on a descriptor change is only useful when the formatted name
    /// actually differs. -[PseudoTerminal loadTmuxLayout:...] installs a controller
    /// on every pane of every window, so an unconditional republish would run the
    /// delegate's full publish path (notifications, presentationName variable,
    /// badge) once per pane even when nothing visible changed.
    func testDescriptorChangeWithSameFormattedNameDoesNotRepublish() {
        delegate.descriptor = tmuxDescriptor()
        controller.formattingDescriptorDidChange()
        XCTAssertEqual(controller.presentationSessionTitle, "\(prefix)\(windowName)",
                       "test setup: the decorated name has been published once")

        let published = publishedSinceSetup {
            controller.formattingDescriptorDidChange()
        }

        XCTAssertEqual(published, [],
                       "a descriptor change that leaves the formatted name alone must not republish")
    }

    /// Publishing must not re-enter the evaluation machinery. The publish path used
    /// to read -presentationSessionTitle, which calls -updateIfNeeded first; from
    /// inside a synchronous evaluation's completion, with a reevaluation already
    /// flagged, that started a nested asynchronous evaluation and published twice
    /// for one change. The flagged reevaluation belongs to the main-queue hop that
    /// -setNeedsReevaluation scheduled, and this test never spins the runloop, so
    /// exactly one publish is the synchronous pass under test.
    func testSynchronousPublishDoesNotStartANestedEvaluation() {
        let delegate = Delegate()
        delegate.uniqueIdentifier = iTermSessionNameControllerSystemTitleUniqueIdentifier
        let controller = iTermSessionNameController()
        controller.delegate = delegate

        // Drop the cache and flag a reevaluation without spinning the runloop: this
        // is what the controller does when a title provider registers. The next
        // synchronous pass therefore sees a changed result and takes its publish
        // arm with a reevaluation still pending. Call the handler on this one
        // controller rather than posting iTermAPIDidRegisterSessionTitleFunction:
        // every live name controller observes that with object:nil, and a
        // broadcast would reset controllers belonging to other tests.
        controller.perform(NSSelectorFromString("didRegisterSessionTitleFunc:"), with: nil)

        let presentationCountBefore = delegate.publishedPresentationNames.count
        let nameCountBefore = delegate.publishedNames.count
        controller.setNeedsUpdate()

        XCTAssertEqual(delegate.publishedPresentationNames.count - presentationCountBefore, 1,
                       "one synchronous pass must publish exactly once: \(delegate.publishedPresentationNames)")
        XCTAssertEqual(delegate.publishedNames.count - nameCountBefore, 1,
                       "and set the name variable exactly once")
    }
}
