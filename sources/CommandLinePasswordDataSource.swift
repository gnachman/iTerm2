//
//  CommandLinePasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation
import OSLog

/*
@available(macOS 11.0, *)
private let passwordLogger = Logger(subsystem: "com.googlecode.iterm2.PasswordManager", category: "default")
*/

class CommandLineProvidedAccount: NSObject, PasswordManagerAccount {
    private let configuration: CommandLinePasswordDataSource.Configuration
    let identifier: String
    let accountName: String
    let userName: String
    var displayString: String {
        return "\(accountName)\u{2002}—\u{2002}\(userName)"
    }

    func fetchPassword(_ completion: @escaping (String?, Error?) -> ()) {
        configuration.getPasswordRecipe.transformAsync(inputs: CommandLinePasswordDataSource.AccountIdentifier(value: identifier)) { result, error in
            completion(result, error)
        }
    }

    func set(password: String, completion: @escaping (Error?) -> ()) {
        let accountIdentifier = CommandLinePasswordDataSource.AccountIdentifier(value: identifier)
        let request = CommandLinePasswordDataSource.SetPasswordRequest(accountIdentifier: accountIdentifier,
                                                                       newPassword: password)
        configuration.setPasswordRecipe.transformAsync(inputs: request) { _, error in
            completion(error)
        }
    }

    func delete(_ completion: @escaping (Error?) -> ()) {
        configuration.deleteRecipe.transformAsync(inputs: CommandLinePasswordDataSource.AccountIdentifier(value: identifier)) { _, error in
            if error == nil {
                self.configuration.listAccountsRecipe.invalidateRecipe()
            }
            completion(error)
        }
    }

    func matches(filter: String) -> Bool {
        return accountName.containsCaseInsensitive(filter) || userName.containsCaseInsensitive(filter)
    }

    init(identifier: String,
         accountName: String,
         userName: String, configuration: CommandLinePasswordDataSource.Configuration) {
        self.identifier = identifier
        self.accountName = accountName
        self.userName = userName
        self.configuration = configuration
    }
}

struct Output {
    let stderr: Data
    let stdout: Data
    let returnCode: Int32
    let terminationReason: Process.TerminationReason
    fileprivate(set) var timedOut = false
    let userData: [String: String]?

    var lines: [String] {
        return String(data: stdout, encoding: .utf8)?.components(separatedBy: "\n") ?? []
    }
}

protocol CommandLinePasswordDataSourceExecutableCommand {
    func exec() throws -> Output
    func execAsync(_ completion: @escaping (Output?, Error?) -> ())
}

protocol Recipe {
    associatedtype Inputs
    associatedtype Outputs
    func transformAsync(inputs: Inputs, completion: @escaping (Outputs?, Error?) -> ())
}

protocol InvalidatableRecipe {
    func invalidateRecipe()
}

protocol CommandWriting {
    func write(_ data: Data, completion: (() -> ())?)
    func closeForWriting()
}

class CommandLinePasswordDataSource: NSObject {
    struct OutputBuilder {
        var stderr = Data()
        var stdout = Data()
        var timedOut = MutableAtomicObject<Bool>(false)
        var returnCode: Int32? = nil
        var terminationReason: Process.TerminationReason? = nil
        var userData: [String: String]?

        fileprivate var canBuild: Bool {
            return returnCode != nil && terminationReason != nil
        }

        func tryBuild() -> Output? {
            guard let returnCode = returnCode,
                  let terminationReason = terminationReason else {
                return nil
            }
            return Output(stderr: stderr,
                          stdout: stdout,
                          returnCode: returnCode,
                          terminationReason: terminationReason,
                          timedOut: (terminationReason == .uncaughtSignal) && timedOut.value,
                          userData: userData)
        }
    }

    struct CommandRequestWithInput: CommandLinePasswordDataSourceExecutableCommand {
        var command: String
        var args: [String]
        var env: [String: String]
        var input: Data
        private var request: InteractiveCommandRequest {
            var request = InteractiveCommandRequest(command: command,
                                                    args: args,
                                                    env: env)
            request.callbacks = InteractiveCommandRequest.Callbacks(
                callbackQueue: InteractiveCommandRequest.ioQueue,
                handleStdout: nil,
                handleStderr: nil,
                handleTermination: nil,
                didLaunch: { writing in
                    writing.write(input) {
                        writing.closeForWriting()
                    }
                })
            return request
        }

