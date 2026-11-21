//
//  SwiftMigrationHelpers.swift
//  iTerm2SharedARC
//
//  Named operations for Swift ported from Objective-C, so that ported code says what the C did.
//  See docs/swift-migration/phase0.md section 7, translation-rules.md section 1,
//  assertions.md, and concurrency.md section 2.
//
//  Behavior by build (decisions.md, 2026-11-20):
//  - Every integer arithmetic and conversion helper (it_add, it_subtract, it_multiply, it_negate,
//    it_shiftLeft, it_narrow) returns what the C expression it replaces gives in practice on the
//    processor it runs on: add, subtract, multiply and negate wrap; narrowing keeps the low bits;
//    a left shift drops the bits shifted out and masks the count as the hardware does.
//    it_floatToInteger is the exception: what C gives for NaN or an out-of-range value is not one
//    fixed result (it varies with the processor, the optimization level and whether the result is
//    kept in a register), so it clamps: the truncation when it fits, the nearest bound of the type
//    when it does not, 0 for NaN, the same on both processors (decisions.md, 2026-11-20). That is
//    the result in every build and under every policy; only the reporting differs.
//  - Development, Beta and Nightly compile the Objective-C with the BETA macro and this Swift with
//    the BETA compilation condition. There every such event (an overflow, a narrowing that changes
//    the value, a shift that loses set bits or has a count C leaves undefined, a float conversion
//    of NaN or of a value out of range) is a beta assertion, and a failed beta assertion crashes
//    through it_fatalError, as ITBetaAssert does. ModernTests replaces the crash with a failure of
//    the running test (iTermBetaAssertionTestObserver).
//  - Deployment (release) compiles the arithmetic and conversion helpers to their result alone,
//    with no check. Add, subtract, multiply, negate, narrowing, 32 and 64 bit shifts, and on arm64
//    a float conversion to a 32 or 64 bit type then cost what the C did (the float conversion is
//    the one saturating instruction, through the C functions in DebugLogging.h); a shift of an 8
//    or 16 bit value, a float conversion to an 8 or 16 bit type, and a float conversion on x86_64
//    cost a few more instructions. it_betaAssert logs a failure as ITBetaAssert does and
//    continues. it_conservativeBetaAssert compiles to nothing.
//
//  Whether a failure crashes is read at run time from iTermBetaAssertionsCrash, which the
//  Objective-C sets from the BETA macro, so that tests can check the release policy (log and
//  continue, with the same result) in a Development build. The compile-time condition decides
//  only whether a check is compiled at all: it_conservativeBetaAssert and the arithmetic and
//  conversion helpers have none without BETA.
//
//  Each helper that can fail has two entry points. The public one reports failures to
//  iTermBetaAssertionFailed, which applies the build's policy. The other takes the failure
//  handler as its last parameter, `onFailure`, so tests can check both the result and that a
//  failure was reported, without crashing the test host.
//
//  The arithmetic and conversion helpers are scaffolding for a faithful port. Each call is
//  replaced with ordinary Swift in stage two, and the inventory counts the calls that remain.
//  Code whose C relies on wrapping or truncating (hashes, checksums, bit packing) does not use
//  them: it uses &+, &-, &*, &<< and init(truncatingIfNeeded:) with a comment saying what relies
//  on it.
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

/// The process-wide state of the beta assertions.
enum iTermBetaAssertions {
    /// True in builds that define BETA (Development, Beta, Nightly), where ITBetaAssert crashes.
    /// False in Deployment, where it logs and continues.
    static var areFatal: Bool {
        @inline(__always) get { iTermBetaAssertionsCrash.boolValue }
    }

    /// True in builds where ITConservativeBetaAssert is compiled in, which are the same builds.
    static var conservativeAssertionsEnabled: Bool {
        @inline(__always) get {
#if BETA
            return areFatal
#else
            return false
#endif
        }
    }

    /// What a failed beta assertion calls to crash in builds where beta assertions are fatal. It
    /// is it_fatalError in production. ModernTests replaces it for the whole run with one that
    /// fails the running test, and individual tests replace it, and restore it afterwards, to check
    /// that the public helpers apply the build's policy. It is read only after a failure, so it
    /// costs nothing when no check fails.
    static var crashHandler: iTermBetaAssertionFailureHandler = iTermBetaAssertionCrash
}

