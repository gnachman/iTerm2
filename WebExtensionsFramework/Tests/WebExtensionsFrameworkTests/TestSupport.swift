// TestSupport.swift
// Shared test utilities and mock objects

import Foundation
import WebKit
@testable import WebExtensionsFramework

// MARK: - Mock Classes

public class MockInjectionScriptGenerator: BrowserExtensionContentScriptInjectionGeneratorProtocol {
    public init() {}
    
    public func generateInjectionScript(for activeExtension: ActiveExtension) -> String {
        return "// Mock injection script for \(activeExtension.browserExtension.id)"
    }
}

// MockUserScriptFactory already exists in BrowserExtensionUserScriptFactoryTests.swift

public class MockBackgroundService: BrowserExtensionBackgroundServiceProtocol {
    public var activeBackgroundScriptExtensionIds: Set<ExtensionID> = []
    public weak var activeManagerDelegate: BrowserExtensionActiveManagerProtocol?
    
    public init() {}
    
    public func startBackgroundScript(for browserExtension: BrowserExtension) async throws -> (BrowserExtensionWKWebView, BrowserExtensionUserContentManager)? {
        activeBackgroundScriptExtensionIds.insert(browserExtension.id)
        return nil
    }

    public func run(extensionId: ExtensionID) async throws {
    }
    public func stopBackgroundScript(for extensionId: ExtensionID) {
        activeBackgroundScriptExtensionIds.remove(extensionId)
    }
    
    public func stopAllBackgroundScripts() {
        activeBackgroundScriptExtensionIds.removeAll()
    }
    
    public func isBackgroundScriptActive(for extensionId: ExtensionID) -> Bool {
        return activeBackgroundScriptExtensionIds.contains(extensionId)
    }
    
    public func evaluateJavaScript(_ javascript: String, in extensionId: ExtensionID) async throws -> Any? {
        return nil
    }
}

public class MockStorageManager: BrowserExtensionStorageManager {
    public convenience init() {
        self.init(logger: createTestLogger())
    }
}

// MARK: - Test Factory Functions

/// Creates a test logger that by default is quiet (no stdout/stderr output)
/// - Parameter verbose: If true, will print debug and info messages to stdout
/// - Returns: A BrowserExtensionLogger suitable for testing
public func createTestLogger(verbose: Bool = false) -> BrowserExtensionLogger {
    return SimpleTestLogger(verbose: verbose)
}

/// Creates a verbose test logger that prints all messages to stdout
/// Useful for debugging specific tests
public func createVerboseTestLogger() -> BrowserExtensionLogger {
    return SimpleTestLogger(verbose: true)
}

private class SimpleTestLogger: BrowserExtensionLogger {
    private let verbose: Bool
    
    init(verbose: Bool = false) {
        self.verbose = verbose
    }
    
    func info(_ messageBlock: @autoclosure () -> String, file: StaticString = #file, line: Int = #line, function: StaticString = #function) {
        if verbose {
            print("INFO: \(messageBlock())")
        }
    }
    
    func debug(_ messageBlock: @autoclosure () -> String, file: StaticString = #file, line: Int = #line, function: StaticString = #function) {
        if verbose {
            print("DEBUG: \(messageBlock())")
        }
    }
    
    func error(_ messageBlock: @autoclosure () -> String, file: StaticString = #file, line: Int = #line, function: StaticString = #function) {
        // Always show errors, even in non-verbose mode
        print("ERROR: \(messageBlock())")
    }
    
    func assert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String, file: StaticString = #file, line: Int = #line, function: StaticString = #function) {
        if !condition() {
            print("ASSERT: \(message())")
        }
    }
    
    func fatalError(_ message: @autoclosure () -> String, file: StaticString = #file, line: Int = #line, function: StaticString = #function) -> Never {
        Swift.fatalError("FATAL: \(message())", file: file, line: UInt(line))
    }
    
    func preconditionFailure(_ message: @autoclosure () -> String, file: StaticString = #file, line: Int = #line, function: StaticString = #function) -> Never {
        Swift.preconditionFailure("PRECONDITION: \(message())", file: file, line: UInt(line))
    }
    
    func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try closure()
    }
    
    func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await closure()
    }
}

@MainActor
public func createTestBrowserExtension(name: String = "Test Extension", logger: BrowserExtensionLogger? = nil) -> BrowserExtension {
    let manifest = ExtensionManifest(
        manifestVersion: 3,
        name: name,
        version: "1.0.0"
    )
    let baseDirectory = URL(fileURLWithPath: "/test")
    let extensionLocation = "extension-\(UUID().uuidString)"
    return BrowserExtension(manifest: manifest, baseDirectory: baseDirectory, extensionLocation: extensionLocation, logger: logger ?? createTestLogger())
}

// MARK: - Dependencies Extension

extension BrowserExtensionActiveManager.Dependencies {
    @MainActor
    public static var defaultInstance: Self {
        let testLogger = createTestLogger()
        let network = BrowserExtensionNetwork()
        let router = BrowserExtensionRouter(network: network, logger: testLogger)
        return Self(
            injectionScriptGenerator: BrowserExtensionContentScriptInjectionGenerator(logger: testLogger),
            userScriptFactory: BrowserExtensionUserScriptFactory(),
            backgroundService: MockBackgroundService(),
            network: network,
            router: router,
            logger: testLogger,
            storageManager: MockStorageManager()
        )
    }
}

@MainActor
public func createTestActiveManager(logger: BrowserExtensionLogger? = nil) -> BrowserExtensionActiveManager {
    if let logger = logger {
        var deps = BrowserExtensionActiveManager.Dependencies.defaultInstance
        deps.logger = logger
        return BrowserExtensionActiveManager(dependencies: deps)
    } else {
        return BrowserExtensionActiveManager(dependencies: .defaultInstance)
    }
}

@MainActor
public func createTestRegistry(baseDirectory: URL? = nil, logger: BrowserExtensionLogger? = nil) -> BrowserExtensionRegistry {
    let baseDir = baseDirectory ?? URL(fileURLWithPath: "/test/extensions")
    return BrowserExtensionRegistry(baseDirectory: baseDir, logger: logger ?? createTestLogger())
}