        func execAsync(_ completion: @escaping (Output?, Error?) -> ()) {
            request.execAsync { output, error in
                DispatchQueue.main.async {
                    completion(output, error)
                }
            }
        }

        func exec() throws -> Output {
            return try request.exec()
        }
    }

    struct InteractiveCommandRequest: CommandLinePasswordDataSourceExecutableCommand {
        var command: String
        var args: [String]
        var env: [String: String]
        var userData: [String: String]?
        var deadline: Date?
        var callbacks: Callbacks? = nil
        var useTTY = false
        var executionQueue = DispatchQueue.global()
        static let ioQueue = DispatchQueue(label: "com.iterm2.pwcmd-io")

        struct Callbacks {
            var callbackQueue: DispatchQueue
            var handleStdout: ((Data) throws -> Data?)? = nil
            var handleStderr: ((Data) throws -> Data?)? = nil
            var handleTermination: ((Int32, Process.TerminationReason) throws -> ())? = nil
            var didLaunch: ((CommandWriting) -> ())? = nil
        }

        init(command: String,
             args: [String],
             env: [String: String]) {
            self.command = command
            self.args = args
            self.env = env
        }

        func exec() throws -> Output {
            var _output: Output? = nil
            var _error: Error? = nil
            let group = DispatchGroup()
            group.enter()
            DLog("Execute: \(command) \(args) with environment keys \(Array(env.keys.map { String($0) }))")
            execAsync { output, error in
                _output = output
                _error = error
                group.leave()
            }
            group.wait()
            if let error = _error {
                throw error
            }
            return _output!
        }

        func execAsync(_ completion: @escaping (Output?, Error?) -> ()) {
            let tty: TTY?
            if useTTY {
                do {
                    var term = termios.standard
                    var size = winsize(ws_row: 25, ws_col: 80, ws_xpixel: 250, ws_ypixel: 800)
                    tty = try TTY(term: &term, size: &size)
                } catch {
                    completion(nil, error)
                    return
                }
            } else {
                tty = nil
            }
            executionQueue.async {
                do {
                    let command = RunningInteractiveCommand(
                        request: self,
                        process: Process(),
                        stdout: Pipe(),
                        stderr: Pipe(),
                        stdin: tty ?? Pipe(),
                        ioQueue: Self.ioQueue)
                    let output = try command.run()
                    completion(output, nil)
                } catch {
                    completion(nil, error)
                }
            }
        }
    }

    private class RunningInteractiveCommand: CommandWriting {
        private enum Event: CustomDebugStringConvertible {
            case readOutput(Data?)
            case readError(Data?)
            case terminated(Int32, Process.TerminationReason)

            var debugDescription: String {
                switch self {
                case .readOutput(let data):
                    guard let data = data else {
                        return "stdout:[eof]"
                    }
                    guard let string = String(data: data, encoding: .utf8) else {
                        return "stdout:[not utf-8]"
                    }
                    return "stdout:\(string)"
                case .readError(let data):
                    guard let data = data else {
                        return "stderr:[eof]"
                    }
                    guard let string = String(data: data, encoding: .utf8) else {
                        return "stderr:[not utf-8]"
                    }
                    return "stderr:\(string)"
                case .terminated(let code, let reason):
                    return "terminated(code=\(code), reason=\(reason))"
                }
            }
        }

        private let request: InteractiveCommandRequest
        private let process: Process
        private var stdoutChannel: DispatchIO?
        private var stderrChannel: DispatchIO?
        private var stdinChannel: DispatchIO?
        private var stdin: ReadWriteFileHandleVending
        private let queue: AtomicQueue<Event>
        private let timedOut = MutableAtomicObject(false)
        private let ioQueue: DispatchQueue
        private let group = DispatchGroup()
        private var debugging: Bool {
            gDebugLogging.boolValue
        }
        private let lastError = MutableAtomicObject<Error?>(nil)
        private var returnCode: Int32? = nil
        private var terminationReason: Process.TerminationReason? = nil
        private var stdoutData = Data()
        private var stderrData = Data()
        private var ran = false