// The BETA compilation condition is set in the project separately from the C macro of the same
// name, and the two must agree in every configuration. DebugLogging.m refers to
// iTermSwiftBetaConditionIsSet when the macro is defined and to iTermSwiftBetaConditionIsNotSet
// when it is not, and only the one matching this condition exists, so a configuration where they
// disagree fails to link. ModernTests also compares iTermSwiftBetaConditionIsActive with
// iTermBetaMacroIsDefined().
#if BETA
/// Whether this Swift was compiled with the BETA condition.
let iTermSwiftBetaConditionIsActive = true

/// Exists only with the BETA condition. See above.
@_cdecl("iTermSwiftBetaConditionIsSet")
public func iTermSwiftBetaConditionIsSet() {
}
#else
/// Whether this Swift was compiled with the BETA condition.
let iTermSwiftBetaConditionIsActive = false

/// Exists only without the BETA condition. See above.
@_cdecl("iTermSwiftBetaConditionIsNotSet")
public func iTermSwiftBetaConditionIsNotSet() {
}
#endif

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
/// Deployment builds it compiles to nothing: neither the condition nor the message is evaluated,
/// and no load or branch remains.
@inline(__always)
func it_conservativeBetaAssert(_ condition: @autoclosure () -> Bool,
                               _ message: @autoclosure () -> String = "",
                               file: StaticString = #file,
                               line: UInt = #line,
                               function: StaticString = #function) {
#if BETA
    if iTermBetaAssertions.conservativeAssertionsEnabled && !condition() {
        iTermBetaAssertionFailed(message(), file: file, line: line, function: function)
    }
#endif
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
                             fatal: iTermBetaAssertions.areFatal,
                             crash: iTermBetaAssertions.crashHandler)
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

/// The production crash handler.
private func iTermBetaAssertionCrash(_ message: String,
                                     file: StaticString,
                                     line: UInt,
                                     function: StaticString) {
    it_fatalError("[BETA ASSERT] \(message)", file: file, line: line, function: function)
}

// MARK: - Arithmetic

// Each of these replaces a C expression whose operands have type T and whose result is stored in
// a T. The result is the C result: the low bits of the exact value. For 8 and 16 bit types C first
// promotes the operands to int, computes there (where add and subtract cannot overflow), and the
// store truncates; the low bits are the same as wrapping in T. A port of an expression whose
// promoted result is used at int width (`int x = a + b` with `uint8_t a, b`) widens the operands
// first and does not use the T overload.

