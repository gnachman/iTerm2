// BrowserExtensionLogger.swift
// Logging protocol and implementation for WebExtensions framework

import Foundation

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