        private static func readingChannel(_ pipe: ReadWriteFileHandleVending,
                                    ioQueue: DispatchQueue,
                                    handler: @escaping (Data?) -> ()) -> DispatchIO {
            let channel = DispatchIO(type: .stream,
                                     fileDescriptor: pipe.fileHandleForReading.fileDescriptor,
                                     queue: ioQueue,
                                     cleanupHandler: { _ in })
            channel.setLimit(lowWater: 1)
            read(channel, ioQueue: ioQueue, handler: handler)
            return channel
        }

        private static func read(_ channel: DispatchIO,
                                 ioQueue: DispatchQueue,
                                 handler: @escaping (Data?) -> ()) {
            channel.read(offset: 0, length: 1024, queue: ioQueue) { [channel] done, data, error in
                Self.didRead(channel,
                             done: done,
                             data: data,
                             error: error,
                             ioQueue: ioQueue,
                             handler: handler)
            }
        }

        private static func didRead(_ channel: DispatchIO?,
                                    done: Bool,
                                    data: DispatchData?,
                                    error: Int32,
                                    ioQueue: DispatchQueue,
                                    handler: @escaping (Data?) -> ()) {
            if done && (data?.isEmpty ?? true) {
                handler(nil)
                return
            }
            guard let regions = data?.regions else {
                if done {
                    handler(nil)
                }
                return
            }
            for region in regions {
                var data = Data(count: region.count)
                data.withUnsafeMutableBytes {
                    _ = region.copyBytes(to: $0)
                }
                handler(data)
            }
            if let channel = channel {
                read(channel, ioQueue: ioQueue, handler: handler)
            }
        }

        init(request: InteractiveCommandRequest,
             process: Process,
             stdout: ReadWriteFileHandleVending,
             stderr: ReadWriteFileHandleVending,
             stdin: ReadWriteFileHandleVending,
             ioQueue: DispatchQueue) {
            self.request = request
            self.process = process
            self.stdin = stdin
            let queue = AtomicQueue<Event>()
            self.queue = queue
            self.ioQueue = ioQueue
            stdoutChannel = Self.readingChannel(stdout, ioQueue: ioQueue) { data in
                queue.enqueue(.readOutput(data))
            }
            stderrChannel = Self.readingChannel(stderr, ioQueue: ioQueue) { data in
                DLog("\(request.command) \(request.args) produced error output: \(String(data: data ?? Data(), encoding: .utf8) ?? String(describing: data))")
                queue.enqueue(.readError(data))
            }
            stdinChannel = DispatchIO(type: .stream,
                                      fileDescriptor: stdin.fileHandleForWriting.fileDescriptor,
                                      queue: ioQueue) { _ in }
            stdinChannel!.setLimit(lowWater: 1)
            process.launchPath = request.command
            process.arguments = request.args
            process.environment = request.env
            process.standardOutput = stdout
            process.standardError = stderr
            // NSProcess treats Pipe and NSFileHandle as magic types and defines standardInput as
            // Any? so the hacks trickle downhill to me here.
            if let pipe = stdin as? Pipe {
                process.standardInput = pipe
            } else if let tty = stdin as? TTY {
                process.standardInput = tty.slave
            } else {
                fatalError("Don't know what to do with stdin of type \(type(of: stdin))")
            }
        }

        private func beginTimeoutTimer(_ date: Date) {
            let dt = date.timeIntervalSinceNow
            self.ioQueue.asyncAfter(deadline: .now() + max(0, dt)) { [weak self] in
                _ = try? ObjC.catching {
                    self?.timedOut.set(true)
                    self?.process.terminate()
                }
            }
        }

        private func waitInBackground() {
            DispatchQueue.global().async {
                self.process.waitUntilExit()
                DLog("\(self.request.command) \(self.request.args) terminated status=\(self.process.terminationStatus) reason=\(self.process.terminationReason)")
                self.log("TERMINATED status=\(self.process.terminationStatus) reason=\(self.process.terminationReason)")
                self.queue.enqueue(.terminated(self.process.terminationStatus,
                                               self.process.terminationReason))
            }
        }

