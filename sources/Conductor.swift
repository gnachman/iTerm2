//
//  Conductor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/22.
//

import Foundation

protocol SSHCommandRunning {
    func runRemoteCommand(_ commandLine: String,
                          completion: @escaping  (Data, Int32) -> ())
}

@objc(iTermConductorDelegate)
protocol ConductorDelegate: Any {
    @objc(conductorWriteString:) func conductorWrite(string: String)
    func conductorAbort(reason: String)
}

@objc(iTermConductor)
class Conductor: NSObject, Codable {
    override var debugDescription: String {
        return "<Conductor: \(self.it_addressString) \(sshargs) dcs=\(dcsID) clientUniqueID=\(clientUniqueID) state=\(state) parent=\(String(describing: parent?.debugDescription))>"
    }

    private let sshargs: String
    private let vars: [String: String]
    private struct Payload: Codable {
        let path: String
        let destination: String
    }
    private var payloads: [Payload] = []
    private let initialDirectory: String?
    private let parsedSSHArguments: ParsedSSHArguments
    private let depth: Int32
    @objc let parent: Conductor?
    private var _queueWrites = true
    @objc var queueWrites: Bool {
        if let parent = parent {
            return _queueWrites && parent.queueWrites
        }
        return _queueWrites
    }
    @objc var framing: Bool {
        return framedPID != nil
    }
    @objc(framedPID) var objcFramedPID: NSNumber? {
        if let pid = framedPID {
            return NSNumber(value: pid)
        }
        return nil
    }
    private(set) var framedPID: Int32? = nil
    // If this returns true, route writes through sendKeys(_:).
    @objc var handlesKeystrokes: Bool {
        return framedPID != nil && queueWrites
    }
    @objc var sshIdentity: SSHIdentity {
        return parsedSSHArguments.identity
    }
    private lazy var _processInfoProvider: SSHProcessInfoProvider = {
        let provider = SSHProcessInfoProvider(rootPID: framedPID!, runner: self)
        provider.register(trackedPID: framedPID!)
        return provider
    }()
    @objc var processInfoProvider: ProcessInfoProvider & SessionProcessInfoProvider {
        if framedPID == nil {
            return NullProcessInfoProvider()
        }
        return _processInfoProvider
    }
    private var backgroundJobs = [Int32: State]()

