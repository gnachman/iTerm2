import Foundation

// #selector, key paths, dynamic lookups and optional protocol methods.
class FXSelectorUser: NSObject {
    @objc private func privateAction(_ sender: Any) {}
    @objc fileprivate func filePrivateThing(with value: Int, other: Int) {}

    func selectors() -> [Selector] {
        return [#selector(FXWidget.takeFocus),
                #selector(getter: FXWidget.isEnabled),
                #selector(setter: FXWidget.title),
                #selector(privateAction(_:)),
                #selector(filePrivateThing(with:other:)),
                #selector(FXDelegate.fixtureDidChange(_:))]
    }

    func keyPaths(widget: FXWidget) -> [AnyKeyPath] {
        let name = #keyPath(FXWidget.title)
        _ = name
        return [\FXWidget.count, \FXWidget.delegate]
    }

    func dynamic(anything: AnyObject, widget: FXWidget) {
        anything.takeFocus?()
        widget.delegate?.fixtureDidChange?(self)
        widget.delegate?.requiredThing("x")
        _ = widget.delegate?.optionalCount?()
    }
}