        private func terminate() throws {
            try ObjC.catching {
                DLog("Terminate \(Thread.callStackSymbols)")
                process.terminate()
            }
        }

        private func runCallback(_ closure: @escaping () throws -> ()) {
            request.callbacks?.callbackQueue.async {
                guard self.lastError.value == nil else {
                    return
                }
                do {
                    try closure()
                } catch {
                    self.lastError.set(error)
                    try? self.terminate()
                }
            }
        }

        private func mainloop() -> Output {
            var builder = OutputBuilder(userData: request.userData)
            while !allChannelsClosed || !builder.canBuild {
                log("dequeue…")
                let event = queue.dequeue()
                log("handle event \(event)")
                switch event {
                case .readOutput(let data):
                    log("\(request.command) \(request.args) read from stdout")
                    handleRead(channel: &stdoutChannel,
                               destination: &builder.stdout,
                               handler: request.callbacks?.handleStdout,
                               data: data)
                case .readError(let data):
                    log("\(request.command) \(request.args) read from stderr")
                    handleRead(channel: &stderrChannel,
                               destination: &builder.stderr,
                               handler: request.callbacks?.handleStderr,
                               data: data)
                case .terminated(let code, let reason):
                    log("\(request.command) \(request.args) terminated")
                    stdinChannel?.close()
                    stdinChannel = nil
                    builder.returnCode = code
                    builder.terminationReason = reason
                }
            }
            group.wait()
            let output = builder.tryBuild()!
            runTerminationHandler(output: output)
            group.wait()
            return output
        }

        private func runTerminationHandler(output: Output) {
            guard let handler = request.callbacks?.handleTermination else {
                return
            }
            group.enter()
            runCallback { [weak self] in
                try handler(output.returnCode, output.terminationReason)
                self?.group.leave()
            }
        }

        private func handleRead(channel: inout DispatchIO?,
                                destination: inout Data,
                                handler: ((Data) throws -> Data?)?,
                                data: Data?) {
            if let data = data {
                destination.append(data)
                if let handler = handler {
                    group.enter()
                    runCallback { [weak self] in
                        if let dataToWrite = try handler(data)  {
                            self?.write(dataToWrite, completion: nil)
                        }
                        self?.group.leave()
                    }
                }
            } else {
                channel?.close()
                channel = nil
            }
        }

        private var allChannelsClosed: Bool {
            return stdoutChannel == nil && stderrChannel == nil && stdinChannel == nil
        }

        func write(_ data: Data, completion: (() -> ())?) {
            dispatchPrecondition(condition: .onQueue(ioQueue))
            guard let channel = stdinChannel else {
                return
            }
            log("\(request.command) \(request.args) wants to write \(data.count) bytes: \(String(data: data, encoding: .utf8) ?? "(non-utf-8")")
            data.withUnsafeBytes { pointer in
                channel.write(offset: 0,
                              data: DispatchData(bytes: pointer),
                              queue: ioQueue) { _done, _data, _error in
                    self.log("\(self.request.command) \(self.request.args) wrote \(_data?.count ?? 0) of \(data.count) bytes. done=\(_done) error=\(_error)")
                    if _done, let completion = completion {
                        completion()
                    }
                    guard self.debugging else {
                        return
                    }
                    if let data = _data {
                        for region in data.regions {
                            var data = Data(count: region.count)
                            data.withUnsafeMutableBytes {
                                _ = region.copyBytes(to: $0)
                            }
                            self.log("stdin> \(String(data: data, encoding: .utf8) ?? "(non-UTF8)")")
                        }
                    } else if _error != 0 {
                        self.log("stdin error: \(_error)")
                    }
                }
            }
        }

        func closeForWriting() {
            dispatchPrecondition(condition: .onQueue(ioQueue))
            log("close stdin")
            stdin.fileHandleForWriting.closeFile()
            stdinChannel?.close()
            stdinChannel = nil
        }

        func run() throws -> Output {
            precondition(!ran)
            ran = true
            try ObjC.catching {
                self.process.launch()
            }
            log("Launched \(self.process.executableURL!.path) with args \(self.process.arguments ?? [])")
            if let date = request.deadline {
                beginTimeoutTimer(date)
            }
            waitInBackground()
            if let handler = request.callbacks?.didLaunch {
                runCallback {
                    handler(self)
                }
            }
            let output = mainloop()
            if let error = lastError.value {
                log("command threw \(error)")

                throw error
            }
            log("[\(request.command) \(request.args.joined(separator: " "))] Completed with return code \(output.returnCode)")
            return output
        }

        private func log(_ messageBlock: @autoclosure () -> String,
                         file: String = #file,
                         line: Int = #line,
                         function: String = #function) {
            if debugging {
                let message = messageBlock()
                // This is commented out because we don't want to log passwords. I keep it around
                // only for testing locally.
                /*
                if #available(macOS 11.0, *) {
                    passwordLogger.info("\(message, privacy: .public)")
                }
                 */
                DebugLogImpl(file, Int32(line), function, message)
            }
        }
    }

