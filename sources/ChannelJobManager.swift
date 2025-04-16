//
//  ChannelJobManager.swift
//  iTerm2
//
//  Created by George Nachman on 4/14/25.
//

@objc(iTermChannelJobManager)
class ChannelJobManager: NSObject, iTermJobManager {
    @objc var ioBuffer: IOBuffer?
    var fd: Int32 = -1
    var tty = "(embedded)"  // TODO: This actually could be plumbed through the protocol
    var externallyVisiblePid: pid_t { 0 }
    var hasJob: Bool { true }
    var sessionRestorationIdentifier: Any? { nil }
    var pidToWaitOn: pid_t { 0 }
    var isSessionRestorationPossible: Bool { false }
    var ioAllowed: Bool { ioBuffer?.isValid ?? false }
    var queue: dispatch_queue_t? { nil }
    var isReadOnly: Bool { true }
    static func available() -> Bool {
        true
    }

    func forkAndExec(with ttyState: iTermTTYState,
                     argpath: String!,
                     argv: [String]!,
                     initialPwd: String!,
                     newEnviron: [String]!,
                     task: (any iTermTask)!,
                     completion: ((iTermJobManagerForkAndExecStatus, NSNumber?) -> Void)!) {
        it_fatalError("Not supported")
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: (any iTermTask)!,
                completion: ((iTermJobManagerAttachResults) -> Void)!) {
        it_fatalError("Not supported")
    }

    func attach(toServer serverConnection: iTermGeneralServerConnection,
                withProcessID thePid: NSNumber!,
                task: (any iTermTask)!) -> iTermJobManagerAttachResults {
        it_fatalError("Not supported")
    }

    func kill(with mode: iTermJobManagerKillingMode) {
// TODO: I think I should support this
    }

    func closeFileDescriptor() -> Bool {
        guard let ioBuffer, ioBuffer.isValid else {
            return false
        }
        ioBuffer.invalidate()
        return true
    }


    @objc(initWithQueue:)
    required init(queue: DispatchQueue) {
        super.init()
    }

    override var description: String {
        return "<\(Self.self): \(it_addressString) ioBuffer=\(ioBuffer.d)>"
    }

    
}
