// Declarations of the swift_interface.py test fixture module (SIF).
import Foundation

@objc(SIFRenamedWidget)
class Widget: NSObject {
    @objc var title: String = ""
    @objc var subtitle: String? = nil
    @objc(fancyCount) var count: Int = 0
    var swiftOnly: [Int] = []
    @nonobjc var notExported: Int = 0
    private var secret = 0
    fileprivate var lessSecret = 0
    public let constant = 3

    @objc init(title: String) {
        self.title = title
    }

    @objc func doThing(_ a: Int, with b: Int) -> Int { return a + b }
    @objc(renamedSelector:) func otherThing(_ x: String) {}
    @objc func load(path: String) throws {}
    @objc func compute() async -> Int { return 1 }
    @objc private func privateObjC() {}
    @objc class func make() -> Widget { return Widget(title: "") }
    func genericThing<T: Equatable>(_ x: T) -> T { return x }
    private func privateHelper() {}
}

extension Widget {
    @objc func extensionMethod() {}
    func swiftExtensionMethod() {}
}

@objc protocol WidgetDelegate {
    func widgetDidChange(_ w: Widget)
    @objc optional func widgetWillChange(_ w: Widget)
}

protocol SwiftProtocol {
    associatedtype Item
    func handle(_ item: Item)
}

@objc enum Shade: Int {
    case light
    case dark = 5
}

enum SwiftEnum {
    case one
    case two(Int)
}

struct Point<T> {
    var x: T
    var y: T
}

typealias Callback = (Int) -> Void

func freeFunction(_ a: Int) -> String { return "\(a)" }

public func publicFunction() {}

@propertyWrapper
struct Clamped {
    var wrappedValue: Int {
        get { value }
        set { value = min(max(newValue, 0), 10) }
    }
    private var value = 0
    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
}

final class Holder {
    @Clamped var level: Int = 3
}

extension NSString {
    @objc func sifShout() -> String { return uppercased }
}

extension String {
    func sifWhisper() -> String { return lowercased() }
}

@available(macOS 14, *)
@objc class NewerThing: NSObject {
    @objc static var shared: NewerThing? = nil
    @available(*, deprecated, message: "use something else")
    @objc func oldWay() {}
}

@objcMembers class AllExposed: NSObject {
    var exposedValue: Int = 0
    func exposedMethod() {}
}

@_cdecl("sif_c_function")
func cFunction(_ x: Int32) -> Int32 { return x }
