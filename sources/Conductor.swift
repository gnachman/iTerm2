//
//  Conductor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/22.
//

import Foundation

@objc(iTermConductorDelegate)
protocol ConductorDelegate: Any {
    @objc(conductorWriteString:) func conductorWrite(string: String)
    func conductorAbort(reason: String)
    func conductorTerminate(_ conductor: Conductor)
}

@objc(iTermConductor)
class Conductor: NSObject {
    private let sshargs: String
    private let vars: [String: String]
    private var payloads: [(path: String, destination: String)] = []
    private let initialDirectory: String?
    private let parsedSSHArguments: ParsedSSHArguments
    private let depth: Int32
    @objc let parent: Conductor?
    @objc private(set) var queueWrites = true
    private var framedPID: Int32? = nil
    @objc var handlesKeystrokes: Bool {
        return framedPID != nil && queueWrites
    }
    @objc var sshIdentity: SSHIdentity {
        return parsedSSHArguments.identity
    }

    enum Command {
        case execLoginShell
        case getShell
        case setenv(key: String, value: String)
        // Replace the conductor with this command
        case run(String)
        // Reads the python program and executes it
        case runPython(String)
        // Shell out to this command and then return to conductor
        case shell(String)
        case write(data: Data, dest: String)
        case cd(String)
        case quit
        case ps
        case getpid

        // Framer commands
        case framerRun(String)
        case framerLogin(cwd: String, args: [String])
        case framerSend(Data, pid: Int32)
        case framerKill(pid: Int)
        case framerQuit

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
            case .runPython(_):
                return "runpython"
            case .shell(let cmd):
                return "shell \(cmd)"
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

