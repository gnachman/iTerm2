//
//  iTermProcessCollection.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/12/22.
//

import Foundation

@objc(iTermProcessCollection)
class ProcessCollection: NSObject, ProcessCollectionProvider {
    private var processes = [pid_t: iTermProcessInfo]()
    private let dataSource: ProcessDataSource

    @objc(initWithDataSource:)
    init(dataSource: ProcessDataSource) {
        self.dataSource = dataSource
    }

    @objc var processIDs: [pid_t] {
        return Array(processes.keys)
    }

    var treeString: String {
        return processes.values.map {
            $0.tree(indent: "")
        }.joined(separator: "\n")
    }

    @discardableResult
    func addProcess(withProcessID pid: pid_t, parentProcessID ppid: pid_t) -> iTermProcessInfo {
        let info = iTermProcessInfo(processID: pid,
                                    parentProcessID: ppid,
                                    collection: self,
                                    dataSource: dataSource)
        processes[pid] = info
        return info
    }

    func commit() {
        for info in processes.values {
            info.parent = processes[info.parentProcessID]
            info.parent?.addChild(pid: info.processID)
        }
    }

    func info(forProcessID pid: pid_t) -> iTermProcessInfo? {
        return processes[pid]
    }
}