    struct CommandRecipe<Inputs, Outputs>: Recipe {
        private let inputTransformer: (Inputs) throws -> (CommandLinePasswordDataSourceExecutableCommand)
        private let recovery: (Error) throws -> Void
        private let outputTransformer: (Output) throws -> Outputs

        func transformAsync(inputs: Inputs, completion: @escaping (Outputs?, Error?) -> ()) {
            do {
                let command = try inputTransformer(inputs)
                DLog("\(inputs) -> \(command)")
                execAsync(command, completion)
            } catch {
                completion(nil, error)
                return
            }
        }

        private func execAsync(_ command: CommandLinePasswordDataSourceExecutableCommand,
                               _ completion: @escaping (Outputs?, Error?) -> ()) {
            command.execAsync { output, error in
                DispatchQueue.main.async {
                    if let output = output {
                        do {
                            completion(try outputTransformer(output), nil)
                        } catch {
                            do {
                                try recovery(error)
                                self.execAsync(command, completion)
                            } catch {
                                completion(nil, error)
                            }
                        }
                    }
                }
            }
        }

        init(inputTransformer: @escaping (Inputs) throws -> (CommandLinePasswordDataSourceExecutableCommand),
             recovery: @escaping (Error) throws -> Void,
             outputTransformer: @escaping (Output) throws -> Outputs) {
            self.inputTransformer = inputTransformer
            self.recovery = recovery
            self.outputTransformer = outputTransformer
        }
    }

    struct PipelineRecipe<FirstRecipe: Recipe, SecondRecipe: Recipe>: Recipe where FirstRecipe.Outputs == SecondRecipe.Inputs {
        typealias Inputs = FirstRecipe.Inputs
        typealias Outputs = SecondRecipe.Outputs

        let firstRecipe: FirstRecipe
        let secondRecipe: SecondRecipe

        init(_ firstRecipe: FirstRecipe, _ secondRecipe: SecondRecipe) {
            self.firstRecipe = firstRecipe
            self.secondRecipe = secondRecipe
        }

        func transformAsync(inputs: FirstRecipe.Inputs, completion: @escaping (SecondRecipe.Outputs?, Error?) -> ()) {
            firstRecipe.transformAsync(inputs: inputs) { outputs, error in
                if let outputs = outputs {
                    secondRecipe.transformAsync(inputs: outputs) { value, error in
                        completion(value, error)
                    }
                    return
                }
                completion(nil, error)
            }
        }
    }

    // Run firstRecipe, then run secondRecipe. The result of SecondRecipe gets returned.
    struct SequenceRecipe<FirstRecipe: Recipe, SecondRecipe: Recipe>: Recipe where SecondRecipe.Inputs == (FirstRecipe.Inputs, FirstRecipe.Outputs) {
        typealias Inputs = FirstRecipe.Inputs
        typealias Outputs = SecondRecipe.Outputs

        let firstRecipe: FirstRecipe
        let secondRecipe: SecondRecipe

        init(_ firstRecipe: FirstRecipe, _ secondRecipe: SecondRecipe) {
            self.firstRecipe = firstRecipe
            self.secondRecipe = secondRecipe
        }

