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
    func conductorQuit()
    func conductorStateDidChange()
    func conductorStopQueueingInput()
    @objc func conductorSendInitialText()
    var guid: String { get }
}

@objc(iTermConductor)
@MainActor
class Conductor: NSObject, SSHIdentityProvider {
    struct Payload: Codable {
        let path: String
        let destination: String
    }
    class Search {
        var id: String
        var continuation: AsyncThrowingStream<RemoteFile, any Error>.Continuation
        var cancellation: Cancellation
        var query: String
        init(id: String,
             query: String,
             continuation: AsyncThrowingStream<RemoteFile, any Error>.Continuation,
             cancellation: Cancellation) {
            self.id = id
            self.query = query
            self.continuation = continuation
            self.cancellation = cancellation
        }
    }

    override var debugDescription: String {
        return "<Conductor: \(self.it_addressString) \(sshargs) dcs=\(dcsID) clientUniqueID=\(clientUniqueID) state=\(state) parent=\(String(describing: parent?.debugDescription))>"
    }

    class RestorableState: Codable {
        let sshargs: String
        let varsToSend: [String: String]
        let clientVars: [String: String]
        var payloads: [Payload] = []
        let initialDirectory: String?
        let shouldInjectShellIntegration: Bool
        let parsedSSHArguments: ParsedSSHArguments
        let depth: Int32
        var parentState: RestorableState?
        var framedPID: Int32? = nil
        var state: State = .ground
        var queue = [ExecutionContext]()
        let boolArgs: String
        let dcsID: String
        let clientUniqueID: String
        var modifiedVars: [String: String]?
        var modifiedCommandArgs: [String]?
        var homeDirectory: String?
        var shell: String?
        var uname: String?
        var _terminalConfiguration: CodableNSDictionary?
        var discoveredHostname: String?

        init(sshargs: String,
             varsToSend: [String: String],
             clientVars: [String: String],
             payloads: [Payload],
             initialDirectory: String?,
             shouldInjectShellIntegration: Bool,
             parsedSSHArguments: ParsedSSHArguments,
             depth: Int32,
             parentState: RestorableState?,
             framedPID: Int32?,
             state: State,
             queue: [ExecutionContext],
             boolArgs: String,
             dcsID: String,
             clientUniqueID: String,
             modifiedVars: [String: String]?,
             modifiedCommandArgs: [String]?,
             homeDirectory: String?,
             shell: String?,
             uname: String?,
             _terminalConfiguration: CodableNSDictionary?,
             discoveredHostname: String?) {
            self.sshargs = sshargs
            self.varsToSend = varsToSend
            self.clientVars = clientVars
            self.payloads = payloads
            self.initialDirectory = initialDirectory
            self.shouldInjectShellIntegration = shouldInjectShellIntegration
            self.parsedSSHArguments = parsedSSHArguments
            self.depth = depth
            self.parentState = parentState
            self.framedPID = framedPID
            self.state = state
            self.queue = queue
            self.boolArgs = boolArgs
            self.dcsID = dcsID
            self.clientUniqueID = clientUniqueID
            self.modifiedVars = modifiedVars
            self.modifiedCommandArgs = modifiedCommandArgs
            self.homeDirectory = homeDirectory
            self.shell = shell
            self.uname = uname
            self._terminalConfiguration = _terminalConfiguration
            self.discoveredHostname = discoveredHostname
        }

        private enum CodingKeys: CodingKey {
            // Note backgroundJobs is not included because it isn't restorable.
          case sshargs, varsToSend, payloads, initialDirectory, parsedSSHArguments, depth, parent,
               framedPID, remoteInfo, state, queue, boolArgs, dcsID, clientUniqueID,
               modifiedVars, modifiedCommandArgs, clientVars, shouldInjectShellIntegration,
               homeDirectory, shell, pythonversion, uname, terminalConfiguration,
               discoveredHostname
        }

        required init(from decoder: Decoder) throws {
            do {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                sshargs = try container.decode(String.self, forKey: .sshargs)
                varsToSend = try container.decode([String: String].self, forKey: .varsToSend)
                clientVars = try container.decode([String: String].self, forKey: .clientVars)
                payloads = try container.decode([(Payload)].self, forKey: .payloads)
                initialDirectory = try container.decode(String?.self, forKey: .initialDirectory)
                shouldInjectShellIntegration = try container.decode(Bool.self, forKey: .shouldInjectShellIntegration)
                parsedSSHArguments = try container.decode(ParsedSSHArguments.self, forKey: .parsedSSHArguments)
                depth = try container.decode(Int32.self, forKey: .depth)
                parentState = try container.decode(RestorableState?.self, forKey: .parent)
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
                _terminalConfiguration = try? container.decode(CodableNSDictionary?.self,
                                                               forKey: .terminalConfiguration)
                discoveredHostname = try? container.decode(String?.self, forKey: .discoveredHostname)
            } catch {
                DLogMain("Failed to restore conductor: \(error)")
                throw error
            }
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
            try container.encode(parentState, forKey: .parent)
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
            try container.encode(discoveredHostname, forKey: .discoveredHostname)
        }
    }
    let guid = UUID().uuidString
    private var restorableState: RestorableState
    private var restored = false
    enum FramerVersion: Int {
        case v1 = 1

        // v2 changes reset to reset2, taking an argument so we can ignore output before it when resynchronizing.
        // Keep this in sync with the version reported by the recovery code in framer.py
        case v2 = 2
    }
    private(set) var framerVersion: FramerVersion?
    @objc var sshargs: String {
        restorableState.sshargs
    }
    private let discoverHostnameCommand = "hostname -f"
    @objc private(set) var discoveredHostname: String? {
        get {
            restorableState.discoveredHostname
        }
        set {
            restorableState.discoveredHostname = newValue
        }
    }

    var varsToSend: [String: String] {
        restorableState.varsToSend
    }
    // Environment variables shared from client before running ssh
    var clientVars: [String: String] {
        restorableState.clientVars
    }
    var payloads: [Payload] {
        get {
            restorableState.payloads
        }
        set {
            restorableState.payloads = newValue
        }
    }
    var initialDirectory: String? {
        restorableState.initialDirectory
    }
    var shouldInjectShellIntegration: Bool {
        restorableState.shouldInjectShellIntegration
    }
    var parsedSSHArguments: ParsedSSHArguments {
        restorableState.parsedSSHArguments
    }
    var depth: Int32 {
        restorableState.depth
    }
    private var _parent: Conductor?
    @objc var parent: Conductor? {
        if let _parent {
            return _parent
        }
        guard let parentState = restorableState.parentState else {
            return nil
        }
        let parent = Conductor(restorableState: parentState, restored: true)
        _parent = parent
        return parent
    }
    var framedPID: Int32? {
        get {
            restorableState.framedPID
        }
        set {
            restorableState.framedPID = newValue
            if restorableState.framedPID != nil {
                ConductorRegistry.instance.addConductor(self, for: sshIdentity)
            }
        }
    }
    var state: State {
        get {
            restorableState.state
        }
        set {
            log("[\(framedPID.map { String($0) } ?? "unframed")] state \(state) -> \(newValue)")
            restorableState.state = newValue
        }
    }
    var queue: [ExecutionContext] {
        get {
            restorableState.queue
        }
        set {
            restorableState.queue = newValue
        }
    }
    @objc var boolArgs: String {
        restorableState.boolArgs
    }
    @objc var dcsID: String {
        restorableState.dcsID
    }
    @objc var clientUniqueID: String {  // provided by client when hooking dcs
        restorableState.clientUniqueID
    }
    var modifiedVars: [String: String]? {
        get {
            restorableState.modifiedVars
        }
        set {
            restorableState.modifiedVars = newValue
        }
    }

