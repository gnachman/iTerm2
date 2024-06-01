//
//  TreeTimer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/31/24.
//

import Foundation

@objc(iTermTreeTimer)
class TreeTimer: NSObject {
    @objc let name: String
    @objc private(set) weak var parent: TreeTimer?
    private var children = [TreeTimer]()
    private var duration = TimeInterval(0)

    @objc
    override init() {
        self.name = "root"
        self.parent = nil
        super.init()
    }

    init(name: String, parent: TreeTimer?) {
        self.name = name
        self.parent = parent
    }

    private func add(childNamed name: String) -> TreeTimer {
        let child = TreeTimer(name: name, parent: self)
        children.append(child)
        return child
    }

    @objc
    func time(_ closure: () -> ()) {
        let begin = NSDate.it_timeSinceBoot()
        closure()
        let end = NSDate.it_timeSinceBoot()
        let elapsed = end - begin
        duration += elapsed
    }

    @objc
    func enter(_ name: String, block closure: (TreeTimer) -> ()) {
        let child = add(childNamed: name)
        child.time {
            closure(child)
        }
    }

    @objc
    func dump(minTime: TimeInterval) {
        dumpInternal(minTime: minTime, indent: "")
    }

    private func dumpInternal(minTime: TimeInterval, indent: String) {
        if duration < minTime {
            return
        }
        print("\(indent)\(name): \(duration) with \(children.count) children")
        for child in children {
            child.dumpInternal(minTime: minTime, indent: indent + "  ")
        }
    }
}