        func transformAsync(inputs: FirstRecipe.Inputs, completion: @escaping (SecondRecipe.Outputs?, Error?) -> ()) {
            firstRecipe.transformAsync(inputs: inputs) { intermediate, error in
                if let intermediate = intermediate {
                    secondRecipe.transformAsync(inputs: (inputs, intermediate), completion: completion)
                    return
                }
                completion(nil, error)
            }
        }
    }

    struct CatchRecipe<Inner: Recipe>: Recipe {
        typealias Inputs = Inner.Inputs
        typealias Outputs = Inner.Outputs
        let inner: Inner
        let errorHandler: (Inputs, Error) -> ()
        init(_ recipe: Inner, errorHandler: @escaping (Inputs, Error) -> ()) {
            inner = recipe
            self.errorHandler = errorHandler
        }

        func transformAsync(inputs: Inner.Inputs, completion: @escaping (Inner.Outputs?, Error?) -> ()) {
            inner.transformAsync(inputs: inputs) { outputs, error in
                if let outputs = outputs {
                    completion(outputs, nil)
                    return
                }
                errorHandler(inputs, error!)
                completion(nil, error)
            }
        }
    }

    // Note that this only works with inputs of type Void. That's because the input type needs to
    // be equatable for the cache to make any kind of sense, but sadly Void is not and cannot
    // be made equatable. For a good time, read: https://nshipster.com/void/
    class CachingVoidRecipe<Outputs>: Recipe, InvalidatableRecipe {
        typealias Inputs = Void

        private struct Entry {
            let outputs: Outputs
            private let timestamp: TimeInterval

            var age: TimeInterval {
                return NSDate.it_timeSinceBoot() - timestamp
            }

            init(_ outputs: Outputs) {
                self.outputs = outputs
                self.timestamp = NSDate.it_timeSinceBoot()
            }
        }
        private var cacheEntry: Entry?
        let maxAge: TimeInterval
        let inner: AnyRecipe<Inputs, Outputs>

        func transformAsync(inputs: Void, completion: @escaping (Outputs?, Error?) -> ()) {
            if let value = cacheEntry, value.age < maxAge {
                completion(value.outputs, nil)
                return
            }
            inner.transformAsync(inputs: inputs) { [weak self] result, error in
                if let result = result {
                    self?.cacheEntry = Entry(result)
                    completion(result, nil)
                } else {
                    completion(nil, error)
                }
            }
        }
        func invalidateRecipe() {
            cacheEntry = nil
        }

        init(_ recipe: AnyRecipe<Inputs, Outputs>, maxAge: TimeInterval) {
            inner = recipe
            self.maxAge = maxAge
        }
    }

    enum CommandLineRecipeError: Error {
        case unsupported(reason: String)
    }

    struct UnsupportedRecipe<Inputs, Outputs>: Recipe {
        let reason: String
        func transform(inputs: Inputs) throws -> Outputs {
            throw CommandLineRecipeError.unsupported(reason: reason)
        }
        func transformAsync(inputs: Inputs, completion: @escaping (Outputs?, Error?) -> ()) {
            completion(nil, CommandLineRecipeError.unsupported(reason: reason))
        }
    }
    struct AnyRecipe<Inputs, Outputs>: Recipe, InvalidatableRecipe {
        private let closure: (Inputs, @escaping (Outputs?, Error?) -> ()) -> ()
        private let invalidate: () -> ()

        func transformAsync(inputs: Inputs, completion: @escaping (Outputs?, Error?) -> ()) {
            DispatchQueue.main.async {
                closure(inputs, completion)
            }
        }

        init<T: Recipe>(_ recipe: T) where T.Inputs == Inputs, T.Outputs == Outputs {
            closure = { recipe.transformAsync(inputs: $0, completion: $1) }
            invalidate = { (recipe as? InvalidatableRecipe)?.invalidateRecipe() }
        }
        func invalidateRecipe() {
            invalidate()
        }
    }

    struct AccountIdentifier {
        let value: String
    }

    struct Account {
        let identifier: AccountIdentifier
        let userName: String
        let accountName: String
    }

