import Foundation

func takesMutable(_ p: UnsafeMutablePointer<Int32>) {}
func takesConst(_ p: UnsafePointer<Int32>) {}
func takesRaw(_ p: UnsafeRawPointer) {}
func takesInout(_ x: inout Int32) {}

func pointerArguments(_ legacy: FixLegacy) {
    var x: Int32 = 0
    takesMutable(&x)
    takesInout(&x)
    let a: [Int32] = [1, 2]
    takesConst(a)
    var b: [Int32] = [1, 2]
    takesMutable(&b)
    takesRaw(&x)
    FixTakesIntPointer(&x)
    FixTakesCString("text")
    FixTakesVoidPointer(&b)
    var error: NSError?
    legacy.stash(&error)
    // SWIFT-MIGRATION-UNSAFE(hot): measured in the fixture
    takesMutable(&x)
    // SWIFT-MIGRATION-SHIM: until the caller is ported
    FixTakesIntPointer(&x)
    // SWIFT-MIGRATION-SHIM: two lines above does not count

    takesMutable(&x)
    takesMutable(&x) // SWIFT-MIGRATION-SHIM: a trailing marker covers the next line, as in swift_lints.py
    takesConst(a)
    let s = "abc"
    FixTakesCString(s)
    _ = (b, error)
}
