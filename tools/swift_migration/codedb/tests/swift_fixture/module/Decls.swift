import Foundation

// Swift declarations visible to Objective-C, in the shapes whose selectors
// the reader derives. Each internal declaration has a private twin with the
// same shape and a "p" prefix: the compiler gives the internal one's selector
// in its USR, and the private one's must be derived.
@objc protocol FXSwiftProto {
    func protoRequired(_ x: Int)
    @objc optional func protoOptional(with x: Int)
}

class FXShapes: NSObject {
    @objc func plain() {}
    @objc func one(_ x: Int) {}
    @objc func one(label x: Int) {}
    @objc func two(_ a: Int, _ b: Int) {}
    @objc func two(a: Int, b: Int) {}
    @objc func move(to p: Int) {}
    @objc func doSomething(for x: Int) {}
    @objc func handle(_ x: Int, with y: Int) {}
    @objc func make(URL x: Int) {}
    @objc func name(withLabel x: Int) {}
    @objc func load(_ completion: @escaping () -> Void) {}
    @objc func with(_ x: Int) {}
    @objc func save() throws {}
    @objc func save(path: String) throws {}
    @objc func remove(at index: Int) throws {}
    @objc func fetch() async {}
    @objc func fetch(id: Int) async -> Int { return id }
    @objc func fetchThrows() async throws {}
    @objc(customName:) func renamed(_ x: Int) {}
    @objc var prop: Int = 0
    @objc var isOn: Bool = false
    @objc var URLString: String = ""
    @objc let constant: Int = 1
    @objc var computed: Int { return 2 }
    @objc(customProp) var renamedProp: Int = 0
    @objc class func classThing() {}
    @objc static var sharedThing: Int = 0
    @objc subscript(index: Int) -> Int { get { return index } set {} }
    @objc init(name: String) { super.init() }
    @objc init(_ x: Int) { super.init() }
    @objc convenience init(a: Int, b: Int) { self.init(a) }
    @objc init(x: Int) throws { super.init() }
    @objc override init() { super.init() }

    @objc private func pPlain() {}
    @objc private func pOne(_ x: Int) {}
    @objc private func pOne(label x: Int) {}
    @objc private func pTwo(_ a: Int, _ b: Int) {}
    @objc private func pTwo(a: Int, b: Int) {}
    @objc private func pMove(to p: Int) {}
    @objc private func pDoSomething(for x: Int) {}
    @objc private func pHandle(_ x: Int, with y: Int) {}
    @objc private func pMake(URL x: Int) {}
    @objc private func pName(withLabel x: Int) {}
    @objc private func pLoad(_ completion: @escaping () -> Void) {}
    @objc private func pSave() throws {}
    @objc private func pSave(path: String) throws {}
    @objc private func pRemove(at index: Int) throws {}
    @objc private func pFetch() async {}
    @objc private func pFetch(id: Int) async -> Int { return id }
    @objc private func pFetchThrows() async throws {}
    @objc(pCustomName:) private func pRenamed(_ x: Int) {}
    @objc private var pProp: Int = 0
    @objc private var pIsOn: Bool = false
    @objc private class func pClassThing() {}
    @objc fileprivate func fpThing(_ x: Int, y: Int) {}
}

class FXSub: FXWidget {
    override func takeFocus() {}
    override var count: Int {
        get { return 1 }
        set {}
    }
}

class FXDel: NSObject, FXDelegate, FXSwiftProto {
    func requiredThing(_ text: String) {}
    func fixtureDidChange(_ sender: Any) {}
    func protoRequired(_ x: Int) {}
    deinit {}
}

// A Swift protocol an Objective-C class conforms to: FXWidget's Objective-C
// property and method witness two of its requirements, which Swift calls
// through the protocol (the dump names the requirement, not the witness).
protocol FXCounting: AnyObject {
    var count: Int { get set }
    func takeFocus()
    func swiftOnly()
}

extension FXCounting {
    func withDefault() {}
}

extension FXWidget: FXCounting {
    func swiftOnly() {}
}

func fxUseCounting(_ c: FXCounting) {
    c.count = 1
    c.takeFocus()
}

// A private protocol: its USR has a private discriminator.
private protocol FXLengthy {
    var isEnabled: Bool { get }
}

extension FXWidget: FXLengthy {}
