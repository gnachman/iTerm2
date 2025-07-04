// BrowserExtensionLogger.swift
// Logging protocol and implementation for WebExtensions framework

import Foundation
import os.log

/// Protocol for logging within the WebExtensions framework
public protocol BrowserExtensionLogger {
    func info(_ messageBlock: @autoclosure () -> String,
              file: StaticString,
              line: Int,
              function: StaticString)

    func debug(_ messageBlock: @autoclosure () -> String,
               file: StaticString,
               line: Int,
               function: StaticString)

    func error(_ messageBlock: @autoclosure () -> String,
               file: StaticString,
               line: Int,
               function: StaticString)

    func assert(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String,
        file: StaticString,
        line: Int,
        function: StaticString)

    func fatalError(
        _ message: @autoclosure () -> String,
        file: StaticString,
        line: Int,
        function: StaticString) -> Never

    func preconditionFailure(
        _ message: @autoclosure () -> String,
        file: StaticString,
        line: Int,
        function: StaticString) -> Never

    func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T
    func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T
}

// MARK: - Convenience Extensions

public extension BrowserExtensionLogger {
    func info(_ messageBlock: @autoclosure () -> String,
              file: StaticString = #file,
              line: Int = #line,
              function: StaticString = #function) {
        info(messageBlock(), file: file, line: line, function: function)
    }
    
    func debug(_ messageBlock: @autoclosure () -> String,
               file: StaticString = #file,
               line: Int = #line,
               function: StaticString = #function) {
        debug(messageBlock(), file: file, line: line, function: function)
    }
    
    func error(_ messageBlock: @autoclosure () -> String,
               file: StaticString = #file,
               line: Int = #line,
               function: StaticString = #function) {
        error(messageBlock(), file: file, line: line, function: function)
    }
}

/// Default implementation of BrowserExtensionLogger using os.log
public class DefaultBrowserExtensionLogger: BrowserExtensionLogger {
    private static let logger = Logger(subsystem: "com.webextensions.framework", category: "main")
    @TaskLocal static var logContexts = ["Root"]

    public init() {}

    public func info(_ messageBlock: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: Int = #line,
                     function: StaticString = #function) {
        let message = "Info: " + prefixed(message: "\(file):\(line) (\(function)): \(messageBlock())")
        Self.logger.info("\(message, privacy: .public)")
    }

    public func debug(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        let message = "Debug: " + prefixed(message: "\(file):\(line) (\(function)): \(messageBlock())")
        Self.logger.debug("\(message, privacy: .public)")
    }

    public func error(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        let message = "Error: " + prefixed(message: "\(file):\(line) (\(function)): \(messageBlock())")
        Self.logger.error("\(message, privacy: .public)")
    }

    public func assert(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) {
        Swift.assert(condition(), message(), file: file, line: UInt(line))
    }

    public func fatalError(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) -> Never {
        Swift.fatalError(message(), file: file, line: UInt(line))
    }

    public func preconditionFailure(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) -> Never {
        Swift.preconditionFailure(message(), file: file, line: UInt(line))
    }

    private func prefixed(message: String) -> String {
        let prefix = DefaultBrowserExtensionLogger.logContexts.joined(separator: " > ")
        return "\(prefix): \(message)"
    }

    public func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try DefaultBrowserExtensionLogger.$logContexts.withValue(
            DefaultBrowserExtensionLogger.logContexts + [prefix]
        ) {
            Self.logger.debug("\(self.prefixed(message: "Begin"), privacy: .public)")
            defer {
                Self.logger.debug("\(self.prefixed(message: "End"), privacy: .public)")
            }
            do {
                return try closure()
            } catch {
                Self.logger.debug("\(self.prefixed(message: "Exiting scope with error \(error)"), privacy: .public)")
                throw error
            }
        }
    }

    public func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await DefaultBrowserExtensionLogger.$logContexts.withValue(
            DefaultBrowserExtensionLogger.logContexts + [prefix]
        ) {
            Self.logger.debug("\(self.prefixed(message: "Begin"), privacy: .public)")
            defer {
                Self.logger.debug("\(self.prefixed(message: "End"), privacy: .public)")
            }
            do {
                return try await closure()
            } catch {
                Self.logger.debug("\(self.prefixed(message: "Exiting scope with error \(error)"), privacy: .public)")
                throw error
            }
        }
    }
}

/// Test implementation of BrowserExtensionLogger that captures messages
public class TestBrowserExtensionLogger: BrowserExtensionLogger {
    public struct LogMessage {
        public let level: String
        public let message: String
        public let file: StaticString
        public let line: Int
        public let function: StaticString
    }
    
    public private(set) var messages: [LogMessage] = []
    
    public init() {}
    
    public func clear() {
        messages.removeAll()
    }
    
    public func info(_ messageBlock: @autoclosure () -> String,
                     file: StaticString = #file,
                     line: Int = #line,
                     function: StaticString = #function) {
        messages.append(LogMessage(level: "INFO", message: messageBlock(), file: file, line: line, function: function))
    }
    
    public func debug(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        messages.append(LogMessage(level: "DEBUG", message: messageBlock(), file: file, line: line, function: function))
    }
    
    public func error(_ messageBlock: @autoclosure () -> String,
                      file: StaticString = #file,
                      line: Int = #line,
                      function: StaticString = #function) {
        messages.append(LogMessage(level: "ERROR", message: messageBlock(), file: file, line: line, function: function))
    }
    
    public func assert(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) {
        Swift.assert(condition(), message(), file: file, line: UInt(line))
    }
    
    public func fatalError(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) -> Never {
        Swift.fatalError(message(), file: file, line: UInt(line))
    }
    
    public func preconditionFailure(
        _ message: @autoclosure () -> String = "",
        file: StaticString = #file,
        line: Int = #line,
        function: StaticString = #function) -> Never {
        Swift.preconditionFailure(message(), file: file, line: UInt(line))
    }
    
    public func inContext<T>(_ prefix: String, closure: () throws -> T) rethrows -> T {
        return try closure()
    }
    
    public func inContext<T>(_ prefix: String, closure: () async throws -> T) async rethrows -> T {
        return try await closure()
    }
}
