//
//  SwiftMigrationHelpers.swift
//  iTerm2SharedARC
//
//  Named operations for Swift ported from Objective-C, so that ported code says what the C did.
//  See docs/swift-migration/phase0.md section 7, translation-rules.md section 1,
//  assertions.md, and concurrency.md section 2.
//
//  Behavior by build:
//  - Development, Beta and Nightly compile the Objective-C with BETA defined. There a failed
//    beta assertion, an arithmetic overflow, an out-of-range narrowing and an out-of-range float
//    conversion all crash through it_fatalError, as ITBetaAssert does.
//  - Deployment (release) logs the failure as ITBetaAssert does and continues. The arithmetic,
//    narrowing and float helpers return the saturated value.
//
//  Each helper that can fail has two entry points. The public one reports failures to
//  iTermBetaAssertionFailed, which applies the build's policy. The other takes the failure
//  handler as its last parameter, `onFailure`, so tests can check both the clamped result and
//  that a failure was reported, without crashing the test host.
//
//  These are written for code that is called often: the checks are inlined, the path where
//  nothing fails is a few instructions with no allocation, and everything that builds a message
//  or logs happens only after a failure.
//

import Foundation

/// Receives a failed beta assertion: the message and the caller's location.
typealias iTermBetaAssertionFailureHandler = (_ message: String,
                                              _ file: StaticString,
                                              _ line: UInt,
                                              _ function: StaticString) -> Void

// MARK: - Beta assertions

/// True in builds that define BETA (Development, Beta, Nightly), where ITBetaAssert crashes.
/// False in Deployment, where it logs and continues.
var iTermBetaAssertionsAreFatal: Bool {
    @inline(__always) get { iTermBetaAssertionsCrash.boolValue }
}

/// True in builds where ITConservativeBetaAssert is compiled in, which are the same builds.
var iTermConservativeBetaAssertionsEnabled: Bool {
    @inline(__always) get { iTermBetaAssertionsAreFatal }
}

/// The Swift equivalent of ITBetaAssert. The condition is evaluated in every build. If it is
/// false: in Development, Beta and Nightly builds this logs and crashes; in Deployment builds it
/// logs and continues. The message is built only when the condition is false.
///
/// The Objective-C macro logs the condition's source text; this cannot, so pass a message that
/// states the assumption that failed. The same applies to it_conservativeBetaAssert.
@inline(__always)
func it_betaAssert(_ condition: @autoclosure () -> Bool,
                   _ message: @autoclosure () -> String = "",
                   file: StaticString = #file,
                   line: UInt = #line,
                   function: StaticString = #function) {
    if !condition() {
        iTermBetaAssertionFailed(message(), file: file, line: line, function: function)
    }
}

/// it_betaAssert with the failure handler injected. For tests and for the other helpers.
@inline(__always)
func it_betaAssert(_ condition: @autoclosure () -> Bool,
                   _ message: @autoclosure () -> String = "",
                   file: StaticString = #file,
                   line: UInt = #line,
                   function: StaticString = #function,
                   onFailure: iTermBetaAssertionFailureHandler) {
    if !condition() {
        onFailure(message(), file, line, function)
    }
}

/// The Swift equivalent of ITConservativeBetaAssert, for conditions that cost anything real to
/// evaluate. In Development, Beta and Nightly builds it behaves like it_betaAssert. In
/// Deployment builds neither the condition nor the message is evaluated.
@inline(__always)
func it_conservativeBetaAssert(_ condition: @autoclosure () -> Bool,
                               _ message: @autoclosure () -> String = "",
                               file: StaticString = #file,
                               line: UInt = #line,
                               function: StaticString = #function) {
    if iTermConservativeBetaAssertionsEnabled && !condition() {
        iTermBetaAssertionFailed(message(), file: file, line: line, function: function)
    }
}

/// it_conservativeBetaAssert with whether it is enabled and the failure handler injected.
@inline(__always)
func it_conservativeBetaAssert(_ condition: @autoclosure () -> Bool,
                               _ message: @autoclosure () -> String = "",
                               file: StaticString = #file,
                               line: UInt = #line,
                               function: StaticString = #function,
                               enabled: Bool,
                               onFailure: iTermBetaAssertionFailureHandler) {
    if enabled && !condition() {
        onFailure(message(), file, line, function)
    }
}

/// Reports a failed beta assertion with the build's policy. Every public helper in this file
/// sends its failures here.
@inline(never)
func iTermBetaAssertionFailed(_ message: String,
                              file: StaticString,
                              line: UInt,
                              function: StaticString) {
    iTermBetaAssertionFailed(message,
                             file: file,
                             line: line,
                             function: function,
                             fatal: iTermBetaAssertionsAreFatal,
                             crash: iTermBetaAssertionCrashHandler)
}

