//
//  CommandLinePasswordDataSource.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/19/22.
//

import Foundation

class CommandLineProvidedAccount: NSObject, PasswordManagerAccount {
    private let configuration: CommandLinePasswordDataSource.Configuration
    let identifier: String
    let accountName: String
    let userName: String
    var displayString: String {
        return "\(accountName)\u{2002}—\u{2002}\(userName)"
    }

    func password() throws -> String {
        return try configuration.getPasswordRecipe.transform(inputs: CommandLinePasswordDataSource.AccountIdentifier(value: identifier))
    }

    func set(password: String) throws {
        let accountIdentifier = CommandLinePasswordDataSource.AccountIdentifier(value: identifier)
        let request = CommandLinePasswordDataSource.SetPasswordRequest(accountIdentifier: accountIdentifier,
                                                                       newPassword: password)
        try configuration.setPasswordRecipe.transform(inputs: request)
    }

    func delete() throws {
        try configuration.deleteRecipe.transform(inputs: CommandLinePasswordDataSource.AccountIdentifier(value: identifier))
        configuration.listAccountsRecipe.invalidateRecipe()
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

protocol CommandLinePasswordDataSourceExecutableCommand {
    func exec() throws -> CommandLinePasswordDataSource.Output
}

protocol Recipe {
    associatedtype Inputs
    associatedtype Outputs
    func transform(inputs: Inputs) throws -> Outputs
}

protocol InvalidatableRecipe {
    func invalidateRecipe()
}

class CommandLinePasswordDataSource: NSObject {
    struct Output {
        let stderr: Data
        let stdout: Data
        let returnCode: Int32
        fileprivate(set) var timedOut = false
        let userData: [String: String]

        var lines: [String] {
            return String(data: stdout, encoding: .utf8)?.components(separatedBy: "\n") ?? []
        }
    }

    class InteractiveCommand: CommandLinePasswordDataSourceExecutableCommand {
        let command: String
        let args: [String]
        let env: [String: String]
        let handleStdout: (Data) throws -> Data?
        let handleStderr: (Data) throws -> Data?
        let handleTermination: (Int32, Process.TerminationReason) throws -> ()
        var didLaunch: (() -> ())? = nil
        var deadline: Date?
        private let serialQueue = DispatchQueue(label: "com.iterm2.pwmgr-cmd")
        private let process = Process()
        private let stdout = Pipe()
        private let stderr = Pipe()
        private let stdin = Pipe()
        private var stdoutChannel: DispatchIO? = nil
        private var stderrChannel: DispatchIO? = nil
        private var stdinChannel: DispatchIO? = nil
        private let queue: AtomicQueue<Event>
        var debugging: Bool = gDebugLogging.boolValue
        var userData = [String: String]()
        private(set) var output: Output? = nil

        private enum Event {
            case readOutput(Data?)
            case readError(Data?)
            case terminated(Int32, Process.TerminationReason)
        }

        private func readingChannel(_ pipe: Pipe,
                                    serialQueue: DispatchQueue,
                                    handler: @escaping (Data?) -> ()) -> DispatchIO {
            let channel = DispatchIO(type: .stream,
                                     fileDescriptor: pipe.fileHandleForReading.fileDescriptor,
                                     queue: serialQueue,
                                     cleanupHandler: { _ in })
            channel.setLimit(lowWater: 1)
            read(channel, handler)
            return channel
        }

        private func read(_ channel: DispatchIO, _ handler: @escaping (Data?) -> ()) {
            if debugging {
                NSLog("Schedule read")
            }
            channel.read(offset: 0, length: 1024, queue: serialQueue) { [weak self, channel] done, data, error in
                self?.didRead(channel, done: done, data: data, error: error, handler: handler)
            }
        }

        private func didRead(_ channel: DispatchIO?,
                             done: Bool,
                             data: DispatchData?,
                             error: Int32,
                             handler: @escaping (Data?) -> ()) {
            if done && (data?.isEmpty ?? true) {
                if debugging {
                    NSLog("done and data is empty, finish up")
                }
                handler(nil)
                return
            }
            guard let regions = data?.regions else {
                if done {
                    if debugging {
                        NSLog("No regions, finish up")
                    }
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
                read(channel, handler)
            } else {
                if debugging {
                    NSLog("NOT scheduling read. channel is nil")
                }
            }
        }

        func exec() throws -> Output {
            if debugging {
                NSLog("run \(command) \(args.joined(separator: " "))")
            }
            stdoutChannel = readingChannel(stdout, serialQueue: serialQueue) { [weak self] data in
                if self?.debugging ?? false {
                    if let data = data {
                        NSLog("stdout< \(String(describing: String(data: data, encoding: .utf8)))")
                    } else {
                        NSLog("stdout eof")
                    }
                }
                self?.queue.enqueue(.readOutput(data))
            }
            stderrChannel = readingChannel(stderr, serialQueue: serialQueue) { [weak self] data in
                if self?.debugging ?? false {
                    if let data = data {
                        NSLog("stderr< \(String(describing: String(data: data, encoding: .utf8)))")
                    } else {
                        NSLog("stderr eof")
                    }
                }
                self?.queue.enqueue(.readError(data))
            }

            stdinChannel = DispatchIO(type: .stream,
                                      fileDescriptor: stdin.fileHandleForWriting.fileDescriptor,
                                      queue: serialQueue) { _ in }
            stdinChannel?.setLimit(lowWater: 1)

            try ObjC.catching {
                self.process.launch()
            }

            let timedOut = MutableAtomicObject(false)
            if let date = deadline {
                let dt = date.timeIntervalSinceNow
                self.serialQueue.asyncAfter(deadline: .now() + max(0, dt)) { [weak self] in
                    _ = try? ObjC.catching {
                        self?.process.terminate()
                        timedOut.set(true)
                    }
                }
            }
            
            DispatchQueue.global().async {
                self.process.waitUntilExit()
                if self.debugging {
                    NSLog("TERMINATED status=\(self.process.terminationStatus) reason=\(self.process.terminationReason)")
                }
                self.queue.enqueue(.terminated(self.process.terminationStatus,
                                               self.process.terminationReason))
            }

            var returnCode: Int32? = nil
            var terminationReason: Process.TerminationReason? = nil
            var stdoutData = Data()
            var stderrData = Data()

            didLaunch?()

            do {
                while stdoutChannel != nil || stderrChannel != nil || returnCode == nil {
                    if debugging {
                        NSLog("dequeue…")
                    }
                    let event = queue.dequeue()
                    if debugging {
                        NSLog("handle event \(event)")
                    }
                    switch event {
                    case .readOutput(let data):
                        if let data = data {
                            stdoutData.append(data)
                            if let dataToWrite = try handleStdout(data) {
                                write(dataToWrite)
                            }
                        } else {
                            stdoutChannel?.close()
                            stdoutChannel = nil
                        }
                    case .readError(let data):
                        if let data = data {
                            stderrData.append(data)
                            if let dataToWrite = try handleStderr(data) {
                                write(dataToWrite)
                            }
                        } else {
                            stderrChannel?.close()
                            stderrChannel = nil
                        }
                    case let .terminated(code, reason):
                        returnCode = code
                        terminationReason = reason
                        // Defer calling handleTermination until all the command's output has been
                        // handled since that happening out of order is mind bending.
                        stdinChannel?.close()
                        stdinChannel = nil
                    }
                }
            } catch {
                if debugging {
                    NSLog("command threw \(error)")
                }
                stdoutChannel?.close()
                stderrChannel?.close()
                stdinChannel?.close()
                if returnCode == nil {
                    process.terminate()
                }
                self.output = Output(stderr: stderrData,
                                     stdout: stdoutData,
                                     returnCode: returnCode ?? -1,
                                     timedOut: (terminationReason == .uncaughtSignal) && timedOut.value,
                                     userData: userData)

                throw error
            }
            if let code = returnCode, let reason = terminationReason {
                try handleTermination(code, reason)
            }
            if debugging {
                NSLog("[\(command) \(args.joined(separator: " "))] Completed with return code \(returnCode!)")
            }
            self.output = Output(stderr: stderrData,
                                 stdout: stdoutData,
                                 returnCode: returnCode!,
                                 timedOut: (terminationReason == .uncaughtSignal) && timedOut.value,
                                 userData: userData)
            return self.output!
        }

        func write(_ data: Data, completion: (() -> ())? = nil) {
            guard let channel = stdinChannel else {
                return
            }
            data.withUnsafeBytes { pointer in
                channel.write(offset: 0,
                              data: DispatchData(bytes: pointer),
                              queue: serialQueue) { _done, _data, _error in
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
                            if self.debugging {
                                NSLog("stdin> \(String(data: data, encoding: .utf8) ?? "(non-UTF8)")")
                            }
                        }
                    } else if _error != 0 {
                        if self.debugging {
                            NSLog("stdin error: \(_error)")
                        }
                    }
                }
            }
        }

        func closeStdin() {
            if debugging {
                NSLog("close stdin")
            }
            stdin.fileHandleForWriting.closeFile()
            stdinChannel?.close()
            stdinChannel = nil
        }

        init(command: String,
             args: [String],
             env: [String: String],
             handleStdout: @escaping (Data) throws -> Data?,
             handleStderr: @escaping (Data) throws -> Data?,
             handleTermination: @escaping (Int32, Process.TerminationReason) throws -> ()) {
            self.command = command
            self.args = args
            self.env = env
            self.handleStdout = handleStdout
            self.handleStderr = handleStderr
            self.handleTermination = handleTermination
            let queue = AtomicQueue<Event>()
            self.queue = queue
            process.launchPath = command
            process.arguments = args
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = stdin
            process.environment = env
        }
    }

    class Command: CommandLinePasswordDataSourceExecutableCommand {
        let command: String
        let args: [String]
        let env: [String: String]
        let stdin: Data?
        private(set) var output: Output?

        func exec() throws -> Output {
            let inner = InteractiveCommand(command: command,
                                           args: args,
                                           env: env,
                                           handleStdout: { _ in nil },
                                           handleStderr: { _ in nil },
                                           handleTermination: { _, _ in })
            if let data = stdin {
                inner.didLaunch = {
                    inner.write(data) {
                        inner.closeStdin()
                    }
                }
            }
            defer {
                output = inner.output
            }
            return try inner.exec()
        }

        init(command: String,
             args: [String],
             env: [String: String],
             stdin: Data?) {
            self.command = command
            self.args = args
            self.env = env
            self.stdin = stdin
        }
    }

    struct CommandRecipe<Inputs, Outputs>: Recipe {
        private let inputTransformer: (Inputs) throws -> (CommandLinePasswordDataSourceExecutableCommand)
        private let recovery: (Error) throws -> Void
        private let outputTransformer: (Output) throws -> Outputs

        func transform(inputs: Inputs) throws -> Outputs {
            let command = try inputTransformer(inputs)
            while true {
                let output = try command.exec()
                do {
                    return try outputTransformer(output)
                } catch {
                    try recovery(error)
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

        func transform(inputs: Inputs) throws -> Outputs {
            let intermediateValue = try firstRecipe.transform(inputs: inputs)
            let value = try secondRecipe.transform(inputs: intermediateValue)
            return value
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

        func transform(inputs: Inputs) throws -> Outputs {
            let intermediate = try firstRecipe.transform(inputs: inputs)
            return try secondRecipe.transform(inputs: (inputs, intermediate))
        }
    }

    struct CatchRecipe<Inner: Recipe>: Recipe {
        typealias Inputs = Inner.Inputs
        typealias Outputs = Inner.Outputs
        let inner: Inner
        let errorHandler: (Error) -> ()
        init(_ recipe: Inner, errorHandler: @escaping (Error) -> ()) {
            inner = recipe
            self.errorHandler = errorHandler
        }
        func transform(inputs: Inputs) throws -> Outputs {
            do {
                return try inner.transform(inputs: inputs)
            } catch {
                errorHandler(error)
                throw error
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

        func transform(inputs: Inputs) throws -> Outputs {
            if let value = cacheEntry, value.age < maxAge {
                return value.outputs
            }
            let result = try inner.transform(inputs: inputs)
            cacheEntry = Entry(result)
            return result
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
    }
    struct AnyRecipe<Inputs, Outputs>: Recipe, InvalidatableRecipe {
        private let closure: (Inputs) throws -> Outputs
        private let invalidate: () -> ()
        func transform(inputs: Inputs) throws -> Outputs {
            return try closure(inputs)
        }
        init<T: Recipe>(_ recipe: T) where T.Inputs == Inputs, T.Outputs == Outputs {
            closure = { try recipe.transform(inputs: $0) }
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

    func standardAccounts(_ configuration: Configuration) -> [PasswordManagerAccount] {
        do {
            return try configuration.listAccountsRecipe.transform(inputs: ()).compactMap { account in
                CommandLineProvidedAccount(identifier: account.identifier.value,
                                           accountName: account.accountName,
                                           userName: account.userName,
                                           configuration: configuration)
            }
        } catch {
            DLog("\(error)")
            return []
        }
    }

    func standardAdd(_ configuration: Configuration, userName: String, accountName: String, password: String) throws -> PasswordManagerAccount {
        let accountIdentifier = try configuration.addAccountRecipe.transform(
            inputs: AddRequest(userName: userName,
                               accountName: accountName,
                               password: password))
        configuration.listAccountsRecipe.invalidateRecipe()
        return CommandLineProvidedAccount(identifier: accountIdentifier.value,
                                          accountName: accountName,
                                          userName: userName,
                                          configuration: configuration)
    }
}