            case .framerRun(let command):
                return ["run", command].joined(separator: "\n")
            case .framerLogin(cwd: let cwd, args: let args):
                return (["login", cwd] + args).joined(separator: "\n")
            case .framerSend(let data, pid: let pid):
                return (["send", String(pid)] + data.base64EncodedString().chunk(80, continuation: "\\")).joined(separator: "\n")
            case .framerKill(pid: let pid):
                return ["kill", String(pid)].joined(separator: "\n")
            case .framerQuit:
                return "quit"
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
            case .shell(let cmd):
                return "running in shell \(cmd)"
            case .runPython(_):
                return "running Python code"
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
            case .framerRun(let command):
                return "run \(command)"
            case .framerLogin(cwd: let cwd, args: let args):
                return "login cwd=\(cwd) args=\(args)"
            case .framerSend(let data, pid: let pid):
                return "send \(data) to \(pid)"
            case .framerKill(pid: let pid):
                return "kill \(pid)"
            case .framerQuit:
                return "quit"
            }
        }
    }

    struct ExecutionContext {
        let command: Command
        let handler: (PartialResult) -> (VT100ScreenSSHAction?)
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

    private var state: State = .ground {
        willSet {
            DLog("State \(state) -> \(newValue)")
        }
    }

    private var queue = [ExecutionContext]()

    @objc weak var delegate: ConductorDelegate?
    @objc let boolArgs: String
    private var verbose = true

    @objc init(_ sshargs: String,
               boolArgs: String,
               vars: [String: String],
               initialDirectory: String?,
               parent: Conductor?) {
        self.sshargs = sshargs
        self.boolArgs = boolArgs
        parsedSSHArguments = ParsedSSHArguments(sshargs, booleanArgs: boolArgs)
        self.vars = vars
        self.initialDirectory = initialDirectory
        self.depth = (parent?.depth ?? -1) + 1
        self.parent = parent
        super.init()
        DLog("Conductor starting")
    }

    private func DLog(_ messageBlock: @autoclosure () -> String,
                      file: String = #file,
                      line: Int = #line,
                      function: String = #function) {
        if verbose {
            let message = messageBlock()
            print("\(file):\(line) \(function): \(message)")
        }
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
        checkForPython { [weak self] in
            self?.doFraming()
        } otherwise: { [weak self] in
            self?.execLoginShell()
        }
    }

    @objc func sendKeys(_ data: Data) {
        guard let pid = framedPID else {
            return
        }
        framerSend(data: data, pid: pid)
    }

    private func doFraming() {
        execFramer()
        framerLogin(cwd: initialDirectory ?? "$HOME", args: [])
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

    private func framerRun(command: String) {
        send(.framerRun(command)) { result in
            switch result {
            case .line(_), .abort, .end(_):
                return nil
            }
        }
    }

    private func framerLogin(cwd: String, args: [String]) {
        send(.framerLogin(cwd: cwd, args: args)) { [weak self] result in
            switch result {
            case .line(let pidString):
                guard let pid = Int32(pidString) else {
                    self?.fail("login responded with non-int pid \(pidString)")
                    return nil
                }
                self?.framedPID = pid
                return nil
            case .end(_):
                guard let pid = self?.framedPID, let self = self else {
                    return nil
                }
                return VT100ScreenSSHAction(type: .setForegroundProcessID,
                                            pid: pid,
                                            depth: self.depth)
            case .abort:
                return nil
            }
        }
    }

    private func framerSend(data: Data, pid: Int32) {
        send(.framerSend(data, pid: pid)) { result in
            switch result {
            case .line(_), .abort, .end(_):
                return nil
            }
        }
    }

    private func framerKill(pid: Int) {
        send(.framerKill(pid: pid)) { result in
            switch result {
            case .line(_), .abort, .end(_):
                return nil
            }
        }
    }

    private func framerQuit() {
        send(.framerQuit) { result in
            switch result {
            case .line(_), .abort, .end(_):
                return nil
            }
        }
    }

    private func requestPID() {
        send(.getpid) { [weak self] result in
            switch result {
            case .line(let value):
                guard let pid = Int(value) else {
                    self?.fail("Invalid process id \(value)")
                    return nil
                }
                guard let self = self, self.remoteInfo.pid == nil else {
                    self?.fail("Too many lines of output from getpid. Second is \(value)")
                    return nil
                }
                self.remoteInfo.pid = pid
                return nil
            case .abort:
                return nil
            case .end(let status):
                guard status == 0 else {
                    self?.fail("getPID failed with status \(status)")
                    return nil
                }
                guard self?.remoteInfo.pid != nil else {
                    self?.fail("No pid")
                    return nil
                }
                return nil
            }
        }
    }

    private func setEnvironmentVariables() {
        for (key, value) in vars {
            send(.setenv(key: key, value: value)) { [weak self] result in
                switch result {
                case .line(let value):
                    self?.fail("Unexpected output from setenv: \(value)")
                    return nil
                case .abort:
                    return nil
                case .end(let status):
                    guard status == 0 else {
                        self?.fail("setenv failed with status \(status)")
                        return nil
                    }
                    return nil
                }
            }
        }
    }

    private func upload(data: Data, destination: String) {
        send(.write(data: data, dest: destination)) { [weak self] result in
            switch result {
            case .line(let value):
                self?.fail("Unexpected output from write: \(value)")
                return nil
            case .abort:
                return nil
            case .end(let status):
                guard status == 0 else {
                    self?.fail("write failed with status \(status)")
                    return nil
                }
                return nil
            }
        }
    }

    private func cd(_ dir: String) {
        send(.cd(dir)) { [weak self] result in
            switch result {
            case .line(let value):
                self?.fail("Unexpected output from cd: \(value)")
                return nil
            case .abort:
                return nil
            case .end(let status):
                guard status == 0 else {
                    self?.fail("cd failed with status \(status)")
                    return nil
                }
                return nil
            }
        }
    }

    private func execLoginShell() {
        send(.execLoginShell) { [weak self] result in
            switch result {
            case .line(_):
                fatalError()
            case .abort:
                return nil
            case .end(let status):
                guard status == 0 else {
                    self?.fail("exec_login_shell failed with status \(status)")
                    return nil
                }
                return nil
            }
        }
    }

    private func execFramer() {
        let path = Bundle(for: Self.self).url(forResource: "framer", withExtension: "py")!
        let pythonCode = try! String(contentsOf: path)
        runPython(pythonCode)
    }

    private func runPython(_ code: String) {
        send(.runPython(code)) { [weak self] result in
            switch result {
            case .line(_), .abort:
                return nil
            case .end(let status):
                if status == 0 {
                    self?.write(code)
                    self?.write("")
                    self?.write("EOF")
                } else {
                    self?.fail("Status \(status) when running python code")
                }
                return nil
            }
        }
    }

    private func run(_ command: String) {
        send(.run(command)) { [weak self] result in
            switch result {
            case .line(_):
                fatalError()
            case .abort:
                return nil
            case .end(let status):
                guard status == 0 else {
                    self?.fail("run \(command) failed with status \(status)")
                    return nil
                }
                return nil
            }
        }
    }

    private func shell(_ command: String) {
        send(.shell(command)) { [weak self] result in
            switch result {
            case .line(_):
                fatalError()
            case .abort:
                return nil
            case .end(let status):
                guard status == 0 else {
                    self?.fail("shell \(command) failed with status \(status)")
                    return nil
                }
                return nil
            }
        }
    }

    private func checkForPython(_ then: @escaping () -> (), otherwise: @escaping () -> ()) {
        var lines = [String]()
        send(.shell("python3 -V")) { result in
            switch result {
            case .line(let output):
                lines.append(output)
                return nil
            case .abort:
                otherwise()
                return nil
            case .end(let status):
                if status != 0 {
                    otherwise()
                    return nil
                }
                let output = lines.joined(separator: "\n")
                let groups = output.captureGroups(regex: "^Python (3\\.[0-9][0-9]*)")
                if groups.count != 2 {
                    otherwise()
                    return nil
                }
                let version = (output as NSString).substring(with: groups[1])
                let number = NSDecimalNumber(string: version)
                let minimum = NSDecimalNumber(string: "3.7")
                if number.isGreaterThanOrEqual(to: minimum) {
                    then()
                } else {
                    otherwise()
                }
                return nil
            }
        }
    }

    @objc(handleLine:) func handle(line: String) {
        DLog("< \(line)")
        switch state {
        case .ground:
            fail("Unexpected input: \(line)")
        case .willExecute(let context):
            state = .executing(context)
            _ = context.handler(.line(line))
        case .executing(let context):
            _ = context.handler(.line(line))
        }
    }

    @objc func handleCommandBegin(identifier: String) {
        DLog("< command \(identifier) response will begin")
    }

    @objc func handleCommandEnd(identifier: String, status: UInt8) -> VT100ScreenSSHAction {
        DLog("< command \(identifier) ended with status \(status)")
        switch state {
        case .ground:
            fail("Unexpected command end in \(state)")
        case .willExecute(let context), .executing(let context):
            let action = context.handler(.end(status))
            DLog("Command ended. Return to ground state.")
            state = .ground
            dequeue()
            if let action = action {
                return action
            }
        }
        return VT100ScreenSSHAction(type: .none, pid: 0, depth: 0)
    }

    @objc(handleTerminatePID:withCode:)
    func handleTerminate(_ pid: Int32, code: Int32) -> VT100ScreenSSHAction {
        DLog("Process \(pid) terminated")
        if pid == framedPID {
            send(.quit) { [weak self] result in
                guard let self = self else {
                    return nil
                }
                switch result {
                case .end(_), .abort:
                    self.delegate?.conductorTerminate(self)
                case .line(_):
                    break
                }
                return nil
            }
            if let parent = parent, let parentPID = parent.framedPID {
                return VT100ScreenSSHAction(type: .setForegroundProcessID,
                                            pid: parentPID,
                                            depth: parent.depth)
            } else {
                return VT100ScreenSSHAction(type: .resetForegroundProcessID, pid: 0, depth: 0)
            }
        }
        return VT100ScreenSSHAction(type: .none, pid: 0, depth: 0)
    }

    @objc(handleSideChannelOutput:pid:channel:)
    func handleSideChannelOutput(_ string: String, pid: Int32, channel: UInt8) {
        DLog("pid \(pid) channel \(channel) produced: \(string)")
        // TODO something
    }

    private func send(_ command: Command, handler: @escaping (PartialResult) -> (VT100ScreenSSHAction?)) {
        queue.append(ExecutionContext(command: command, handler: handler))
        switch state {
        case .ground:
            dequeue()
        case .willExecute(_), .executing(_):
            return
        }
    }

    private func dequeue() {
        guard delegate != nil else {
            while let pending = queue.first {
                queue.removeFirst()
                _ = pending.handler(.abort)
            }
            return
        }
        guard let pending = queue.first else {
            return
        }
        queue.removeFirst()
        state = .willExecute(pending)
        let parts = pending.command.stringValue.chunk(128)
        for part in parts {
            write(part)
        }
        write("")
    }

    private func write(_ string: String, end: String = "\n") {
        let savedQueueWrites = queueWrites
        queueWrites = false
        DLog("> \(string)")
        delegate?.conductorWrite(string: string + end)
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
        DLog("FAIL: \(reason)")
        let cod = currentOperationDescription
        state = .ground
        for context in queue {
            _ = context.handler(.abort)
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
        for (i, _) in tarJobs.enumerated() {
            if tarJobs[i].add(local: localPath, destination: destination) {
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
    func chunk(_ maxSize: Int, continuation: String = "") -> [String] {
        var parts = [String]()
        var index = self.startIndex
        while index < self.endIndex {
            let end = self.index(index,
                                 offsetBy: min(maxSize,
                                               self.distance(from: index,
                                                             to: self.endIndex)))
            let part = String(self[index..<end]) + (end < self.endIndex ? continuation : "")
            parts.append(part)
            index = end
        }
        return parts
    }
}