    // Comes from parsedSSHArguments.commandargs but possibly modified to inject shell integration.
    var modifiedCommandArgs: [String]? {
        get {
            restorableState.modifiedCommandArgs
        }
        set {
            restorableState.modifiedCommandArgs = newValue
        }
    }
    @objc var homeDirectory: String? {
        get {
            restorableState.homeDirectory
        }
        set {
            restorableState.homeDirectory = newValue
        }
    }
    @objc var shell: String? {
        get {
            restorableState.shell
        }
        set {
            restorableState.shell = newValue
        }
    }
    @objc var uname: String? {
        get {
            restorableState.uname
        }
        set {
            restorableState.uname = newValue
        }
    }
    var _terminalConfiguration: CodableNSDictionary? {
        get {
            restorableState._terminalConfiguration
        }
        set {
            restorableState._terminalConfiguration = newValue
        }
    }

    @objc var autopollEnabled = true
    var _queueWrites = true
    var autopoll = ""
    // Jumps that children must do.
    var subsequentJumps: [SSHReconnectionInfo] = []
    // If non-nil, a jump that I haven't done yet.
    var myJump: SSHReconnectionInfo?
    var suggestionCache = SuggestionCache()
    @objc var environmentVariables = [String: String]()
    static var downloadSemaphore = {
        let maxConcurrentDownloads = 2
        return AsyncSemaphore(value: maxConcurrentDownloads)
    }()

    var currentSearch: Search?
    @objc
    lazy var fileChecker: FileChecker? = {
        guard #available(macOS 11, *) else {
            return nil
        }
        let checker = FileChecker()
        checker.dataSource = self
        return checker
    }()
    var ttyState = TTYState()
    private var waitingToResynchronize = false
    lazy var _processInfoProvider: SSHProcessInfoProvider = {
        log("Lazily creating process info provider")
        let provider = SSHProcessInfoProvider(rootPID: framedPID!, runner: self)
        provider.register(trackedPID: framedPID!)
        if let sessionID = delegate?.guid {
            let instance = iTermCPUUtilization.instance(forSessionID: sessionID)
            instance.publisher = provider.cpuUtilizationPublisher
        }
        return provider
    }()
    var backgroundJobs = [Int32: State]()

    @objc weak var delegate: ConductorDelegate? {
        didSet {
            if !restored || framedPID == nil {
                return
            }
            restored = false
        }
    }
    @objc var currentDirectory: String?

    let superVerbose = false

    private init(restorableState: RestorableState,
                 restored: Bool) {
        self.restorableState = restorableState
        self.restored = restored
        super.init()
        if framedPID != nil {
            ConductorRegistry.instance.addConductor(self, for: sshIdentity)
        }
    }
    @objc
    convenience init(_ sshargs: String,
                     boolArgs: String,
                     dcsID: String,
                     clientUniqueID: String,
                     varsToSend: [String: String],
                     clientVars: [String: String],
                     initialDirectory: String?,
                     shouldInjectShellIntegration: Bool,
                     parent: Conductor?) {
        let depth = if let parent {
            if parent.framing {
                parent.depth + 1
            } else {
                // Use same depth as parent because it won't wrap input for us.
                parent.depth
            }
        } else {
            Int32(0)
        }
        self.init(restorableState: RestorableState(
            sshargs: sshargs,
            varsToSend: varsToSend,
            clientVars: clientVars,
            payloads: [],
            initialDirectory: initialDirectory,
            shouldInjectShellIntegration: shouldInjectShellIntegration,
            parsedSSHArguments: ParsedSSHArguments(sshargs,
                                                   booleanArgs: boolArgs,
                                                   hostnameFinder: iTermHostnameFinder()),
            depth: depth,
            parentState: nil,
            framedPID: nil,
            state: .ground,
            queue: [],
            boolArgs: boolArgs,
            dcsID: dcsID,
            clientUniqueID: clientUniqueID,
            modifiedVars: nil,
            modifiedCommandArgs: nil,
            homeDirectory: nil,
            shell: nil,
            uname: nil,
            _terminalConfiguration: nil,
            discoveredHostname: nil),
                  restored: false)
        _parent = parent
        DLog("Conductor starting")
    }

    @objc(initWithRecovery:)
    convenience init(recovery: ConductorRecovery) {
        let depth = if let parent = recovery.parent {
            if parent.framing {
                parent.depth + 1
            } else {
                // Use same depth as parent because it won't wrap input for us.
                parent.depth
            }
        } else {
            Int32(0)
        }
        self.init(restorableState: RestorableState(
            sshargs: recovery.sshargs,
            varsToSend: [:],
            clientVars: [:],
            payloads: [],
            initialDirectory: nil,
            shouldInjectShellIntegration: false,
            parsedSSHArguments: ParsedSSHArguments(recovery.sshargs,
                                                   booleanArgs: recovery.boolArgs,
                                                   hostnameFinder: iTermHostnameFinder()),
            depth: depth,
            parentState: nil,
            framedPID: recovery.pid,
            state: .recovered,
            queue: [],
            boolArgs: recovery.boolArgs,
            dcsID: recovery.dcsID,
            clientUniqueID: recovery.clientUniqueID,
            modifiedVars: nil,
            modifiedCommandArgs: nil,
            homeDirectory: nil,
            shell: nil,
            uname: nil,
            _terminalConfiguration: nil,
            discoveredHostname: nil),
                  restored: false)
        _parent = recovery.parent
        framerVersion = .init(rawValue: recovery.version)
        waitingToResynchronize = true
    }

    deinit {
        let uniqueID = guid
        let sshid = restorableState.parsedSSHArguments.identity
        Task { @MainActor in
            ConductorRegistry.instance.remove(conductorGUID: uniqueID, sshIdentity: sshid)
        }
    }
}

