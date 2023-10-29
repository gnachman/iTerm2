//
//  Conductor.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/8/22.
//

import Foundation
import FileProvider
import FileProviderService

protocol SSHCommandRunning {
    func runRemoteCommand(_ commandLine: String,
                          completion: @escaping  (Data, Int32) -> ())
    func registerProcess(_ pid: pid_t)
    func deregisterProcess(_ pid: pid_t)
    func poll(_ completion: @escaping (Data) -> ())
}

@objc(iTermConductorDelegate)
protocol ConductorDelegate: Any {
    @objc(conductorWriteString:) func conductorWrite(string: String)
    func conductorAbort(reason: String)
    func conductorQuit()
    func conductorStateDidChange()
    @objc func conductorSendInitialText()
    var guid: String { get }
}

struct SSHReconnectionInfo: Codable {
    var sshargs: String
    var initialDirectory: String?
    var boolargs: String
}

@objc(iTermSSHReconnectionInfo)
class SSHReconnectionInfoObjC: NSObject {
    private(set) var state: SSHReconnectionInfo
    init(_ info: SSHReconnectionInfo) {
        self.state = info
    }

    @objc(initWithData:) init?(serialized: Data) {
        do {
            state = try JSONDecoder().decode(SSHReconnectionInfo.self, from: serialized)
        } catch {
            return nil
        }
    }

    @objc var sshargs: String { state.sshargs }
    @objc var initialDirectory: String? { state.initialDirectory }
    @objc var boolargs: String { state.boolargs }

    @objc var serialized: Data {
        return try! JSONEncoder().encode(state)
    }
}

@objc(iTermConductor)
class Conductor: NSObject, Codable {
    override var debugDescription: String {
        return "<Conductor: \(self.it_addressString) \(sshargs) dcs=\(dcsID) clientUniqueID=\(clientUniqueID) state=\(state) parent=\(String(describing: parent?.debugDescription))>"
    }

    @objc let sshargs: String
    private let varsToSend: [String: String]
    // Environment variables shared from client before running ssh
    private let clientVars: [String: String]
    // Comes from parsedSSHArguments.commandargs but possibly modified to inject shell integration.
    private var modifiedCommandArgs: [String]?
    private var modifiedVars: [String: String]?
    private struct Payload: Codable {
        let path: String
        let destination: String
    }
    private var payloads: [Payload] = []
    private let initialDirectory: String?
    private let parsedSSHArguments: ParsedSSHArguments
    private let shouldInjectShellIntegration: Bool
    private let depth: Int32
    @objc let parent: Conductor?
    @objc var autopollEnabled = true
    private var _queueWrites = true
    private var restored = false
    private var autopoll = ""
    // Jumps that children must do.
    private(set) var subsequentJumps: [SSHReconnectionInfo] = []
    @objc(subsequentJumps) var subsequentJumps_objc: [SSHReconnectionInfoObjC] {
        return subsequentJumps.map { SSHReconnectionInfoObjC($0) }
    }
    // If non-nil, a jump that I haven't done yet.
    private var myJump: SSHReconnectionInfo?
    private var suggestionCache = SuggestionCache()

