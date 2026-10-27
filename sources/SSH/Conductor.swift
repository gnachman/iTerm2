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
    // Ask the user, via an in-session announcement (not a modal, so a stray Return
    // cannot accept it), whether the remote it2 CLI described by `displayName` may use
    // the iTerm2 API over this ssh connection. `completion` is called on the main
    // thread with (granted, remember). An explicit Allow/Deny sets remember=true (cache
    // the decision for the connection); closing or dismissing the announcement is not a
    // decision, so it denies just the in-flight request with remember=false and the
    // next command prompts again.
    // `guid` keys the announcement per conductor so two conductors that share an ssh
    // identity in one session cannot cross-cancel each other's prompt; `displayName` is
    // only the human-readable title.
    // `alwaysForHost` means the user chose to allow this host on every future connection, not
    // just this one; the conductor then mints a grant (see IT2HostGrants).
    // `callerTmuxPane` is TMUX_PANE ("%5") of the it2 that asked, if it ran in a tmux pane, so the
    // prompt can go where the user is looking rather than on a hidden tmux gateway.
    @objc(conductorRequestIT2AuthorizationWithGUID:displayName:callerTmuxPane:completion:)
    func conductorRequestIT2Authorization(guid: String, displayName: String, callerTmuxPane: String?,
                                          completion: @escaping (_ granted: Bool, _ remember: Bool, _ alwaysForHost: Bool) -> Void)
    // Dismiss the it2 authorization announcement for `guid` still on screen (e.g. the
    // connection was resolved/torn down before the user answered). No-op if none.
    @objc(conductorDismissIT2AuthorizationPromptWithGUID:)
    func conductorDismissIT2AuthorizationPrompt(guid: String)
    var guid: String { get }
    // Where the session records the flow-controlled frames it parses and executes.
    @objc optional func conductorFlowLedger() -> FramerFlowLedger?
    // Whether the session is a tmux integration gateway, which is never the session a remote
    // it2 in a tmux pane means. See the run closure in it2DemuxForHandling.
    @objc optional var conductorIsTmuxGateway: Bool { get }
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
        // it2 CLI proxy: the per-session auth nonce and remote socket path. Persisted
        // so it2-over-ssh survives state restoration; on SSH recovery (init(recovery:))
        // these start nil and are re-read from the surviving framer env on resync.
        // it2-over-ssh proxy state (nonce/socket/authorization) for this connection,
        // grouped so it travels as one value across recovery (see IT2ProxyState). The
        // nonce/socket are persisted so it2-over-ssh survives state restoration; the
        // authorization grant/denial is persisted so the user is not re-prompted after a
        // relaunch (absent -> undecided -> prompt).
        var it2Proxy = IT2ProxyState()
        // The framer may have flow control on: `flow on` was sent and not refused. It has no
        // way to turn it off, so after a restart it needs a controller whatever the setting.
        var flowMayBeOn = false
        var framerVersion: Int?

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
             discoveredHostname: String?,
             it2Proxy: IT2ProxyState = IT2ProxyState()) {
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
            self.it2Proxy = it2Proxy
        }

        private enum CodingKeys: CodingKey {
            // Note backgroundJobs is not included because it isn't restorable.
          case sshargs, varsToSend, payloads, initialDirectory, parsedSSHArguments, depth, parent,
               framedPID, remoteInfo, state, queue, boolArgs, dcsID, clientUniqueID,
               modifiedVars, modifiedCommandArgs, clientVars, shouldInjectShellIntegration,
               homeDirectory, shell, pythonversion, uname, terminalConfiguration,
               discoveredHostname, it2Proxy, flowMayBeOn, framerVersion,
               // Legacy, decode-only: the committed HEAD schema persisted the it2 proxy as
               // these two separate scalar keys before they were folded into it2Proxy. Kept
               // so init(from:) can migrate an old blob; encode() never writes them.
               it2Nonce, it2SocketPath
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
                flowMayBeOn = (try? container.decode(Bool.self, forKey: .flowMayBeOn)) ?? false
                framerVersion = (try? container.decode(Int?.self, forKey: .framerVersion)) ?? nil
                if let proxy = try? container.decode(IT2ProxyState.self, forKey: .it2Proxy) {
                    it2Proxy = proxy
                } else {
                    // No it2Proxy key. Two cases: (a) a blob saved by the committed HEAD schema,
                    // which persisted it2Nonce/it2SocketPath as separate scalar keys -> migrate
                    // them so the restored session keeps its socket path and auth nonce (the old
                    // schema never persisted `authorized`, so it stays nil -> re-prompt); (b) an
                    // older blob from before any it2 field -> both absent -> default all-nil.
                    let nonce = (try? container.decode(String?.self, forKey: .it2Nonce)) ?? nil
                    let socketPath = (try? container.decode(String?.self, forKey: .it2SocketPath)) ?? nil
                    it2Proxy = IT2ProxyState(nonce: nonce, socketPath: socketPath, authorized: nil)
                }
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
            try container.encode(it2Proxy, forKey: .it2Proxy)
            try container.encode(flowMayBeOn, forKey: .flowMayBeOn)
            try container.encode(framerVersion, forKey: .framerVersion)
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
    /// Saved with the conductor: after a restart, resynchronizing uses `reset2` only for a
    /// framer known to understand it.
    var framerVersion: FramerVersion? {
        get { restorableState.framerVersion.flatMap { FramerVersion(rawValue: $0) } }
        set { restorableState.framerVersion = newValue?.rawValue }
    }

    // Flow control; see Conductor+Flow.swift.
    static var flowControlAvailable: Bool {
        flowControlAvailableForTesting ?? iTermAdvancedSettingsModel.sshFlowControl()
    }
    static var flowControlAvailableForTesting: Bool?
    /// Tests compare nested framers controlled with only the outermost one controlled.
    static var nestedFlowControlAvailableForTesting: Bool?
    var flowController: FramerFlowController?
    /// How long a command took to be answered, written to answered, on the flow clock.
    struct RoundTrip: Equatable {
        var time: TimeInterval
        var seconds: TimeInterval
    }
    /// Recent round trips of commands with replies, for the flow control monitor, whether or not
    /// flow control is on. The oldest first.
    var roundTrips = [RoundTrip]()
    /// The status a completion gets when its command was aborted or canceled rather than
    /// answered.
    static let abortedStatus: Int32 = -2
    /// The framer's clock (boottime, monotonic or uptime), from its reply to `flow on`.
    var flowClockName: String?
    /// The flow control version the framer speaks: 1 has one flow, 2 a flow per source.
    var flowVersion = 1
    /// Flow control is being turned back on while the framer may still be spending credit
    /// granted before: after iTerm2 restarted, or after a relayed grant was lost.
    var flowRestartingAfterRestore = false
    /// `flow on` was sent and not yet answered.
    var flowOnPending = false
    /// Why flow control is off, as decided when it was last tried; see Conductor+Flow.swift.
    var flowOffReason: FlowOffReason?
    /// `flow on`s aborted in a row, each sent again.
    var flowOnRetries = 0
    var flowMayBeOn: Bool {
        get { restorableState.flowMayBeOn }
        set { restorableState.flowMayBeOn = newValue }
    }
    /// Quit, failed or unhooked: its framer is gone or going.
    private(set) var hasEnded = false
    var flowClock: () -> TimeInterval = Conductor.monotonicNow
    /// Tests drive ticks themselves.
    var flowTicksAutomatically = true
    var flowTimer: Timer?
    /// The delegate's ledger, once the controller is listening to it.
    var activeFlowLedger: FramerFlowLedger?
    /// Nested conductors that will turn flow control on once this one runs version 2.
    let flowChildrenWaiting = NSHashTable<Conductor>.weakObjects()

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
            // tmux panes on this host take it (TmuxPaneInferredHost).
            delegate?.conductorStateDidChange()
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
    @objc var depth: Int32 {
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

    // Set while a pipeline transition is running a handler that could call back in.
    // handleCommandEnd captures the pipeline's contents from the pattern match, runs the
    // finished command's handler, and only then writes the remainder back. A re-entrant
    // send() during that window would see the pre-transition state, legitimately extend the
    // pipeline and install its own state, which the write-back would then overwrite -- the
    // new command on the wire with nothing in `state` to attribute its %begin/%end to, and
    // its handler never firing. While this is set, send() only enqueues. Nothing is delayed
    // by it: the transition calls dequeue() or amendPipeline() as its next statement.
    var pipelineTransitionInProgress = false
    var autopoll = ""
    // it2 CLI proxy (see Conductor+IT2). The demux is created lazily on the first
    // %it2 frame; it2Nonce is the per-session secret injected into the remote env
    // at startup, used to authorize incoming HELLOs; it2SocketPath is the remote
    // unix socket framer binds (via it2Listen) and it2.py connects to (IT2_SOCK).
    // The proxy state lives in RestorableState (it2Proxy) so it survives state
    // restoration, and is carried in process across SSH recovery (adoptIT2RecoveryState).
    var it2Demux: ConductorIT2Demux?
    // Remote names claimed by uploads in progress, so concurrent uploads never pick the same one.
    let uploadNameReservations = ConductorUploadNameReservations()
    // Whether framer's most recent it2Listen actually bound the socket. Stored in it2Proxy so
    // it is carried by value across an in-process SSH recovery (a recovered framer keeps its
    // socket bound but never re-runs it2Listen, so without this the menu would go permanently
    // disabled after any transient drop). Not persisted: it lives OUTSIDE IT2ProxyState.Persisted
    // (the only fields IT2ProxyState's Codable encodes), and the custom init(from:) resets it to
    // false on decode -- so on state restoration it2Listen is sent again after resynchronizing,
    // which re-establishes it. Gates
    // it2ProxyActive so the
    // "Remote host can control iTerm2" menu reflects whether the remote can actually connect.
    var it2ListenSucceeded: Bool {
        get { restorableState.it2Proxy.listenSucceeded }
        set { restorableState.it2Proxy.listenSucceeded = newValue }
    }
    // it2-over-ssh API authorization for THIS connection. The decision lives in
    // restorableState (it2Authorized) so a grant/denial survives state restoration; one
    // prompt per connection, and a malicious remote cannot spam prompts. The promise +
    // seal below are the transient in-flight coordinator for the single live prompt: the
    // promise fans the one answer out to every concurrent it2 command, and the Conductor
    // owns the seal so it can resolve it exactly once (on answer, or fail-closed on
    // teardown) and never leave it dangling. See authorizeIT2(then:) in Conductor+IT2.
    var it2AuthPromise: iTermPromise<NSNumber>?
    var it2AuthSeal: iTermPromiseSeal?
    // The whole it2 proxy state as one value, so the recovery hand-off copies it in a
    // single assignment (see adoptIT2RecoveryState). The three field accessors below are
    // conveniences over it for the many call sites that touch just one.
    var it2Proxy: IT2ProxyState {
        get { restorableState.it2Proxy }
        set { restorableState.it2Proxy = newValue }
    }
    var it2Authorized: Bool? {
        get { restorableState.it2Proxy.authorized }
        set { restorableState.it2Proxy.authorized = newValue }
    }
    /// Set at getshell when this connection should get it2; acted on by doFraming.
    private var pendingIT2Home: String?
    /// Set at getshell with pendingIT2Home; see RemoteSetup.putIT2OnShellPath.
    private var pendingIT2OnShellPath = false
    /// Set at getshell; see RemoteSetup.putIT2OnCommandPath.
    private var putIT2OnCommandPath = false
    /// The login shell getshell reported, which runs the command whatever shell it names.
    private var loginShell: String?

    /// Git state for directories on this connection's host. See RemoteGitState.swift.
    private(set) lazy var remoteGitPollWorker = iTermRemoteGitPollWorker(runner: self)

    var it2Nonce: String? {
        get { restorableState.it2Proxy.nonce }
        set { restorableState.it2Proxy.nonce = newValue }
    }
    var it2SocketPath: String? {
        get { restorableState.it2Proxy.socketPath }
        set { restorableState.it2Proxy.socketPath = newValue }
    }
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
    /// Output received from each background job so far, in bytes.
    private var backgroundJobOutputBytes = [Int32: Int]()
    /// A command iTerm2 runs on the remote host, such as `man` or one an AI chat asked for, is
    /// killed past this much output. Its output is held in memory, and flow control shares
    /// credit with it, so one that never ends must not run forever.
    var sideCommandOutputCap = 1024 * 1024
    // Pane processes this conductor's framer runs for workgroup peers. See Conductor+Panes.
    var panes = [Int32: WeakBox<ConductorPaneClient>]()
    /// Output and exits of panes whose sessions have not reattached yet, after a restart or a
    /// recovery. Kept until a session claims them, never dropped. See Conductor+Panes.swift.
    var unclaimedPanes = [Int32: UnclaimedPane]()
    /// Pids known to be panes of this framer: from recovery, or the last `panes` answer.
    var knownPanePIDs = Set<Int32>()
    /// Unclaimed panes the user chose to stop. What they write until they exit is not kept.
    var stoppingPanes = Set<Int32>()
    /// Set for a conductor restored from saved state or recovery until it has resynchronized
    /// with its framer: commands sent before then can be lost, so panes wait to reattach.
    @objc private(set) var awaitingResynchronization = false

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
    // Random prefix prepended to pre-framer command lines to prevent an attacker
    // from planting executables that match the base64-encoded commands we write.
    // Empty for restored/recovered sessions (their remote code predates this change).
    let linePrefix: String

    private init(restorableState: RestorableState,
                 restored: Bool) {
        self.restorableState = restorableState
        self.restored = restored
        // Send a ^C at the start of every line because writing a newline is
        // otherwise unsafe (could cause the output of previous reports to be
        // executed as a command)
        self.linePrefix = restored ? "" : "\u{0003}" + UUID().uuidString
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
            discoveredHostname: nil,
            it2Proxy: recovery.it2Proxy),
                  restored: true)
        _parent = recovery.parent
        framerVersion = .init(rawValue: recovery.version)
        waitingToResynchronize = true
        awaitingResynchronization = true
        knownPanePIDs = Set(recovery.panes)
        unclaimedPanes = recovery.unclaimedPanes
        if let flow = recovery.flow {
            resumeFlowControl(afterRecoveryWith: flow)
        }
    }

    deinit {
        // Fulfill a pending it2 auth seal so iTermPromiseSeal.dealloc's not-fulfilled
        // assertion does not trip (fail closed). deinit is nonisolated, so touch the
        // seal directly rather than the main-actor resolveIT2Authorization method.
        it2AuthSeal?.fulfill(NSNumber(value: false))
        it2AuthSeal = nil
        let uniqueID = guid
        let sshid = restorableState.parsedSSHArguments.identity
        // Stop any it2 command still looping on a background queue. cancelAll() mutates the
        // demux's connections dictionary, which is NOT thread-safe and must run on main (the
        // output sinks are dispatched there). deinit is nonisolated and can run off-main, so
        // hop: fold it into this main-actor Task, which serializes it with any still-queued
        // sendLine/finish. Capturing `demux` (not used again here) transfers it to the main
        // actor. The normal teardown is the on-main unhook path (which already drains the
        // demux); this covers an off-main last-release of a conductor with a live stream.
        let demux = it2Demux
        Task { @MainActor in
            demux?.cancelAll()
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
    /// A tmux pane on this connection's host: tracks its pid with framer, so the host's process
    /// table includes its subtree, and returns the pane's view of that table. nil when not
    /// framing. Safe to call on every title update: registration happens once per provider, and
    /// after an SSH recovery the new provider registers the pane again.
    @objc(sessionProcessInfoProviderForTmuxPanePID:)
    func sessionProcessInfoProvider(forTmuxPanePID pid: Int32) -> SessionProcessInfoProvider? {
        guard framing, !waitingToResynchronize, let provider = sshProcessInfoProvider else {
            return nil
        }
        provider.register(trackedPID: pid)
        return provider.sessionProcessInfoProvider(forPID: pid)
    }

    /// The pane closed: stop tracking its pid.
    @objc(stopTrackingTmuxPanePID:)
    func stopTrackingTmuxPane(pid: Int32) {
        guard framing, let provider = sshProcessInfoProvider else {
            return
        }
        provider.unregister(trackedPID: pid)
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
        /// `hangUp`: a hangup rather than SIGTERM (see killRemoteJob).
        case framerKill(pid: Int, hangUp: Bool = false)
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

        // it2 CLI proxy: bind/accept a unix socket on the remote, relay bytes back
        // to an accepted connection, and close it. See framer.py handle_it2*.
        case framerIT2Listen(path: String)
        case framerIT2Send(connid: String, data: Data)
        case framerIT2Close(connid: String)

        // A workgroup peer's program on its own pty (framer.py handle_pane), and its size.
        case framerPane(rows: Int, cols: Int, cwd: String, command: String, environment: [String: String])
        case framerPaneSize(pid: Int32, rows: Int, cols: Int)

        // Flow control (see FramerFlowController). Grants have no reply, so they are written
        // directly instead of being queued.
        /// Asks for flow control version 2, with credit per flow.
        case framerFlowOn
        /// What a framer that predates version 2 understands.
        case framerFlowOnVersion1
        case framerDrain
        case framerPing
        /// The pids of the framer's running panes.
        case framerPanes

        /// The lines sent for this command, each base64-encoded on its own. A command whose
        /// arguments are free text lists them, so an argument containing a newline (a multi-line
        /// remote command) stays one argument instead of being split by its newlines.
        var wireArguments: [String] {
            switch self {
            case .framerLogin(cwd: let cwd, args: let args):
                return ["login", cwd] + args
            case .framerRun(let command):
                return ["run", command]
            case .framerPane(rows: let rows, cols: let cols, cwd: let cwd, command: let command,
                             environment: let environment):
                return ["pane", String(rows), String(cols), cwd, command] +
                    environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }
            default:
                return stringValue.components(separatedBy: "\n")
            }
        }

        var isFramer: Bool {
            switch self {
            case .execLoginShell, .setenv(_, _), .run(_), .runPython(_), .shell(_), .pythonversion,
                    .write(_, _), .cd(_), .quit, .getshell, .eval(_):
                return false

            case .framerRun, .framerLogin, .framerSend, .framerKill, .framerQuit, .framerRegister(_),
                    .framerDeregister(_), .framerPoll, .framerReset1, .framerReset2, .framerAutopoll, .framerSave(_),
                    .framerFile(_), .framerEval, .framerGetenv, .framerExecPythonStatements,
                    .framerIT2Listen, .framerIT2Send, .framerIT2Close, .framerPane, .framerPaneSize,
                    .framerFlowOn, .framerFlowOnVersion1, .framerDrain, .framerPing, .framerPanes:
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
            case .framerKill(pid: let pid, hangUp: let hangUp):
                return (["kill", String(pid)] + (hangUp ? ["hup"] : [])).joined(separator: "\n")
            case .framerGetenv(let name):
                return ["getenv", name].joined(separator: "\n")
            case .framerExecPythonStatements(let statements):
                return ["runpy", statements.lossyData.base64EncodedString()].joined(separator: "\n")
            case .framerQuit:
                return "quit"
            case .framerRegister(pid: let pid):
                return ["register", String(pid)].joined(separator: "\n")
            case .framerDeregister(pid: let pid):
                return ["deregister", String(pid)].joined(separator: "\n")
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
            case .framerIT2Listen(path: let path):
                return ["it2listen", path].joined(separator: "\n")
            case .framerIT2Send(connid: let connid, data: let data):
                return ["it2send", connid, data.base64EncodedString()].joined(separator: "\n")
            case .framerIT2Close(connid: let connid):
                return ["it2close", connid].joined(separator: "\n")
            case .framerPane(rows: let rows, cols: let cols, cwd: let cwd, command: let command,
                             environment: let environment):
                return (["pane", String(rows), String(cols), cwd, command] +
                    environment.keys.sorted().map { "\($0)=\(environment[$0]!)" }).joined(separator: "\n")
            case .framerPaneSize(pid: let pid, rows: let rows, cols: let cols):
                return ["panesize", String(pid), String(rows), String(cols)].joined(separator: "\n")
            case .framerFlowOn:
                return ["flow", "on", "2"].joined(separator: "\n")
            case .framerFlowOnVersion1:
                return ["flow", "on"].joined(separator: "\n")
            case .framerDrain:
                return "drain"
            case .framerPing:
                return "ping"
            case .framerPanes:
                return "panes"
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
            case .framerKill(pid: let pid, hangUp: let hangUp):
                return "kill \(pid)\(hangUp ? " hup" : "")"
            case .framerGetenv(let name):
                return "getenv \(name)"
            case .framerExecPythonStatements(let statements):
                return "exec python statements \(statements)"
            case .framerQuit:
                return "quit"
            case .framerRegister(pid: let pid):
                return ["register", String(pid)].joined(separator: " ")
            case .framerDeregister(pid: let pid):
                return ["deregister", String(pid)].joined(separator: " ")
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
            case .framerIT2Listen(path: let path):
                return "it2listen \(path)"
            case .framerIT2Send(connid: let connid, data: let data):
                return "it2send \(connid) \(data.semiVerboseDescription)"
            case .framerIT2Close(connid: let connid):
                return "it2close \(connid)"
            case .framerPane(rows: let rows, cols: let cols, cwd: let cwd, command: let command, environment: _):
                return "pane \(rows)x\(cols) cwd=\(cwd) “\(command)”"
            case .framerPaneSize(pid: let pid, rows: let rows, cols: let cols):
                return "panesize \(pid) \(rows)x\(cols)"
            case .framerFlowOn:
                return "flow on 2"
            case .framerFlowOnVersion1:
                return "flow on"
            case .framerDrain:
                return "drain"
            case .framerPing:
                return "ping"
            case .framerPanes:
                return "panes"
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
                case .it2Listen:
                    return "it2Listen"
                case .handleFramerLogin(let output):
                    return "handleFramerLogin(\(output.string))"
                case .handleJump:
                    return "handleJump"
                case .writeOnSuccess(let code):
                    return "writeOnSuccess(\(code.count) chars)"
                case .handleRunRemoteCommand(let command, _, _):
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
                case .handleResetMarker(let marker, _):
                    return "handleResetMarker(\(marker))"
                case .handleProbedReset(let code, let actual):
                    return "handleProbedReset(\(code), \(actual.string))"
                case .handleGetHostname:
                    return "handleGetHostname"
                case .handleEphemeralCompletion:
                    return "handleEphemeralCompletion"
                }
            }

            case failIfNonzeroStatus  // if .end(status) has status == 0 call fail("unexpected status")
            case handleCheckForPython(StringArray)
            case fireAndForget  // don't care what the result is
            case it2Listen  // like fireAndForget but logs a non-zero framer bind status
            case handleFramerLogin(StringArray)
            case handleJump(StringArray)
            case writeOnSuccess(String)  // see runPython
            /// The command line, the completion, and what to tell once the job's pid is known.
            case handleRunRemoteCommand(String, OneTimeClosure2<Data, Int32, Void>, OneTimeClosure1<Int32, Void>?)
            case handleBackgroundJob(StringArray, OneTimeClosure2<Data, Int32, Void>)
            case handlePoll(StringArray, OneTimeClosure1<Data, Void>)
            case handleGetShell(StringArray)
            case handleFile(StringArray, OneTimeClosure2<String, Int32, Void>)
            case handleNonFramerLogin
            case handleGetenv(String, StringArray)
            case handleReset(expected: String, lines: StringArray)
            /// Skips replies until the one that spells `marker`, a `file stat` of "/" whose reply
            /// echoes the path; everything before it answered earlier commands.
            case handleResetMarker(marker: String, lines: StringArray)
            /// The `reset2` sent right after a marker: its reply is the next one, so without the
            /// code it is a framer that predates `reset2`.
            case handleProbedReset(code: String, lines: StringArray)
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
                case it2Listen
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
                case handleResetMarker
                case handleProbedReset
            }

            private var rawValue: Int {
                switch self {
                case .failIfNonzeroStatus:
                    return RawValues.failIfNonzeroStatus.rawValue
                case .handleCheckForPython:
                    return RawValues.handleCheckForPython.rawValue
                case .fireAndForget:
                    return RawValues.fireAndForget.rawValue
                case .it2Listen:
                    return RawValues.it2Listen.rawValue
                case .handleFramerLogin:
                    return RawValues.handleFramerLogin.rawValue
                case .handleJump:
                    return RawValues.handleJump.rawValue
                case .handleGetenv:
                    return RawValues.handleGetenv.rawValue
                case .writeOnSuccess(_):
                    return RawValues.writeOnSuccess.rawValue
                case .handleRunRemoteCommand(_, _, _):
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
                case .handleResetMarker:
                    return RawValues.handleResetMarker.rawValue
                case .handleProbedReset:
                    return RawValues.handleProbedReset.rawValue
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
                case .failIfNonzeroStatus, .fireAndForget, .it2Listen, .handleFramerLogin(_), .handlePoll(_, _),
                        .handleJump, .handleNonFramerLogin, .handleGetenv, .handleReset,
                        .handleResetMarker, .handleProbedReset,
                        .handleGetHostname, .handleEphemeralCompletion:
                    break
                case .handleCheckForPython(let value):
                    try container.encode(value, forKey: .stringArray)
                case .handleGetShell(let value):
                    try container.encode(value, forKey: .stringArray)
                case .writeOnSuccess(let value):
                    try container.encode(value, forKey: .string)
                case .handleRunRemoteCommand(let value, _, _):
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
                case .it2Listen:
                    self = .it2Listen
                case .handleFramerLogin:
                    self = .handleFramerLogin(try container.decode(StringArray.self, forKey: .stringArray))
                case .handleJump:
                    self = .handleJump(try container.decode(StringArray.self, forKey: .stringArray))
                case .writeOnSuccess:
                    self = .writeOnSuccess(try container.decode(String.self, forKey: .string))
                case .handleRunRemoteCommand:
                    self = .handleRunRemoteCommand(try container.decode(String.self, forKey: .string), .init({_, _ in}), nil)
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
                case .handleResetMarker:
                    self = .handleResetMarker(marker: "", lines: StringArray())
                case .handleProbedReset:
                    self = .handleProbedReset(code: "", lines: StringArray())
                }
            }
        }
        let handler: Handler
        var canceled = false
        /// Queued in the priority lane, ahead of ordinary commands.
        var isHighPriority: Bool?
        /// When it was written, on Conductor.monotonicNow's clock, to time its round trip.
        var writtenAt: TimeInterval?

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
            case .framerSend, .framerIT2Send:
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
                // Unchanged from before it2: measure the base64-encoded command form. Since
                // stringValue already base64-encodes the payload (~4/3), this is ~data.count *
                // 16/9. Keystroke payloads are tiny, so building stringValue to measure is
                // negligible, and keeping it preserves existing keystroke backpressure exactly
                // (do NOT fold this into the raw-count estimate below -- that quietly shrinks
                // the hot-path window ~25%).
                return command.stringValue.count * 4 / 3
            case .framerIT2Send(connid: _, data: let data):
                // it2 carries large API responses. Approximate from the raw payload (base64
                // inflates ~4/3) rather than base64-encoding the whole thing here just to
                // measure it and then again in stringValue/encode() to send it.
                return data.count * 4 / 3
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
        /// "1 <clock>" when the framer has flow control on.
        var flow: String?
        var panes: [Int32] = []

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
        var flow: String?
        var panes: [Int32] = []

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
                version: version ?? 1,
                flow: flow,
                panes: panes)
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

    /// The session reattached to the process that still runs ssh after iTerm2 restarted, so
    /// whatever this conductor writes reaches its framer. Each framer in the chain is reset,
    /// outermost first, to resynchronize.
    @objc func resetAfterReattaching() {
        resetTransitively()
    }

    @objc(newConductorWithJSON:delegate:)
    static func create(_ json: String, delegate: ConductorDelegate) -> Conductor? {
        let decoder = JSONDecoder()
        guard let data = json.data(using: .utf8),
              let leafState = try? decoder.decode(Conductor.RestorableState.self, from: data) else {
            return nil
        }
        let leaf = Conductor(restorableState: leafState, restored: true)
        leaf.awaitingResynchronization = true
        var current: Conductor? = leaf
        while current != nil {
            current?.delegate = delegate
            current = current?.parent
        }
        // Nothing is written yet: the session may not reattach to the process that runs ssh,
        // and then whatever is written goes to a new shell (F-706). The session calls
        // resetAfterReattaching once it has reattached.
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
        if !linePrefix.isEmpty {
            write(linePrefix)
        }
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
            let choice = await Self.downloadOrViewChoice(path: path.path) { remotePath in
                try await self.stat(remotePath)
            }
            if choice == .download {
                download(path: path)
                return
            }
            // Only "View" should be remembered. Remembering "Download" could cause
            // repeated download prompts if the download fails or isn't handled.
            let warning = iTermWarning()
            warning.title = String(localized: "Conductor.DownloadOrViewTitle", defaultValue: "Download \(path.path.lastPathComponent) or view in browser?", comment: "Prompt asking whether to download a remote file or view it in the browser")
            let downloadLabel = String(localized: "Conductor.Download", defaultValue: "Download", comment: "Download button")
            let cancel = iTermLocalizedCancel()
            warning.actionLabels = [downloadLabel, String(localized: "Conductor.View", defaultValue: "View", comment: "View button"), cancel]
            warning.identifier = "DownloadOrViewInBrowser_" + mimeType + " " + path.usernameHostnameString
            warning.warningType = .kiTermWarningTypePermanentlySilenceable
            warning.heading = String(localized: "Conductor.DownloadOrViewHeading", defaultValue: "Download or View File?", comment: "Heading for the download-or-view prompt")
            warning.window = window
            warning.doNotRememberLabels = [downloadLabel, cancel]
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

    @objc(uploadFile:to:)
    func upload(file: String, to destinationPath: SCPPath) {
        _ = upload(file: file, to: destinationPath, completion: { _, _ in })
    }

    @objc(uploadFile:to:withCompletion:)
    func upload(file: String, to destinationPath: SCPPath, completion: @escaping (Bool, String?) -> Void) -> TransferrableFile? {
        let localPath: String
        let remotePath: SCPPath
        let tempArchivePath: String?

        // Check if it's a directory - create a tgz archive
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: file, isDirectory: &isDirectory), isDirectory.boolValue {
            do {
                let result = try createArchiveForDirectory(file, destinationPath: destinationPath)
                localPath = result.localPath
                remotePath = result.remotePath
                tempArchivePath = result.tempArchivePath
            } catch {
                DLog("Failed to create tgz archive: \(error)")
                completion(false, error.localizedDescription)
                return nil
            }
        } else {
            localPath = file
            remotePath = destinationPath
            tempArchivePath = nil
        }

        let transfer = ConductorFileTransfer(path: remotePath,
                                             localPath: localPath,
                                             data: nil,
                                             delegate: self)
        transfer.completionBlock = { success, error in
            // Clean up temp archive if we created one
            if let tempPath = tempArchivePath {
                try? FileManager.default.removeItem(atPath: tempPath)
            }
            completion(success, error)
        }
        transfer.upload()
        return transfer
    }

    private struct DirectoryArchiveResult {
        let localPath: String
        let remotePath: SCPPath
        let tempArchivePath: String
    }

    private func createArchiveForDirectory(_ directoryPath: String, destinationPath: SCPPath) throws -> DirectoryArchiveResult {
        DLog("Converting directory to tgz for conductor upload: \(directoryPath)")

        let tempPath = try NSData.temporaryTGZArchive(ofDirectory: directoryPath)

        let remotePath = SCPPath()
        remotePath.hostname = destinationPath.hostname
        remotePath.username = destinationPath.username
        remotePath.path = destinationPath.path + ".tgz"

        return DirectoryArchiveResult(localPath: tempPath, remotePath: remotePath, tempArchivePath: tempPath)
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
        it2ssh_wrapper \(shouldInjectShellIntegration ? "" : "--no-shell-integration ")\(myJump!.sshargs)
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
        // The conductor made from the recovery takes flow control over.
        stopFlowControl()
        abandonPanes()
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
        awaitingResynchronization = false
        forceReturnToGroundState()
        resetTransitively()
        // A conductor restored after a restart doesn't know whether the framer still listens
        // for it2 (that isn't saved), so it asks again. A framer that already listens answers
        // that it does. After the reset, which would abort it.
        if let path = it2SocketPath, it2Nonce != nil {
            it2Listen(path: path)
        }
        exfiltrateUsefulFramerInfo()
        flowRecoveryDidFinish()
        restartFlowControlAfterResynchronizing()
        // Pane sessions reattach now that commands are safe.
        NotificationCenter.default.post(name: Self.didResynchronizeNotification, object: self)
        // it2 proxy state (nonce/socket/authorization) is carried across recovery in
        // process from the pre-recovery conductor (see init(recovery:)), not re-read
        // from the framer: a fresh $SHELL -c getenv cannot see the one-time-injected
        // nonce, and the authorization grant must not be re-derivable from the remote.
        DLog(self.debugDescription)
    }

    // Instead of start(), when the hook's parameters could not be understood (F-608). The
    // remote conductor reads the line prefix and then waits for a command with its tty in
    // raw mode, so tell it to quit. It restores the tty as it exits, which ends the
    // connection. The delegate is responsible for tearing this conductor down.
    @objc func quitWithoutStarting() {
        log("quitWithoutStarting")
        hasEnded = true
        flowMayBeOn = false
        if !linePrefix.isEmpty {
            write(linePrefix)
        }
        send(.quit, .fireAndForget)
        ConductorRegistry.instance.remove(conductorGUID: guid, sshIdentity: sshIdentity)
    }

    /// Whether Disconnect can end this connection. Without a framer only conductor.sh reads
    /// the pre-framer quit, and once it has unhooked to run the login shell or a command,
    /// nothing does: the quit would be typed into the remote shell (F-950). A connection
    /// without a framer restored after iTerm2 restarted is taken to be past that point.
    @objc var canQuit: Bool {
        return framing || (!hasEnded && !restored)
    }

    @objc func quit() {
        let canSendQuit = canQuit
        hasEnded = true
        flowMayBeOn = false
        stopFlowControl()
        abandonPanes()
        cancelAllRequests()
        if framing {
            // The framer reads framer commands; the pre-framer `quit` means nothing to it.
            framerQuit()
        } else if canSendQuit {
            send(.quit, .fireAndForget)
        } else {
            log("conductor.sh no longer reads commands. Do not send quit.")
        }
        ConductorRegistry.instance.remove(conductorGUID: guid, sshIdentity: sshIdentity)
        delegate?.conductorQuit()
        delegate?.conductorStateDidChange()
    }

    private func cancelAllRequests() {
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
    }

    func eval(code: String) {
        send(.eval(code.base64Encoded), .fireAndForget)
    }

    @objc(ancestryContainsClientUniqueID:)
    func ancestryContains(clientUniqueID: String) -> Bool {
        return self.clientUniqueID == clientUniqueID || (parent?.ancestryContains(clientUniqueID: clientUniqueID) ?? false)
    }

    /// Typed input, which takes the priority lane.
    @objc func sendKeys(_ data: Data) {
        sendKeys(data, highPriority: true)
    }

    /// `onAbort` runs if the keys were queued for the framer and the queue was dropped before
    /// it answered.
    func sendKeys(_ data: Data, highPriority: Bool, onAbort: (() -> Void)? = nil) {
        guard let pid = framedPID else {
            DLog("[sendKeys] Write: \(data.stringOrHex)")
            delegate?.conductorWrite(string: String(data: data, encoding: .isoLatin1)!)
            return
        }
        guard let onAbort else {
            framerSend(data: data, pid: pid, highPriority: highPriority)
            return
        }
        send(.framerSend(data, pid: pid),
             highPriority: highPriority,
             .handleEphemeralCompletion(StringArray(), .init({ _, status in
                 if status == Self.abortedStatus {
                     onAbort()
                 }
             })))
    }

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
        Task { [self] in
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
        activatePendingIT2()
        execFramer()
        startFlowControlIfPossible()
        framerSave(["dcsID": dcsID,
                    "sshargs": sshargs,
                    "boolArgs": boolArgs,
                    "clientUniqueID": clientUniqueID])
        // Bind the it2 proxy socket now that framer is running. The path/nonce were
        // minted and injected into the shell env during the shell-integration setup.
        if let path = it2SocketPath {
            it2Listen(path: path)
        } else {
            RLog("Framing without an it2 socket, so it2 on this host cannot reach iTerm2")
        }
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
            // One string: framer joins its arguments with spaces into `-c`, so anything else would
            // be split and lose its quoting.
            let command = Self.framerLoginCommand(
                Self.remoteCommandString(modifiedCommandArgs: modifiedCommandArgs,
                                         commandLine: parsedSSHArguments.commandLine),
                putIT2OnPath: putIT2OnCommandPath && it2Nonce != nil,
                loginShell: loginShell,
                launchKind: Self.remoteLaunchKind(commandArgs: parsedSSHArguments.commandArgs))
            DLog("Command for the login shell: \(command ?? "(none)")")
            framerLogin(cwd: initialDirectory ?? "$HOME",
                        args: command.map { [$0] } ?? [])
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
        // Who the login is as, which ssh may have taken from ~/.ssh/config rather than the
        // command line, so the identity doesn't know it.
        framerGetenv("USER")
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

    private func framerSend(data: Data, pid: Int32, highPriority: Bool) {
        send(.framerSend(data, pid: pid), highPriority: highPriority, .fireAndForget)
    }

    // it2 CLI proxy senders. The demux (see Conductor+IT2) drives these to open a
    // listening socket on the remote, push bytes back to an accepted it2.py
    // connection, and tear it down.
    func it2Listen(path: String) {
        // .it2Listen (not .fireAndForget): the framer bind can fail, and that status must not
        // be swallowed -- it drives it2ListenSucceeded / it2ProxyActive and a DLog.
        send(.framerIT2Listen(path: path), .it2Listen)
    }

    func it2Send(connid: String, data: Data) {
        send(.framerIT2Send(connid: connid, data: data), .fireAndForget)
    }

    func it2Close(connid: String) {
        send(.framerIT2Close(connid: connid), .fireAndForget)
    }

    private func framerKill(pid: Int) {
        send(.framerKill(pid: pid), .fireAndForget)
    }

    private func framerGetenv(_ name: String) {
        send(.framerGetenv(name), .handleGetenv(name, StringArray()))
    }

    func framerExecPythonStatements(statements: String,
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
        } else if parsedSSHArguments.commandLine.isEmpty {
            send(.execLoginShell([]), .handleNonFramerLogin)
        } else {
            run(Self.remoteCommandString(modifiedCommandArgs: modifiedCommandArgs,
                                         commandLine: parsedSSHArguments.commandLine) ?? "")
        }
    }

    /// The command the remote login shell runs with `-c`, or nil for an interactive login shell.
    ///
    /// Unmodified, it is the command exactly as given, the string ssh would send. When shell
    /// integration adjusted a shell named as the command (bash gets --posix), the arguments are
    /// exact words by then and each is quoted, so none can be split or reinterpreted.
    enum RemoteLaunchKind: Equatable {
        /// No command: the login shell, interactively.
        case interactive
        /// A shell named as the command (`it2ssh host bash`): the session's shell, which shell
        /// integration may adjust.
        case customShell(String)
        /// Anything else: run by the login shell exactly as given.
        case command
    }

    /// Shells that can be the session's shell when named as the command.
    private nonisolated static let shellNames: Set<String> = [
        "sh", "bash", "zsh", "fish", "xonsh", "nu", "tcsh", "csh", "ksh", "mksh", "dash", "ash", "yash"
    ]

    nonisolated static func remoteLaunchKind(commandArgs: [String]) -> RemoteLaunchKind {
        guard let first = commandArgs.first else {
            return .interactive
        }
        if shellNames.contains((first as NSString).lastPathComponent) {
            return .customShell(first)
        }
        return .command
    }

    /// What getshell sets up on the remote.
    struct RemoteSetup: Equatable {
        /// Adjust the shell so it loads the shell-integration scripts, and upload them.
        var injectShellIntegration: Bool
        /// Upload ~/.iterm2/bin/it2 and the interpreter it runs.
        var uploadIT2: Bool
        /// Mint the it2 socket and nonce and put IT2_SOCK, IT2_NONCE and IT2_PY in the shell's
        /// environment.
        var activateIT2: Bool
        /// Have the framer put ~/.iterm2/bin first on the PATH it gives the login shell (whose
        /// own login files may still reorder it: macOS's path_helper does). Only for the login
        /// shell itself (no command) when it gets the upload without the scripts (tcsh, macOS
        /// bash 3.2): the injected scripts do it themselves, and a command, or a shell named as
        /// the command, gets it from commandPuttingIT2OnPath, which would put it there twice.
        var putIT2OnShellPath = false
        /// Run the command through commandPuttingIT2OnPath. A command always is, and so is a
        /// shell named as the command (`it2ssh host sh -c …`, `it2ssh host bash`) unless the
        /// scripts are injected into it and it is interactive. One the scripts can't be
        /// injected into has nothing else to put ~/.iterm2/bin on its PATH, and an injected one
        /// loads them only when interactive, so `zsh -c …` would miss out too. An interactive
        /// injected one is left to the scripts: most of them add the directory only when it is
        /// absent, so a prefix here would let the shell's own startup files push it back.
        var putIT2OnCommandPath = false
    }

    /// it2 used to come only with injection, so with "Load shell integration automatically" off,
    /// or a shell that cannot be injected (tcsh, macOS bash 3.2), there was no socket at all and
    /// every remote it2 feature failed silently. The socket is not shell integration: it only
    /// needs the framer, and its variables reach any shell through setenv. So it is always
    /// minted. The setting decides what is written to the host: off means nothing is uploaded,
    /// though an it2 already there (installed by hand, or by an earlier session) still works.
    nonisolated static func remoteSetup(launchKind: RemoteLaunchKind,
                                        shellSupportsInjection: Bool,
                                        shouldInjectShellIntegration: Bool,
                                        haveHome: Bool,
                                        customShellIsInteractive: Bool = true) -> RemoteSetup {
        guard haveHome else {
            return RemoteSetup(injectShellIntegration: false, uploadIT2: false, activateIT2: false)
        }
        // A command is run by the login shell exactly as given, never through the scripts.
        let inject = shouldInjectShellIntegration && launchKind != .command && shellSupportsInjection
        return RemoteSetup(injectShellIntegration: inject,
                           uploadIT2: shouldInjectShellIntegration,
                           activateIT2: true,
                           putIT2OnShellPath: shouldInjectShellIntegration && launchKind == .interactive && !inject,
                           putIT2OnCommandPath: launchKind == .command ||
                            (launchKind != .interactive && !(inject && customShellIsInteractive)))
    }

    /// Whether a shell named as the command, given these arguments (after its name), will be
    /// interactive: not when it runs a command string (-c) or a script file, unless -i says so.
    /// The same reading BashShellIntegrationInjection uses to decide whether to inject. An
    /// option's value (`-o vi`) reads as a script file, which errs toward the prefix: it2 is
    /// still on PATH, just possibly not first.
    nonisolated static func customShellIsInteractive(arguments: [String]) -> Bool {
        var expectingFile = false
        for argument in arguments {
            if expectingFile {
                return false
            }
            if argument == "--" || argument == "-" {
                expectingFile = true
                continue
            }
            if argument.hasPrefix("--") {
                continue
            }
            if argument.hasPrefix("-") || argument.hasPrefix("+") {
                let letters = argument.dropFirst()
                if letters.contains("i") {
                    return true
                }
                if letters.contains("c") {
                    return false
                }
                continue
            }
            // A script file.
            return false
        }
        return true
    }

    /// Queues the shell-integration scripts for upload with the other payloads.
    private func uploadShellIntegrationPayloads() {
        let base = URL(fileURLWithPath: "/$HOME/.iterm2/shell-integration")
        let it2 = ShellIntegrationInjector.instance.it2Files(dotIterm2: base.deletingLastPathComponent())
        for (local, remote) in ShellIntegrationInjector.instance.files(destinationBase: base)
        where it2[local] == nil {
            payloads.append(Payload(path: local.path, destination: remote.path))
        }
    }

    /// Queues ~/.iterm2/bin/it2 and its interpreter for upload with the other payloads.
    private func uploadIT2Payloads() {
        let dotIterm2 = URL(fileURLWithPath: "/$HOME/.iterm2")
        for (local, remote) in ShellIntegrationInjector.instance.it2Files(dotIterm2: dotIterm2) {
            payloads.append(Payload(path: local.path, destination: remote.path))
        }
    }

    nonisolated static func remoteCommandString(modifiedCommandArgs: [String]?, commandLine: String) -> String? {
        if let modifiedCommandArgs {
            if modifiedCommandArgs.isEmpty {
                return nil
            }
            return modifiedCommandArgs.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                .joined(separator: " ")
        }
        return commandLine.isEmpty ? nil : commandLine
    }

    /// `command` with ~/.iterm2/bin put on PATH first, in the syntax of the login shell that runs
    /// it with -c. A command gets it2's environment at getshell, but PATH cannot go that way (see
    /// activateIT2Proxy), and only the interactive shell-integration scripts add the directory.
    /// It has to happen inside the command because a login shell's profile may reset PATH
    /// outright (Debian's /etc/profile does). A shell whose syntax is unknown gets the command
    /// unchanged.
    ///
    /// With `execFinal`, the command replaces the login shell (`exec`) rather than running as its
    /// child. A list is not exec'd by every shell (bash 3.2 runs its last command as a child), so
    /// without it a shell named as the command would sit under an extra non-interactive one.
    /// Only for a single simple command: `exec` of a list, a builtin or a function would break it.
    nonisolated static func commandPuttingIT2OnPath(_ command: String,
                                                    loginShell: String,
                                                    execFinal: Bool = false) -> String {
        let final = execFinal ? "exec " + command : command
        switch (loginShell as NSString).lastPathComponent {
        case "sh", "bash", "zsh", "ksh", "mksh", "dash", "ash", "yash":
            return #"PATH="$HOME/.iterm2/bin:$PATH"; export PATH; "# + final
        case "csh", "tcsh":
            return #"setenv PATH "${HOME}/.iterm2/bin:${PATH}"; "# + final
        case "fish":
            return #"set -gx PATH "$HOME/.iterm2/bin" $PATH; "# + final
        default:
            return command
        }
    }

    /// What the framer's login shell runs with -c: `command`, put through commandPuttingIT2OnPath
    /// when it2 should be on its PATH, in the syntax of the LOGIN shell (which runs it, even when
    /// it names another shell). A shell named as the command is exec'd when it is one simple
    /// command, so it replaces the login shell instead of running under it.
    nonisolated static func framerLoginCommand(_ command: String?,
                                               putIT2OnPath: Bool,
                                               loginShell: String?,
                                               launchKind: RemoteLaunchKind) -> String? {
        guard let command, putIT2OnPath, let loginShell, !loginShell.isEmpty else {
            return command
        }
        let execFinal: Bool
        if case .customShell = launchKind {
            execFinal = isSimpleCommand(command)
        } else {
            execFinal = false
        }
        return commandPuttingIT2OnPath(command, loginShell: loginShell, execFinal: execFinal)
    }

    /// Whether `command` has none of a shell's list, pipe, background, subshell or redirection
    /// operators outside quotes, so prefixing it with `exec` keeps its meaning. Conservative: a
    /// false negative only costs an extra process.
    nonisolated static func isSimpleCommand(_ command: String) -> Bool {
        // A reserved word or an assignment in front is not a program exec could run.
        let firstWord = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
        let reserved: Set<String> = ["!", "time", "{", "}", "if", "then", "else", "elif", "fi", "while",
                                     "until", "for", "do", "done", "case", "esac", "function",
                                     "begin", "end", "not", "and", "or", "switch", "foreach",
                                     "exec", "builtin", "command", "nohup", "env", "sudo"]
        if firstWord.isEmpty || reserved.contains(firstWord) || firstWord.contains("=") {
            return false
        }
        var inSingle = false
        var inDouble = false
        var escaped = false
        for c in command {
            if escaped {
                escaped = false
                continue
            }
            if inSingle {
                if c == "'" {
                    inSingle = false
                }
                continue
            }
            if c == "\\" {
                escaped = true
                continue
            }
            if inDouble {
                if c == "\"" {
                    inDouble = false
                }
                continue
            }
            switch c {
            case "'":
                inSingle = true
            case "\"":
                inDouble = true
            case ";", "&", "|", "<", ">", "(", ")", "\n", "`":
                return false
            default:
                break
            }
        }
        return !inSingle && !inDouble && !escaped
    }

    /// Names the flag the framer reads in handle_login and handle_pane. Must match framer.py.
    static let it2PutBinOnPathVariable = "IT2_PUT_BIN_ON_PATH"

    /// Mints the it2 socket and nonce and sends IT2_SOCK, IT2_NONCE and IT2_PY, now that the
    /// framer that binds the socket is about to start. They go by setenv to conductor.sh, which
    /// then execs the framer, so the framer and the login shell it starts inherit them. Only here,
    /// so a host without a usable Python never gets an IT2_SOCK that nothing listens on.
    private func activatePendingIT2() {
        let putIT2OnShellPath = pendingIT2OnShellPath
        pendingIT2OnShellPath = false
        guard let home = pendingIT2Home else {
            return
        }
        pendingIT2Home = nil
        var vars = [String: String]()
        activateIT2Proxy(home: home, env: &vars)
        if putIT2OnShellPath {
            // A flag, not a PATH: see activateIT2Proxy for why PATH can't go by setenv. The
            // framer takes the flag out of its own environment when it starts, so nothing it
            // starts inherits it, and does the prepend for the login shell and its panes.
            vars[Self.it2PutBinOnPathVariable] = "1"
        }
        for (key, value) in vars.sorted(by: { $0.key < $1.key }) {
            send(.setenv(key: key, value: value), .failIfNonzeroStatus)
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
    /// Whether `shell` (a path or a name) can be injected. `loginShellVersion` is what getshell
    /// reported, which describes the login shell, so it only says which bash `shell` is when the
    /// login shell is that bash. A different bash on a macOS host, named `bash` or /bin/bash, is
    /// taken to be macOS's own 3.2, which ignores the injection.
    nonisolated static func shellSupportsInjection(_ shell: String,
                                                   loginShell: String,
                                                   loginShellVersion: String) -> Bool {
        let name = shell.lastPathComponent
        let alwaysSupported = ["fish", "nu", "xonsh", "zsh"]
        if alwaysSupported.contains(name) {
            return true
        }
        guard name == "bash" else {
            // Unrecognized shell
            return false
        }
        let versionIsThisShells = loginShell.lastPathComponent == "bash" &&
            (shell == loginShell || !shell.contains("/"))
        if versionIsThisShells {
            // macOS's bash doesn't support --posix
            return !(loginShellVersion.contains("GNU bash, version 3.2.57") &&
                     loginShellVersion.contains("apple-darwin"))
        }
        let macOS = loginShellVersion.contains("apple-darwin")
        return !(macOS && (shell == "bash" || shell == "/bin/bash"))
    }

    private func sendInitialText() {
        delegate?.conductorSendInitialText()
    }

    struct IgnoreCommandError: Error { }

    // Internal for tests, which feed it the remote's answers.
    func update(executionContext: ExecutionContext, result: PartialResult) throws {
        log("update \(executionContext) result=\(result)")
        switch executionContext.handler {
        case .handleNonFramerLogin:
            switch result {
            case .end(let status):
                if status == 0 {
                    sendInitialText()
                } else {
                    fail(String(localized: "Conductor.UnexpectedStatus", defaultValue: "\(executionContext.command.stringValue): Unepected status \(String(describing: status))", comment: "Error when a remote command returns an unexpected exit status"))
                }
            case .abort, .line(_), .sideChannelLine(line: _, channel: _, pid: _), .canceled:
                break
            }
        case .failIfNonzeroStatus:
            switch result {
            case .end(let status):
                if status != 0 {
                    fail(String(localized: "Conductor.UnexpectedStatus", defaultValue: "\(executionContext.command.stringValue): Unepected status \(String(describing: status))", comment: "Error when a remote command returns an unexpected exit status"))
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
        case .it2Listen:
            // Otherwise fire-and-forget, but a framer bind failure (read-only or full $HOME,
            // EACCES on the dir, lock contention, start_unix_server error) returns non-zero
            // and would vanish silently -- the remote it2 then just cannot connect with no
            // diagnostic on either side. Record success so it2ProxyActive reflects reality (the
            // menu is enabled only when the socket is actually bound), and DLog for the field.
            switch result {
            case .end(let status):
                it2ListenSucceeded = (status == 0)
                if status != 0 {
                    DLog("it2Listen: framer failed to bind the it2 socket (status \(status)); it2 over ssh will not work for this session")
                }
            case .abort, .canceled:
                it2ListenSucceeded = false
            case .line(_), .sideChannelLine(line: _, channel: _, pid: _):
                break
            }
            return
        case .handleResetMarker(let marker, let lines):
            switch result {
            case .line(let message):
                lines.strings.append(message)
            case .end:
                // The reply is a JSON record whose absolutePath is the marker.
                if lines.strings.contains(where: { $0.contains("\"\(marker)\"") }) {
                    log("Have received the reset marker")
                } else {
                    log("Skip a reply to an earlier command while waiting for the reset marker")
                    lines.strings.removeAll()
                    throw IgnoreCommandError()
                }
            case .abort, .sideChannelLine, .canceled:
                break
            }
        case .handleProbedReset(let code, let lines):
            switch result {
            case .line(let message):
                lines.strings.append(message)
            case .end:
                if lines.strings.contains(code) {
                    log("The framer speaks reset2")
                    framerVersion = .v2
                } else {
                    log("The framer predates reset2; reset it the old way")
                    framerVersion = .v1
                    // Ahead of the autopoll and registrations queued after the reset, which the
                    // old reset would otherwise clear.
                    send(.framerReset1, highPriority: true, .fireAndForget)
                }
            case .abort, .sideChannelLine, .canceled:
                break
            }
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
                    if name == "USER" {
                        // tmux panes on this host take it (TmuxPaneInferredHost).
                        delegate?.conductorStateDidChange()
                    }
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
                    fail(String(localized: "Conductor.PythonCodeStatus", defaultValue: "Status \(String(describing: status)) when running python code", comment: "Error when running remote python code returns a nonzero status"))
                }
                return
            }
        case .handleRunRemoteCommand(let commandLine, let completion, let started):
            switch result {
            case .line(let line):
                guard let pid = Int32(line) else {
                    return
                }
                addBackgroundJob(pid,
                                 command: .framerRun(commandLine)) { data, status in
                    completion.call(data, status)
                }
                started?.call(pid)
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
                // If you ran `it2ssh localhost claude`, the login shell from getshell runs claude.
                let parts = lines.strings.joined(separator: "").components(separatedBy: "\n").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let launchKind = Self.remoteLaunchKind(commandArgs: parsedSSHArguments.commandArgs)
                let shell: String
                if case .customShell(let customShell) = launchKind {
                    shell = customShell
                } else {
                    shell = parts.get(0, default: "")
                }
                let home = parts.get(1, default: "")
                let version: String
                if parts.count > 1 {
                    version = parts[2...].joined(separator: "\n")
                } else {
                    version = ""
                }
                let setup = Self.remoteSetup(
                    launchKind: launchKind,
                    shellSupportsInjection: !shell.isEmpty && Self.shellSupportsInjection(
                        shell, loginShell: parts.get(0, default: ""), loginShellVersion: version),
                    shouldInjectShellIntegration: shouldInjectShellIntegration,
                    haveHome: !home.isEmpty,
                    customShellIsInteractive: Self.customShellIsInteractive(
                        arguments: Array(parsedSSHArguments.commandArgs.dropFirst())))
                DLog("getshell: shell=\(shell) launch=\(launchKind) setup=\(setup)")
                if setup.injectShellIntegration {
                    (modifiedVars, modifiedCommandArgs) = ShellIntegrationInjector.instance.modifyRemoteShellEnvironment(
                        shellIntegrationDir: "\(home)/.iterm2/shell-integration",
                        env: varsToSend,
                        shell: shell,
                        argv: Array(parsedSSHArguments.commandArgs.dropFirst()))
                    if let firstArg = parsedSSHArguments.commandArgs.first {
                        // The user gave an explicit command/shell (`it2ssh host <argv0> …`); keep it
                        // as argv[0] so the framer runs it (through its `-c` path).
                        modifiedCommandArgs?.insert(firstArg, at: 0)
                    } else if modifiedCommandArgs?.isEmpty == false {
                        // Plain interactive session whose injection modified argv (bash's --posix).
                        // The shell must be named explicitly so those args take effect, which routes
                        // through the framer's `-c` path (there the interactive child still honors
                        // env-based injection like bash's $ENV loader).
                        modifiedCommandArgs?.insert(shell, at: 0)
                    }
                    // Otherwise: a plain interactive session with purely env-based injection
                    // (zsh/fish/xonsh/nu add no argv). Leave modifiedCommandArgs empty so framerLogin
                    // passes no args and the framer execs the login shell *interactively*, inheriting
                    // the injected environment (e.g. ZDOTDIR). If we named the shell here the framer
                    // would run `login_shell -c "<shell>"`; when the login shell is the same shell
                    // (notably zsh) the outer non-interactive shell reads and dismantles the injection
                    // before the inner interactive shell runs -- zsh's injected .zshenv unsets ZDOTDIR
                    // and skips its interactive-only shell-integration load -- so integration would
                    // never load.
                    uploadShellIntegrationPayloads()
                }
                if setup.uploadIT2 {
                    uploadIT2Payloads()
                }
                if setup.activateIT2 {
                    // Not yet: the socket only exists if the framer starts, which needs a usable
                    // Python, and that is checked next. See doFraming.
                    pendingIT2Home = home
                    pendingIT2OnShellPath = setup.putIT2OnShellPath
                } else {
                    RLog("No it2 socket for this connection: the remote home directory is unknown")
                }
                self.shell = shell
                putIT2OnCommandPath = setup.putIT2OnCommandPath
                loginShell = parts.get(0, default: "")
                delegate?.conductorStateDidChange()
                didFinishGetShell()
            }
        case .handleBackgroundJob(let output, let completion):
            switch result {
            case .line(_):
                fail(String(localized: "Conductor.UnexpectedOutput", defaultValue: "Unexpected output from \(executionContext.command.stringValue)", comment: "Error when a background job produces unexpected output"))
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
            case .sideChannelLine(_, _, _):
                break
            case .abort, .canceled:
                // As other handlers do, so a caller waiting on the reply is not left hanging
                // when the connection ends or the queue is reset.
                completion.call("", Self.abortedStatus)
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
            fail(String(localized: "Conductor.InvalidPID", defaultValue: "Invalid process ID from remote: \(lines.string)", comment: "Error when the remote returns a non-numeric process ID"))
            return
        }
        framedPID = pid
        sendInitialText()
        delegate?.conductorStateDidChange()
        delegate?.conductorStopQueueingInput()
    }

    @objc(handleLine:depth:) func handle(line: String, depth: Int32) {
        log("[\(framedPID.map { String($0) } ?? "unframed")] handle input: \(line) depth=\(depth)")
        // A shallower depth is an ancestor's even when this one does not frame yet, as while it
        // is being recovered: the parser only goes deeper below a framing conductor.
        if (depth != self.depth && framing) || depth < self.depth {
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
        hasEnded = true
        flowMayBeOn = false
        stopFlowControl()
        abandonPanes()
        // Settle the state before notifying anyone, the way forceReturnToGroundState does.
        // These handlers can call back into send() -- handleCheckForPython's abort arm calls
        // execLoginShell() -- and a re-entrant send() that saw the pipeline still in `state`
        // would extend it and write to a conductor being torn down, on a connection whose
        // framer is gone, after which `state = .unhooked` drops the contexts so those
        // handlers never fire.
        var aborted = contextsInFlight
        log("Abort pending commands")
        aborted.append(contentsOf: queue)
        queue = []
        state = .unhooked
        for context in aborted {
            try? update(executionContext: context, result: .abort)
        }
        // Cancel any in-flight it2 commands so a streaming command (monitor
        // --follow) does not keep looping on a background queue holding an
        // in-process API connection after the conductor is gone.
        it2Demux?.cancelAll()
        resolveIT2Authorization(false, persist: false)
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
        if (!expectFraming && type == "f") || (framing && depth != self.depth) || depth < self.depth {
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
                try withPipelineTransition {
                    try update(executionContext: contexts.first!, result: .end(status))
                    // After the handler accepted the end (reset2 ignores stale ones), and
                    // inside the transition, so a ping it sends waits until this command has
                    // left the pipeline.
                    flowCommandDidEnd(contexts.first!)
                }
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
                try withPipelineTransition {
                    try update(executionContext: context, result: .end(status))
                    flowCommandDidEnd(context)
                }
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
        if handlePaneTermination(pid, code: code) {
            return
        }
        if pid == framedPID {
            // The framer reads framer commands; the pre-framer `quit` means nothing to it.
            framerQuit()
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
                backgroundJobOutputBytes.removeValue(forKey: pid)
            case let .executingPipeline(context, _):
                do {
                    try update(executionContext: context, result: .end(UInt8(code)))
                    backgroundJobs.removeValue(forKey: pid)
                    backgroundJobOutputBytes.removeValue(forKey: pid)
                    log("Remove background job \(pid) after handling termination while in executingPipeline job state")
                } catch {
                    log("Got \(error) so not updating state")
                }
            }
        }
    }

    // Remote it2 CLI RPC. Framer emits "%it2 <connid> <event> [<base64>]" frames
    // that arrive here whole (see SSH_IT2 / VT100ConductorParser). Route by depth
    // so a frame is handled by the conductor that owns its nesting level, then hand
    // it to the per-connid demux (Conductor+IT2) which reconstructs the it2.py wire
    // protocol and dispatches through the in-process API server.
    @objc(handleIT2:depth:)
    func handleIT2(_ string: String, depth: Int32) {
        if depth != self.depth {
            DLog("Pass it2 frame with depth \(depth) to parent \(String(describing: parent)) because my depth is \(self.depth)")
            parent?.handleIT2(string, depth: depth)
            return
        }
        DLog("handleIT2 \(string.semiVerboseDescription) depth=\(depth)")
        // Under flow control version 2, data carries the framer's clock and flags, which the
        // screen recorded on arrival.
        let parts = string.split(separator: " ", omittingEmptySubsequences: false)
        if parts.count == 5, parts[1] == "data" {
            it2DemuxForHandling().handle(parts[0...2].joined(separator: " "))
            flowIT2DidConsume(bytes: Data(base64Encoded: String(parts[2]))?.count ?? 0)
            return
        }
        it2DemuxForHandling().handle(string)
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
        guard acceptBackgroundJobOutput(string, pid: pid) else {
            return
        }
//        DLog("pid \(pid) channel \(channel) produced: \(string)")
        switch jobState {
        case .ground, .unhooked, .recovery, .recovered:
            // Tolerate unexpected inputs - this is essential for getting back on your feet when
            // restoring.
            log("Unexpected input: \(string)")
        case let .willExecutePipeline(contexts):
            // The job's own state, not the conductor's: this is backgroundJobs[pid]. Mirrors
            // the same transition in handle(line:), including delivering the line that
            // triggered it.
            backgroundJobs[pid] = .executingPipeline(contexts.first!, Array(contexts.dropFirst()))
            try? update(executionContext: contexts.first!,
                        result: .sideChannelLine(line: string, channel: channel, pid: pid))
        case let .executingPipeline(context, _):
            try? update(executionContext: context,
                        result: .sideChannelLine(line: string, channel: channel, pid: pid))
        }
    }

    /// Counts a background job's output against sideCommandOutputCap. Past it, the job is
    /// killed and the rest of its output dropped; it still ends when the framer reports it.
    private func acceptBackgroundJobOutput(_ string: String, pid: Int32) -> Bool {
        let before = backgroundJobOutputBytes[pid, default: 0]
        let after = before + string.utf8.count
        backgroundJobOutputBytes[pid] = after
        guard after > sideCommandOutputCap else {
            return true
        }
        if before <= sideCommandOutputCap {
            RLog("Background job \(pid) produced more than \(sideCommandOutputCap) bytes. Kill it.")
            send(.framerKill(pid: Int(pid)), .fireAndForget)
        }
        return false
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

        if message.trimmingCharacters(in: .whitespacesAndNewlines) == "%notif valve" {
            flowValveDidOpen()
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
                        let recovery = ConductorRecovery(pid: finished.login,
                                                 dcsID: finished.dcsID,
                                                 tree: finished.tree,
                                                 sshargs: finished.sshargs,
                                                 boolArgs: finished.boolArgs,
                                                 clientUniqueID: finished.clientUniqueID,
                                                 version: finished.version,
                                                 flow: finished.flow,
                                                 panes: finished.panes,
                                                 parent: parent,
                                                 it2Proxy: it2Proxy)
                        recovery.unclaimedPanes = unclaimedPanes
                        return recovery
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
                case "flow":
                    temp.flow = String(value)
                case "pane":
                    guard let pid = Int32(value) else {
                        return nil
                    }
                    temp.panes.append(pid)
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
            // First in, first out among high-priority commands, so typed keys stay in order,
            // and ahead of everything else, such as upload chunks.
            var context = context
            context.isHighPriority = true
            let index = queue.firstIndex { $0.isHighPriority != true } ?? queue.count
            queue.insert(context, at: index)
        } else {
            // A possible optimization is to merge search acks here. Rather than appending a new
            // ack to the queue, just increment the count.
            queue.append(context)
        }
        guard !pipelineTransitionInProgress else {
            // A pipeline transition is mid-flight and will dispatch this as soon as the
            // handler it is running returns. See pipelineTransitionInProgress.
            log("Defer dispatch: a pipeline transition is in progress")
            return
        }
        switch state {
        case .ground, .recovery:
            dequeue()
        case .willExecutePipeline(let inFlight):
            // Top up a pipeline that has been written but whose first command has not begun.
            //
            // Without this a command enqueued while anything is in flight waits for that
            // command's %end to come back before it is even written, which is a full round
            // trip to the remote. Keystrokes are such commands: framerSend is pipelinable
            // precisely so several can be outstanding at once (issue 11266), but a keystroke
            // could only join a pipeline still being formed, never one already sent, so
            // typing faster than the round trip made every key after the first wait one out.
            // Issue 13013.
            extendPipeline(inFlight) { contexts in
                state = .willExecutePipeline(contexts)
            }
        case .executingPipeline(let context, let pending):
            // Same, except `context` has already had its begin parsed, so it stays the
            // executing one and the new commands join those queued behind it.
            extendPipeline([context] + pending) { contexts in
                state = .executingPipeline(context, Array(contexts.dropFirst()))
            }
        case .unhooked, .recovered:
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
        return Self.encodeForWire(pending.command, linePrefix: linePrefix)
    }

    // Produces the bytes written to the remote for `command`. Internal for testing.
    nonisolated static func encodeForWire(_ command: Command, linePrefix: String) -> String {
        return encode(arguments: command.wireArguments,
                      isFramer: command.isFramer,
                      linePrefix: linePrefix)
    }

    /// The text written for a command's arguments, without the blank line that ends it.
    nonisolated static func encode(arguments: [String], isFramer: Bool, linePrefix: String) -> String {
        let encoded = arguments.map(\.base64Encoded)
        guard isFramer else {
            return encoded
                .joined(separator: "\n")
                .chunk(128)
                .map { linePrefix + $0 }
                .joined(separator: "\n") + "\n"
        }
        // framer.py reads a line that ends in a backslash as continued on the next, and a blank
        // line as the end of the command. Each argument is chunked on its own, since cutting
        // the joined arguments could put a backslash just before a separating newline and
        // leave a blank line. Base64 has no backslashes or newlines. An empty argument is
        // sent as "=", which decodes to nothing.
        return encoded
            .flatMap { ($0.isEmpty ? "=" : $0).chunk(128, continuation: "\\") }
            .joined(separator: "\n") + "\n"
    }

    private func amendPipeline(_ existing: [ExecutionContext]) {
        log("amendPipeline")
        extendPipeline(existing) { contexts in
            state = .willExecutePipeline(contexts)
        }
    }

    // Takes whatever queued commands can ride along with the pipeline `existing`, hands the
    // resulting pipeline to `setState`, and writes the new commands. State is set before
    // anything is written, as it must be: write() reaches the delegate and, for a nested
    // conductor, the parent, so the pipeline has to be recorded before we give up control.
    // `setState` rather than a return value because only the caller knows whether the first
    // context has already had its begin parsed.
    private func extendPipeline(_ existing: [ExecutionContext],
                                setState: ([ExecutionContext]) -> ()) {
        // takeNextContextPipeline measures `existing` and requires its first element to be
        // pipelinable. A pipeline of one may hold a command that is not, and nothing can
        // ride along with such a command anyway.
        guard existing.allSatisfy(\.supportsPipelining) else {
            log("Can't pipeline behind \(existing.last?.debugDescription ?? "nothing")")
            return
        }
        // A nil delegate means nothing can be written, so tear down rather than build. The
        // in-flight contexts live in `state`, not in `queue`, so they have to be aborted
        // explicitly: takeNextContext's own nil-delegate branch only drains the queue, and
        // before send() could reach here from an in-flight state there was never anything
        // in flight to lose. Dropping one silently strands its handler, and
        // performFileOperation's continuation is only resumed from that handler, so the
        // awaiting task would hang forever.
        guard delegate != nil else {
            log("delegate is nil. abort everything in flight and queued, and reset state.")
            var dropped: [DroppedContext] = existing.map { ($0, .abort) }
            dropped.append(contentsOf: queue.map { ($0, .abort) })
            queue = []
            state = .ground
            for (context, result) in dropped {
                try? update(executionContext: context, result: result)
            }
            return
        }
        // Take without notifying anyone. Dropping a canceled or aborted context runs its
        // handler, and those handlers re-enter the conductor: handleCheckForPython's
        // cancel arm calls execLoginShell(), which calls send(), and several call fail(),
        // which calls forceReturnToGroundState(). Running them here, with the pipeline
        // half-built, would let the re-entrant call install a state that setState below
        // then overwrites -- leaving commands on the wire that `state` does not know
        // about, so their responses are attributed to the wrong context and their handlers
        // never fire -- or resurrect a pipeline that fail() had just torn down. Collect
        // them and notify once the state is consistent.
        var dropped: [DroppedContext] = []
        defer {
            for (context, result) in dropped {
                try? update(executionContext: context, result: result)
            }
        }
        var contexts = takeNextContextPipeline(existing, dropped: &dropped)
        guard contexts.count > existing.count else {
            log("Nothing to take")
            return
        }
        let now = flowClock()
        for i in existing.count..<contexts.count {
            contexts[i].writtenAt = now
        }
        // The writes are a mutation window as well. State is already consistent here, so a
        // re-entrant send() would legitimately extend the pipeline and write immediately,
        // interleaving with this loop: the wire order would be B, D, C while `state` says
        // A, B, C, D, so D's %begin/%end would be attributed to C. That is worse than the
        // windows above, where commands were merely missing from state. Defer instead;
        // anything enqueued during the writes goes out on the next transition.
        withPipelineTransition {
            setState(contexts)
            for pending in contexts[existing.count...] {
                willSend(pending)
                let chunked = encode(pending)
                write(chunked, highPriority: pending.isHighPriority == true)
            }
        }
    }

    // A context removed from the queue without being sent, plus the result its handler is
    // owed. See extendPipeline for why these are collected instead of dispatched inline.
    private typealias DroppedContext = (context: ExecutionContext, result: PartialResult)

    // Runs `body` with pipeline mutation from send() deferred; see
    // pipelineTransitionInProgress. Nested transitions restore the previous value rather
    // than clearing the flag outright.
    private func withPipelineTransition<T>(_ body: () throws -> T) rethrows -> T {
        let saved = pipelineTransitionInProgress
        pipelineTransitionInProgress = true
        defer { pipelineTransitionInProgress = saved }
        return try body()
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

    private func takeNextContextPipeline(_ existing: [ExecutionContext],
                                        dropped: inout [DroppedContext]) -> [ExecutionContext] {
        if let first = existing.first {
            precondition(first.supportsPipelining)
        }
        var size = existing.map(\.size).reduce(0, +)
        var result = existing
        let maxSize = 1024
        log("Initial size is \(size)")
        while size < maxSize, let context = takeNextContext(onlyIfSupportsPipelining: !result.isEmpty,
                                                            dropped: &dropped) {
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

    // Appends to `dropped` rather than notifying handlers directly, so that nothing can
    // re-enter the conductor while a pipeline is being assembled. The caller notifies.
    private func takeNextContext(onlyIfSupportsPipelining: Bool,
                                 dropped: inout [DroppedContext]) -> ExecutionContext? {
        guard delegate != nil else {
            log("delegate is nil. clear queue and reset state.")
            while let pending = queue.first {
                queue.removeFirst()
                dropped.append((pending, .abort))
            }
            state = .ground
            return nil
        }
        while let pending = queue.first, pending.canceled {
            log("cancel \(pending)")
            queue.removeFirst()
            dropped.append((pending, .canceled))
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

    /// A nested conductor's writes become its parent's keystrokes. `highPriority` carries the
    /// priority lane through, so a key typed in a nested session is not held behind the
    /// parent's own queued commands, while relayed bulk such as upload chunks is.
    func write(_ string: String, end: String = "\n", highPriority: Bool = false) {
        log("write: \(string)")
        let savedQueueWrites = _queueWrites
        _queueWrites = false
        if let parent = parent {
            if let data = (string + end).data(using: .utf8) {
                log("ask parent to send: \(string)")
                parent.sendKeys(data, highPriority: highPriority)
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

    /// Every command written and not yet answered, oldest first.
    var contextsInFlight: [ExecutionContext] {
        switch state {
        case .executingPipeline(let context, let pending):
            return [context] + pending
        case .willExecutePipeline(let contexts):
            return contexts
        case .ground, .recovered, .unhooked, .recovery:
            return []
        }
    }

    func forceReturnToGroundState() {
        log("forceReturnToGroundState")
        // Commands in flight are abandoned as well as queued ones. Each handler hears of it,
        // or a caller waiting on its reply (a pane's start, say) would wait forever. State is
        // settled first, since handlers can send again.
        let aborted = contextsInFlight + queue
        state = .ground
        queue = []
        for context in aborted {
            try? update(executionContext: context, result: .abort)
        }
        parent?.forceReturnToGroundState()
    }

    private func fail(_ reason: String) {
        DLog("FAIL: \(reason)")
        hasEnded = true
        flowMayBeOn = false
        stopFlowControl()
        abandonPanes()
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
