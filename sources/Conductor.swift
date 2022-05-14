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
    func conductorWrite(data: Data)
    func conductorAbort(reason: String)
}


@objc(iTermConductor)
class Conductor: NSObject {
    private let sshargs: String
    private let vars: [String: String]
    private var payloads: [(path: String, destination: String)] = []
    private let initialDirectory: String?
    private let parsedSSHArguments: ParsedSSHArguments
    @objc private(set) var queueWrites = true

    @objc var sshIdentity: SSHIdentity {
        return parsedSSHArguments.identity
    }

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

        var operationDescription: String {
            switch self {
            case .execLoginShell:
                return "starting login shell"
            case .getShell:
                return "querying for the login shell"
            case .setenv(let key, let value):
                return "setting \(key)=\(value)"
            case .run(let cmd):
                return "running \(cmd)"
            case .write(_, let dest):
                return "copying files to \(dest)"
            case .cd(let dir):
                return "changing directory to \(dir)"
            case .quit:
                return "quitting"
            case .ps:
                return "Running ps"
            case .getpid:
                return "Getting the shell's process ID"
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
    @objc let boolArgs: String

    @objc init(_ sshargs: String,
               boolArgs: String,
               vars: [String: String],
               initialDirectory: String?) {
        DLog("Conductor starting")
        self.sshargs = sshargs
        self.boolArgs = boolArgs
        parsedSSHArguments = ParsedSSHArguments(sshargs, booleanArgs: boolArgs)
        self.vars = vars
        self.initialDirectory = initialDirectory
    }

    @objc(addPath:destination:)
    func add(path: String, destination: String) {
        var tweakedDestination: String
        if destination == "~/" || destination == "~" {
            tweakedDestination = "/$HOME"
        } else if !destination.hasPrefix("/") {
            tweakedDestination = "/$HOME/" + destination.dropFirst(2)
        } else {
            tweakedDestination = destination
        }
        while tweakedDestination != "/" && tweakedDestination.hasSuffix("/") {
            tweakedDestination = String(tweakedDestination.dropLast())
        }
        payloads.append((path: (path as NSString).expandingTildeInPath,
                         destination: tweakedDestination))
    }

    @objc func start() {
        remoteInfo = RemoteInfo()
        requestPID()
        setEnvironmentVariables()
        uploadPayloads()
        if let dir = initialDirectory {
            cd(dir)
        }
        if !parsedSSHArguments.commandArgs.isEmpty {
            run(parsedSSHArguments.commandArgs.joined(separator: " "))
            return
        }
        execLoginShell()
    }

    private func uploadPayloads() {
        let builder = ConductorPayloadBuilder()
        for (path, destination) in payloads {
            builder.add(localPath: URL(fileURLWithPath: path),
                        destination: URL(fileURLWithPath: destination))
        }
        builder.enumeratePayloads { data, destination in
            upload(data: data, destination: destination)
        }
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
        send(.write(data: data, dest: destination)) { [weak self] result in
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

    private func run(_ command: String) {
        send(.run(command)) { [weak self] result in
            switch result {
            case .line(_):
                fatalError()
            case .abort:
                break
            case .end(let status):
                guard status == 0 else {
                    self?.fail("run \(command) failed with status \(status)")
                    return
                }
            }
        }
    }

    @objc(handleLine:) func handle(line: String) {
        DLog("< \(line)")
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
        DLog("< command ended with status \(status)")
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
        DLog("> \(pending.command.stringValue)")
        let savedQueueWrites = queueWrites
        queueWrites = false
        let parts = pending.command.stringValue.chunk(128)
        for part in parts {
            delegate.conductorWrite(string: part + "\n")
        }
        delegate.conductorWrite(string: "\n")
        queueWrites = savedQueueWrites
    }

    private var currentOperationDescription: String {
        switch state {
        case .ground:
            return "waiting"
        case .executing(let context):
            return context.command.operationDescription
        case .willExecute(let context):
            return context.command.operationDescription + " (preparation stage)"
        }
    }

    private func fail(_ reason: String) {
        let cod = currentOperationDescription
        state = .ground
        for context in queue {
            context.handler(.abort)
        }
        queue = []
        // Try to launch the login shell so you're not completely stuck.
        delegate?.conductorWrite(string: Command.execLoginShell.stringValue + "\n")
        delegate?.conductorAbort(reason: reason + " while " + cod)
    }
}

fileprivate class ConductorPayloadBuilder {
    private var tarJobs = [TarJob]()

    func add(localPath: URL, destination: URL) {
        for var job in tarJobs {
            if job.add(local: localPath, destination: destination) {
                return
            }
        }
        tarJobs.append(TarJob(local: localPath, destination: destination))
    }

    func enumeratePayloads(_ closure: (Data, String) -> ()) {
        for job in tarJobs {
            if let data = try? job.tarballData() {
                closure(data, job.destinationBase.path)
            }
        }
    }
}

extension String {
    func chunk(_ maxSize: Int) -> [String] {
        var parts = [String]()
        var index = self.startIndex
        while index < self.endIndex {
            let end = self.index(index,
                                 offsetBy: min(maxSize,
                                               self.distance(from: index,
                                                             to: self.endIndex)))
            let part = String(self[index..<end])
            parts.append(part)
            index = end
        }
        return parts
    }
}