/// a + b, wrapping as C does. A result that wraps fails a beta assertion.
@inline(__always)
func it_add<T: FixedWidthInteger>(_ a: T,
                                  _ b: T,
                                  file: StaticString = #file,
                                  line: UInt = #line,
                                  function: StaticString = #function) -> T {
#if BETA
    return it_add(a, b, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
#else
    return a &+ b
#endif
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
    if overflow {
        onFailure(iTermOverflowMessage(a, "+", b), file, line, function)
    }
    return result
}

/// a - b, wrapping as C does. A result that wraps fails a beta assertion. For unsigned types,
/// b > a gives 2^bitWidth - (b - a), as in C.
@inline(__always)
func it_subtract<T: FixedWidthInteger>(_ a: T,
                                       _ b: T,
                                       file: StaticString = #file,
                                       line: UInt = #line,
                                       function: StaticString = #function) -> T {
#if BETA
    return it_subtract(a, b, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
#else
    return a &- b
#endif
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
    if overflow {
        onFailure(iTermOverflowMessage(a, "-", b), file, line, function)
    }
    return result
}

/// a * b, wrapping as C does (the low bits of the exact product). A result that wraps fails a
/// beta assertion.
@inline(__always)
func it_multiply<T: FixedWidthInteger>(_ a: T,
                                       _ b: T,
                                       file: StaticString = #file,
                                       line: UInt = #line,
                                       function: StaticString = #function) -> T {
#if BETA
    return it_multiply(a, b, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
#else
    return a &* b
#endif
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
    if overflow {
        onFailure(iTermOverflowMessage(a, "*", b), file, line, function)
    }
    return result
}

/// -a, for signed types, wrapping as C does: -T.min is T.min, and fails a beta assertion.
@inline(__always)
func it_negate<T: FixedWidthInteger & SignedInteger>(_ a: T,
                                                     file: StaticString = #file,
                                                     line: UInt = #line,
                                                     function: StaticString = #function) -> T {
#if BETA
    return it_negate(a, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
#else
    return 0 &- a
#endif
}

/// it_negate with the failure handler injected.
@inline(__always)
func it_negate<T: FixedWidthInteger & SignedInteger>(_ a: T,
                                                     file: StaticString = #file,
                                                     line: UInt = #line,
                                                     function: StaticString = #function,
                                                     onFailure: iTermBetaAssertionFailureHandler) -> T {
    let (result, overflow) = T.zero.subtractingReportingOverflow(a)
    if overflow {
        onFailure(iTermNegationOverflowMessage(a), file, line, function)
    }
    return result
}

/// a << count, as the C expression `(T)(a << count)` gives it on arm64 and x86_64.
///
/// C shifts at the width of the promoted operand: int (32 bits) for 8, 16 and 32 bit types, and
/// 64 bits for 64 bit types. Both processors use only the low 5 bits of the count for a 32 bit
/// shift and the low 6 bits for a 64 bit shift, so a count C leaves undefined (negative, or at
/// least the promoted width) is masked to those bits. Bits shifted out are dropped, for signed
/// and unsigned types alike, and for 8 and 16 bit types the store keeps the low bits.
///
/// Fails a beta assertion when the count is one C leaves undefined (negative, or at least the
/// promoted width), or when the shift loses a set bit or changes the sign, so that the result is
/// not a * 2^count. A left shift of a negative value that loses nothing (-3 << 2 is -12) is not
/// reported.
@inline(__always)
func it_shiftLeft<T: FixedWidthInteger, U: BinaryInteger>(_ a: T,
                                                          _ count: U,
                                                          file: StaticString = #file,
                                                          line: UInt = #line,
                                                          function: StaticString = #function) -> T {
#if BETA
    return it_shiftLeft(a, count, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
#else
    return iTermShiftLeftAsC(a, count)
#endif
}

/// it_shiftLeft with the failure handler injected.
@inline(__always)
func it_shiftLeft<T: FixedWidthInteger, U: BinaryInteger>(_ a: T,
                                                          _ count: U,
                                                          file: StaticString = #file,
                                                          line: UInt = #line,
                                                          function: StaticString = #function,
                                                          onFailure: iTermBetaAssertionFailureHandler) -> T {
    let result = iTermShiftLeftAsC(a, count)
    if count < 0 || count >= iTermPromotedShiftWidth(T.self) {
        onFailure(iTermShiftCountMessage(a, count), file, line, function)
    } else if count >= T.bitWidth {
        // Possible only for 8 and 16 bit types: the promoted shift is defined and the store
        // drops every bit.
        if a != 0 {
            onFailure(iTermOverflowMessage(a, "<<", count), file, line, function)
        }
    } else if result &>> Int(truncatingIfNeeded: count) != a {
        // An arithmetic right shift restores a exactly when no bit, including the sign, was lost.
        onFailure(iTermOverflowMessage(a, "<<", count), file, line, function)
    }
    return result
}

/// The width at which C shifts a value of type T: int for the narrower types.
@inline(__always)
private func iTermPromotedShiftWidth<T: FixedWidthInteger>(_ type: T.Type) -> Int {
    return Swift.max(T.bitWidth, 32)
}

/// The C result of `(T)(a << count)`: the count masked to the promoted width, as the hardware
/// masks it, and the low bits of the shifted value.
@inline(__always)
private func iTermShiftLeftAsC<T: FixedWidthInteger, U: BinaryInteger>(_ a: T, _ count: U) -> T {
    let shift = Int(truncatingIfNeeded: count) & (iTermPromotedShiftWidth(T.self) - 1)
    return shift < T.bitWidth ? a &<< shift : 0
}

// MARK: - Narrowing

/// Converts `value` to `T` as a C conversion between integer types does: the low bits of the
/// two's complement value, sign-extended or zero-extended when T is wider. This covers narrowing
/// and reinterpreting signed as unsigned or back. A conversion that changes the value fails a
/// beta assertion.
///
/// Use this for any conversion the code does not rely on truncating. Where the C relies on it
/// (a hash, a byte taken from a wider value), write `init(truncatingIfNeeded:)` with a comment.
@inline(__always)
func it_narrow<S: BinaryInteger, T: FixedWidthInteger>(_ value: S,
                                                       to type: T.Type,
                                                       file: StaticString = #file,
                                                       line: UInt = #line,
                                                       function: StaticString = #function) -> T {
#if BETA
    return it_narrow(value, to: type, file: file, line: line, function: function, onFailure: iTermBetaAssertionFailed)
#else
    return T(truncatingIfNeeded: value)
#endif
}

/// it_narrow with the failure handler injected.
@inline(__always)
func it_narrow<S: BinaryInteger, T: FixedWidthInteger>(_ value: S,
                                                       to type: T.Type,
                                                       file: StaticString = #file,
                                                       line: UInt = #line,
                                                       function: StaticString = #function,
                                                       onFailure: iTermBetaAssertionFailureHandler) -> T {
    if T(exactly: value) == nil {
        onFailure(iTermNarrowingMessage(value, type), file, line, function)
    }
    return T(truncatingIfNeeded: value)
}

// MARK: - Float to integer

/// Converts a floating point value to an integer type as the C cast `(T)value` does for a value
/// whose truncation fits in T, and clamps otherwise (decisions.md, 2026-11-20).
///
/// A value whose truncation toward zero fits in T gives that truncation; a fractional part is
/// dropped silently, as C drops it, and is not reported. A value whose truncation is above T.max
/// (including +infinity) gives T.max, one whose truncation is below T.min (including -infinity)
/// gives T.min, so 0 for an unsigned T, and NaN gives 0. The result is the same on arm64 and x86_64 and in every build.
/// NaN and values out of range fail a beta assertion. C leaves those inputs undefined, and what it
/// produces for them varies with the processor, the optimization level and whether the result is
/// kept in a register, so no single value reproduces C; the clamp is the result most likely to
/// keep working code working.
///
/// F is Float, Double, CGFloat or Float16, each of which converts to Double exactly. T is at most
/// 64 bits wide.
///
/// In Deployment builds this is the conversion alone: one instruction (fcvtzs or fcvtzu) on arm64
/// for a 32 or 64 bit T, and a clamp after a 32 bit conversion for an 8 or 16 bit T. With BETA
/// (Development, Beta and Nightly) it also rounds and compares to check the value, so it does not
/// belong in a loop that runs per character, per cell, per token or per frame (assertions.md
/// section 1). A hot path that needs a conversion uses it_floatToIntegerUnchecked with the owner's
/// sign-off (translation-rules.md section 1).
@inline(__always)
func it_floatToInteger<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                     to type: T.Type,
                                                                     file: StaticString = #file,
                                                                     line: UInt = #line,
                                                                     function: StaticString = #function) -> T {
#if BETA
    return it_floatToInteger(value, to: type, file: file, line: line, function: function,
                             onFailure: iTermBetaAssertionFailed)
#else
    return iTermFloatToIntegerClamp.convert(value, to: type)
#endif
}

/// it_floatToInteger with the failure handler injected.
@inline(__always)
func it_floatToInteger<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                     to type: T.Type,
                                                                     file: StaticString = #file,
                                                                     line: UInt = #line,
                                                                     function: StaticString = #function,
                                                                     onFailure: iTermBetaAssertionFailureHandler) -> T {
    if !iTermFloatToIntegerClamp.fits(value, in: type) {
        onFailure(iTermFloatConversionMessage(value, type), file, line, function)
    }
    return iTermFloatToIntegerClamp.convert(value, to: type)
}

/// The less safe form of it_floatToInteger, for a hot path, used only where the owner has signed
/// off on it when that code is ported, and listed with the sign-off in the unit's dossier
/// (decisions.md, 2026-11-20; translation-rules.md section 1).
///
/// It gives exactly the result it_floatToInteger gives, for every input, on every processor and in
/// every build: the truncation when it fits, T.max or T.min when it does not, and 0 for NaN. It
/// never traps and is never undefined behavior. What it gives up is the report: nothing checks
/// the value in any build, so a NaN or an out-of-range value that it_floatToInteger would report
/// as a failed beta assertion passes silently, clamped. On arm64 it is the same single
/// instruction as it_floatToInteger in a Deployment build; on x86_64 it is a few comparisons and
/// a conversion.
@inline(__always)
func it_floatToIntegerUnchecked<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                              to type: T.Type) -> T {
    return iTermFloatToIntegerClamp.convert(value, to: type)
}

/// The clamped conversion behind it_floatToInteger and it_floatToIntegerUnchecked.
enum iTermFloatToIntegerClamp {
    /// Whether `value` truncated toward zero is a value of T. False for NaN and infinities.
    @inline(__always)
    static func fits<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F, in type: T.Type) -> Bool {
        let truncated = Double(value).rounded(.towardZero)
        // T.min is zero or minus a power of two, so it converts exactly. T.max + 1 is a power of
        // two; Double(T.max) is either exact or rounds up to that power, and adding one gives it
        // in both cases. NaN fails both comparisons.
        return truncated >= Double(T.min) && truncated < Double(T.max) + 1
    }

    /// The clamped conversion. With `portable` false this uses the processor's conversion (the
    /// saturating instruction on arm64); with it true it uses the comparisons that x86_64 uses,
    /// so that tests can check those on arm64. Both give the same result for every input.
    ///
    /// Float converts with the Float functions; every other F converts to Double exactly first.
    /// No processor converts to 8 or 16 bits directly, so those convert at 32 bits and clamp.
    @inline(__always)
    static func convert<F: BinaryFloatingPoint, T: FixedWidthInteger>(_ value: F,
                                                                      to type: T.Type,
                                                                      portable: Bool = false) -> T {
        if F.self == Float.self {
            let float = Float(value)
            if T.isSigned {
                if T.bitWidth > 32 {
                    return T(truncatingIfNeeded: portable ? iTermSaturatingInt64FromFloatPortable(float)
                                                          : iTermSaturatingInt64FromFloat(float))
                }
                return clamp(portable ? iTermSaturatingInt32FromFloatPortable(float)
                                      : iTermSaturatingInt32FromFloat(float), to: type)
            }
            if T.bitWidth > 32 {
                return T(truncatingIfNeeded: portable ? iTermSaturatingUInt64FromFloatPortable(float)
                                                      : iTermSaturatingUInt64FromFloat(float))
            }
            return clamp(portable ? iTermSaturatingUInt32FromFloatPortable(float)
                                  : iTermSaturatingUInt32FromFloat(float), to: type)
        }
        let double = Double(value)
        if T.isSigned {
            if T.bitWidth > 32 {
                return T(truncatingIfNeeded: portable ? iTermSaturatingInt64FromDoublePortable(double)
                                                      : iTermSaturatingInt64FromDouble(double))
            }
            return clamp(portable ? iTermSaturatingInt32FromDoublePortable(double)
                                  : iTermSaturatingInt32FromDouble(double), to: type)
        }
        if T.bitWidth > 32 {
            return T(truncatingIfNeeded: portable ? iTermSaturatingUInt64FromDoublePortable(double)
                                                  : iTermSaturatingUInt64FromDouble(double))
        }
        return clamp(portable ? iTermSaturatingUInt32FromDoublePortable(double)
                              : iTermSaturatingUInt32FromDouble(double), to: type)
    }

    /// A 32 bit result clamped to T, which is at most 32 bits wide and has the same signedness.
    @inline(__always)
    private static func clamp<I: FixedWidthInteger, T: FixedWidthInteger>(_ wide: I, to type: T.Type) -> T {
        if T.bitWidth >= I.bitWidth {
            return T(truncatingIfNeeded: wide)
        }
        let low = I(truncatingIfNeeded: T.min)
        let high = I(truncatingIfNeeded: T.max)
        return T(truncatingIfNeeded: Swift.min(Swift.max(wide, low), high))
    }
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