/// Reports a failed beta assertion with the policy injected. When `fatal` is true this logs as
/// ITBetaAssert does in a BETA build and then calls `crash`, which in production never returns.
/// Otherwise it logs as ITBetaAssert does in a release build and returns.
@inline(never)
func iTermBetaAssertionFailed(_ message: String,
                              file: StaticString,
                              line: UInt,
                              function: StaticString,
                              fatal: Bool,
                              crash: iTermBetaAssertionFailureHandler) {
    if fatal {
        DLog("Crashing because of a failed beta assertion at \(file):\(line) in \(function) from:\n\(Thread.callStackSymbols)",
             file: "\(file)", line: Int(line), function: "\(function)")
        iTermBetaAssertionErrorLog(message, file: file, line: line, function: function)
        crash(message, file, line, function)
    } else {
        iTermBetaAssertionErrorLog("BETA ASSERT: Failed beta assert at \(file):\(line) in \(function) from:\n\(Thread.callStackSymbols)",
                                   file: file, line: line, function: function)
        iTermBetaAssertionErrorLog(message, file: file, line: line, function: function)
    }
}

/// Does what the ELog macro does: debug log, the log saved for the next crash report, and syslog.
private func iTermBetaAssertionErrorLog(_ message: String,
                                        file: StaticString,
                                        line: UInt,
                                        function: StaticString) {
    DLog(message, file: "\(file)", line: Int(line), function: "\(function)")
    LogForNextCrash(file.utf8Start,
                    Int32(truncatingIfNeeded: line),
                    function.utf8Start,
                    message,
                    false)
    NSLog("%@", message)
}

/// What a failed beta assertion calls to crash in builds where beta assertions are fatal. It is
/// it_fatalError in production. Tests replace it, and restore it afterwards, to check that the
/// public helpers apply the build's policy without crashing the test host. It is read only after
/// a failure, so it costs nothing when no check fails.
var iTermBetaAssertionCrashHandler: iTermBetaAssertionFailureHandler = iTermBetaAssertionCrash

/// The production crash handler.
private func iTermBetaAssertionCrash(_ message: String,
                                     file: StaticString,
                                     line: UInt,
                                     function: StaticString) {
    it_fatalError("[BETA ASSERT] \(message)", file: file, line: line, function: function)
}

// MARK: - Arithmetic

