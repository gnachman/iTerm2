import Foundation

func fxBump(_ value: inout Int) {
    value += 1
}

// Property reads, writes and read-modify-writes.
class FXPropertyUser {
    func use(widget: FXWidget) -> Int {
        let a = widget.count
        widget.count = 5
        widget.count += 1
        fxBump(&widget.count)
        widget.isEnabled.toggle()
        widget.title = "t"
        widget.title?.append("u")
        widget.frame.origin.x = 3
        let b = FXWidget.sharedCount
        FXWidget.sharedCount = b
        let c = widget.readOnlyValue
        widget.sendableHandler = { }    // the compiler wraps the target in abi_safe_conversion_expr
        widget.peer.count = 7    // writes count; reads the object reference peer
        let d = if widget.isEnabled { widget.readOnlyValue } else { 0 }    // then_stmt
        let e = widget.names[0]    // the subscript's base is in an implicit inout_expr
        widget.names[0] = e
        return a + c + d
    }
}

// A settable property of an extension of a protocol that is not class-bound:
// its setter is mutating, so writing it through sibling writes sibling back.
protocol FXExtended {}

extension FXExtended {
    var extv: Int { get { return 0 } set {} }
}

extension FXWidget: FXExtended {}

func fxWriteThroughExtension(_ widget: FXWidget) -> Int {
    widget.sibling!.extv = 1
    return widget.sibling!.extv
}

func fxWriteThroughPointer(_ widget: FXWidget) {
    widget.rectPointer.pointee.origin.x = 1    // writes the memory rectPointer points to, not rectPointer
}
