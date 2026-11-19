import Cocoa

@objc(iTermPanel)
class Panel: NSObject {
    @objc func show(_ widget: iTermWidget) {
        widget.renamed()
        widget.fooBar = "z"
        let item = NSMenuItem(title: "Go", action: #selector(iTermWidget.go), keyEquivalent: "")
        _ = item
#if ENTRY_POINTS_NEVER_DEFINED
        widget.go()
#endif
    }

    @objc func unusedPanelMethod() {
    }
}

// Swift calls of Swift declarations: of an @objc method with an Objective-C
// USR (recorded), of a private @objc method and of a member of a nested
// class (Swift USRs: not recorded).
@objc(iTermSwiftCaller)
class SwiftCaller: NSObject {
    @objc func publicCallee() {
    }
    @objc private func privateCallee() {
    }
    @objc func publicNeverCalled() {
    }
    @objc(iTermSwiftCallerInner)
    class Inner: NSObject {
        @objc func innerCallee() {
        }
    }
    @objc func run() {
        publicCallee()
        privateCallee()
        Inner().innerCallee()
    }
}

// A Swift class that implements an Objective-C protocol's property.
@objc(iTermPanelHost)
class PanelHost: NSObject, iTermPanelOwnerProtocol {
    var panelDelegate: Any?
    func ownerPing() {
    }
}

// Accesses through the protocol type: they name the protocol's property and
// method, not any class's.
func pokePanelOwner(_ o: iTermPanelOwnerProtocol) {
    o.panelDelegate = nil
    o.ownerPing()
}

func readPanelOwner(_ o: iTermPanelOwnerProtocol) -> Any? {
    return o.panelDelegate
}

// A Swift protocol whose requirement an Objective-C method witnesses.
protocol Wobbler {
    func wobble()
}

extension iTermProbe: Wobbler {
}

func shake(_ w: Wobbler) {
    w.wobble()
}

func probeInactive(_ p: iTermProbe) {
#if ENTRY_POINTS_NEVER_DEFINED
    p.swiftInactiveOnly()
#endif
}

// A Swift class whose member has the name of a Swift protocol requirement:
// the database does not record which Swift protocols Swift classes conform
// to, so a call through Wobbler may reach it.
@objc(iTermSwiftWobbler)
class SwiftWobbler: NSObject {
    @objc func wobble() {
    }
}
