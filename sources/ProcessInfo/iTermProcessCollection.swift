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
        return addProcess(withProcessID: pid, parentProcessID: ppid, name: nil, isForeground: false)
    }

    // name and isForeground come from a process-table snapshot so the process info
    // doesn't have to ask the data source for them one pid at a time. A nil name
    // (empty p_comm, typically mid-exec) defers to the data source as if there were
    // no snapshot, and isForeground is ignored.
    @discardableResult
    @objc(addProcessWithProcessID:parentProcessID:name:isForeground:)
    func addProcess(withProcessID pid: pid_t,
                    parentProcessID ppid: pid_t,
                    name: String?,
                    isForeground: Bool) -> iTermProcessInfo {
        let info = iTermProcessInfo(processID: pid,
                                    parentProcessID: ppid,
                                    collection: self,
                                    dataSource: dataSource,
                                    snapshotName: name,
                                    snapshotIsForeground: isForeground)
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