    @objc
    lazy var fileChecker: FileChecker? = {
        guard #available(macOS 11, *) else {
            return nil
        }
        let checker = FileChecker()
        checker.dataSource = self
        return checker
    }()

    @objc var queueWrites: Bool {
        if let parent = parent {
            return nontransitiveQueueWrites && parent.queueWrites
        }
        return nontransitiveQueueWrites
    }
    private var nontransitiveQueueWrites: Bool {
        switch state {
        case .unhooked:
            return false

        default:
            return _queueWrites
        }
    }

    private struct TTYState {
        var echo = true
        var icanon = true

        var atPasswordPrompt: Bool {
            return !echo && icanon
        }
    }

    private var ttyState = TTYState()

    @objc var framing: Bool {
        return framedPID != nil
    }
    @objc var transitiveProcesses: [iTermProcessInfo] {
        guard let pid = framedPID else {
            return []
        }
        let mine = processInfoProvider.processInfo(for: pid)?.descendants(skipping: 0) ?? []
        let parents = parent?.transitiveProcesses ?? []
        var result = mine
        result.append(contentsOf: parents)
        return result
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
        if let sessionID = delegate?.guid {
            let instance = iTermCPUUtilization.instance(forSessionID: sessionID)
            instance.publisher = provider.cpuUtilizationPublisher
        }
        return provider
    }()
    @objc var cpuUtilizationPublisher: iTermPublisher<NSNumber> {
        if let remote = sshProcessInfoProvider?.cpuUtilizationPublisher {
            return remote
        }
        return iTermLocalCPUUtilizationPublisher.sharedInstance()
    }

    private var sshProcessInfoProvider: SSHProcessInfoProvider? {
        if framedPID == nil && autopollEnabled {
            return nil
        }
        return _processInfoProvider
    }
    @objc var processInfoProvider: ProcessInfoProvider & SessionProcessInfoProvider {
        if framedPID == nil {
            return NullProcessInfoProvider()
        }
        return _processInfoProvider
    }
    private var backgroundJobs = [Int32: State]()
    @objc private(set) var homeDirectory: String?
    @objc private(set) var uname: String?
    @objc private(set) var shell: String?
    private var _terminalConfiguration: CodableNSDictionary?
    @objc var terminalConfiguration: NSDictionary? {
        get {
            _terminalConfiguration?.dictionary
        }
        set {
            _terminalConfiguration = newValue.map { CodableNSDictionary($0) }
        }
    }
    @objc var reconnectionInfo: SSHReconnectionInfoObjC {
        return SSHReconnectionInfoObjC(SSHReconnectionInfo(sshargs: sshargs,
                                                           initialDirectory: currentDirectory ?? initialDirectory,
                                                           boolargs: boolArgs))
    }

    enum FileSubcommand: Codable, Equatable {
        case ls(path: Data, sorting: FileSorting)
        case fetch(path: Data, chunk: DownloadChunk?)
        case stat(path: Data)
        case fetchSuggestions(request: SuggestionRequest.Inputs)
        case rm(path: Data, recursive: Bool)
        case ln(source: Data, symlink: Data)
        case mv(source: Data, dest: Data)
        case mkdir(path: Data)
        case create(path: Data, content: Data)
        case append(path: Data, content: Data)
        case utime(path: Data, date: Date)
        case chmod(path: Data, r: Bool, w: Bool, x: Bool)

        var stringValue: String {
            switch self {
            case .ls(let path, let sort):
                let sortString: String
                switch sort {
                case .byDate:
                    sortString = "d"
                case .byName:
                    sortString = "n"
                }
                return "ls\n\(path.base64EncodedString())\n\(sortString)"

            case .fetch(let path, let chunk):
                if let chunk {
                    return "fetch\n\(path.base64EncodedString())\n\(chunk.offset)\n\(chunk.size)"
                } else {
                    return "fetch\n\(path.base64EncodedString())"
                }

            case .stat(let path):
                return "stat\n\(path.base64EncodedString())"

            case .fetchSuggestions(let request):
                return ["suggest",
                        request.prefix.base64Encoded,
                        request.directories.map { $0.base64Encoded }.joined(separator: " "),
                        (request.workingDirectory ?? "//").base64Encoded,
                        request.executable ? "rx" : "r"
                ].joined(separator: "\n")

            case .rm(let path, let recursive):
                let args = ["rm"] + (recursive ? ["-r"] : []) + [path.base64EncodedString()]
                return args.joined(separator: "\n")

            case .ln(let source, let symlink):
                return ["ln",
                        source.base64EncodedString(),
                        symlink.base64EncodedString()].joined(separator: "\n")
            case .mv(let source, let dest):
                return ["mv",
                        source.base64EncodedString(),
                        dest.base64EncodedString()].joined(separator: "\n")
            case .mkdir(let path):
                return "mkdir\n\(path.base64EncodedString())"
            case .create(path: let path, content: let content):
                return [
                    "create",
                    path.base64EncodedString(),
                    content.base64EncodedString()].joined(separator: "\n")
            case .append(path: let path, content: let content):
                return [
                    "append",
                    path.base64EncodedString(),
                    content.base64EncodedString()].joined(separator: "\n")
            case .utime(path: let path, date: let date):
                return [
                    "utime",
                    path.base64EncodedString(),
                    String(date.timeIntervalSince1970)
                ].joined(separator: "\n")
            case .chmod(path: let path, r: let r, w: let w, x: let x):
                return [
                    "chmod-u",
                    path.base64EncodedString(),
                    (r ? "r" : "-") + (w ? "w" : "-") + (x ? "x" : "-")
                ].joined(separator: "\n")
            }
        }

        var operationDescription: String {
            switch self {
            case .ls(let path, let sort):
                return "ls \(path.stringOrHex) \(sort)"
            case .fetch(let path, let chunk):
                if let chunk {
                    return "fetch \(path.stringOrHex) offset=\(chunk.offset) size=\(chunk.size)"
                } else {
                    return "fetch \(path.stringOrHex)"
                }
            case .stat(let path):
                return "stat \(path.stringOrHex)"
            case .fetchSuggestions(request: let request):
                return "fetchSuggestions \(request)"
            case .rm(path: let path, recursive: let recursive):
                return "rm " + (recursive ? "-r " : "") + path.stringOrHex
            case .ln(source: let source, symlink: let symlink):
                return "ln -s \(source.stringOrHex) \(symlink.stringOrHex)"
            case .mv(source: let source, dest: let dest):
                return "mv \(source.stringOrHex) \(dest.stringOrHex)"
            case .mkdir(path: let path):
                return "mkdir \(path.stringOrHex)"
            case .create(path: let path, content: let content):
                return "create \(path.stringOrHex) length=\(content.count) bytes"
            case .append(path: let path, content: let content):
                return "append \(path.stringOrHex) length=\(content.count) bytes"
            case .utime(path: let path, date: let date):
                return "utime \(path.stringOrHex) \(date)"
            case .chmod(path: let path, r: let r, w: let w, x: let x):
                return "chmod \(path.stringOrHex) r=\(r) w=\(w) x=\(x)"
            }
        }
    }


    enum Command: Equatable, Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "<Command: \(operationDescription)>"
        }

        case execLoginShell([String])
        case setenv(key: String, value: String)
        // Replace the conductor with this command
        case run(String)
        // Reads the python program and executes it
        case runPython(String)
        // Shell out to this command and then return to conductor
        case shell(String)
        case getshell
        case write(data: Data, dest: String)
        case cd(String)
        case quit
        case eval(String)  // string is base-64 encoded bash code

        // Framer commands
        case framerRun(String)
        case framerLogin(cwd: String, args: [String])
        case framerEval(String)
        case framerSend(Data, pid: Int32)
        case framerKill(pid: Int)
        case framerQuit
        case framerRegister(pid: pid_t)
        case framerDeregister(pid: pid_t)
        case framerPoll
        case framerReset
        case framerAutopoll
        case framerSave([String:String])
        case framerFile(FileSubcommand)

        var isFramer: Bool {
            switch self {
            case .execLoginShell, .setenv(_, _), .run(_), .runPython(_), .shell(_),
                    .write(_, _), .cd(_), .quit, .getshell, .eval(_):
                return false

            case .framerRun, .framerLogin, .framerSend, .framerKill, .framerQuit, .framerRegister(_),
                    .framerDeregister(_), .framerPoll, .framerReset, .framerAutopoll, .framerSave(_),
                    .framerFile(_), .framerEval:
                return true
            }
        }

        var stringValue: String {
            switch self {
            case .execLoginShell(let args):
                return (["exec_login_shell"] + args).joined(separator: "\n")
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
            case .eval(let b64):
                return "eval \(b64)"
            case .getshell:
                return "getshell"

            case .framerRun(let command):
                return ["run", command].joined(separator: "\n")
            case .framerLogin(cwd: let cwd, args: let args):
                return (["login", cwd] + args).joined(separator: "\n")
            case .framerEval(let script):
                return ["eval", script.base64Encoded].joined(separator: "\n")
            case .framerSend(let data, pid: let pid):
                return (["send", String(pid), data.base64EncodedString()]).joined(separator: "\n")
            case .framerKill(pid: let pid):
                return ["kill", String(pid)].joined(separator: "\n")
            case .framerQuit:
                return "quit"
            case .framerRegister(pid: let pid):
                return ["register", String(pid)].joined(separator: "\n")
            case .framerDeregister(pid: let pid):
                return ["dereigster", String(pid)].joined(separator: "\n")
            case .framerPoll:
                return "poll"
            case .framerReset:
                return "reset"
            case .framerAutopoll:
                return "autopoll"
            case .framerSave(let dict):
                let kvps = dict.keys.map { "\($0)=\(dict[$0]!)" }
                return (["save"] + kvps).joined(separator: "\n")
            case .framerFile(let subcommand):
                return "file\n" + subcommand.stringValue
            }
        }

        var operationDescription: String {
            switch self {
            case .execLoginShell(let args):
                return "starting login shell with args \(args.joined(separator: " "))"
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
            case .eval:
                return "evaling"
            case .getshell:
                return "getshell"
            case .framerRun(let command):
                return "run “\(command)”"
            case .framerLogin(cwd: let cwd, args: let args):
                return "login cwd=\(cwd) args=\(args)"
            case .framerEval:
                return "eval"
            case .framerSave(let dict):
                return "save \(dict.keys.joined(separator: ", "))"
            case .framerSend(let data, pid: let pid):
                return "send \(data.semiVerboseDescription) to \(pid)"
            case .framerKill(pid: let pid):
                return "kill \(pid)"
            case .framerQuit:
                return "quit"
            case .framerRegister(pid: let pid):
                return ["register", String(pid)].joined(separator: " ")
            case .framerDeregister(pid: let pid):
                return ["dereigster", String(pid)].joined(separator: " ")
            case .framerPoll:
                return "poll"
            case .framerReset:
                return "reset"
            case .framerAutopoll:
                return "autopoll"
            case .framerFile(let subcommand):
                return "file \(subcommand.operationDescription)"
            }
        }
    }

    class StringArray: Codable {
        var string: String {
            return strings.joined(separator: "")
        }
        var strings = [String]()
    }

    struct ExecutionContext: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "<ExecutionContext: command=\(command) handler=\(handler)\(canceled ? " CANCELED": ""))>"
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
                case .handleFramerLogin(let output):
                    return "handleFramerLogin(\(output.string))"
                case .handleJump:
                    return "handleJump"
                case .writeOnSuccess(let code):
                    return "writeOnSuccess(\(code.count) chars)"
                case .handleRunRemoteCommand(let command, _):
                    return "handleRunRemoteCommand(\(command))"
                case .handleBackgroundJob(let output, _):
                    return"handleBackgroundJob(\(output.strings.count) lines)"
                case .handlePoll(_, _):
                    return "handlePoll"
                case .handleGetShell(let output):
                    return "handleGetShell(\(output.string))"
                case .handleFile(_, _):
                    return "handleFile"
                case .handleNonFramerLogin:
                    return "handleNonFramerLogin"
                }
            }

            case failIfNonzeroStatus  // if .end(status) has status == 0 call fail("unexpected status")
            case handleCheckForPython(StringArray)
            case fireAndForget  // don't care what the result is
            case handleFramerLogin(StringArray)
            case handleJump(StringArray)
            case writeOnSuccess(String)  // see runPython
            case handleRunRemoteCommand(String, (Data, Int32) -> ())
            case handleBackgroundJob(StringArray, (Data, Int32) -> ())
            case handlePoll(StringArray, (Data) -> ())
            case handleGetShell(StringArray)
            case handleFile(StringArray, (String, Int32) -> ())
            case handleNonFramerLogin

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
                case handleJump
                case writeOnSuccess
                case handleRunRemoteCommand
                case handleBackgroundJob
                case handlePoll
                case handleGetShell
                case handleFile
                case handleNonFramerLogin
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
                case .handleJump:
                    return RawValues.handleJump.rawValue
                case .writeOnSuccess(_):
                    return RawValues.writeOnSuccess.rawValue
                case .handleRunRemoteCommand(_, _):
                    return RawValues.handleRunRemoteCommand.rawValue
                case .handleBackgroundJob(_, _):
                    return RawValues.handleBackgroundJob.rawValue
                case .handlePoll(_, _):
                    return RawValues.handlePoll.rawValue
                case .handleGetShell(_):
                    return RawValues.handleGetShell.rawValue
                case .handleFile(_, _):
                    return RawValues.handleFile.rawValue
                case .handleNonFramerLogin:
                    return RawValues.handleNonFramerLogin.rawValue
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                try container.encode(rawValue, forKey: .rawValue)
                switch self {
                case .failIfNonzeroStatus, .fireAndForget, .handleFramerLogin(_), .handlePoll(_, _),
                        .handleJump, .handleNonFramerLogin:
                    break
                case .handleCheckForPython(let value):
                    try container.encode(value, forKey: .stringArray)
                case .handleGetShell(let value):
                    try container.encode(value, forKey: .stringArray)
                case .writeOnSuccess(let value):
                    try container.encode(value, forKey: .string)
                case .handleRunRemoteCommand(let value, _):
                    try container.encode(value, forKey: .string)
                case .handleBackgroundJob(let value, _):
                    try container.encode(value, forKey: .stringArray)
                case .handleFile(_, _):
                    break
                }
            }

            enum Exception: Error {
                case noncodable
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
                    self = .handleFramerLogin(try container.decode(StringArray.self, forKey: .stringArray))
                case .handleJump:
                    self = .handleJump(try container.decode(StringArray.self, forKey: .stringArray))
                case .writeOnSuccess:
                    self = .writeOnSuccess(try container.decode(String.self, forKey: .string))
                case .handleRunRemoteCommand:
                    self = .handleRunRemoteCommand(try container.decode(String.self, forKey: .string), {_, _ in})
                case .handleBackgroundJob:
                    self = .handleBackgroundJob(try container.decode(StringArray.self, forKey: .stringArray), {_, _ in})
                case .handlePoll:
                    self = .handlePoll(try container.decode(StringArray.self, forKey: .stringArray), {_ in})
                case .handleGetShell:
                    self = .handleGetShell(try container.decode(StringArray.self, forKey: .stringArray))
                case .handleFile:
                    self = .handleFile(StringArray(), { _, _ in })
                case .handleNonFramerLogin:
                    self = .handleNonFramerLogin
                }
            }
        }
        let handler: Handler
        var canceled = false
    }

    struct Nesting: Codable {
        let pid: pid_t
        let dcsID: String
    }

    struct FinishedRecoveryInfo {
        var login: pid_t
        var dcsID: String
        var parentage: [Nesting] = []
        var sshargs: String
        var boolArgs: String
        var clientUniqueID: String

        var tree: NSDictionary {
            return (parentage + [Nesting(pid: login, dcsID: dcsID)]).tree
        }
    }

    struct RecoveryInfo: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            return "login=\(String(describing: login)) dcsID=\(String(describing: dcsID)) parentage=\(parentage) sshargs=\(String(describing: sshargs)) boolArgs=\(String(describing: boolArgs)) clientUniqueID=\(String(describing: clientUniqueID))"
        }
        var login: pid_t?
        var dcsID: String?
        // [(child pid 0, dcs ID 0), (child pid 1, dcs ID 1)] -> [child pid 0: (dcs ID 0, [child pid 1: (dcis ID 1, [:])])]
        var parentage: [Nesting] = []
        var sshargs: String?
        var boolArgs: String?
        var clientUniqueID: String?

        var finished: FinishedRecoveryInfo? {
            guard let login = login,
                  let dcsID = dcsID,
                  let sshargs = sshargs,
                  let boolArgs = boolArgs,
                  let clientUniqueID = clientUniqueID else {
                return nil
            }
            return FinishedRecoveryInfo(
                login: login,
                dcsID: dcsID,
                parentage: parentage,
                sshargs: sshargs,
                boolArgs: boolArgs,
                clientUniqueID: clientUniqueID)
        }
    }

    enum RecoveryState: Codable, CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .ground:
                return "ground"
            case .building(let info):
                return "building \(info)"
            }
        }
        case ground
        case building(RecoveryInfo)
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
            case .unhooked:
                return "<State: unhooked>"
            case .recovery(let recoveryState):
                return "<State: recovery \(recoveryState)>"
            case .recovered:
                return "<State: recovered>"
            }
        }

        case ground  // Have not written, not expecting anything.
        case willExecute(ExecutionContext)  // After writing, before parsing begin.
        case executing(ExecutionContext)  // After parsing begin, before parsing end.
        case unhooked  // Not using framer. IO is direct.
        case recovery(RecoveryState)  // In recovery mode. Will enter ground when done.
        case recovered // short-lived state while waiting for vt100parser to get updated.
    }

    enum PartialResult {
        case sideChannelLine(line: String, channel: UInt8, pid: Int32)
        case line(String)
        case end(UInt8)  // arg is exit status
        case abort  // couldn't even send the command
        case canceled
    }

    private var state: State = .ground {
        willSet {
            DLog("[\(framedPID.map { String($0) } ?? "unframed")] state \(state) -> \(newValue)")
        }
    }

    private var queue = [ExecutionContext]()

    @objc weak var delegate: ConductorDelegate? {
        didSet {
            if !restored || framedPID == nil {
                return
            }
            restored = false
        }
    }
    @objc let boolArgs: String
    @objc let dcsID: String
    @objc let clientUniqueID: String  // provided by client when hooking dcs
    @objc var currentDirectory: String?

    private let superVerbose = false
    private var verbose: Bool {
        return superVerbose || gDebugLogging.boolValue
    }

    enum CodingKeys: CodingKey {
        // Note backgroundJobs is not included because it isn't restorable.
      case sshargs, varsToSend, payloads, initialDirectory, parsedSSHArguments, depth, parent,
           framedPID, remoteInfo, state, queue, boolArgs, dcsID, clientUniqueID,
           modifiedVars, modifiedCommandArgs, clientVars, shouldInjectShellIntegration,
           homeDirectory, shell, uname, terminalConfiguration
    }


    @objc init(_ sshargs: String,
               boolArgs: String,
               dcsID: String,
               clientUniqueID: String,
               varsToSend: [String: String],
               clientVars: [String: String],
               initialDirectory: String?,
               shouldInjectShellIntegration: Bool,
               parent: Conductor?) {
        self.sshargs = sshargs
        self.boolArgs = boolArgs
        self.dcsID = dcsID
        self.clientUniqueID = clientUniqueID
        parsedSSHArguments = ParsedSSHArguments(sshargs, booleanArgs: boolArgs)
        self.varsToSend = varsToSend
        self.clientVars = clientVars

        self.initialDirectory = initialDirectory
        self.shouldInjectShellIntegration = shouldInjectShellIntegration
        if let parent {
            if parent.framing {
                self.depth = parent.depth + 1
            } else {
                // Use same depth as parent because it won't wrap input for us.
                self.depth = parent.depth
            }
        } else {
            self.depth = 0
        }
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
        leaf.resetTransitively()
        return leaf
    }

    @objc(initWithRecovery:)
    init(recovery: ConductorRecovery) {
        sshargs = recovery.sshargs
        varsToSend = [:]
        clientVars = [:]
        payloads = []
        initialDirectory = nil
        shouldInjectShellIntegration = false
        parsedSSHArguments = ParsedSSHArguments(sshargs, booleanArgs: recovery.boolArgs)
        if let parent = recovery.parent {
            if parent.framing {
                depth = parent.depth + 1
            } else {
                depth = parent.depth
            }
        } else {
            depth = 0
        }
        framedPID = recovery.pid
        state = .recovered
        boolArgs = recovery.boolArgs
        dcsID = recovery.dcsID
        clientUniqueID = recovery.clientUniqueID
        parent = recovery.parent
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sshargs = try container.decode(String.self, forKey: .sshargs)
        varsToSend = try container.decode([String: String].self, forKey: .varsToSend)
        clientVars = try container.decode([String: String].self, forKey: .clientVars)
        payloads = try container.decode([(Payload)].self, forKey: .payloads)
        initialDirectory = try container.decode(String?.self, forKey: .initialDirectory)
        shouldInjectShellIntegration = try container.decode(Bool.self, forKey: .shouldInjectShellIntegration)
        parsedSSHArguments = try container.decode(ParsedSSHArguments.self, forKey: .parsedSSHArguments)
        depth = try container.decode(Int32.self, forKey: .depth)
        parent = try container.decode(Conductor?.self, forKey: .parent)
        framedPID = try container.decode(Int32?.self, forKey: .framedPID)
        state = try  container.decode(State.self, forKey: .state)
        queue = try container.decode([ExecutionContext].self, forKey: .queue)
        boolArgs = try container.decode(String.self, forKey: .boolArgs)
        dcsID = try container.decode(String.self, forKey: .dcsID)
        clientUniqueID = try container.decode(String.self, forKey: .clientUniqueID)
        modifiedVars = try container.decode([String: String]?.self, forKey: .modifiedVars)
        modifiedCommandArgs = try container.decode([String]?.self, forKey: .modifiedCommandArgs)
        homeDirectory = try? container.decode(String?.self, forKey: .homeDirectory)
        shell = try? container.decode(String?.self, forKey: .shell)
        uname = try? container.decode(String?.self, forKey: .uname)
        _terminalConfiguration = try? container.decode(CodableNSDictionary?.self, forKey: .terminalConfiguration)
        restored = true
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
        let children: [AnyHashable: Any] = [:]
        let rhs: [Any] =  [dcsID, children] as [Any]
        return [framedPID: rhs]
    }

    private func treeWithChildTree(_ childTree: NSDictionary) -> NSDictionary {
        guard let framedPID = framedPID else {
            return [0: [dcsID, childTree] as [Any]]
        }
        return [framedPID: [dcsID, childTree] as [Any]]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sshargs, forKey: .sshargs)
        try container.encode(varsToSend, forKey: .varsToSend)
        try container.encode(clientVars, forKey: .clientVars)
        try container.encode(payloads, forKey: .payloads)
        try container.encode(initialDirectory, forKey: .initialDirectory)
        try container.encode(shouldInjectShellIntegration, forKey: .shouldInjectShellIntegration)
        try container.encode(parsedSSHArguments, forKey: .parsedSSHArguments)
        try container.encode(depth, forKey: .depth)
        try container.encode(parent, forKey: .parent)
        try container.encode(framedPID, forKey: .framedPID)
        try container.encode(State.ground, forKey: .state)
        try container.encode([ExecutionContext](), forKey: .queue)
        try container.encode(boolArgs, forKey: .boolArgs)
        try container.encode(dcsID, forKey: .dcsID)
        try container.encode(clientUniqueID, forKey: .clientUniqueID)
        try container.encode(modifiedVars, forKey: .modifiedVars)
        try container.encode(modifiedCommandArgs, forKey: .modifiedCommandArgs)
        try container.encode(homeDirectory, forKey: .homeDirectory)
        try container.encode(shell, forKey: .shell)
        try container.encode(uname, forKey: .uname)
        try container.encode(_terminalConfiguration, forKey: .terminalConfiguration)
    }

    private func DLog(_ messageBlock: @autoclosure () -> String,
                      file: String = #file,
                      line: Int = #line,
                      function: String = #function) {
        if verbose {
            let message = messageBlock()
            DebugLogImpl(file, Int32(line), function, "[\(self.it_addressString)@\(depth)] \(message)")
            if superVerbose {
                NSLog("%@", "[\(self.it_addressString)@\(depth)] \(message)")
            }
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
        getshell()
    }

    @objc(startJumpingTo:) func startJumping(to jumps: [SSHReconnectionInfoObjC]) {
        precondition(!jumps.isEmpty)
        myJump = jumps.first!.state
        subsequentJumps = Array(jumps.dropFirst().map { $0.state })
        start()
    }

    @objc(canTransferFilesTo:)
    func canTransferFilesTo(_ path: SCPPath) -> Bool {
        guard framing else {
            return false
        }
        return sshIdentity.hostname == path.hostname && (sshIdentity.username == nil || sshIdentity.username == path.username)
    }

    @available(macOS 11, *)
    @objc(download:)
    func download(path: SCPPath) {
        let file = ConductorFileTransfer(path: path,
                                         localPath: nil,
                                         delegate: self)
        file.download()
    }

    @available(macOS 11, *)
    @objc(uploadFile:to:)
    func upload(file: String, to destinationPath: SCPPath) {
        let file = ConductorFileTransfer(path: destinationPath,
                                         localPath: file,
                                         delegate: self)
        file.upload()
    }

    private var jumpScript: String {
        defer {
            myJump = nil
        }
        let path = Bundle(for: Conductor.self).path(forResource: "utilities/it2ssh", ofType: nil)!
        let it2ssh = try! String(contentsOfFile: path)
        let code = """
        #!/usr/bin/env bash
        rm $SELF
        unset SELF
        it2ssh_wrapper() {
        \(it2ssh)
        }
        it2ssh_wrapper \(myJump!.sshargs)
        """
        return code
    }

    private func jumpWithEval() {
        eval(code: jumpScript)
    }

    @objc func childDidBeginJumping() {
        myJump = nil
    }

    private func didFinishGetShell() {
        setEnvironmentVariables()
        uploadPayloads()
        if let dir = initialDirectory {
            cd(dir)
        }
        checkForPython()
    }

    @objc func startRecovery() {
        write("\nrecover\n\n")
        state = .recovery(.ground)
        delegate?.conductorStateDidChange()
    }

    @objc func recoveryDidFinish() {
        DLog("Recovery finished")
        switch state {
        case .recovered:
            delegate?.conductorStateDidChange()
            state = .ground
        default:
            break
        }
    }

    @objc func quit() {
        queue = []
        state = .ground
        send(.quit, .fireAndForget)
        delegate?.conductorQuit()
        delegate?.conductorStateDidChange()
    }

    func eval(code: String) {
        send(.eval(code.base64Encoded), .fireAndForget)
    }

    @objc(ancestryContainsClientUniqueID:)
    func ancestryContains(clientUniqueID: String) -> Bool {
        return self.clientUniqueID == clientUniqueID || (parent?.ancestryContains(clientUniqueID: clientUniqueID) ?? false)
    }

    @objc func sendKeys(_ data: Data) {
        guard let pid = framedPID else {
            DLog("[sendKeys] Write: \(data.stringOrHex)")
            delegate?.conductorWrite(string: String(data: data, encoding: .isoLatin1)!)
            return
        }
        framerSend(data: data, pid: pid)
    }

    @available(macOS 11, *)
    @objc
    func fetchSuggestions(_ request: SuggestionRequest) {
        // Always run the completion block after a spin of the mainloop because
        // iTermStatusBarLargeComposerViewController will erase the suggestion asynchronously :(
        guard framing else {
            DispatchQueue.main.async {
                request.completion([])
            }
            return
        }
        if let cached = suggestionCache.get(request.inputs) {
            DispatchQueue.main.async {
                request.completion(cached)
            }
            return
        }
        Task {
            do {
                DLog("Request suggestions \(request)")
                let suggestions = try await self.suggestions(request.inputs)
                DispatchQueue.main.async { [weak self] in
                    self?.suggestionCache.insert(inputs: request.inputs, suggestions: suggestions)
                    request.completion(suggestions)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.suggestionCache.insert(inputs: request.inputs, suggestions: [])
                    request.completion([])
                }
            }
        }
    }

    private func doFraming() {
        execFramer()
        framerSave(["dcsID": dcsID,
                    "sshargs": sshargs,
                    "boolArgs": boolArgs,
                    "clientUniqueID": clientUniqueID])
        runRemoteCommand("uname -a") { [weak self] data, status in
            if status == 0 {
                self?.uname = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.delegate?.conductorStateDidChange()
            }
        }
        runRemoteCommand("echo $HOME") { [weak self] data, status in
            if status == 0 {
                self?.homeDirectory = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.delegate?.conductorStateDidChange()
            }
        }
        if myJump != nil {
            framerJump()
        } else {
            framerLogin(cwd: initialDirectory ?? "$HOME",
                        args: modifiedCommandArgs ?? parsedSSHArguments.commandArgs)
        }
        if autopollEnabled {
            send(.framerAutopoll, .fireAndForget)
        }
        delegate?.conductorStateDidChange()
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

    @available(macOS 11.0, *)
    fileprivate func framerFile(_ subcommand: FileSubcommand,
                                highPriority: Bool = false,
                                completion: @escaping (String, Int32) -> ()) {
        log("Sending framerFile request \(subcommand)")
        send(.framerFile(subcommand),
             highPriority: highPriority,
             .handleFile(StringArray(), completion))
    }

    private func framerSave(_ dict: [String: String]) {
        send(.framerSave(dict), .fireAndForget)
    }

    private func framerLogin(cwd: String, args: [String]) {
        send(.framerLogin(cwd: cwd, args: args), .handleFramerLogin(StringArray()))
    }

    private func framerJump() {
        send(.framerEval(jumpScript), .handleJump(StringArray()))
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

    private func setEnvironmentVariables() {
        for (key, value) in modifiedVars ?? varsToSend {
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
        if let modifiedCommandArgs = modifiedCommandArgs,
           modifiedCommandArgs.isEmpty {
            send(.execLoginShell(modifiedCommandArgs), .handleNonFramerLogin)
        } else if parsedSSHArguments.commandArgs.isEmpty {
            send(.execLoginShell([]), .handleNonFramerLogin)
        } else {
            run((parsedSSHArguments.commandArgs).joined(separator: " "))
        }
    }

    private func getshell() {
        send(.getshell, .handleGetShell(StringArray()))
    }

    private func execFramer() {
        let path = Bundle(for: Self.self).url(forResource: "framer", withExtension: "py")!
        var customCode = """
        DEPTH=\(depth)
        """
        if verbose {
            customCode += "\nVERBOSE=1\n"
        }
        let pythonCode = try! String(contentsOf: path).replacingOccurrences(of: "#{SUB}",
                                                                            with: customCode)
        runPython(pythonCode)
    }

    private func runPython(_ code: String) {
        send(.runPython(code), .writeOnSuccess(code))
    }

    private func run(_ command: String) {
        send(.run(command), .failIfNonzeroStatus)
    }

    private func checkForPython() {
        send(.shell("command -v python3 >/dev/null 2>&1 && python3 -V"), .handleCheckForPython(StringArray()))
    }

    private static let minimumPythonMajorVersion = 3
    private static let minimumPythonMinorVersion = 7
    @objc static var minimumPythonVersionForFramer: String {
        "\(minimumPythonMajorVersion).\(minimumPythonMinorVersion)"
    }

    private func shellSupportsInjection(_ shell: String, _ version: String) -> Bool {
        let alwaysSupported = ["zsh", "fish"]
        if alwaysSupported.contains(shell.lastPathComponent) {
            return true
        }
        if shell == "bash" {
            if version.contains("GNU bash, version 3.2.57") && version.contains("apple-darwin") {
                // macOS's bash doesn't support --posix
                return false
            }
            // Non-macOS bash
            return true
        }
        // Unrecognized shell
        return false
    }

    private func sendInitialText() {
        delegate?.conductorSendInitialText()
    }

    private func update(executionContext: ExecutionContext, result: PartialResult) -> () {
        log("update \(executionContext) result=\(result)")
        switch executionContext.handler {
        case .handleNonFramerLogin:
            switch result {
            case .end(let status):
                if status == 0 {
                    sendInitialText()
                } else {
                    fail("\(executionContext.command.stringValue): Unepected status \(status)")
                }
            case .abort, .line(_), .sideChannelLine(line: _, channel: _, pid: _), .canceled:
                break
            }
        case .failIfNonzeroStatus:
            switch result {
            case .end(let status):
                if status != 0 {
                    fail("\(executionContext.command.stringValue): Unepected status \(status)")
                }
            case .abort, .line(_), .sideChannelLine(line: _, channel: _, pid: _), .canceled:
                break
            }
            return
        case .handleCheckForPython(let lines):
            switch result {
            case .line(let output), .sideChannelLine(line: let output, channel: 1, pid: _):
                lines.strings.append(output)
                return
            case .abort, .sideChannelLine(_, _, _), .canceled:
                execLoginShell()
                return
            case .end(let status):
                if status != 0 {
                    execLoginShell()
                    return
                }
                let output = lines.strings.joined(separator: "\n")
                let groups = output.captureGroups(regex: "^Python ([0-9]\\.[0-9][0-9]*)")
                if groups.count != 2 {
                    execLoginShell()
                    return
                }
                let version = (output as NSString).substring(with: groups[1])
                let parts = version.components(separatedBy: ".")
                let major = Int(parts.get(0, default: "0")) ?? 0
                let minor = Int(parts.get(1, default: "0")) ?? 0
                DLog("Treating version \(version) as \(major).\(minor)")
                if major > Self.minimumPythonMajorVersion ||
                    (major == Self.minimumPythonMajorVersion && minor >= Self.minimumPythonMinorVersion) {
                    doFraming()
                } else if myJump != nil {
                    jumpWithEval()
                } else {
                    execLoginShell()
                }
                return
            }
        case .fireAndForget:
            return
        case .handleFramerLogin(let lines):
            switch result {
            case .line(let message):
                lines.strings.append(message)
            case .end(let status):
                finalizeFraming(status: status, lines: lines)
                return
            case .abort, .sideChannelLine(_, _, _), .canceled:
                return
            }
        case .handleJump(let lines):
            // TODO: Would be nice to offer to reconnect?
            switch result {
            case .line(let message):
                lines.strings.append(message)
            case .end(let status):
                finalizeFraming(status: status, lines: lines)
                return
            case .abort, .sideChannelLine, .canceled:
                break
            }
        case .writeOnSuccess(let code):
            switch result {
            case .line(_), .abort, .sideChannelLine(_, _, _), .canceled:
                return
            case .end(let status):
                if status == 0 {
                    write(code + "\nEOF\n")
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
            case .sideChannelLine(_, _, _), .abort, .end(_), .canceled:
                break
            }
            return
        case .handleFile(let lines, let completion):
            switch result {
            case .line(let line):
                lines.strings.append(line)
            case .abort, .canceled:
                completion("", -1)
            case .sideChannelLine(line: _, channel: _, pid: _):
                break
            case .end(let status):
                completion(lines.strings.joined(separator: ""), Int32(status))
            }
        case .handlePoll(let output, let completion):
            switch result {
            case .line(let line):
                output.strings.append(line)
            case .sideChannelLine(_, _, _), .abort, .canceled:
                break
            case .end(_):
                if let data = output.strings.joined(separator: "\n").data(using: .utf8) {
                    completion(data)
                }
            }
            return
        case .handleGetShell(let lines):
            switch result {
            case .line(let output), .sideChannelLine(line: let output, channel: 1, pid: _):
                lines.strings.append(output)
                return
            case .abort, .sideChannelLine(_, _, _), .canceled:
                return
            case .end(let status):
                if status != 0 {
                    DLog("Failed to get shell")
                    return
                }
                // If you ran `it2ssh localhost /usr/local/bin/bash` then the shell is /usr/local/bin/bash.
                // If you ran `it2ssh localhost` then the shell comes from the response to getshell.
                let parts = lines.strings.joined(separator: "").components(separatedBy: "\n").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let shell = parsedSSHArguments.commandArgs.first ?? parts.get(0, default: "")
                let home = parts.get(1, default: "")
                let version: String
                if parts.count > 1 {
                    version = parts[2...].joined(separator: "\n")
                } else {
                    version = ""
                }
                if !shell.isEmpty &&
                    !home.isEmpty &&
                    shouldInjectShellIntegration && shellSupportsInjection(shell.lastPathComponent, version) {
                    (modifiedVars, modifiedCommandArgs) = ShellIntegrationInjector.instance.modifyRemoteShellEnvironment(
                        shellIntegrationDir: "\(home)/.iterm2/shell-integration",
                        env: varsToSend,
                        shell: shell,
                        argv: Array(parsedSSHArguments.commandArgs.dropFirst()))
                    if let firstArg = parsedSSHArguments.commandArgs.first {
                        modifiedCommandArgs?.insert(firstArg, at: 0)
                    } else {
                        modifiedCommandArgs?.insert(shell, at: 0)
                    }
                    let dict = ShellIntegrationInjector.instance.files(
                        destinationBase: URL(fileURLWithPath: "/$HOME/.iterm2/shell-integration"))
                    for (local, remote) in dict {
                        payloads.append(Payload(path: local.path,
                                                destination: remote.path))
                    }
                }
                self.shell = shell
                delegate?.conductorStateDidChange()
                didFinishGetShell()
            }
        case .handleBackgroundJob(let output, let completion):
            switch result {
            case .line(_):
                fail("Unexpected output from \(executionContext.command.stringValue)")
            case .sideChannelLine(line: let line, channel: 1, pid: _):
                output.strings.append(line)
            case .abort, .sideChannelLine(_, _, _), .canceled:
                completion(Data(), -2)
            case .end(let status):
                let combined = output.strings.joined(separator: "")
                completion(combined.data(using: .utf8) ?? Data(),
                           Int32(status))
            }
            return
        }
    }

    private func finalizeFraming(status: UInt8, lines: StringArray) {
        guard status == 0 else {
            fail(lines.string)
            return
        }
        guard let pid = Int32(lines.string) else {
            fail("Invalid process ID from remote: \(lines.string)")
            return
        }
        if iTermAdvancedSettingsModel.enableSSHFileProvider() {
            if #available(macOS 11.0, *) {
                Task {
                    await ConductorRegistry.shared.register(self)
                }
            }
        }
        framedPID = pid
        sendInitialText()
        delegate?.conductorStateDidChange()
    }

    @objc(handleLine:depth:) func handle(line: String, depth: Int32) {
        DLog("[\(framedPID.map { String($0) } ?? "unframed")] handle input: \(line)")
        if depth != self.depth && framing {
            DLog("Pass line with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handle(line: line, depth: depth)
            return
        }
        DLog("< \(line)")
        switch state {
        case .ground, .unhooked, .recovery(_), .recovered:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            DLog("Unexpected input: \(line)")
        case .willExecute(let context), .executing(let context):
            state = .executing(context)
            update(executionContext: context, result: .line(line))
        }
    }

    @objc func handleUnhook() {
        DLog("< unhook")
        switch state {
        case .executing(let context), .willExecute(let context):
            update(executionContext: context, result: .abort)
        case .ground, .recovered, .unhooked, .recovery:
            break
        }
        DLog("Abort pending commands")
        while let pending = queue.first {
            queue.removeFirst()
            update(executionContext: pending, result: .abort)
        }
        state = .unhooked
    }

    @objc func handleCommandBegin(identifier: String, depth: Int32) {
        // NOTE: no attempt is made to ensure this is meant for me; could be for my parent but it
        // only logs so who cares.
        DLog("[\(framedPID.map { String($0) } ?? "unframed")] begin \(identifier) depth=\(depth)")
    }

    // type can be "f" for framer or "r" for regular (non-framer)
    @objc func handleCommandEnd(identifier: String, type: String, status: UInt8, depth: Int32) {
        DLog("[\(framedPID.map { String($0) } ?? "unframed")] end \(identifier) depth=\(depth)")
        let expectFraming: Bool
        if framing {
            expectFraming = true
        } else {
            switch state {
            case .executing(let context):
                expectFraming = context.command.isFramer
            default:
                expectFraming = false}
        }
        if (!expectFraming && type == "f") || (framing && depth != self.depth) {
            // The purpose of the type argument is so that a non-framing conductor with a framing
            // parent can know whether to handle end itself or to pass it on. The depth is not
            // useful for non-framing conductors since the parser is unaware of them.
            // If a conductor is non-framing then its ancestors will either be framing or will not
            // expect input.
            DLog("Pass command-end with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handleCommandEnd(identifier: identifier, type: type, status: status, depth: depth)
            return
        }
        DLog("< command \(identifier) ended with status \(status) while in state \(state)")
        switch state {
        case .ground, .unhooked, .recovery, .recovered:
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
            case .ground, .unhooked, .recovery, .recovered:
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
        if pid == SSH_OUTPUT_AUTOPOLL_PID {
            if string == "EOF" {
                DLog("Handle autopoll output:\n\(autopoll)")
                sshProcessInfoProvider?.handle(autopoll)
                autopoll = ""
                send(.framerAutopoll, .fireAndForget)
            } else {
                DLog("Add autopoll output of \(string)")
                autopoll.append(string)
                return
            }
            return
        } else if pid == SSH_OUTPUT_NOTIF_PID {
            handleNotif(string)
        }
        guard let jobState = backgroundJobs[pid] else {
            return
        }
//        DLog("pid \(pid) channel \(channel) produced: \(string)")
        switch jobState {
        case .ground, .unhooked, .recovery, .recovered:
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

    private func handleNotif(_ message: String) {
        let notifTTY = "%notif tty "
        if message.hasPrefix(notifTTY) {
            handleTTYNotif(String(message.dropFirst(notifTTY.count)))
        }
    }

    private func handleTTYNotif(_ message: String) {
        DLog("handleTTYNotif: \(message)")
        let parts = message.components(separatedBy: " ")
        struct Flag {
            var enabled: Bool
            var name: String
            init?(_ string: String) {
                if string.count <= 1 {
                    return nil
                }
                if string.hasPrefix("-") {
                    enabled = false
                } else if string.hasPrefix("+") {
                    enabled = true
                } else {
                    return nil
                }
                name = String(string.dropFirst())
            }
            var keyValueTuple: (String, Bool) { (name, enabled) }
        }
        let flagsArray = parts.compactMap { Flag($0) }
        let flags = Dictionary.init(uniqueKeysWithValues: flagsArray.map { $0.keyValueTuple })
        if let value = flags["echo"] {
            ttyState.echo = value
        }
        if let value = flags["icanon"] {
            ttyState.icanon = value
        }
    }

    @objc var atPasswordPrompt: Bool {
        return ttyState.atPasswordPrompt
    }

    private var nesting: [Nesting] {
        guard let framedPID = framedPID else {
            return []
        }

        return [Nesting(pid: framedPID, dcsID: dcsID)] + (parent?.nesting ?? [])
    }

    @objc(handleRecoveryLine:)
    func handleRecovery(line rawline: String) -> ConductorRecovery? {
        let line = rawline.trimmingTrailingNewline
        if !line.hasPrefix(":") {
            return nil
        }
        if line == ":begin-recovery" {
            state = .recovery(.building(RecoveryInfo()))
        }
        if line.hasPrefix(":recovery: process ") {
            // Don't care about background jobs
            return nil
        }
        switch state {
        case .recovery(let recoveryState):
            switch recoveryState {
            case .ground:
                break
            case .building(let info):
                if line.hasPrefix(":end-recovery") {
                    switch recoveryState {
                    case .ground:
                        startRecovery()
                    case .building(var info):
                        if let parent = parent {
                            info.parentage = parent.nesting
                        }

                        guard let finished = info.finished else {
                            quit()
                            return nil
                        }
                        framedPID = finished.login
                        state = .ground

                        return ConductorRecovery(pid: finished.login,
                                                 dcsID: finished.dcsID,
                                                 tree: finished.tree,
                                                 sshargs: finished.sshargs,
                                                 boolArgs: finished.boolArgs,
                                                 clientUniqueID: finished.clientUniqueID,
                                                 parent: parent)
                        delegate?.conductorStateDidChange()
                    }
                    return nil
                }

                let recoveryPrefix = ":recovery: "
                guard line.hasPrefix(recoveryPrefix) else {
                    return nil
                }
                let trimmed = line.removing(prefix: recoveryPrefix)
                guard let (command, value) = trimmed.split(onFirst: " ") else {
                    return nil
                }
                var temp = info
                // See corresponding call to save() that stores these values before starting a login shell.
                switch command {
                case "login":
                    guard let pid = pid_t(value) else {
                        return nil
                    }
                    temp.login = pid
                case "dcsID":
                    temp.dcsID = String(value)
                case "sshargs":
                    temp.sshargs = String(value)
                case "boolArgs":
                    temp.boolArgs = String(value)
                case "clientUniqueID":
                    temp.clientUniqueID = String(value)
                default:
                    return nil
                }
                state = .recovery(.building(temp))
            }
            return nil
        default:
            return nil
        }
    }

    private func send(_ command: Command,
                      highPriority: Bool = false,
                      _ handler: ExecutionContext.Handler) {
        log("append \(command) to queue in state \(state)")
        let context = ExecutionContext(command: command, handler: handler)
        if highPriority {
            queue.insert(context, at: 0)
        } else {
            queue.append(context)
        }
        switch state {
        case .ground, .recovery:
            dequeue()
        case .willExecute(_), .executing(_), .unhooked, .recovered:
            return
        }
    }

    private func cancelEnqueuedRequests(where predicate: (Command) -> (Bool)) {
        let indexes = queue.indexes {
            predicate($0.command)
        }
        for i in indexes {
            if !queue[i].canceled {
                DLog("cancel \(queue[i])")
                queue[i].canceled = true
            }
        }
    }

    private func dequeue() {
        log("dequeue")
        guard let pending = takeNextContext() else {
            return
        }
        state = .willExecute(pending)
        let chunked = pending.command.stringValue.chunk(128, continuation: pending.command.isFramer ? "\\" : "").joined(separator: "\n") + "\n"
        write(chunked)
    }

    private func takeNextContext() -> ExecutionContext? {
        guard delegate != nil else {
            log("delegate is nil. clear queue and reset state.")
            while let pending = queue.first {
                queue.removeFirst()
                update(executionContext: pending, result: .abort)
            }
            state = .ground
            return nil
        }
        while let pending = queue.first, pending.canceled {
            log("cancel \(pending)")
            queue.removeFirst()
            update(executionContext: pending, result: .canceled)
        }
        guard let pending = queue.first else {
            log("queue is empty")
            return nil
        }
        queue.removeFirst()
        return pending
    }

    private func write(_ string: String, end: String = "\n") {
        log("write: \(string)")
        let savedQueueWrites = _queueWrites
        _queueWrites = false
        if let parent = parent {
            if let data = (string + end).data(using: .utf8) {
                DLog("ask parent to send: \(string)")
                parent.sendKeys(data)
            } else {
                DLog("can't utf-8 encode string to send: \(string)")
            }
        } else {
            if delegate == nil {
                DLog("[can't send - nil delegate]")
            }
            DLog("[to \(framedPID.map { String($0) } ?? "non-framing")] Write: \(string)")
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
        case .unhooked:
            return "unhooked"
        case .recovery:
            return "recovery"
        case .recovered:
            return "recovered"
        }
    }

    private func forceReturnToGroundState() {
        DLog("forceReturnToGroundState")
        state = .ground
        for context in queue {
            update(executionContext: context, result: .abort)
        }
        queue = []
        parent?.forceReturnToGroundState()
    }

    private func fail(_ reason: String) {
        DLog("FAIL: \(reason)")
        forceReturnToGroundState()
        // Try to launch the login shell so you're not completely stuck.
        delegate?.conductorWrite(string: Command.execLoginShell([]).stringValue + "\n")
        delegate?.conductorAbort(reason: reason)
    }
}

extension Conductor: SSHCommandRunning {
    func registerProcess(_ pid: pid_t) {
        send(.framerRegister(pid: pid), .fireAndForget)
    }

    func deregisterProcess(_ pid: pid_t) {
        send(.framerDeregister(pid: pid), .fireAndForget)
    }

    func poll(_ completion: @escaping (Data) -> ()) {
        if queue.anySatisfies({ $0.command == .framerPoll }) {
            DLog("Declining to add second poll to queue")
            return
        }
        send(.framerPoll, .handlePoll(StringArray(), completion))
    }

    @objc
    func reset() {
        send(.framerReset, .fireAndForget)
        if autopollEnabled {
            send(.framerAutopoll, .fireAndForget)
            if let framedPID = framedPID {
                sshProcessInfoProvider?.register(trackedPID: framedPID)
            }
        }
    }

    @objc
    func resetTransitively() {
        parent?.reset()
        reset()
    }

    @objc
    func didResynchronize() {
        DLog("didResynchronize")
        forceReturnToGroundState()
        resetTransitively()
        DLog(self.debugDescription)
    }

    private func addBackgroundJob(_ pid: Int32, command: Command, completion: @escaping (Data, Int32) -> ()) {
        let context = ExecutionContext(command: command, handler: .handleBackgroundJob(StringArray(), completion))
        backgroundJobs[pid] = .executing(context)
    }

    @objc
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
            if !part.isEmpty {
                parts.append(part)
            }
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

extension Array where Element == Conductor.Nesting {
    var tree: NSDictionary {
        guard let first = first else {
            return NSDictionary()
        }
        let tuple = [first.dcsID as NSString,
                     Array(dropFirst()).tree]
        return [first.pid: tuple]
    }
}

extension Data {
    func last(_ n: Int) -> Data {
        if count < n {
            return self
        }
        let i = count - n
        return self[i...]
    }
    
    var semiVerboseDescription: String {
        if count > 32 {
            return self[..<16].semiVerboseDescription + "…" + self.last(16).semiVerboseDescription
        }
        if let string = String(data: self, encoding: .utf8) {
            let safe = (string as NSString).escapingControlCharactersAndBackslash()!
            return "“\(safe)”"
        }
        return (self as NSData).it_hexEncoded()
    }
}

@available(macOS 11.0, *)
extension Conductor: SSHEndpoint {
    @MainActor
    private func performFileOperation(subcommand: FileSubcommand,
                                      highPriority: Bool = false) async throws -> String {
        let (output, code) = await withCheckedContinuation { continuation in
            framerFile(subcommand, highPriority: highPriority) { content, code in
                log("File subcommand \(subcommand) finished with code \(code)")
                continuation.resume(returning: (content, code))
            }
        }
        if code < 0 {
            throw SSHEndpointException.connectionClosed
        }
        if code > 0 {
            throw SSHEndpointException.fileNotFound
        }
        return output
    }

    @MainActor
    func listFiles(_ path: String, sort: FileSorting) async throws -> [RemoteFile] {
        return try await logging("listFiles")  {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to list \(path)")
            let json = try await performFileOperation(subcommand: .ls(path: pathData,
                                                                      sorting: sort))
            log("file operation completed with \(json.count) characters")
            guard let jsonData = json.data(using: .utf8) else {
                throw iTermFileProviderServiceError.internalError("Server returned garbage")
            }
            let decoder = JSONDecoder()
            return try iTermFileProviderServiceError.wrap {
                return try decoder.decode([RemoteFile].self, from: jsonData)
            }
        }
    }

    @MainActor
    func download(_ path: String, chunk: DownloadChunk?) async throws -> Data {
        return try await logging("download \(path) \(String(describing: chunk))") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to download \(path)")
            let b64: String = try await performFileOperation(subcommand: .fetch(path: pathData, chunk: chunk))
            log("file operation completed with \(b64.count) characters")
            guard let data = Data(base64Encoded: b64) else {
                throw iTermFileProviderServiceError.internalError("Server returned garbage")
            }
            return data
        }
    }

    private func remoteFile(_ json: String) throws -> RemoteFile {
        log("file operation completed with \(json.count) characters")
        guard let jsonData = json.data(using: .utf8) else {
            throw iTermFileProviderServiceError.internalError("Server returned garbage")
        }
        let decoder = JSONDecoder()
        return try iTermFileProviderServiceError.wrap {
            return try decoder.decode(RemoteFile.self, from: jsonData)
        }
    }

    @MainActor
    func stat(_ path: String) async throws -> RemoteFile {
        return try await stat(path, highPriority: false)
    }

    @MainActor
    func stat(_ path: String, highPriority: Bool = false) async throws -> RemoteFile {
        return try await logging("stat \(path)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to stat \(path)")
            let json = try await performFileOperation(subcommand: .stat(path: pathData),
                                                      highPriority: highPriority)
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func suggestions(_ requestInputs: SuggestionRequest.Inputs) async throws -> [String] {
        log("Request suggestions for inputs \(requestInputs)")
        return try await logging("suggestions \(requestInputs)") {
            cancelEnqueuedRequests { request in
                switch request {
                case .framerFile(let sub):
                    switch sub {
                    case .fetchSuggestions:
                        return true
                    default:
                        return false
                    }
                default:
                    return false
                }
            }
            let json = try await performFileOperation(subcommand: .fetchSuggestions(request: requestInputs),
                                                      highPriority: true)
            log("Suggestions for \(requestInputs) are: \(json)")
            guard let data = json.data(using: .utf8) else {
                return []
            }
            return try JSONDecoder().decode([String].self, from: data)
        }
    }

    @MainActor
    func delete(_ path: String, recursive: Bool) async throws {
        try await logging("delete \(path) recursive=\(recursive)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to delete \(path)")
            _ = try await performFileOperation(subcommand: .rm(path: pathData, recursive: recursive))
            log("finished")
        }
    }

    @MainActor
    func ln(_ source: String, _ symlink: String) async throws -> RemoteFile {
        try await logging("ln -s \(source) \(symlink)") {
            guard let sourceData = source.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(source)
            }
            guard let symlinkData = symlink.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(symlink)
            }
            log("perform file operation to make a symlink")
            let json = try await performFileOperation(subcommand: .ln(source: sourceData,
                                                                      symlink: symlinkData))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func mv(_ source: String, newParent: String, newName: String) async throws -> RemoteFile {
        let dest = newParent.appending(pathComponent: newName)
        return try await logging("mv \(source) \(dest)") {
            guard let sourceData = source.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(source)
            }
            guard let destData = dest.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(newName)
            }
            log("perform file operation to make a symlink")
            let json = try await performFileOperation(subcommand: .mv(source: sourceData,
                                                                      dest: destData))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func rm(_ file: String, recursive: Bool) async throws {
        try await logging("rm \(recursive ? "-rf " : "-f") \(file)") {
            log("perform file operation to unlink")
            guard let fileData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            _ = try await performFileOperation(subcommand: .rm(path: fileData,
                                                               recursive: recursive))
        }
    }

    @MainActor
    func mkdir(_ path: String) async throws {
        try await logging("mkdir \(path)") {
            guard let pathData = path.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(path)
            }
            log("perform file operation to mkdir \(path)")
            _ = try await performFileOperation(subcommand: .mkdir(path: pathData))
            log("finished")
        }
    }

    @MainActor
    func create(_ file: String, content: Data) async throws {
        try await logging("create \(file) length=\(content.count) bytes") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to create \(file)")
            _ = try await performFileOperation(subcommand: .create(path: pathData, content: content))
            log("finished")
        }
    }

    @MainActor
    func append(_ file: String, content: Data) async throws {
        try await logging("append \(file) length=\(content.count) bytes") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to append \(file)")
            _ = try await performFileOperation(subcommand: .append(path: pathData, content: content))
            log("finished")
        }
    }

    // This is just create + stat
    @MainActor
    func replace(_ file: String, content: Data) async throws -> RemoteFile {
        try await logging("replace \(file) length=\(content.count) bytes") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to replace \(file)")
            let json = try await performFileOperation(subcommand: .create(path: pathData, content: content))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func setModificationDate(_ file: String, date: Date) async throws -> RemoteFile {
        try await logging("utime \(file) \(date)") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to utime \(file)")
            let json = try await performFileOperation(subcommand: .utime(path: pathData,
                                                                         date: date))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }

    @MainActor
    func chmod(_ file: String, permissions: RemoteFile.Permissions) async throws -> RemoteFile {
        try await logging("utime \(file) \(permissions)") {
            guard let pathData = file.data(using: .utf8) else {
                throw iTermFileProviderServiceError.notFound(file)
            }
            log("perform file operation to chmod \(file)")
            let json = try await performFileOperation(subcommand: .chmod(path: pathData,
                                                                         r: permissions.r,
                                                                         w: permissions.w,
                                                                         x: permissions.x))
            let result = try remoteFile(json)
            log("finished")
            return result
        }
    }
}

struct CodableNSDictionary: Codable {
    let dictionary: NSDictionary

    init(_ dictionary: NSDictionary) {
        self.dictionary = dictionary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let data = try container.decode(Data.self)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(from: data, format: &format)
        if let dictionary = plist as? NSDictionary {
            self.dictionary = dictionary
        } else {
            throw DecodingError.typeMismatch(Swift.type(of: plist),
                                             .init(codingPath: [],
                                                   debugDescription: "Not a dictionary"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary,
                                                      format: .binary,
                                                      options: 0)
        try container.encode(data)
    }
}

@available(macOS 11.0, *)
extension Conductor: ConductorFileTransferDelegate {
    func beginDownload(fileTransfer: ConductorFileTransfer) {
        guard let path = fileTransfer.localPath() else {
            fileTransfer.fail(reason: "No local path specified")
            return
        }
        let remotePath = fileTransfer.path.path!

        FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
        guard let fileHandle = FileHandle(forUpdatingAtPath: path) else {
            fileTransfer.fail(reason: "Could not open \(path)")
            return
        }
        Task {
            await reallyBeginDownload(fileTransfer: fileTransfer,
                                      remotePath: remotePath,
                                      fileHandle: fileHandle)
        }
    }

    @MainActor
    private func reallyBeginDownload(fileTransfer: ConductorFileTransfer,
                                     remotePath: String,
                                     fileHandle: FileHandle) async {
        do {
            let info = try await stat(fileTransfer.path.path)
            let sizeKnown: Bool
            if let size = info.size {
                sizeKnown = true
                fileTransfer.fileSize = size
            } else {
                sizeKnown = false
            }
            var done = false
            var offset = 0

            let chunkSize = 1024
            defer {
                try? fileHandle.close()
            }
            while !done {
                if fileTransfer.isStopped {
                    fileTransfer.abort()
                    return
                }
                let chunk = DownloadChunk(offset: offset, size: chunkSize)
                let data = try await download(remotePath, chunk: chunk)
                if data.isEmpty {
                    done = true
                } else {
                    try fileHandle.write(contentsOf: data)
                    if !sizeKnown {
                        fileTransfer.fileSize = fileTransfer.fileSize + data.count
                    }
                    fileTransfer.didTransferBytes(UInt(data.count))
                    offset += data.count
                }
            }
            fileTransfer.didFinishSuccessfully()
        } catch {
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }

    func beginUpload(fileTransfer: ConductorFileTransfer) {
        guard let path = fileTransfer.localPath() else {
            fileTransfer.fail(reason: "No local filename specified")
            return
        }
        Task {
            await reallyBeginUpload(fileTransfer: fileTransfer,
                                    from: path)
        }
    }

    @MainActor
    private func reallyBeginUpload(fileTransfer: ConductorFileTransfer,
                                   from path: String) async {
        let tempfile = fileTransfer.path.path + ".uploading-\(UUID().uuidString)"
        do {
            let fileURL = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: fileURL)
            // Make an empty file and then upload chunks so we don't monopolize the connection.
            try await create(tempfile,
                             content: Data())
            fileTransfer.fileSize = data.count
            var offset = 0
            while offset < data.count {
                if fileTransfer.isStopped {
                    fileTransfer.abort()
                    return
                }
                let maxChunkSize = 1024
                let chunk = data.subdata(in: offset..<min(data.count, offset + maxChunkSize))
                offset += chunk.count
                try await append(tempfile, content: chunk)
                fileTransfer.didTransferBytes(UInt(chunk.count))
            }
            // Find a good name
            var proposedName = fileTransfer.path.path!
            var remoteName: String?
            for i in 0..<100 {
                let info = try? await stat(proposedName)
                if info == nil {
                    remoteName = proposedName
                    break
                }
                proposedName = fileTransfer.path.path + " (\(i + 2))"
            }
            guard let remoteName else {
                throw ConductorFileTransfer.ConductorFileTransferError("Too many iterations to find a valid file name on remote host for upload")
            }
            fileTransfer.remoteName = remoteName
            // Rename the tempfile to the proper name
            _ = try await mv(
                tempfile,
                newParent: remoteName.deletingLastPathComponent,
                newName: remoteName.lastPathComponent)
            fileTransfer.didFinishSuccessfully()
        } catch {
            // Delete the temp file
            try? await rm(tempfile, recursive: false)
            fileTransfer.fail(reason: error.localizedDescription)
        }
    }
}

@available(macOS 11, *)
extension Conductor: FileCheckerDataSource {
    func fileCheckerDataSourceDidReset() {
        parent?.fileChecker?.reset()
    }

    @objc
    var canCheckFiles: Bool {
        guard framing && delegate != nil else {
            return false
        }
        if case .unhooked = state {
            return false
        }
        return true
    }

    var fileCheckerDataSourceCanPerformFileChecking: Bool {
        return canCheckFiles
    }

    func fileCheckerDataSourceCheck(path: String, completion: @escaping (Bool) -> ()) {
        Task {
            let exists: Bool
            do {
                DLog("Really stat \(path)")
                _ = try await self.stat(path, highPriority: true)
                exists = true
            } catch {
                exists = false
            }
            DispatchQueue.main.async {
                completion(exists)
            }
        }
    }
}
