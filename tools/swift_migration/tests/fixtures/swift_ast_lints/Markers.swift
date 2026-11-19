import Foundation

func takesMutable(_ p: UnsafeMutablePointer<Int32>) {}

// Each call line both converts &x to a pointer and names an unsafe pointer
// type, so that swift_lints.py and swift_ast_lints.py judge the same line.
func markerPlacements() {
    var x: Int32 = 0
    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self
    // SWIFT-MIGRATION-UNSAFE(hot): above
    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self
    // SWIFT-MIGRATION-SHIM: two above

    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self
    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self // SWIFT-MIGRATION-SHIM: trailing
    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self
    /* SWIFT-MIGRATION-SHIM: block comment */
    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self
    // SWIFT-MIGRATION-SHIM:
    takesMutable(&x); _ = UnsafeMutablePointer<Int32>.self
}