extension Conductor {
    @objc(fetchTimeOffset:)
    func fetchTimeOffset(completion: @escaping (TimeInterval, String?, NSError?) -> ()) {
        let script = """
        import time
        from datetime import datetime, timezone

        tz = time.tzname[time.daylight and time.localtime().tm_isdst]
        delta = time.time() - \(Date().timeIntervalSince1970)
        return f"{delta}\\n{tz}"
        """
        let start = NSDate.it_timeSinceBoot()
        framerExecPythonStatements(statements: script) { [weak self] ok, output in
            let end = NSDate.it_timeSinceBoot()
            guard ok else {
                self?.DLog("Failed to fetch time: \(output)")
                completion(0, nil, iTermError("Failed to fetch time: \(output)") as NSError)
                return
            }
            let lines = output.components(separatedBy: "\n")
            if lines.count >= 2, let diff = Double(lines[0]) {
                let latency = end - start
                let offset = diff - latency / 2.0
                let tzName = lines[1]
                completion(offset, tzName, nil)
            } else {
                completion(0, nil, iTermError("Invalid output: \(output)") as NSError)
            }
        }
    }
}

extension Conductor {
    @objc(subsequentJumps) var subsequentJumps_objc: [SSHReconnectionInfoObjC] {
        return subsequentJumps.map { SSHReconnectionInfoObjC($0) }
    }

    @objc var queueWrites: Bool {
        if let parent = parent {
            return nontransitiveQueueWrites && parent.queueWrites
        }
        return nontransitiveQueueWrites
    }
    var nontransitiveQueueWrites: Bool {
        switch state {
        case .unhooked:
            return false

        default:
            return _queueWrites
        }
    }

    struct TTYState {
        var echo = true
        var icanon = true

        var atPasswordPrompt: Bool {
            return !echo && icanon
        }
    }

