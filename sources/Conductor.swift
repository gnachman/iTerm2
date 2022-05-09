//
//  Conductor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/22.
//

import Foundation

@objc(iTermConductorDelegate)
protocol ConductorDelegate: Any {
    func conductorWrite(string: String)
    func conductorAbort(reason: String)
}

@objc(iTermConductor)
class Conductor: NSObject {
    let sshargs: String
    let vars: [String: String]
    let payload: Data?
    let payloadDestination: String?
    let initialDirectory: String?

    enum Command {
        case execLoginShell
        case getShell
        case setenv(key: String, value: String)
        case run(String)
        case write(data: Data, dest: String)
        case cd(String)
        case quit
        case ps
        case getpid

        var stringValue: String {
            switch self {
            case .execLoginShell:
                return "exec_login_shell"
            case .getShell:
                return "get_shell"
            case .setenv(let key, let value):
                return "setenv \(key) \((value as NSString).stringEscapedForBash()!)"
            case .run(let cmd):
                return "run \(cmd)"
            case .write(let data, let dest):
                return "write \(data.base64EncodedString()) \(dest)"
            case .cd(let dir):
                return "cd \(dir)"
            case .quit:
                return "quit"
            case .ps:
                return "ps"
            case .getpid:
                return "getpid"
            }
        }
    }

    struct ExecutionContext {
        let command: Command
        let handler: (PartialResult) -> ()
    }

    enum State {
        case ground  // Have not written, not expecting anything.
        case willExecute(ExecutionContext)  // After writing, before parsing begin.
        case executing(ExecutionContext)  // After parsing begin, before parsing end.
    }

    enum PartialResult {
        case line(String)
        case end(UInt8)  // arg is exit status
        case abort  // couldn't even send the command
    }

    struct RemoteInfo {
        var pid: Int?
    }
    private var remoteInfo = RemoteInfo()

    private var state: State = .ground

    private var queue = [ExecutionContext]()

    @objc weak var delegate: ConductorDelegate?

    @objc init(_ sshargs: String,
               vars: [String: String],
               payload: Data?,
               payloadDestination: String?,
               initialDirectory: String?) {
        self.sshargs = sshargs
        self.vars = vars
        self.payload = payload
        self.payloadDestination = payloadDestination
        self.initialDirectory = initialDirectory
    }

    @objc func start() {
        remoteInfo = RemoteInfo()
        requestPID()
        setEnvironmentVariables()
        if let payload = payload, let payloadDestination = payloadDestination {
            upload(data: payload, destination: payloadDestination)
        }
        if let dir = initialDirectory {
            cd(dir)
        }
        execLoginShell()
    }

    private func requestPID() {
        send(.getpid) { [weak self] result in
            switch result {
            case .line(let value):
                guard let pid = Int(value) else {
                    self?.fail("Invalid process id \(value)")
                    return
                }
                guard let self = self, self.remoteInfo.pid == nil else {
                    self?.fail("Too many lines of output from getpid. Second is \(value)")
                    return
                }
                self.remoteInfo.pid = pid
            case .abort:
                break
            case .end(let status):
                guard status == 0 else {
                    self?.fail("getPID failed with status \(status)")
                    return
                }
                guard self?.remoteInfo.pid != nil else {
                    self?.fail("No pid")
                    return
                }
            }
        }
    }

    private func setEnvironmentVariables() {
        for (key, value) in vars {
            send(.setenv(key: key, value: value)) { [weak self] result in
                switch result {
                case .line(let value):
                    self?.fail("Unexpected output from setenv: \(value)")
                case .abort:
                    break
                case .end(let status):
                    guard status == 0 else {
                        self?.fail("setenv failed with status \(status)")
                        return
                    }
                }
            }
        }
    }

    private func upload(data: Data, destination: String) {
        send(.write(data: data.base64EncodedData(), dest: destination)) { [weak self] result in
            switch result {
            case .line(let value):
                self?.fail("Unexpected output from write: \(value)")
            case .abort:
                break
            case .end(let status):
                guard status == 0 else {
                    self?.fail("write failed with status \(status)")
                    return
                }
            }
        }
    }

    private func cd(_ dir: String) {
        send(.cd(dir)) { [weak self] result in
            switch result {
            case .line(let value):
                self?.fail("Unexpected output from cd: \(value)")
            case .abort:
                break
            case .end(let status):
                guard status == 0 else {
                    self?.fail("cd failed with status \(status)")
                    return
                }
            }
        }
    }

    private func execLoginShell() {
        send(.execLoginShell) { [weak self] result in
            switch result {
            case .line(_):
                fatalError()
            case .abort:
                break
            case .end(let status):
                guard status == 0 else {
                    self?.fail("exec_login_shell failed with status \(status)")
                    return
                }
            }
        }
    }

    @objc(handleLine:) func handle(line: String) {
        switch state {
        case .ground:
            DLog("Unexpected input: \(line)")
            fail("Unexpected input: \(line)")
        case .willExecute(let context):
            state = .executing(context)
            context.handler(.line(line))
        case .executing(let context):
            context.handler(.line(line))
        }
    }

    @objc func handleCommandEnd(status: UInt8) {
        switch state {
        case .ground:
            fail("Unexpected command end in \(state)")
        case .willExecute(let context), .executing(let context):
            context.handler(.end(status))
            state = .ground
            dequeue()
        }
    }

    private func send(_ command: Command, handler: @escaping (PartialResult) -> ()) {
        queue.append(ExecutionContext(command: command, handler: handler))
        switch state {
        case .ground:
            dequeue()
        case .willExecute(_), .executing(_):
            return
        }
    }

    private func dequeue() {
        guard let delegate = delegate else {
            while let pending = queue.first {
                queue.removeFirst()
                pending.handler(.abort)
            }
            return
        }
        guard let pending = queue.first else {
            return
        }
        queue.removeFirst()
        state = .willExecute(pending)
        delegate.conductorWrite(string: pending.command.stringValue + "\n")
    }

    private func fail(_ reason: String) {
        state = .ground
        for context in queue {
            context.handler(.abort)
        }
        queue = []
        delegate?.conductorAbort(reason: reason)
    }
}
