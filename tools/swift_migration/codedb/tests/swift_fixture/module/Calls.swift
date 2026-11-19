import Foundation

// Calls, initializers, class methods, renamed imports, closures.
class FXCaller {
    func run(widget: FXWidget) {
        widget.takeFocus()
        widget.doThing(1, with: 2)
        widget.draw(NSRect())
        try? widget.save(toPath: "/tmp/x")
        widget.removeItems(at: IndexSet())
        widget.newName(x: 3)
        let other = FXWidget(name: "a")
        let third = FXWidget(name: "b", count: 2)
        FXWidget.classMethod(withValue: 4)
        _ = FXWidget.shared()
        widget.perform {
            other.takeFocus()
        }
        _ = third
    }

    func later(widget: FXWidget) async {
        await widget.fetchValue()
    }

    func cleanUp(widget: FXWidget) {
        defer { widget.takeFocus() }
    }

    #if FIXTURE_NEVER_DEFINED
    func inactive(widget: FXWidget) {
        widget.takeFocus()
    }
    #endif
}