/// a + b. On overflow, fails a beta assertion and returns the bound in the direction of the
/// overflow.
@inline(__always)
func it_add<T: FixedWidthInteger>(_ a: T,
                                  _ b: T,
                                  file: StaticString = #file,
                                  line: UInt = #line,
                                  function: StaticString = #function) -> T {
    return it_add(a, b, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
}

/// it_add with the failure handler injected.
@inline(__always)
func it_add<T: FixedWidthInteger>(_ a: T,
                                  _ b: T,
                                  file: StaticString = #file,
                                  line: UInt = #line,
                                  function: StaticString = #function,
                                  onFailure: iTermBetaAssertionFailureHandler) -> T {
    let (result, overflow) = a.addingReportingOverflow(b)
    if !overflow {
        return result
    }
    onFailure(iTermOverflowMessage(a, "+", b), file, line, function)
    return b > 0 ? .max : .min
}

/// a - b. On overflow, fails a beta assertion and returns the bound in the direction of the
/// overflow. For unsigned types, b > a gives zero.
@inline(__always)
func it_subtract<T: FixedWidthInteger>(_ a: T,
                                       _ b: T,
                                       file: StaticString = #file,
                                       line: UInt = #line,
                                       function: StaticString = #function) -> T {
    return it_subtract(a, b, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
}

/// it_subtract with the failure handler injected.
@inline(__always)
func it_subtract<T: FixedWidthInteger>(_ a: T,
                                       _ b: T,
                                       file: StaticString = #file,
                                       line: UInt = #line,
                                       function: StaticString = #function,
                                       onFailure: iTermBetaAssertionFailureHandler) -> T {
    let (result, overflow) = a.subtractingReportingOverflow(b)
    if !overflow {
        return result
    }
    onFailure(iTermOverflowMessage(a, "-", b), file, line, function)
    return b > 0 ? .min : .max
}

/// a * b. On overflow, fails a beta assertion and returns the bound with the sign of the true
/// product.
@inline(__always)
func it_multiply<T: FixedWidthInteger>(_ a: T,
                                       _ b: T,
                                       file: StaticString = #file,
                                       line: UInt = #line,
                                       function: StaticString = #function) -> T {
    return it_multiply(a, b, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
}

/// it_multiply with the failure handler injected.
@inline(__always)
func it_multiply<T: FixedWidthInteger>(_ a: T,
                                       _ b: T,
                                       file: StaticString = #file,
                                       line: UInt = #line,
                                       function: StaticString = #function,
                                       onFailure: iTermBetaAssertionFailureHandler) -> T {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    if !overflow {
        return result
    }
    onFailure(iTermOverflowMessage(a, "*", b), file, line, function)
    return (a < 0) != (b < 0) ? .min : .max
}

/// -a, for signed types. Negating .min fails a beta assertion and returns .max.
@inline(__always)
func it_negate<T: FixedWidthInteger & SignedInteger>(_ a: T,
                                                     file: StaticString = #file,
                                                     line: UInt = #line,
                                                     function: StaticString = #function) -> T {
    return it_negate(a, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
}

/// it_negate with the failure handler injected.
@inline(__always)
func it_negate<T: FixedWidthInteger & SignedInteger>(_ a: T,
                                                     file: StaticString = #file,
                                                     line: UInt = #line,
                                                     function: StaticString = #function,
                                                     onFailure: iTermBetaAssertionFailureHandler) -> T {
    let (result, overflow) = T.zero.subtractingReportingOverflow(a)
    if !overflow {
        return result
    }
    onFailure(iTermNegationOverflowMessage(a), file, line, function)
    return .max
}

/// a << count, where the result is a * 2^count.
///
/// Fails a beta assertion, and returns a defined value, when the shift loses set bits or the
/// count is out of range. This is reported for unsigned types too, although C defines an
/// unsigned left shift as dropping the bits shifted out; code that relies on that uses `&<<`.
/// - The result does not fit: returns .max, or .min if a is negative.
/// - count is at least the bit width: the same, or zero if a is zero.
/// - count is negative, which C leaves undefined: reported, then returns a shifted right by the
///   magnitude of count, which is what Swift's `<<` does.
@inline(__always)
func it_shiftLeft<T: FixedWidthInteger, U: BinaryInteger>(_ a: T,
                                                          _ count: U,
                                                          file: StaticString = #file,
                                                          line: UInt = #line,
                                                          function: StaticString = #function) -> T {
    return it_shiftLeft(a, count, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
}

/// it_shiftLeft with the failure handler injected.
@inline(__always)
func it_shiftLeft<T: FixedWidthInteger, U: BinaryInteger>(_ a: T,
                                                          _ count: U,
                                                          file: StaticString = #file,
                                                          line: UInt = #line,
                                                          function: StaticString = #function,
                                                          onFailure: iTermBetaAssertionFailureHandler) -> T {
    if count >= 0 && count < T.bitWidth {
        let shift = Int(truncatingIfNeeded: count)
        let result = a &<< shift
        // An arithmetic right shift restores a exactly when no bit, including the sign, was lost.
        if result &>> shift == a {
            return result
        }
        onFailure(iTermOverflowMessage(a, "<<", count), file, line, function)
        return a < 0 ? .min : .max
    }
    onFailure(iTermShiftCountMessage(a, count), file, line, function)
    if count < 0 {
        return a >> count.magnitude
    }
    if a == 0 {
        return 0
    }
    return a < 0 ? .min : .max
}

// MARK: - Narrowing

/// Converts `value` to `T`. If it does not fit, fails a beta assertion and returns the nearest
/// value of T (T.max or T.min).
///
/// Use this for any narrowing the code does not rely on truncating. Plain `init(clamping:)`
/// clamps silently in every build and is only for places where clamping is expected.
@inline(__always)
func it_narrow<S: BinaryInteger, T: FixedWidthInteger>(_ value: S,
                                                       to type: T.Type,
                                                       file: StaticString = #file,
                                                       line: UInt = #line,
                                                       function: StaticString = #function) -> T {
    return it_narrow(value, to: type, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
}

/// it_narrow with the failure handler injected.
@inline(__always)
func it_narrow<S: BinaryInteger, T: FixedWidthInteger>(_ value: S,
                                                       to type: T.Type,
                                                       file: StaticString = #file,
                                                       line: UInt = #line,
                                                       function: StaticString = #function,
                                                       onFailure: iTermBetaAssertionFailureHandler) -> T {
    if let result = T(exactly: value) {
        return result
    }
    onFailure(iTermNarrowingMessage(value, type), file, line, function)
    return T(clamping: value)
}

// MARK: - Float to integer

/// Converts a floating point value to an integer type, rounding toward zero as C does.
///
/// The result is defined for every input. If the value rounded toward zero does not fit in T,
/// this fails a beta assertion and returns:
/// - zero for NaN,
/// - T.max for +infinity and for finite values above the range,
/// - T.min for -infinity and for finite values below the range.
/// Negative zero, and any value strictly between -1 and 1, gives zero without failing.
@inline(__always)
func it_floatToInteger<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                     to type: T.Type,
                                                                     file: StaticString = #file,
                                                                     line: UInt = #line,
                                                                     function: StaticString = #function) -> T {
    return it_floatToInteger(value, to: type, file: file, line: line, function: function,
                             onFailure: iTermBetaAssertionFailed)
}

/// it_floatToInteger with the failure handler injected.
@inline(__always)
func it_floatToInteger<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                     to type: T.Type,
                                                                     file: StaticString = #file,
                                                                     line: UInt = #line,
                                                                     function: StaticString = #function,
                                                                     onFailure: iTermBetaAssertionFailureHandler) -> T {
    let truncated = value.rounded(.towardZero)
    // T.min is zero or minus a power of two, so it converts exactly. T.max + 1 is a power of two;
    // F(T.max) is either exact or rounds up to that power, and adding one gives it in both cases.
    // NaN fails both comparisons. That holds when F can represent the bounds, as Float, Double
    // and CGFloat can for every integer type here. A narrower type such as Float16 rounds the
    // bounds of the wide integer types to infinity, so an infinite value is rejected on its own.
    if truncated.isFinite && truncated >= F(T.min) && truncated < F(T.max) + 1 {
        // Every value of Float, Double and CGFloat converts to Double exactly, and an in-range
        // value fits in Int64 or UInt64, so these concrete conversions compile to single
        // instructions. The generic T(truncated) calls into the standard library.
        if F.significandBitCount <= Double.significandBitCount {
            let double = Double(truncated)
            return T.isSigned ? T(truncatingIfNeeded: Int64(double)) : T(truncatingIfNeeded: UInt64(double))
        }
        return T(truncated)
    }
    onFailure(iTermFloatConversionMessage(value, type), file, line, function)
    if value.isNaN {
        return 0
    }
    return value < 0 ? .min : .max
}

// MARK: - Synchronized

/// Runs `body` holding the same lock `@synchronized(lock)` takes, and returns its result.
///
/// The lock is recursive, is released when `body` returns or throws, and is the lock
/// Objective-C `@synchronized` on the same object uses. Use this only for blocks with no
/// control flow out of them; a block that leaves by `return`, `break` or `continue` uses the
/// `do` and `defer` form in concurrency.md section 2 instead. `lock` must be a class instance
/// with a stable identity; never pass a Swift value converted to AnyObject.
@inline(__always)
func it_synchronized<R>(_ lock: AnyObject, _ body: () throws -> R) rethrows -> R {
    objc_sync_enter(lock)
    defer {
        objc_sync_exit(lock)
    }
    return try body()
}

/// it_synchronized for a lock that might be nil. A nil lock fails a beta assertion and then
/// runs `body` with no lock, which is what `@synchronized(nil)` does. Each call site that needs
/// this goes in the bug ledger (concurrency.md section 2).
@inline(__always)
func it_synchronized<R>(_ lock: AnyObject?,
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function,
                        _ body: () throws -> R) rethrows -> R {
    return try it_synchronized(lock, file: file, line: line, function: function,
                               onFailure: iTermBetaAssertionFailed, body)
}

/// it_synchronized for a lock that might be nil, with the failure handler injected.
@inline(__always)
func it_synchronized<R>(_ lock: AnyObject?,
                        file: StaticString = #file,
                        line: UInt = #line,
                        function: StaticString = #function,
                        onFailure: iTermBetaAssertionFailureHandler,
                        _ body: () throws -> R) rethrows -> R {
    guard let lock else {
        onFailure("nil lock passed to it_synchronized; running unprotected", file, line, function)
        return try body()
    }
    return try it_synchronized(lock, body)
}

// MARK: - Messages

// These run only after a failure. They are kept out of line so the inlined helpers stay small.

@inline(never)
private func iTermOverflowMessage<T: FixedWidthInteger, U: BinaryInteger>(_ a: T,
                                                                          _ op: StaticString,
                                                                          _ b: U) -> String {
    return "overflow in \(a) \(op) \(b) (\(T.self))"
}

@inline(never)
private func iTermNegationOverflowMessage<T: FixedWidthInteger>(_ a: T) -> String {
    return "overflow in -(\(a)) (\(T.self))"
}

@inline(never)
private func iTermShiftCountMessage<T: FixedWidthInteger, U: BinaryInteger>(_ a: T, _ count: U) -> String {
    return "shift count out of range in \(a) << \(count) (\(T.self))"
}

@inline(never)
private func iTermNarrowingMessage<S: BinaryInteger, T: FixedWidthInteger>(_ value: S, _ type: T.Type) -> String {
    return "narrowing \(value) (\(S.self)) to \(T.self) is out of range"
}

@inline(never)
private func iTermFloatConversionMessage<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                                       _ type: T.Type) -> String {
    return "converting \(value) (\(F.self)) to \(T.self) is out of range"
}
