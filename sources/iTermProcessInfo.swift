//
//  ProcessInfo.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/11/22.
//

import Foundation

@objc(iTermProcessInfo)
class iTermProcessInfo: NSObject {
    @objc let processID: pid_t
    @objc let parentProcessID: pid_t
    private(set) weak var collection: ProcessCollectionProvider?
    @objc let dataSource: ProcessDataSource
    private var childProcessIDs = IndexSet()
    private var buildingTreeString = false
    @objc var parent: iTermProcessInfo?

    @objc(initWithPid:ppid:collection:dataSource:)
    init(processID: pid_t,
         parentProcessID: pid_t,
         collection: ProcessCollectionProvider,
         dataSource: ProcessDataSource) {
        self.processID = processID
        self.parentProcessID = parentProcessID
        self.collection = collection
        self.dataSource = dataSource
    }

    override func isEqual(to object: Any?) -> Bool {
        guard let other = object as? iTermProcessInfo else {
            return false
        }
        return self == other
    }

    override var debugDescription: String {
        return "<iTermProcessInfo: pid=\(processID) name=\(name.debugDescriptionOrNil) children.count=\(childProcessIDs.count)>"
    }

    var recursiveDescription: String {
        return recursiveDescription(depth: 0)
    }

    private func recursiveDescription(depth: Int) -> String {
        if depth == 100 {
            return "Truncated at 100 levels"
        }
        let me = String(repeating: " ", count: depth) + String(processID) + " " + name.debugDescriptionOrNil
        if children.isEmpty {
            return me
        }
        let lines = [me] + children.map {
            $0.recursiveDescription(depth: depth + 1)
        }
        return lines.joined(separator: "\n")
    }

    static func ==(lhs: iTermProcessInfo, rhs: iTermProcessInfo) -> Bool {
        return (lhs.processID == rhs.processID &&
                lhs.name == rhs.name &&
                lhs.parentProcessID == rhs.parentProcessID)
    }

    @objc(treeStringWithIndent:)
    func tree(indent: String) -> String {
        guard !buildingTreeString else {
            return "<CYCLE DETECTED AT \(processID)>"
        }
        buildingTreeString = true
        let childArray = children
        var children = childArray.map {
            $0.tree(indent: indent + "    ")
        }.joined(separator: "\n")
        buildingTreeString = false
        if !childArray.isEmpty {
            children = "\n" + children
        }
        return "\(indent)pid=\(processID) name=\(name.debugDescriptionOrNil) fg=\(isForegroundJob)" + children
    }

    @objc var children: [iTermProcessInfo] {
        return childProcessIDs.compactMap {
            collection?.info(forProcessID: pid_t($0))
        }
    }

    @objc var sortedChildren: [iTermProcessInfo] {
        return children.sorted { lhs, rhs in
            lhs.processID < rhs.processID
        }
    }

    @objc(addChildWithProcessID:)
    func addChild(pid: pid_t) {
        childProcessIDs.insert(Int(pid))
    }

    @objc lazy var startTime: Date? = {
         dataSource.startTime(forProcess: processID)
    }()

    @objc lazy var deepestForegroundJob: iTermProcessInfo? = {
        var level = 0
        var visitedPIDs = Set<pid_t>()
        var cycle = false
        return deepestForegroundJob(level: &level, visited: &visitedPIDs, cycle: &cycle, depth: 0)
    }()

    func deepestForegroundJob(level levelInOut: inout Int,
                              visited: inout Set<pid_t>,
                              cycle: inout Bool,
                              depth: Int) -> iTermProcessInfo? {
        if depth > 50 || visited.contains(processID) {
            cycle = true
            return nil
        }
        visited.insert(processID)

        var bestLevel = levelInOut
        var bestProcessInfo: iTermProcessInfo? = nil
        if childProcessIDs.isEmpty && isForegroundJob {
            return self
        }
        bestProcessInfo = self
        for child in children {
            var level = levelInOut + 1
            let candidate = child.deepestForegroundJob(level: &level,
                                                       visited: &visited,
                                                       cycle: &cycle,
                                                       depth: depth + 1)
            if cycle {
                return nil
            }
            if let candidate = candidate, (level > bestLevel || bestProcessInfo == nil) {
                bestLevel = level
                bestProcessInfo = candidate
            }
        }
        levelInOut = bestLevel
        return bestProcessInfo
    }

    var flattenedTree: [iTermProcessInfo] {
        [self] + children.flatMap {
            $0.flattenedTree
        }
    }

    @objc(descendantsSkippingLevels:)
    func descendants(skipping levels: Int) -> [iTermProcessInfo] {
        if levels <= 0 {
            return flattenedTree
        }
        return children.flatMap {
            $0.descendants(skipping: levels - 1)
        }
    }

    // Returns true if prematurely stopped.
    @objc(enumerateTree:)
    @discardableResult
    func objcEnumerateTree(_ block: (iTermProcessInfo, UnsafeMutablePointer<ObjCBool>) -> ()) -> Bool {
        enumerateTree { info, stop in
            var temp = ObjCBool(false)
            block(info, &temp)
            stop = temp.boolValue
        }
    }

    func enumerateTree(_ block: (iTermProcessInfo, inout Bool) -> ()) -> Bool {
        var stop = false
        block(self, &stop)
        if stop {
            return true
        }
        for child in children {
            block(child, &stop)
            if stop {
                return true
            }
            if child.enumerateTree(block) {
                return true
            }
        }
        return false
    }

    lazy var executable: String? = {
        var execName = NSString()
        guard dataSource.commandLineArguments(forProcess: processID, execName: &execName) != nil else {
            return nil
        }
        return execName as String
    }()

    private struct ExpensiveValues {
        var isForegroundJob: Bool
        var commandLineValue: String?
        var argv0Value: String?
        var nameValue: String?

        init(processID: pid_t, parent: iTermProcessInfo?, dataSource: ProcessDataSource) {
            var fg = ObjCBool(false)
            nameValue = dataSource.nameOfProcess(withPid: processID, isForeground: &fg)
            if fg.boolValue || parent?.name == "login" || parent == nil {
                // Full command line with hacked command name
                let argv = dataSource.commandLineArguments(forProcess: processID, execName: nil)
                commandLineValue = argv?.joined(separator: " ")
                if let argv0 = argv?.first, !argv0.isEmpty {
                    argv0Value = argv0
                } else {
                    argv0Value = nil
                }
            }
            isForegroundJob = fg.boolValue
        }
    }

    private lazy var expensiveValues: ExpensiveValues = {
        ExpensiveValues(processID: processID,
                        parent: parent,
                        dataSource: dataSource)
    }()

    @objc var name: String? {
        return expensiveValues.nameValue
    }

    @objc var argv0: String? {
        return expensiveValues.argv0Value
    }

    @objc var commandLine: String? {
        return expensiveValues.commandLineValue
    }

    var _testValueForForegroundJob: Bool? = nil
    @objc var isForegroundJob: Bool {
        return _testValueForForegroundJob ?? expensiveValues.isForegroundJob
    }
}