    enum Command: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "<Command: \(operationDescription)>"
        }

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

        var isFramer: Bool {
            switch self {
            case .execLoginShell, .getShell, .setenv(_, _), .run(_), .runPython(_), .shell(_),
                    .write(_, _), .cd(_), .quit, .ps, .getpid:
                return false

            case .framerRun, .framerLogin, .framerSend, .framerKill, .framerQuit:
                return true
            }
        }

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
                return (["send", String(pid), data.base64EncodedString()]).joined(separator: "\n")
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
                return "running “\(cmd)”"
            case .shell(let cmd):
                return "running in shell “\(cmd)”"
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
                return "run “\(command)”"
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

    class StringArray: Codable {
        var strings = [String]()
    }

    struct ExecutionContext: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "<ExecutionContext: command=\(command) handler=\(handler)>"
        }

        let command: Command
        enum Handler: Codable, CustomDebugStringConvertible {
            var debugDescription: String {
                switch self {
                case .failIfNonzeroStatus:
                    return "failIfNonzeroStatus"
                case .handleCheckForPython:
                    return "handleCheckForPython"
                case .fireAndForget:
                    return "fireAndForget"
                case .handleFramerLogin:
                    return "handleFramerLogin"
                case .handleRequestPID:
                    return "handleRequestPID"
                case .writeOnSuccess(let code):
                    return "writeOnSuccess(\(code.count) chars)"
                case .handleRunRemoteCommand(let command, _):
                    return "handleRunRemoteCommand(\(command))"
                case .handleBackgroundJob(let output, _):
                    return"handleBackgroundJob(\(output.strings.count) lines)"
                }
            }

            case failIfNonzeroStatus  // if .end(status) has status == 0 call fail("unexpected status")
            case handleCheckForPython(StringArray)
            case fireAndForget  // don't care what the result is
            case handleFramerLogin
            case handleRequestPID
            case writeOnSuccess(String)  // see runPython
            case handleRunRemoteCommand(String, (Data, Int32) -> ())
            case handleBackgroundJob(StringArray, (Data, Int32) -> ())

            private enum Key: CodingKey {
                case rawValue
                case stringArray
                case string
            }

            private enum RawValues: Int, Codable {
                case failIfNonzeroStatus
                case handleCheckForPython
                case fireAndForget
                case handleFramerLogin
                case handleRequestPID
                case writeOnSuccess
                case handleRunRemoteCommand
                case handleBackgroundJob
            }

            private var rawValue: Int {
                switch self {
                case .failIfNonzeroStatus:
                    return RawValues.failIfNonzeroStatus.rawValue
                case .handleCheckForPython:
                    return RawValues.handleCheckForPython.rawValue
                case .fireAndForget:
                    return RawValues.fireAndForget.rawValue
                case .handleFramerLogin:
                    return RawValues.handleFramerLogin.rawValue
                case .handleRequestPID:
                    return RawValues.handleRequestPID.rawValue
                case .writeOnSuccess(_):
                    return RawValues.writeOnSuccess.rawValue
                case .handleRunRemoteCommand(_, _):
                    return RawValues.handleRunRemoteCommand.rawValue
                case .handleBackgroundJob(_, _):
                    return RawValues.handleBackgroundJob.rawValue
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                try container.encode(rawValue, forKey: .rawValue)
                switch self {
                case .failIfNonzeroStatus, .fireAndForget, .handleFramerLogin, .handleRequestPID:
                    break
                case .handleCheckForPython(let value):
                    try container.encode(value, forKey: .stringArray)
                case .writeOnSuccess(let value):
                    try container.encode(value, forKey: .string)
                case .handleRunRemoteCommand(let value, _):
                    try container.encode(value, forKey: .string)
                case .handleBackgroundJob(let value, _):
                    try container.encode(value, forKey: .stringArray)
                }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                switch try container.decode(RawValues.self, forKey: .rawValue) {
                case .failIfNonzeroStatus:
                    self = .failIfNonzeroStatus
                case .handleCheckForPython:
                    self = .handleCheckForPython(try container.decode(StringArray.self, forKey: .stringArray))
                case .fireAndForget:
                    self = .fireAndForget
                case .handleFramerLogin:
                    self = .handleFramerLogin
                case .handleRequestPID:
                    self = .handleRequestPID
                case .writeOnSuccess:
                    self = .writeOnSuccess(try container.decode(String.self, forKey: .string))
                case .handleRunRemoteCommand:
                    self = .handleRunRemoteCommand(try container.decode(String.self, forKey: .string), {_, _ in})
                case .handleBackgroundJob:
                    self = .handleBackgroundJob(try container.decode(StringArray.self, forKey: .stringArray), {_, _ in})
                }
            }
        }
        let handler: Handler
    }

    enum State: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .ground:
                return "<State: ground>"
            case .willExecute(let context):
                return "<State: willExecute(\(context))>"
            case .executing(let context):
                return "<State: executing(\(context))>"
            }
        }

        case ground  // Have not written, not expecting anything.
        case willExecute(ExecutionContext)  // After writing, before parsing begin.
        case executing(ExecutionContext)  // After parsing begin, before parsing end.
    }

    enum PartialResult {
        case sideChannelLine(line: String, channel: UInt8, pid: Int32)
        case line(String)
        case end(UInt8)  // arg is exit status
        case abort  // couldn't even send the command
    }

    struct RemoteInfo: Codable {
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
    @objc let dcsID: String
    @objc let clientUniqueID: String  // provided by client when hooking dcs
    private var verbose = true

    enum CodingKeys: CodingKey {
        // Note backgroundJobs is not included because it isn't restorable.
      case sshargs, vars, payloads, initialDirectory, parsedSSHArguments, depth, parent,
           framedPID, remoteInfo, state, queue, boolArgs, dcsID, clientUniqueID
    }


    @objc init(_ sshargs: String,
               boolArgs: String,
               dcsID: String,
               clientUniqueID: String,
               vars: [String: String],
               initialDirectory: String?,
               parent: Conductor?) {
        self.sshargs = sshargs
        self.boolArgs = boolArgs
        self.dcsID = dcsID
        self.clientUniqueID = clientUniqueID
        parsedSSHArguments = ParsedSSHArguments(sshargs, booleanArgs: boolArgs)
        self.vars = vars
        self.initialDirectory = initialDirectory
        self.depth = (parent?.depth ?? -1) + 1
        self.parent = parent
        super.init()
        DLog("Conductor starting")
    }

    @objc(newConductorWithJSON:delegate:)
    static func create(_ json: String, delegate: ConductorDelegate) -> Conductor? {
        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8),
              let leaf = try? decoder.decode(Conductor.self, from: data) else {
            return nil
        }
        var current: Conductor? = leaf
        while current != nil {
            current?.delegate = delegate
            current = current?.parent
        }
        return leaf
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sshargs = try container.decode(String.self, forKey: .sshargs)
        vars = try container.decode([String: String].self, forKey: .vars)
        payloads = try container.decode([(Payload)].self, forKey: .payloads)
        initialDirectory = try container.decode(String?.self, forKey: .initialDirectory)
        parsedSSHArguments = try container.decode(ParsedSSHArguments.self, forKey: .parsedSSHArguments)
        depth = try container.decode(Int32.self, forKey: .depth)
        parent = try container.decode(Conductor?.self, forKey: .parent)
        framedPID = try container.decode(Int32?.self, forKey: .framedPID)
        remoteInfo = try container.decode(RemoteInfo.self, forKey: .remoteInfo)
        state = try  container.decode(State.self, forKey: .state)
        queue = try container.decode([ExecutionContext].self, forKey: .queue)
        boolArgs = try container.decode(String.self, forKey: .boolArgs)
        dcsID = try container.decode(String.self, forKey: .dcsID)
        clientUniqueID = try container.decode(String.self, forKey: .clientUniqueID)
    }

    @objc var jsonValue: String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @objc var tree: NSDictionary {
        if let parent = parent {
            return parent.treeWithChildTree(mysubtree)
        }
        return mysubtree
    }

    private var mysubtree: NSDictionary {
        guard let framedPID = framedPID else {
            return [:]
        }
        return [framedPID: [dcsID, [:]]]
    }
    private func treeWithChildTree(_ childTree: NSDictionary) -> NSDictionary {
        guard let framedPID = framedPID else {
            fatalError()
        }
        return [framedPID: [dcsID, childTree]]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sshargs, forKey: .sshargs)
        try container.encode(vars, forKey: .vars)
        try container.encode(payloads, forKey: .payloads)
        try container.encode(initialDirectory, forKey: .initialDirectory)
        try container.encode(parsedSSHArguments, forKey: .parsedSSHArguments)
        try container.encode(depth, forKey: .depth)
        try container.encode(parent, forKey: .parent)
        try container.encode(framedPID, forKey: .framedPID)
        try container.encode(remoteInfo, forKey: .remoteInfo)
        try container.encode(State.ground, forKey: .state)
        try container.encode([ExecutionContext](), forKey: .queue)
        try container.encode(boolArgs, forKey: .boolArgs)
        try container.encode(dcsID, forKey: .dcsID)
        try container.encode(clientUniqueID, forKey: .clientUniqueID)
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
        payloads.append(Payload(path: (path as NSString).expandingTildeInPath,
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
        for payload in payloads {
            builder.add(localPath: URL(fileURLWithPath: payload.path),
                        destination: URL(fileURLWithPath: payload.destination))
        }
        builder.enumeratePayloads { data, destination in
            upload(data: data, destination: destination)
        }
    }

    private func framerLogin(cwd: String, args: [String]) {
        send(.framerLogin(cwd: cwd, args: args), .handleFramerLogin)
    }

    private func framerSend(data: Data, pid: Int32) {
        send(.framerSend(data, pid: pid), .fireAndForget)
    }

    private func framerKill(pid: Int) {
        send(.framerKill(pid: pid), .fireAndForget)
    }

    private func framerQuit() {
        send(.framerQuit, .fireAndForget)
    }

    private func requestPID() {
        send(.getpid, .handleRequestPID)
    }

    private func setEnvironmentVariables() {
        for (key, value) in vars {
            send(.setenv(key: key, value: value), .failIfNonzeroStatus)
        }
    }

    private func upload(data: Data, destination: String) {
        send(.write(data: data, dest: destination), .failIfNonzeroStatus)
    }

    private func cd(_ dir: String) {
        send(.cd(dir), .failIfNonzeroStatus)
    }

    private func execLoginShell() {
        send(.execLoginShell, .failIfNonzeroStatus)
    }

    private func execFramer() {
        let path = Bundle(for: Self.self).url(forResource: "framer", withExtension: "py")!
        let pythonCode = try! String(contentsOf: path)
        runPython(pythonCode)
    }

    private func runPython(_ code: String) {
        send(.runPython(code), .writeOnSuccess(code))
    }

    private func run(_ command: String) {
        send(.run(command), .failIfNonzeroStatus)
    }

    private func shell(_ command: String) {
        send(.shell(command), .failIfNonzeroStatus)
    }

    private func checkForPython(_ then: @escaping () -> (), otherwise: @escaping () -> ()) {
        send(.shell("python3 -V"), .handleCheckForPython(StringArray()))
    }

    private func update(executionContext: ExecutionContext, result: PartialResult) -> () {
        switch executionContext.handler {
        case .failIfNonzeroStatus:
            switch result {
            case .end(let status):
                if status != 0 {
                    fail("\(executionContext.command.stringValue): Unepected status \(status)")
                }
            case .abort, .line(_), .sideChannelLine(line: _, channel: _, pid: _):
                break
            }
            return
        case .handleCheckForPython(let lines):
            switch result {
            case .line(let output), .sideChannelLine(line: let output, channel: 1, pid: _):
                lines.strings.append(output)
                return
            case .abort, .sideChannelLine(_, _, _):
                execLoginShell()
                return
            case .end(let status):
                if status != 0 {
                    execLoginShell()
                    return
                }
                let output = lines.strings.joined(separator: "\n")
                let groups = output.captureGroups(regex: "^Python (3\\.[0-9][0-9]*)")
                if groups.count != 2 {
                    execLoginShell()
                    return
                }
                let version = (output as NSString).substring(with: groups[1])
                let parts = version.components(separatedBy: ".")
                let major = Int(parts.get(0, default: "0")) ?? 0
                let minor = Int(parts.get(1, default: "0")) ?? 0
                DLog("Treating version \(version) as \(major).\(minor)")
                if major == 3 && minor >= 7 {
                    doFraming()
                } else {
                    execLoginShell()
                }
                return
            }
        case .fireAndForget:
            return
        case .handleFramerLogin:
            switch result {
            case .line(let pidString):
                guard let pid = Int32(pidString) else {
                    fail("login responded with non-int pid \(pidString)")
                    return
                }
                framedPID = pid
                return
            case .abort, .sideChannelLine(_, _, _), .end(_):
                return
            }
        case .handleRequestPID:
            switch result {
            case .line(let value):
                guard let pid = Int(value) else {
                    fail("Invalid process id \(value)")
                    return
                }
                guard remoteInfo.pid == nil else {
                    fail("Too many lines of output from getpid. Second is \(value)")
                    return
                }
                remoteInfo.pid = pid
                return
            case .abort, .sideChannelLine(_, _, _):
                return
            case .end(let status):
                guard status == 0 else {
                    fail("getPID failed with status \(status)")
                    return
                }
                guard remoteInfo.pid != nil else {
                    fail("No pid")
                    return
                }
                return
            }
        case .writeOnSuccess(let code):
            switch result {
            case .line(_), .abort, .sideChannelLine(_, _, _):
                return
            case .end(let status):
                if status == 0 {
                    write(code)
                    write("")
                    write("EOF")
                } else {
                    fail("Status \(status) when running python code")
                }
                return
            }
        case .handleRunRemoteCommand(let commandLine, let completion):
            switch result {
            case .line(let line):
                guard let pid = Int32(line) else {
                    return
                }
                addBackgroundJob(pid,
                                 command: .framerRun(commandLine),
                                 completion: completion)
            case .sideChannelLine(_, _, _), .abort, .end(_):
                break
            }
            return
        case .handleBackgroundJob(let output, let completion):
            switch result {
            case .line(_):
                fail("Unexpected output from \(executionContext.command.stringValue)")
            case .sideChannelLine(line: let line, channel: 1, pid: _):
                output.strings.append(line)
            case .abort, .sideChannelLine(_, _, _):
                completion(Data(), -2)
            case .end(let status):
                let combined = output.strings.joined(separator: "")
                completion(combined.data(using: .utf8) ?? Data(),
                           Int32(status))
            }
            return
        }
    }

    @objc(handleLine:depth:) func handle(line: String, depth: Int32) {
        if depth != self.depth {
            DLog("Pass line with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handle(line: line, depth: depth)
            return
        }
        DLog("< \(line)")
        switch state {
        case .ground:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            DLog("Unexpected input: \(line)")
        case .willExecute(let context), .executing(let context):
            state = .executing(context)
            update(executionContext: context, result: .line(line))
        }
    }

    @objc func handleCommandBegin(identifier: String, depth: Int32) {
        DLog("< command \(identifier) response will begin for depth \(depth) vs my depth of \(self.depth)")
    }

    @objc func handleCommandEnd(identifier: String, status: UInt8, depth: Int32) {
        if depth != self.depth {
            DLog("Pass command-end with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handleCommandEnd(identifier: identifier, status: status, depth: depth)
            return
        }
        DLog("< command \(identifier) ended with status \(status) while in state \(state)")
        switch state {
        case .ground:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            DLog("Unexpected command end in \(state)")
        case .willExecute(let context), .executing(let context):
            update(executionContext: context, result: .end(status))
            DLog("Command ended. Return to ground state.")
            state = .ground
            dequeue()
        }
    }

    @objc(handleTerminatePID:withCode:depth:)
    func handleTerminate(_ pid: Int32, code: Int32, depth: Int32) {
        if depth != self.depth {
            DLog("Pass command-terminated with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handleTerminate(pid, code: code, depth: depth)
            return
        }
        DLog("Process \(pid) terminated")
        if pid == framedPID {
            send(.quit, .fireAndForget)
        } else if let jobState = backgroundJobs[pid] {
            switch jobState {
            case .ground:
                // Tolerate unexpected inputs - this is essential for getting back on your feet when
                // restoring.
                DLog("Unexpected termination of \(pid)")
            case .willExecute(let context), .executing(let context):
                update(executionContext: context, result: .end(UInt8(code)))
                backgroundJobs.removeValue(forKey: pid)
            }
        }
    }

    @objc(handleSideChannelOutput:pid:channel:depth:)
    func handleSideChannelOutput(_ string: String, pid: Int32, channel: UInt8, depth: Int32) {
        if depth != self.depth {
            DLog("Pass side-channel output with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handleSideChannelOutput(string, pid: pid, channel: channel, depth: depth)
            return
        }
        guard let jobState = backgroundJobs[pid] else {
            return
        }
//        DLog("pid \(pid) channel \(channel) produced: \(string)")
        switch jobState {
        case .ground:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            DLog("Unexpected input: \(string)")
        case .willExecute(let context):
            state = .executing(context)
        case .executing(let context):
            update(executionContext: context,
                   result: .sideChannelLine(line: string, channel: channel, pid: pid))
        }
    }

    private func send(_ command: Command, _ handler: ExecutionContext.Handler) {
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
                update(executionContext: pending, result: .abort)
            }
            return
        }
        guard let pending = queue.first else {
            return
        }
        queue.removeFirst()
        state = .willExecute(pending)
        let parts = pending.command.stringValue.chunk(128, continuation: pending.command.isFramer ? "\\" : "")
        for part in parts {
            write(part)
        }
        write("")
    }

    private func write(_ string: String, end: String = "\n") {
        let savedQueueWrites = _queueWrites
        _queueWrites = false
        DLog("> \(string)")
        if let parent = parent {
            if let data = (string + end).data(using: .utf8) {
                parent.sendKeys(data)
            } else {
                DLog("bogus string \(string)")
            }
        } else {
            if delegate == nil {
                DLog("[can't send - nil delegate]")
            }
            delegate?.conductorWrite(string: string + end)
        }
        _queueWrites = savedQueueWrites
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
            update(executionContext: context, result: .abort)
        }
        queue = []
        // Try to launch the login shell so you're not completely stuck.
        delegate?.conductorWrite(string: Command.execLoginShell.stringValue + "\n")
        delegate?.conductorAbort(reason: reason + " while " + cod)
    }
}

extension Conductor: SSHCommandRunning {
    private func addBackgroundJob(_ pid: Int32, command: Command, completion: @escaping (Data, Int32) -> ()) {
        let context = ExecutionContext(command: command, handler: .handleBackgroundJob(StringArray(), completion))
        backgroundJobs[pid] = .executing(context)
    }

    func runRemoteCommand(_ commandLine: String,
                          completion: @escaping (Data, Int32) -> ()) {
        if framedPID == 0 {
            completion(Data(), -1)
            return
        }

        // This command ends almost immediately, providing only the child process's pid as output,
        // but in actuality continues running in the background producing %output messages and
        // eventually %terminate.
        send(.framerRun(commandLine), .handleRunRemoteCommand(commandLine, completion))
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

extension Array {
    func get(_ index: Index, default defaultValue: Element) -> Element {
        if index < endIndex {
            return self[index]
        }
        return defaultValue
    }
}
