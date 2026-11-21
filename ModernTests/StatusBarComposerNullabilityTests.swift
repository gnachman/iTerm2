//
//  StatusBarComposerNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims of the status bar and the composer that
//  the nullability sanitizer found false (unit N8 of
//  docs/swift-migration/nullability-triage.md). The Objective-C code accepts
//  or produces nil by design; these tests pin what Swift sees. Claims in
//  headers Swift cannot see are pinned in StatusBarNullabilityTests.m.
//

import XCTest
@testable import iTerm2SharedARC

final class CPUUtilizationNullabilityTests: XCTestCase {
    // PTYSession asks for the tmux gateway session's instance, and the gateway
    // session can be missing. The body returns nil for a nil ID, so the
    // returned instance is optional too.
    func testNilSessionIDHasNoInstance() {
        XCTAssertNil(iTermCPUUtilization.instance(forSessionID: nil))
    }

    func testSessionIDHasAnInstance() {
        let sessionID = "nullability-test-" + UUID().uuidString
        defer {
            iTermCPUUtilization.setInstance(nil, forSessionID: sessionID)
        }
        XCTAssertNotNil(iTermCPUUtilization.instance(forSessionID: sessionID))
    }
}

final class GitStateNullabilityTests: XCTestCase {
    // -initWithScope: returns nil when a git variable is not set in the scope.
    // While it was claimed nonnull, Swift held that nil as a non-optional
    // object; the initializer is failable now.
    func testInitWithScopeMissingGitVariablesIsNil() {
        XCTAssertNil(iTermGitState(scope: iTermVariableScope()))
    }
}

final class StatusBarComponentNullabilityTests: XCTestCase {
    // A component made without an advanced configuration has no background
    // color. Making it also passes a nil dictionary to
    // +advancedConfigurationFromDictionary:, which reads it like an empty one.
    func testBaseComponentWithoutAdvancedConfigurationHasNoBackgroundColor() {
        let component = iTermStatusBarBaseComponent(configuration: [:], scope: nil)
        XCTAssertNil(component.statusBarBackgroundColor)
    }

    func testAdvancedConfigurationFromNilDictionaryIsEmpty() {
        let configuration = iTermStatusBarAdvancedConfiguration(from: nil)
        XCTAssertNil(configuration.backgroundColor)
        XCTAssertNil(configuration.separatorColor)
        XCTAssertNil(configuration.defaultTextColor)
        XCTAssertFalse(configuration.removeEmptyComponents)
    }

    // A layout made without a scope hands the nil scope to each component,
    // which accepts it.
    func testLayoutFromDictionaryWithoutScopeMakesItsComponents() {
        let component = iTermStatusBarBaseComponent(configuration: [.knobValues: [String: Any]()], scope: nil)
        let template = iTermStatusBarLayout(components: [component],
                                            advancedConfiguration: iTermStatusBarAdvancedConfiguration())
        let layout = iTermStatusBarLayout(dictionary: template.dictionaryValue(), scope: nil)
        XCTAssertEqual(layout.components.count, 1)
    }

    // The next claims need a live view controller, session or composer to
    // call, and their bodies only return a lookup or forward the value, so
    // they are pinned at compile time: guard let needs an optional, and nil
    // can only be passed to an optional parameter.
    func testOptionalClaimsCompile() {
        let fullStringLength: (iTermStatusBarVariableBaseComponent) -> Int = { component in
            guard let string = component.fullString else {
                return 0
            }
            return string.count
        }
        let haveFindViewControllers: (iTermStatusBarViewController) -> Bool = { viewController in
            guard let search = viewController.searchViewController,
                  let filter = viewController.filterViewController else {
                return false
            }
            return search !== filter
        }
        // A local, non-tmux session has neither a remote host nor a tmux
        // controller.
        let shouldFetch: (any iTermMinimalComposerViewControllerDelegate, iTermMinimalComposerViewController) -> Bool = { delegate, composer in
            delegate.minimalComposerShouldFetchSuggestions(composer, forHost: nil, tmuxController: nil)
        }
        XCTAssertNotNil(fullStringLength as Any)
        XCTAssertNotNil(haveFindViewControllers as Any)
        XCTAssertNotNil(shouldFetch as Any)
    }
}
