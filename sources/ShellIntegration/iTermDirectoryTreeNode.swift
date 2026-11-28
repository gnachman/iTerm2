//
//  iTermDirectoryTreeNode.swift
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

import Foundation

// A node of iTermDirectoryTree: one path component, the nodes for the
// components that have followed it in recorded paths, keyed by component,
// and the number of recorded paths that pass through it. The tree's root has
// no component.
@objc(iTermDirectoryTreeNode)
class iTermDirectoryTreeNode: NSObject {
    @objc var component: String?
    // iTermDirectoryTree adds children by changing this dictionary in place.
    @objc let children = NSMutableDictionary()
    @objc var count: Int32 = 0

    @objc(initWithComponent:)
    required init(component: String?) {
        self.component = component
        super.init()
    }

    @objc(nodeWithComponent:)
    class func node(withComponent component: String?) -> Self {
        return self.init(component: component)
    }

    override var description: String {
        return "<\(NSStringFromClass(type(of: self))): \(it_addressString) component=\(component ?? "(null)") \(children.count) children>"
    }

    // The prefix and the keys are compared as NSStrings with
    // -[NSString hasPrefix:], which compares UTF-16 code units. Swift String
    // would compare by canonical equivalence instead. iTermDirectoryTree
    // passes the first UTF-16 unit of a component, which can be half of a
    // surrogate pair, and relies on a decomposed accented letter matching its
    // base letter.
    @objc(numberOfChildrenStartingWithString:)
    func numberOfChildren(startingWith prefix: NSString?) -> Int32 {
        guard let prefix else {
            // A nil prefix has nothing to compare with. With no children the
            // answer is 0; with children, a nil prefix is a programming error,
            // so stop.
            it_assert(children.count == 0, "numberOfChildrenStartingWithString: needs a prefix")
            return 0
        }
        let number = children.allKeys.filter { ($0 as? NSString)?.hasPrefix(prefix as String) == true }.count
        return it_narrow(number, to: Int32.self)
    }

    // Undoes one recorded path below this node. Every node on the path loses
    // one from its count and a child left with a count of zero is removed,
    // except that the node for the last component is not visited.
    @objc(removePathWithParts:)
    func removePath(withParts parts: [Any]?) {
        count = it_subtract(count, 1)
        guard let parts, parts.count > 1 else {
            return
        }
        let firstPart = parts[0]
        let tailParts = Array(parts.dropFirst())
        let node = children[firstPart] as? iTermDirectoryTreeNode
        node?.removePath(withParts: tailParts)
        if (node?.count ?? 0) == 0 {
            children.removeObject(forKey: firstPart)
        }
    }
}