    @objc var framing: Bool {
        return framedPID != nil
    }
    @objc var transitiveProcesses: [iTermProcessInfo] {
        guard let pid = framedPID else {
            return []
        }
        let mine = processInfoProvider?.processInfo(for: pid)?.descendants(skipping: 0) ?? []
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
    // If this returns true, route writes through sendKeys(_:).
    @objc var handlesKeystrokes: Bool {
        return framedPID != nil && queueWrites
    }
    @objc var sshIdentity: SSHIdentity {
        return parsedSSHArguments.identity
    }
    @objc var cpuUtilizationPublisher: iTermPublisher<NSNumber> {
        if let remote = sshProcessInfoProvider?.cpuUtilizationPublisher {
            return remote
        }
        return iTermLocalCPUUtilizationPublisher.sharedInstance()
    }

    var sshProcessInfoProvider: SSHProcessInfoProvider? {
        if framedPID == nil && autopollEnabled {
            return nil
        }
        return _processInfoProvider
    }
    @objc var processInfoProvider: (ProcessInfoProvider & SessionProcessInfoProvider)? {
        if waitingToResynchronize {
            return nil
        }
        if framedPID == nil {
            return NullProcessInfoProvider()
        }
        return _processInfoProvider
    }
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
        case fetch(path: Data, chunk: DownloadChunk?, uniqueID: String?)
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
        case zip(path: Data)
        case search(SearchSubCommand)

        enum SearchSubCommand: Codable, Equatable {
            case start(query: Data, baseDirectory: Data)
            case ack(id: String, count: Int)
            case stop(id: String)
        }

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
                return "ls\n\(path.nonEmptyBase64EncodedString())\n\(sortString)"

            case .fetch(let path, let chunk, _):
                if let chunk {
                    return "fetch\n\(path.nonEmptyBase64EncodedString())\n\(chunk.offset)\n\(chunk.size)"
                } else {
                    return "fetch\n\(path.nonEmptyBase64EncodedString())"
                }

            case .zip(let path):
                return "zip\n\(path.nonEmptyBase64EncodedString())"

            case .stat(let path):
                return "stat\n\(path.nonEmptyBase64EncodedString())"

            case .fetchSuggestions(let request):
                var dirs = request.directories.map { $0.base64Encoded }.joined(separator: " ")
                if dirs.isEmpty {
                    dirs = " "
                }
                return ["suggest",
                        request.prefix.nonEmptyBase64Encoded,
                        dirs,
                        (request.workingDirectory ?? "//").nonEmptyBase64Encoded,
                        request.executable ? "rx" : "r",
                        "\(request.limit)"
                ].joined(separator: "\n")

            case .rm(let path, let recursive):
                let args = ["rm"] + (recursive ? ["-r"] : []) + [path.nonEmptyBase64EncodedString()]
                return args.joined(separator: "\n")

            case .ln(let source, let symlink):
                return ["ln",
                        source.nonEmptyBase64EncodedString(),
                        symlink.nonEmptyBase64EncodedString()].joined(separator: "\n")
            case .mv(let source, let dest):
                return ["mv",
                        source.nonEmptyBase64EncodedString(),
                        dest.nonEmptyBase64EncodedString()].joined(separator: "\n")
            case .mkdir(let path):
                return "mkdir\n\(path.nonEmptyBase64EncodedString())"
            case .create(path: let path, content: let content):
                return [
                    "create",
                    path.nonEmptyBase64EncodedString(),
                    content.nonEmptyBase64EncodedString()].joined(separator: "\n")
            case .append(path: let path, content: let content):
                return [
                    "append",
                    path.nonEmptyBase64EncodedString(),
                    content.nonEmptyBase64EncodedString()].joined(separator: "\n")
            case .utime(path: let path, date: let date):
                return [
                    "utime",
                    path.nonEmptyBase64EncodedString(),
                    String(date.timeIntervalSince1970)
                ].joined(separator: "\n")
            case .chmod(path: let path, r: let r, w: let w, x: let x):
                return [
                    "chmod-u",
                    path.nonEmptyBase64EncodedString(),
                    (r ? "r" : "-") + (w ? "w" : "-") + (x ? "x" : "-")
                ].joined(separator: "\n")
            case .search(let subcommand):
                let parts: [String] = switch subcommand {
                case .start(let query, let baseDirectory):
                    [
                        "search",
                        "start",
                        query.nonEmptyBase64EncodedString(),
                        baseDirectory.nonEmptyBase64EncodedString()
                    ]
                case .ack(let id, let count):
                    [
                        "search",
                        "ack",
                        id,
                        "\(count)"
                    ]
                case .stop(let id):
                    [
                        "search",
                        "stop",
                        id
                    ]
                }
                return parts.joined(separator: "\n")
            }
        }

        var operationDescription: String {
            switch self {
            case .ls(let path, let sort):
                return "ls \(path.stringOrHex) \(sort)"
            case .fetch(let path, let chunk, _):
                if let chunk {
                    return "fetch \(path.stringOrHex) offset=\(chunk.offset) size=\(chunk.size)"
                } else {
                    return "fetch \(path.stringOrHex)"
                }
            case .zip(path: let path):
                return "zip \(path.stringOrHex)"
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
            case .search(let subcommand):
                switch subcommand {
                case .start(query: let query, baseDirectory: let baseDirectory):
                    return "search start \(query.lossyString) \(baseDirectory.lossyString)"
                case .ack(id: let id, count: let count):
                    return "search ack \(id) \(count)"
                case .stop(id: let id):
                    return "search stop \(id)"
                }
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
        case pythonversion
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
        case framerReset1
        case framerReset2(String)
        case framerAutopoll
        case framerSave([String:String])
        case framerFile(FileSubcommand)
        case framerGetenv(String)
        case framerExecPythonStatements(String)

        var isFramer: Bool {
            switch self {
            case .execLoginShell, .setenv(_, _), .run(_), .runPython(_), .shell(_), .pythonversion,
                    .write(_, _), .cd(_), .quit, .getshell, .eval(_):
                return false

            case .framerRun, .framerLogin, .framerSend, .framerKill, .framerQuit, .framerRegister(_),
                    .framerDeregister(_), .framerPoll, .framerReset1, .framerReset2, .framerAutopoll, .framerSave(_),
                    .framerFile(_), .framerEval, .framerGetenv, .framerExecPythonStatements:
                return true
            }
        }

        var stringValue: String {
            switch self {
            case .execLoginShell(let args):
                return (["exec_login_shell"] + args).joined(separator: "\n")
            case .setenv(let key, let value):
                return "setenv \(key) \((value as NSString).stringEscapedForBash())"
            case .run(let cmd):
                return "run \(cmd)"
            case .runPython(_):
                return "runpython"
            case .shell(let cmd):
                return "shell \(cmd)"
            case .pythonversion:
                return "pythonversion"
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
            case .framerGetenv(let name):
                return ["getenv", name].joined(separator: "\n")
            case .framerExecPythonStatements(let statements):
                return ["runpy", statements.lossyData.base64EncodedString()].joined(separator: "\n")
            case .framerQuit:
                return "quit"
            case .framerRegister(pid: let pid):
                return ["register", String(pid)].joined(separator: "\n")
            case .framerDeregister(pid: let pid):
                return ["dereigster", String(pid)].joined(separator: "\n")
            case .framerPoll:
                return "poll"
            case .framerReset1:
                return "reset"
            case .framerReset2(let code):
                return ["reset2", code].joined(separator: "\n")
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
            case .pythonversion:
                return "running pythonversion"
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
            case .framerGetenv(let name):
                return "getenv \(name)"
            case .framerExecPythonStatements(let statements):
                return "exec python statements \(statements)"
            case .framerQuit:
                return "quit"
            case .framerRegister(pid: let pid):
                return ["register", String(pid)].joined(separator: " ")
            case .framerDeregister(pid: let pid):
                return ["dereigster", String(pid)].joined(separator: " ")
            case .framerPoll:
                return "poll"
            case .framerReset1:
                return "reset"
            case .framerReset2(let code):
                return ["reset2", code].joined(separator: " ")
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

    // TODO: When I set the deployment target to 14, use parameter packs
    final class OneTimeClosure0<Output> {
        private var closure: (() -> Output)?

        init(_ closure: (() -> Output)?) {
            self.closure = closure
        }

        func call() -> Output? {
            guard let c = closure else {
                return nil
            }
            closure = nil
            return c()
        }
    }

    final class OneTimeClosure1<A, Output> {
        private var closure: ((A) -> Output)?

        init(_ closure: ((A) -> Output)?) {
            self.closure = closure
        }

        func call(_ a: A) -> Output? {
            guard let c = closure else {
                return nil
            }
            closure = nil
            return c(a)
        }
    }

    final class OneTimeClosure2<A, B, Output> {
        private var closure: ((A, B) -> Output)?

        init(_ closure: ((A, B) -> Output)?) {
            self.closure = closure
        }

        func call(_ a: A, _ b: B) -> Output? {
            guard let c = closure else {
                return nil
            }
            closure = nil
            return c(a, b)
        }
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
                case .handleGetenv:
                    return "handleGetenv"
                case .handleReset(let expected, let actual):
                    return "handleReset(\(expected), \(actual.string))"
                case .handleGetHostname:
                    return "handleGetHostname"
                case .handleEphemeralCompletion:
                    return "handleEphemeralCompletion"
                }
            }

            case failIfNonzeroStatus  // if .end(status) has status == 0 call fail("unexpected status")
            case handleCheckForPython(StringArray)
            case fireAndForget  // don't care what the result is
            case handleFramerLogin(StringArray)
            case handleJump(StringArray)
            case writeOnSuccess(String)  // see runPython
            case handleRunRemoteCommand(String, OneTimeClosure2<Data, Int32, Void>)
            case handleBackgroundJob(StringArray, OneTimeClosure2<Data, Int32, Void>)
            case handlePoll(StringArray, OneTimeClosure1<Data, Void>)
            case handleGetShell(StringArray)
            case handleFile(StringArray, OneTimeClosure2<String, Int32, Void>)
            case handleNonFramerLogin
            case handleGetenv(String, StringArray)
            case handleReset(expected: String, lines: StringArray)
            case handleGetHostname
            case handleEphemeralCompletion(StringArray, OneTimeClosure2<String, Int32, Void>)

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
                case handleGetenv
                case handleReset
                case handleGetHostname
                case handleEphemeralCompletion
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
                case .handleGetenv:
                    return RawValues.handleGetenv.rawValue
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
                case .handleReset:
                    return RawValues.handleReset.rawValue
                case .handleGetHostname:
                    return RawValues.handleGetHostname.rawValue
                case .handleEphemeralCompletion:
                    return RawValues.handleEphemeralCompletion.rawValue
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: Key.self)
                try container.encode(rawValue, forKey: .rawValue)
                switch self {
                case .failIfNonzeroStatus, .fireAndForget, .handleFramerLogin(_), .handlePoll(_, _),
                        .handleJump, .handleNonFramerLogin, .handleGetenv, .handleReset,
                        .handleGetHostname, .handleEphemeralCompletion:
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
                    self = .handleRunRemoteCommand(try container.decode(String.self, forKey: .string), .init({_, _ in}))
                case .handleBackgroundJob:
                    self = .handleBackgroundJob(try container.decode(StringArray.self, forKey: .stringArray), .init({_, _ in}))
                case .handlePoll:
                    self = .handlePoll(try container.decode(StringArray.self, forKey: .stringArray), .init({_ in}))
                case .handleGetShell:
                    self = .handleGetShell(try container.decode(StringArray.self, forKey: .stringArray))
                case .handleFile:
                    self = .handleFile(StringArray(), .init({ _, _ in }))
                case .handleNonFramerLogin:
                    self = .handleNonFramerLogin
                case .handleGetenv:
                    self = .handleGetenv(try container.decode(String.self, forKey: .string),
                                         try container.decode(StringArray.self, forKey: .stringArray))
                case .handleReset:
                    self = .handleReset(expected: try container.decode(String.self, forKey: .string),
                                        lines: try container.decode(StringArray.self, forKey: .stringArray))
                case .handleGetHostname:
                    self = .handleGetHostname
                case .handleEphemeralCompletion:
                    self = .handleEphemeralCompletion(StringArray(), .init({ _, _ in }))
                }
            }
        }
        let handler: Handler
        var canceled = false

        mutating func cancel() {
            if canceled {
                return
            }
            canceled = true
            switch handler {
            case .handleFile(_, let completion):
                // Cause performFileOperation to throw .connectionclosed
                completion.call("", -1)
            default:
                break
            }
        }
        // Pipelining means many of these can be sent without waiting for the result.
        // It's particularly important for keystrokes to reduce latency when typing quickly.
        var supportsPipelining: Bool {
            switch self.command {
            case .framerSend:
                return true
            case .framerFile(let sub):
                switch sub {
                case .fetch: return true
                default: return false
                }
            default:
                return false
            }
        }

        // Approximate number of bytes on the wire to send this command.
        var size: Int {
            precondition(supportsPipelining)
            switch self.command {
            case .framerSend:
                // This only needs to be a rough approximation of the size (for example it doesn't
                // include line breaks or try to account for UTF-8 encoding)
                return command.stringValue.count * 4 / 3
            case .framerFile(let sub):
                switch sub {
                case .fetch:
                    return command.stringValue.count * 4 / 3
                default:
                    return .max
                }
            default:
                return .max
            }
        }
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
        var version: Int

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
        var version: Int?

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
                clientUniqueID: clientUniqueID,
                version: version ?? 1)
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
            case .willExecutePipeline(let contexts):
                return "<State: willExecute(\(contexts.map { $0.debugDescription }.joined(separator: ", ")))>"
            case .executingPipeline(let context, let pending):
                return "<State: executing(context=\(context), pending=\(pending.map { $0.debugDescription }.joined(separator: ", "))>"
            case .unhooked:
                return "<State: unhooked>"
            case .recovery(let recoveryState):
                return "<State: recovery \(recoveryState)>"
            case .recovered:
                return "<State: recovered>"
            }
        }

        case ground  // Have not written, not expecting anything.
        case willExecutePipeline([ExecutionContext])  // After writing, before parsing begin. All contexts in the pipeline will have been written. The array is never empty.
        case executingPipeline(ExecutionContext, [ExecutionContext])  // After parsing begin, before parsing end. Only the first one has had parsing begin. The pending array may be empty.
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

    private var verbose: Bool {
        return superVerbose || gDebugLogging.boolValue
    }

    @objc(newConductorWithJSON:delegate:)
    static func create(_ json: String, delegate: ConductorDelegate) -> Conductor? {
        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8),
              let leafState = try? decoder.decode(Conductor.RestorableState.self, from: data) else {
            return nil
        }
        let leaf = Conductor(restorableState: leafState, restored: true)
        var current: Conductor? = leaf
        while current != nil {
            current?.delegate = delegate
            current = current?.parent
        }
        leaf.resetTransitively()
        return leaf
    }

    private func prepareToEncode() {
        parent?.prepareToEncode()
        restorableState.parentState = parent?.restorableState
    }
    @objc var jsonValue: String? {
        let encoder = JSONEncoder()
        prepareToEncode()
        guard let data = try? encoder.encode(restorableState) else {
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

    func DLog(_ messageBlock: @autoclosure () -> String,
              file: String = #file,
              line: Int = #line,
              function: String = #function) {
        if verbose {
            let message = messageBlock()
            DebugLogImpl(file, Int32(line), function, "[\(self.it_addressString)@\(depth)] \(message)")
            if superVerbose {
                NSLog("%@", "[\(self.it_addressString)@\(depth)] \(message)")
            } else {
                log(message)
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
        return sshIdentity.matches(host: path.hostname,
                                   user: path.username,
                                   discoveredHostname: discoveredHostname)
    }

    @objc(downloadOrView:window:)
    func downloadOrView(path: SCPPath, window: NSWindow?) {
        let ext = path.path.pathExtension.lowercased()
        let mimeType = mimeType(for: ext)
        let unsupportedMimeTypes = [
            "application/zip",
            "application/x-gtar",
            "application/x-tar",
        ]
        guard iTermBrowserGateway.browserAllowed(checkIfNo: false),
              let mimeType,
              let url = path.viewInBrowserURL,
              !unsupportedMimeTypes.contains(mimeType) else {
            download(path: path)
            return
        }
        Task { @MainActor in
            guard let sb = try? await stat(path.path) else {
                return
            }
            if sb.kind.isFolder {
                download(path: path)
                return
            }
            // Only "View" should be remembered. Remembering "Download" could cause
            // repeated download prompts if the download fails or isn't handled.
            let warning = iTermWarning()
            warning.title = "Download \(path.path.lastPathComponent) or view in browser?"
            warning.actionLabels = ["Download", "View", "Cancel"]
            warning.identifier = "DownloadOrViewInBrowser_" + mimeType + " " + path.usernameHostnameString
            warning.warningType = .kiTermWarningTypePermanentlySilenceable
            warning.heading = "Download or View File?"
            warning.window = window
            warning.doNotRememberLabels = ["Download", "Cancel"]
            switch warning.runModal() {
            case .kiTermWarningSelection0:  // Download
                download(path: path)
            case .kiTermWarningSelection1:  // View
                iTermController.sharedInstance().open(url, target: nil, openStyle: .tab, select: true)
            default:
                break
            }
        }
    }

    @available(macOS 11, *)
    @objc(download:)
    func download(path: SCPPath) {
        let file = ConductorFileTransfer(path: path,
                                         localPath: nil,
                                         data: nil,
                                         delegate: self)
        file.download()
    }

    func streamDownload(path: SCPPath) -> AsyncThrowingStream<Data, Error> {
        return stream(remotePath: path.path)
    }

    @available(macOS 11, *)
    @objc(uploadFile:to:)
    func upload(file: String, to destinationPath: SCPPath) {
        let file = ConductorFileTransfer(path: destinationPath,
                                         localPath: file,
                                         data: nil,
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
        write("\n\("recover".base64Encoded)\n\n")
        waitingToResynchronize = true
        state = .recovery(.ground)
        delegate?.conductorStateDidChange()
    }

    // Don't try to do anything from here until resynchronization is complete.
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

    @objc
    func didResynchronize() {
        DLog("didResynchronize")
        waitingToResynchronize = false
        forceReturnToGroundState()
        resetTransitively()
        exfiltrateUsefulFramerInfo()
        DLog(self.debugDescription)
    }

    @objc func quit() {
        cancelEnqueuedRequests(where: { _ in true })
        switch state {
        case .willExecutePipeline(var contexts):
            for i in 0..<contexts.count {
                contexts[i].cancel()
            }
        case .executingPipeline(var current, var pending):
            current.cancel()
            for i in 0..<pending.count {
                pending[i].cancel()
            }
        default:
            break
        }
        queue = []
        state = .ground
        send(.quit, .fireAndForget)
        ConductorRegistry.instance.remove(conductorGUID: guid, sshIdentity: sshIdentity)
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
    func fetchSuggestions(_ request: SuggestionRequest, suggestionOnly: Bool) {
        // Always run the completion block after a spin of the mainloop because
        // iTermStatusBarLargeComposerViewController will erase the suggestion asynchronously :(
        guard framing else {
            DispatchQueue.main.async {
                request.completion(suggestionOnly, [])
            }
            return
        }
        if let cached = suggestionCache.get(request.inputs) {
            DispatchQueue.main.async {
                request.completion(suggestionOnly, cached)
            }
            return
        }
        Task {
            do {
                DLog("Request suggestions \(request)")
                let suggestions = try await self.suggestions(request.inputs)
                DispatchQueue.main.async { [weak self] in
                    let items = suggestions.map {
                        CompletionItem(value: $0, detail: $0, kind: .file)
                    }
                    self?.suggestionCache.insert(
                        inputs: request.inputs,
                        suggestions: items)
                    request.completion(suggestionOnly, items)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.suggestionCache.insert(inputs: request.inputs, suggestions: [])
                    request.completion(suggestionOnly, [])
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
        runRemoteCommand(iTermAdvancedSettingsModel.unameCommand()) { [weak self] data, status in
            if status == 0 {
                self?.uname = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.delegate?.conductorStateDidChange()
            }
        }
        exfiltrateUsefulFramerInfo()
        if myJump != nil {
            framerJump()
        } else {
            framerLogin(cwd: initialDirectory ?? "$HOME",
                        args: modifiedCommandArgs ?? parsedSSHArguments.commandArgs)
        }
        if autopollEnabled {
            send(.framerAutopoll, .fireAndForget)
        }
        send(.framerRun(discoverHostnameCommand), .handleGetHostname)
        delegate?.conductorStateDidChange()
    }

    private func exfiltrateUsefulFramerInfo() {
        runRemoteCommand("echo $HOME") { [weak self] data, status in
            if status == 0 {
                self?.homeDirectory = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self?.delegate?.conductorStateDidChange()
            }
        }
        framerGetenv("PATH")
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
    func framerFile(_ subcommand: FileSubcommand,
                                highPriority: Bool = false,
                                completion: @escaping (String, Int32) -> ()) {
        log("Sending framerFile request \(subcommand)")
        send(.framerFile(subcommand),
             highPriority: highPriority,
             .handleFile(StringArray(), .init(completion)))
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

    private func framerGetenv(_ name: String) {
        send(.framerGetenv(name), .handleGetenv(name, StringArray()))
    }

    private func framerExecPythonStatements(statements: String,
                                            completion: @escaping (Bool, String) -> ()) {
        send(.framerExecPythonStatements(statements), .handleEphemeralCompletion(StringArray(), .init({ string, code in
            completion(code == 0, string)
        })))
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
        delegate?.conductorStopQueueingInput()
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
        var path = Bundle(for: Self.self).url(forResource: "framer", withExtension: "py")!
#if DEBUG
        let alt = iTermAdvancedSettingsModel.alternateSSHIntegrationScript()!
        if !alt.isEmpty {
            NSLog("Using \(alt) rather than \(path)")
            path = URL(fileURLWithPath: alt)
        }
#endif
        var customCode = """
        DEPTH=\(depth)
        """
        if verbose {
            customCode += "\nVERBOSE=1\n"
        }
        let pythonCode = try! String(contentsOf: path).replacingOccurrences(of: "#{SUB}",
                                                                            with: customCode)
        runPython(pythonCode)
        framerVersion = .v2
    }

    private func runPython(_ code: String) {
        send(.runPython(code), .writeOnSuccess(code))
    }

    private func run(_ command: String) {
        send(.run(command), .failIfNonzeroStatus)
    }

    private func checkForPython() {
        send(.pythonversion, .handleCheckForPython(StringArray()))
    }

    private static let minimumPythonMajorVersion = 3
    private static let minimumPythonMinorVersion = 7
    @objc static var minimumPythonVersionForFramer: String {
        "\(minimumPythonMajorVersion).\(minimumPythonMinorVersion)"
    }

    private func shellSupportsInjection(_ shell: String, _ version: String) -> Bool {
        let alwaysSupported = ["fish", "xonsh", "zsh"]
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

    struct IgnoreCommandError: Error { }

    private func update(executionContext: ExecutionContext, result: PartialResult) throws {
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
        case .handleReset(let code, let lines):
            switch result {
            case .line(let message):
                lines.strings.append(message)
            case .end:
                if lines.strings.contains(code) {
                    log("Have received the reset code \(code)")
                } else {
                    log("Throwing because we have not received the reset code")
                    throw IgnoreCommandError()
                }
            case .abort, .sideChannelLine, .canceled:
                break
            }
        case .handleGetHostname:
            switch result {
            case .line(let line):
                guard let pid = Int32(line) else {
                    return
                }
                addBackgroundJob(pid,
                                 command: .framerRun(discoverHostnameCommand)) { [weak self] data, status in
                    let name = data.lossyString
                    if status == 0 && !name.isEmpty {
                        self?.DLog("Got hostname: \(name)")
                        self?.discoveredHostname = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            case .abort, .sideChannelLine, .canceled, .end:
                break
            }
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
        case .handleGetenv(let name, let lines):
            switch result {
            case .line(let message):
                lines.strings.append(message)
            case .sideChannelLine, .abort, .canceled:
                break
            case .end:
                if let line = lines.strings.first {
                    environmentVariables[name] = line
                }
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
                                 command: .framerRun(commandLine)) { data, status in
                    completion.call(data, status)
                }
            case .sideChannelLine(_, _, _), .abort, .end(_), .canceled:
                break
            }
            return
        case .handleFile(let lines, let completion):
            switch result {
            case .line(let line):
                if case let .framerFile(sub) = executionContext.command,
                   case let .fetch(_, chunk, _) = sub,
                   let chunk,
                   let poc = chunk.performanceOperationCounter {
                    poc.complete(.sent)
                }
                lines.strings.append(line)
            case .abort, .canceled:
                completion.call("", -1)
            case .sideChannelLine(line: _, channel: _, pid: _):
                break
            case .end(let status):
                DLog("Response from server complete for: \(executionContext.command)")
                completion.call(lines.strings.joined(separator: ""), Int32(status))
            }
        case .handlePoll(let output, let completion):
            switch result {
            case .line(let line):
                output.strings.append(line)
            case .sideChannelLine(_, _, _), .abort, .canceled:
                break
            case .end(_):
                if let data = output.strings.joined(separator: "\n").data(using: .utf8) {
                    completion.call(data)
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
                completion.call(Data(), -2)
            case .end(let status):
                let combined = output.strings.joined(separator: "")
                completion.call(combined.data(using: .utf8) ?? Data(),
                                Int32(status))
            }
            return
        case .handleEphemeralCompletion(let lines, let completion):
            switch result {
            case .line(let line):
                lines.strings.append(line)
            case .sideChannelLine(_, _, _), .abort, .canceled:
                break
            case .end(let status):
                completion.call(lines.strings.joined(separator: ""), Int32(status))
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
        framedPID = pid
        sendInitialText()
        delegate?.conductorStateDidChange()
        delegate?.conductorStopQueueingInput()
    }

    @objc(handleLine:depth:) func handle(line: String, depth: Int32) {
        log("[\(framedPID.map { String($0) } ?? "unframed")] handle input: \(line) depth=\(depth)")
        if depth != self.depth && framing {
            log("Pass line with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handle(line: line, depth: depth)
            return
        }
        DLog("< \(line)")
        switch state {
        case .ground, .unhooked, .recovery(_), .recovered:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            log("Unexpected input: \(line)")
        case .willExecutePipeline(let contexts):
            let pending = Array(contexts.dropFirst())
            state = .executingPipeline(contexts.first!, pending)
            try? update(executionContext: contexts.first!, result: .line(line))
        case let .executingPipeline(context, _):
            try? update(executionContext: context, result: .line(line))
        }
    }

    @objc func handleUnhook() {
        log("unhook")
        switch state {
        case .executingPipeline(let context, _):
            try? update(executionContext: context, result: .abort)
        case .willExecutePipeline(let contexts):
            try? update(executionContext: contexts.first!, result: .abort)
        case .ground, .recovered, .unhooked, .recovery:
            break
        }
        log("Abort pending commands")
        while let pending = queue.first {
            queue.removeFirst()
            try? update(executionContext: pending, result: .abort)
        }
        state = .unhooked
        ConductorRegistry.instance.remove(conductorGUID: guid, sshIdentity: sshIdentity)
    }

    @objc func handleCommandBegin(identifier: String, depth: Int32) {
        // NOTE: no attempt is made to ensure this is meant for me; could be for my parent but it
        // only logs so who cares.
        log("[\(framedPID.map { String($0) } ?? "unframed")] begin \(identifier) depth=\(depth)")
    }

    // type can be "f" for framer or "r" for regular (non-framer)
    @objc func handleCommandEnd(identifier: String, type: String, status: UInt8, depth: Int32) {
        log("[\(framedPID.map { String($0) } ?? "unframed")] end \(identifier) depth=\(depth) state=\(state)")
        let expectFraming: Bool
        if framing {
            expectFraming = true
        } else {
            switch state {
            case let .executingPipeline(context, _):
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
        case let .willExecutePipeline(contexts):
            do {
                try update(executionContext: contexts.first!, result: .end(status))
                if contexts.count == 1 {
                    DLog("Command ended. Return to ground state.")
                    state = .ground
                    dequeue()
                } else {
                    DLog("Command ended. Remain in willExecute with remaining commands.")
                    let pending = Array(contexts.dropFirst())
                    it_assert(!pending.isEmpty)
                    state = .willExecutePipeline(pending)
                    amendPipeline(pending)
                }
            } catch {
                log("Got \(error) so not updating state")
            }
        case let .executingPipeline(context, pending):
            do {
                try update(executionContext: context, result: .end(status))
                DLog("Command ended. Return to ground state.")
                if pending.isEmpty {
                    DLog("Command ended. Return to ground state.")
                    state = .ground
                    dequeue()
                } else {
                    it_assert(!pending.isEmpty)
                    DLog("Command ended. Return to willExecute with remaining commands.")
                    state = .willExecutePipeline(Array(pending))
                    amendPipeline(pending)
                }
            } catch {
                log("Got \(error) so not updating state")
            }
        }
    }

    @objc(handleTerminatePID:withCode:depth:)
    func handleTerminate(_ pid: Int32, code: Int32, depth: Int32) {
        if depth != self.depth {
            DLog("Pass command-terminated with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handleTerminate(pid, code: code, depth: depth)
            return
        }
        log("Process \(pid) terminated")
        if pid == framedPID {
            send(.quit, .fireAndForget)
        } else if let jobState = backgroundJobs[pid] {
            switch jobState {
            case .ground, .unhooked, .recovery, .recovered:
                // Tolerate unexpected inputs - this is essential for getting back on your feet when
                // restoring.
                DLog("Unexpected termination of \(pid)")
            case let .willExecutePipeline(contexts):
                try? update(executionContext: contexts.first!, result: .end(UInt8(code)))
                log("Remove background job \(pid) after handling termination while in willExecutePipeline job state")
                backgroundJobs.removeValue(forKey: pid)
            case let .executingPipeline(context, _):
                do {
                    try update(executionContext: context, result: .end(UInt8(code)))
                    backgroundJobs.removeValue(forKey: pid)
                    log("Remove background job \(pid) after handling termination while in executingPipeline job state")
                } catch {
                    log("Got \(error) so not updating state")
                }
            }
        }
    }

    @objc(handleSideChannelOutput:pid:channel:depth:)
    func handleSideChannelOutput(_ string: String, pid: Int32, channel: UInt8, depth: Int32) {
        log("handleSideChannelOutput string=\(string) pid=\(pid) channel=\(channel) depth=\(depth)")
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
            log("No background job with pid \(pid)")
            return
        }
//        DLog("pid \(pid) channel \(channel) produced: \(string)")
        switch jobState {
        case .ground, .unhooked, .recovery, .recovered:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            log("Unexpected input: \(string)")
        case let .willExecutePipeline(contexts):
            state = .executingPipeline(contexts.first!, Array(contexts.dropFirst()))
        case let .executingPipeline(context, _):
            try? update(executionContext: context,
                        result: .sideChannelLine(line: string, channel: channel, pid: pid))
        }
    }

    private func handleNotif(_ message: String) {
        let notifTTY = "%notif tty "
        if message.hasPrefix(notifTTY) {
            handleTTYNotif(String(message.dropFirst(notifTTY.count)))
        }

        let notifSearch = "%notif search "
        if message.hasPrefix(notifSearch) {
            handleSearchNotif(String(message.dropFirst(notifSearch.count)))
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

    private func handleSearchNotif(_ message: String) {
        if #available(macOS 11.0, *) {
            DLog("handleSearchNotif: \(message)")
            guard let space = message.firstIndex(of: " ") else {
                DLog("Malformed message lacks space")
                return
            }
            let id = message[..<space]
            if let currentSearch, currentSearch.id == id {
                let json = String(message[message.index(space, offsetBy: 1)...])
                if let remoteFile = try? remoteFile(json) {
                    DLog("Yielding \(remoteFile) for search \(currentSearch.id), query \(currentSearch.query)")
                    currentSearch.continuation.yield(remoteFile)
                }
            }
            Task {
                try? await performFileOperation(subcommand: .search(.ack(id: String(id), count: 1)))
            }
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
        log("handleRecovery: \(rawline)")
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

                        delegate?.conductorStateDidChange()
                        return ConductorRecovery(pid: finished.login,
                                                 dcsID: finished.dcsID,
                                                 tree: finished.tree,
                                                 sshargs: finished.sshargs,
                                                 boolArgs: finished.boolArgs,
                                                 clientUniqueID: finished.clientUniqueID,
                                                 version: finished.version,
                                                 parent: parent)
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
                case "version":
                    guard let version = Int(value) else {
                        return nil
                    }
                    temp.version = version
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

    func send(_ command: Command,
              highPriority: Bool = false,
              _ handler: ExecutionContext.Handler) {
        log("append \(command) to queue in state \(state)")
        let context = ExecutionContext(command: command, handler: handler)
        DLog("Enqueue: \(command)")
        if highPriority {
            queue.insert(context, at: 0)
        } else {
            // A possible optimization is to merge search acks here. Rather than appending a new
            // ack to the queue, just increment the count.
            queue.append(context)
        }
        switch state {
        case .ground, .recovery:
            dequeue()
        case .willExecutePipeline, .executingPipeline, .unhooked, .recovered:
            return
        }
    }

    func cancelEnqueuedRequests(where predicate: (Command) -> (Bool)) {
        let indexes = queue.indexes {
            predicate($0.command)
        }
        for i in indexes {
            if !queue[i].canceled {
                DLog("cancel \(queue[i])")
                queue[i].cancel()
            }
        }
    }

    private func dequeue() {
        log("dequeue")
        switch state {
        case .ground, .recovery:
            break
        default:
            it_fatalError()
        }
        amendPipeline([])
    }

    private func encode(_ pending: Conductor.ExecutionContext) -> String {
        return pending.command.stringValue.components(separatedBy: "\n")
            .map(\.base64Encoded)
            .joined(separator: "\n")
            .chunk(128, continuation: pending.command.isFramer ? "\\" : "")
            .joined(separator: "\n") + "\n"
    }

    private func amendPipeline(_ existing: [ExecutionContext]) {
        log("amendPipeline")
        if let last = existing.last, !last.supportsPipelining {
            log("Can't pipeline \(last.debugDescription)")
            return
        }
        let contexts = takeNextContextPipeline(existing)
        guard !contexts.isEmpty else {
            log("Nothing to take")
            return
        }
        state = .willExecutePipeline(contexts)
        for pending in contexts[existing.count...] {
            willSend(pending)
            let chunked = encode(pending)
            write(chunked)
        }
    }

    private func willSend(_ pending: ExecutionContext) {
        DLog("Dequeue and send request: \(pending.command)")
        switch pending.command {
        case .framerFile(let sub):
            switch sub {
            case .fetch(path: _, chunk: let chunk, uniqueID: _):
                chunk?.performanceOperationCounter?.complete(.queued)
            default:
                return
            }
        default:
            return
        }
    }

    private func takeNextContextPipeline(_ existing: [ExecutionContext]) -> [ExecutionContext] {
        if let first = existing.first {
            precondition(first.supportsPipelining)
        }
        var size = existing.map(\.size).reduce(0, +)
        var result = existing
        let maxSize = 1024
        log("Initial size is \(size)")
        while size < maxSize, let context = takeNextContext(onlyIfSupportsPipelining: !result.isEmpty) {
            log("taking \(context.debugDescription)")
            result.append(context)
            if !context.supportsPipelining {
                log("stopping because it does not support pipelining")
                break
            }
            size += context.size
            log("size is now \(size)")
        }
        log("Done with \(result.map(\.debugDescription).joined(separator: ", "))")
        return result
    }

    private func takeNextContext(onlyIfSupportsPipelining: Bool) -> ExecutionContext? {
        guard delegate != nil else {
            log("delegate is nil. clear queue and reset state.")
            while let pending = queue.first {
                queue.removeFirst()
                try? update(executionContext: pending, result: .abort)
            }
            state = .ground
            return nil
        }
        while let pending = queue.first, pending.canceled {
            log("cancel \(pending)")
            queue.removeFirst()
            try? update(executionContext: pending, result: .canceled)
        }
        guard let pending = queue.first else {
            log("queue is empty")
            return nil
        }
        if onlyIfSupportsPipelining && !pending.supportsPipelining {
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
                log("ask parent to send: \(string)")
                parent.sendKeys(data)
            } else {
                log("can't utf-8 encode string to send: \(string)")
            }
        } else {
            if delegate == nil {
                log("[can't send - nil delegate]")
            }
            log("[to \(framedPID.map { String($0) } ?? "non-framing")] Write: \(string)")
            delegate?.conductorWrite(string: string + end)
        }
        _queueWrites = savedQueueWrites
    }

    private var currentOperationDescription: String {
        switch state {
        case .ground:
            return "waiting"
        case let .executingPipeline(context, pending):
            if pending.isEmpty {
                return context.command.operationDescription
            } else {
                return context.command.operationDescription + " and \(pending.count) more"
            }
        case .willExecutePipeline(let contexts):
            if contexts.count > 1 {
                return contexts.first!.command.operationDescription + " (preparation stage) and \(contexts.count - 1) more"
            } else {
                return contexts.first!.command.operationDescription + " (preparation stage)"
            }
        case .unhooked:
            return "unhooked"
        case .recovery:
            return "recovery"
        case .recovered:
            return "recovered"
        }
    }

    func forceReturnToGroundState() {
        log("forceReturnToGroundState")
        state = .ground
        for context in queue {
            try? update(executionContext: context, result: .abort)
        }
        queue = []
        parent?.forceReturnToGroundState()
    }

    private func fail(_ reason: String) {
        DLog("FAIL: \(reason)")
        forceReturnToGroundState()
        // Try to launch the login shell so you're not completely stuck.
        ConductorRegistry.instance.remove(conductorGUID: guid, sshIdentity: sshIdentity)
        delegate?.conductorWrite(string: Command.execLoginShell([]).stringValue + "\n")
        delegate?.conductorAbort(reason: reason)
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

extension SCPPath {
    var viewInBrowserURL: URL? {
        var components = URLComponents()
        components.scheme = iTermBrowserSchemes.ssh
        components.host = hostname
        components.path = path
        return components.url
    }
}