    struct SetPasswordRequest {
        let accountIdentifier: AccountIdentifier
        let newPassword: String
    }

    struct AddRequest {
        let userName: String
        let accountName: String
        let password: String
    }

    struct Configuration {
        let listAccountsRecipe: AnyRecipe<Void, [Account]>
        let getPasswordRecipe: AnyRecipe<AccountIdentifier, String>
        let setPasswordRecipe: AnyRecipe<SetPasswordRequest, Void>
        let deleteRecipe: AnyRecipe<AccountIdentifier, Void>
        let addAccountRecipe: AnyRecipe<AddRequest, AccountIdentifier>
    }

    func standardAccounts(_ configuration: Configuration,
                          completion: @escaping ([PasswordManagerAccount]?, Error?) -> ()) {
        return configuration.listAccountsRecipe.transformAsync(inputs: ()) { maybeAccounts, maybeError in
            if let error = maybeError {
                completion(nil, error)
                return
            }
            let accounts = maybeAccounts!.compactMap { account in
                CommandLineProvidedAccount(identifier: account.identifier.value,
                                           accountName: account.accountName,
                                           userName: account.userName,
                                           configuration: configuration)
            }
            completion(accounts, nil)
        }
    }

    func standardAdd(_ configuration: Configuration,
                     userName: String,
                     accountName: String,
                     password: String,
                     completion: @escaping (PasswordManagerAccount?, Error?) -> ()) {
        let inputs = AddRequest(userName: userName,
                                accountName: accountName,
                                password: password)
        configuration.addAccountRecipe.transformAsync(inputs: inputs) { accountIdentifier, maybeError in
            configuration.listAccountsRecipe.invalidateRecipe()
            if let error = maybeError {
                completion(nil, error)
                return
            }
            let account = CommandLineProvidedAccount(identifier: accountIdentifier!.value,
                                                     accountName: accountName,
                                                     userName: userName,
                                                     configuration: configuration)
            completion(account, nil)
        }
    }
}

protocol ReadWriteFileHandleVending: AnyObject {
    var fileHandleForReading: FileHandle { get }
    var fileHandleForWriting: FileHandle { get }
}

extension Pipe: ReadWriteFileHandleVending {
}

class TTY: NSObject, ReadWriteFileHandleVending {
    private(set) var master: FileHandle
    private(set) var slave: FileHandle?
    private(set) var path: String = ""

    init(term: inout termios,
         size: inout winsize) throws {
        var temp = Array<CChar>(repeating: 0, count: Int(PATH_MAX))
        var masterFD = Int32(-1)
        var slaveFD = Int32(-1)
        let rc = openpty(&masterFD,
                         &slaveFD,
                         &temp,
                         &term,
                         &size)
        if rc == -1 {
            throw POSIXError(POSIXError.Code(rawValue: errno)!)
        }
        master = FileHandle(fileDescriptor: masterFD)
        slave = FileHandle(fileDescriptor: slaveFD)
        path = String(cString: temp)

        super.init()
    }

    var fileHandleForReading: FileHandle {
        master
    }

    var fileHandleForWriting: FileHandle {
        master
    }
}

extension termios {
    static var standard: termios = {
        let ctrl = { (c: String) -> cc_t in cc_t(c.utf8[c.utf8.startIndex] - 64) }
        return termios(c_iflag: tcflag_t(ICRNL | IXON | IXANY | IMAXBEL | BRKINT | IUTF8),
                       c_oflag: tcflag_t(OPOST | ONLCR),
                       c_cflag: tcflag_t(CREAD | CS8 | HUPCL),
                       c_lflag: tcflag_t(ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL),
                       c_cc: (ctrl("D"), cc_t(0xff), cc_t(0xff), cc_t(0x7f),
                              ctrl("W"), ctrl("U"), ctrl("R"), cc_t(0),
                              ctrl("C"), cc_t(0x1c), ctrl("Z"), ctrl("Y"),
                              ctrl("Q"), ctrl("S"), ctrl("V"), ctrl("O"),
                              cc_t(1), cc_t(0), cc_t(0), ctrl("T")),
                       c_ispeed: speed_t(B38400),
                       c_ospeed: speed_t(B38400))
    }()
}
