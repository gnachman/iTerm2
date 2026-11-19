import Foundation

func dynamicSelectors(name: String) {
    _ = Selector(name)
    _ = Selector("literalSelector:")
    _ = NSSelectorFromString(name)
    _ = NSSelectorFromString("literalToo")
}

extension Plain {
}

func performByName(target: NSObject, action: Selector) {
    target.perform(action, with: nil)
    target.perform(#selector(NSObject.description))
    _ = Timer(timeInterval: 1, target: target, selector: #selector(NSObject.description), userInfo: nil, repeats: false)
    _ = Timer(timeInterval: 1, target: target, selector: action, userInfo: nil, repeats: false)
}

func actionsByName(item: NSMenuItem, holder: Holder, action: Selector, target: NSObject) {
    item.action = action
    item.action = #selector(NSObject.description)
    item.action = nil
    target.perform(holder.action, with: nil)
    item.doubleAction = action
    state.action = .close
}

func moreByName(app: NSApplication, window: NSWindow, item: NSMenuItem, action: Selector, close: Selector) {
    app.sendAction(action, to: nil, from: item)
    app.sendAction(#selector(NSObject.description), to: nil, from: item)
    _ = window.tryToPerform(close, with: item)
    _ = app.target(forAction: action)
    _ = app.target(forAction: #selector(NSObject.description))
    perform(action, with: nil)
    perform(#selector(NSObject.description))
    _ = NSMenuItem(title: "t", action: action, keyEquivalent: "")
    _ = NSMenuItem(title: "t", action: #selector(NSObject.description), keyEquivalent: "")
    _ = NSMenuItem(title: "t", action: nil, keyEquivalent: "")
    item.sendAction(on: .leftMouseUp)
    Button(action: { })
}

func perform(_ x: Int) {
}

func moreDeclarations(action: @escaping () -> Void, later: (action: (() -> Void)?, count: Int)) {
    _ = #selector(NSObject.handle(action:sender:))
    _ = #selector(handle(_:action:))
}
func fixtureView(action: some Sendable, selector: [Selector]) {
}
func moreNonSites(window: NSWindow, item: NSMenuItem, sel: Selector) {
    _ = window.tryToPerform(nil, with: item)
    _ = trigger(action: "Mark", selector: "x:")
    _ = button(action: .close, selector: [sel])
    _ = button(action: Fixture.close, selector: Self.chosen)
}
func declared(action: iTermFixtureAction, selector: iTermFixtureSelector) {
}
enum FixtureEvent {
    case run(action: iTermFixtureAction)
}
struct FixtureThing {
    init(action: iTermFixtureAction) { }
    subscript(action: iTermFixtureAction) -> Int { return 0 }
}
func parenthesized(flag: Bool, a: Selector, b: Selector) {
    _ = NSMenuItem(title: "t", action: (flag ? a : b), keyEquivalent: "")
}
