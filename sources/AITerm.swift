import Security

protocol AITermControllerDelegate: AnyObject {
    func aitermControllerWillSendRequest(_ sender: AITermController)
    func aitermController(_ sender: AITermController, offerChoices: [String])
    func aitermController(_ sender: AITermController, didFailWithErrorMessage: String)
    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ())
}

fileprivate func openAIModelIsLegacy(model: String) -> Bool {
    return !model.hasPrefix("gpt-")
}

class iTermAIClient {
    let requiredVersion = "1.0"
    private let executionQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-execution")
    private let outputQueue = DispatchQueue(label: "com.googlecode.iterm2.ai-output")
    private let bundleID = "com.googlecode.iterm2.iTermAI"
    static let instance = iTermAIClient()

    var available: Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil {
            return false
        }
        return true
    }

    private let codeSigningRequirementString = "anchor apple generic and certificate leaf[subject.OU] = \"H7V7XYVQ7D\""

    private func certificatePinningCheck(pid: Int32) -> Bool {
        var code: SecCode?
        do {
            let status = SecCodeCopyGuestWithAttributes(
                nil,
                [kSecGuestAttributePid: pid] as CFDictionary,
                SecCSFlags(rawValue: 0),
                &code)
            guard status == errSecSuccess else {
                DLog("SecCodeCopyGuestWithAttributes failed with \(status)")
                return false
            }
        }

        var requirement: SecRequirement? = nil
        do {
            let status = SecRequirementCreateWithString(
                codeSigningRequirementString as CFString,
                [],
                &requirement)

            guard status == errSecSuccess && requirement != nil else {
                DLog("SecRequirementCreateWithString failed \(status)")
                return false
            }
        }

        do {
            let status = SecCodeCheckValidity(code!,
                                              SecCSFlags(rawValue: 0),
                                              requirement!)
            guard status == errSecSuccess else {
                DLog("CheckValidity failed with \(status)")
                return false
            }
        }

        return true
    }

    private func certificatePinningCheck() -> Bool {
        DLog("certificatePinningCheck")
        guard let bundleURL = self.bundleURL else {
            DLog("No bundle URL")
            return false
        }
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(bundleURL as CFURL,
                                                 [],
                                                 &staticCode)
        guard status == errSecSuccess else {
            DLog("SecStaticCodeCreateWithPath failed with \(status)")
            return false
        }
        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(staticCode!, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo)
        guard infoStatus == errSecSuccess else {
            DLog("SecCodeCopySigningInformation failed with \(infoStatus)")
            return false
        }

        var reqRef: SecRequirement? = nil
        let reqErr = SecRequirementCreateWithString(codeSigningRequirementString as CFString, [], &reqRef)

        guard reqErr == errSecSuccess, let requirement = reqRef else {
            DLog("SecRequirementCreateWithString failed \(reqErr)")
            return false
        }
        var verifyErrors: Unmanaged<CFError>? = nil
        let checkValidityErr = SecStaticCodeCheckValidityWithErrors(staticCode!, [], requirement, &verifyErrors)

        guard checkValidityErr == errSecSuccess else {
            DLog("CheckValidity failed with \(checkValidityErr)")
            if let verifyError = verifyErrors?.takeRetainedValue() {
                DLog("Detailed error: \(verifyError.localizedDescription)")
            }
            return false
        }

        return true
    }

    func validateSync() -> String? {
        DLog("validateSync")
        let (status, data) = runSync(arg: "v", stdin: Data(), checkSignature: false)
        return problem(status: status, data: data ?? Data())
    }

    func validate(_ completion: @escaping (String?) -> ()) {
        DLog("validate")
        _ = run(arg: "v", stdin: Data(), checkSignature: false) { status, data in
            let problem = self.problem(status: status, data: data)
            DLog("problem=\(String(describing: problem))")
            DispatchQueue.main.async {
                completion(problem)
            }
        }
    }

    private func problem(status: AIPluginStatus, data: Data) -> String? {
        DLog("status=\(status), data=\(data.stringOrHex)")
        switch status {
        case .canceled:
            return nil
        case .badOutput:
            return "Plugin malfunctioning"
        case .executionError:
            return "Unable to execute plugin"
        case .pluginNotFound:
            return "Plugin not found"
        case .runtimeError:
            return data.stringOrHex
        case .status(let status):
            if status != 0 {
                return "Failed to check plugin version"
            }
            guard let string = String(data: data, encoding: .utf8),
                  let decimal = Decimal(string: string) else {
                return "Plugin produced invalid output"
            }
            if decimal != Decimal(string: iTermAIClient.instance.requiredVersion)! {
                return "Wrong version of plugin installed"
            }
            if iTermAIClient.instance.certificatePinningCheck() {
                return nil
            } else {
                return "The plugin’s code signature is incorrect"
            }
        }
    }

    func version() -> Decimal? {
        DLog("version")
        switch runSync(arg: "v", stdin: Data(), checkSignature: false) {
        case (.status(0), let data):
            if let data, let string = String(data: data, encoding: .utf8) {
                return Decimal(string: string)
            }
            return nil
        default:
            return nil
        }
    }

    func runSync(arg: String, stdin: Data, checkSignature: Bool) -> (AIPluginStatus, Data?) {
        DLog("runSync(\(arg), \(stdin.stringOrHex))")
        var resultStatus: AIPluginStatus?
        var resultData: Data?

        let sema = DispatchSemaphore(value: 0)
        _ = run(arg: arg, stdin: stdin, checkSignature: checkSignature) { status, data in
            resultStatus = status
            resultData = data
            DLog("signal")
            sema.signal()
        }
        sema.wait()

        DLog("return")
        return (resultStatus!, resultData)
    }

    var bundleURL: URL? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    // A Cancellation provides a way to cancel an asynchronous operation. The function to implement
    // cancellation can be provided after creation.
    // It safe to use concurrently.
    // It guarantees that the code to perform cancellation is executed exactly once if canceled.
    class Cancellation {
        private var lock = Mutex()
        private var _impl: (() -> ())?
        private var _canceled = false

        // Set this to a closure that implements cancellation. You can reassign to this as needed.
        // If this was canceled prior to setting impl for the first time, the setter may run the
        // closure synchronously.
        var impl: (() -> ())? {
            set {
                lock.sync {
                    if let f = newValue, _impl == nil, _canceled {
                        // Canceled before the first impl was set so cancel immediately.
                        f()
                    } else {
                        _impl = newValue
                    }
                }
            }
            get {
                lock.sync { _impl }
            }
        }

        // Has cancel() ever been called?
        var canceled: Bool {
            lock.sync { _canceled }
        }

        // Idempotent. Runs the cancellation handler eventually.
        func cancel() {
            lock.sync {
                guard !_canceled else {
                    return
                }
                _canceled = true
                let f = _impl
                _impl = nil
                f?()
            }
        }
    }

    func run(arg: String,
             stdin: Data,
             checkSignature: Bool,
             completion: @escaping (AIPluginStatus, Data) -> ()) -> Cancellation? {
        DLog("run(\(arg), \(stdin.stringOrHex))")
        // Find the application bundle
        guard let bundleURL = self.bundleURL else {
            DLog("no bundle")
            completion(.pluginNotFound, "Application bundle not found.".data(using: .utf8)!)
            return nil
        }

        let cancellation = Cancellation()
        executionQueue.async {
            self.runOnExecutionQueue(bundleURL: bundleURL,
                                     arg: arg,
                                     stdin: stdin,
                                     checkSignature: checkSignature,
                                     cancellation: cancellation,
                                     completion: completion)
        }
        return cancellation
    }

    private func runOnExecutionQueue(bundleURL: URL,
                                     arg: String,
                                     stdin: Data,
                                     checkSignature: Bool,
                                     cancellation: Cancellation,
                                     completion: @escaping (AIPluginStatus, Data) -> ()) {
        dispatchPrecondition(condition: .onQueue(executionQueue))

        // Construct the path to the executable
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/iTermAIPlugin")

        let childStdin = Pipe()
        let childStdout = Pipe()

        // Setup a queue to handle output data to prevent race conditions
        var outputData = Data()  // only use on outputQueue
        let outputQueue = self.outputQueue

        // I wish I could use Swift's Process class, but it doesn't give enough control over when
        // the process is wait()ed on. See the note below about the certificate check.
        let pid = iTermStartProcess(executableURL,
                                    [executableURL.lastPathComponent, arg],
                                    childStdin.fileHandleForReading.fileDescriptor,
                                    childStdout.fileHandleForWriting.fileDescriptor)
        guard pid > 0 else {
            DLog("iTermStartProcess failed")
            // Handle errors: also switch to the output queue to clean up
            outputQueue.async {
                completion(.executionError,
                           "Failed to start the AI plugin".data(using: .utf8)!)
            }
            return
        }

        cancellation.impl = {
            kill(pid, SIGKILL)
        }
        if cancellation.canceled {
            outputQueue.async {
                completion(.canceled, Data())
            }
            return
        }

        try? childStdin.fileHandleForReading.close()
        try? childStdout.fileHandleForWriting.close()

        // The purpose of the following certificate check is to ensure we don't send the
        // very sensistive data in `stdin` to a malicious program.
        //
        // Doing the code signature check by process ID in general suffers from a process ID
        // reuse race. That is impossible here because we don't call waitpid until after
        // the check finishes so the process ID cannot be reused.
        if checkSignature && !iTermAIClient.instance.certificatePinningCheck(pid: pid) {
            DLog("Code signature error")
            outputQueue.async {
                cancellation.cancel()
                completion(.executionError,
                           "The AI plugin’s code signature check failed. Reinstall it and upgrade iTerm2.".data(using: .utf8)!)
            }
            return
        }

        do {
            // First, write. We know that the plugin will drain stdin until EOF so this is safe.
            DLog("write: " + stdin.stringOrHex)
            if #available(macOS 10.15.4, *) {
                try childStdin.fileHandleForWriting.write(contentsOf: stdin)
            } else {
                try ObjCTry {
                    childStdin.fileHandleForWriting.write(stdin)
                }
            }
            DLog("Write finished")

            try? childStdin.fileHandleForWriting.close()

            // Read and append to outputData.
            DLog("Begin reading")
            let sema = DispatchSemaphore(value: 0)
            childStdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    DLog("EOF")
                    sema.signal()
                } else {
                    DLog("read \(data.stringOrHex)")
                    outputQueue.async {
                        outputData.append(data)
                    }
                }
            }

            // Block until reading completes. This avoids a race between waitpid and read.
            sema.wait()

            // At this point we assume waitpid will succeed immediately, so it is no longer cancelable.
            // We can't wait until after waitpid to do this or else a cancellation might kill the
            // wrong process when the PID gets reused.
            cancellation.impl = nil

            // Allow the process ID to be reused.
            var status: Int32 = 0
            while true {
                DLog("Call waitpid")
                let rc = waitpid(pid, &status, 0)
                if rc >= 0 {
                    DLog("rc=\(rc)")
                    break
                }
                if errno != EINTR {
                    DLog("error \(errno) from waitpid")
                    throw NSError(domain: "com.googlecode.iterm2.ai-plugin", code: Int(errno))
                }
            }
            DLog("terminated with \(iTermProcessExitStatus(status))")

            // Finished.
            outputQueue.async {
                // Call completion handler
                completion(.status(Int(iTermProcessExitStatus(status))), outputData)
            }
        } catch {
            DLog("Error \(error)")
            // Handle errors: also switch to the output queue to clean up
            outputQueue.async {
                cancellation.cancel()
                completion(.executionError,
                           "Failed to start the process: \(error.localizedDescription)".data(using: .utf8)!)
            }
        }
    }

    func runiTermAIPlugin(withData data: Data,
                          completion: @escaping (AIPluginStatus, Data?) -> Void) -> Cancellation? {
        DLog("runiTermAIPlugin data=\(data.stringOrHex)")
        return run(arg: "request", stdin: data, checkSignature: true) { status, outputData in
            DispatchQueue.main.async {
                switch status {
                case .status(let terminationStatus):
                    let decoder = JSONDecoder()
                    do {
                        let response = try decoder.decode(WebResponse.self, from: outputData)
                        if let error = response.error {
                            DLog("response has error \(error)")
                            completion(.runtimeError, error.data(using: .utf8))
                        } else {
                            DLog("response is ok")
                            completion(status, response.data)
                        }
                    } catch {
                        if terminationStatus == 0 {
                            DLog("can't parse response but status is 0. \(outputData.stringOrHex)")
                            completion(.badOutput, outputData)
                        } else {
                            DLog("status=\(status) \(outputData.stringOrHex)")
                            completion(status, outputData)
                        }
                    }
                case .badOutput, .executionError, .pluginNotFound, .runtimeError, .canceled:
                    DLog("fail \(status)")
                    completion(status, outputData)
                }
            }
        }
    }
}

@objc
class iTermAITermGatekeeper: NSObject {
    @objc
    static func validatePlugin(_ completion: @escaping (String?) -> ()) {
        DLog("validatePlugin")
        iTermAIClient.instance.validate(completion)
    }

    @objc
    static func check() -> Bool {
        DLog("check")
        if !iTermAdvancedSettingsModel.generativeAIAllowed() {
            iTermWarning.show(withTitle: "Generative AI features have been disabled. Check with your system administrator.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Feature Unavailable",
                              window: nil)
            return false
        }
        if !SecureUserDefaults.instance.enableAI.value {
            let selection = iTermWarning.show(withTitle: "You must enable AI features in settings before you can use this feature.",
                                              actions: ["Reveal", "Cancel"],
                                              accessory: nil,
                                              identifier: nil,
                                              silenceable: .kiTermWarningTypePersistent,
                                              heading: "Feature Unavailable",
                                              window: nil)
            if selection == .kiTermWarningSelection0 {
                PreferencePanel.sharedInstance().openToPreference(withKey: kPreferenceKeyEnableAI)
            }
            return false
        }
        let version = iTermAIClient.instance.version()
        if let bundleURL = iTermAIClient.instance.bundleURL, let version, version != Decimal(string: iTermAIClient.instance.requiredVersion) {
            iTermWarning.show(withTitle: "The version of the AI plugin at \(bundleURL.path) is incorrect. This version of iTerm2 expects \(iTermAIClient.instance.requiredVersion) but \(version) was found.",
                              actions: ["OK"],
                              accessory: nil,
                              identifier: nil,
                              silenceable: .kiTermWarningTypePersistent,
                              heading: "Feature Unavailable",
                              window: nil)
            return false
        }
        if version == nil {
            let selection = iTermWarning.show(withTitle: "The AI plugin could not be found.",
                                              actions: ["Install", "Cancel"],
                                              accessory: nil,
                                              identifier: nil,
                                              silenceable: .kiTermWarningTypePersistent,
                                              heading: "Feature Unavailable",
                                              window: nil)
            if selection == .kiTermWarningSelection0 {
                NSWorkspace.shared.open(URL(string: "https://iterm2.com/ai-plugin.html")!)
            }
            return false
        }
        if let problem = iTermAIClient.instance.validateSync() {
            let selection = iTermWarning.show(withTitle: "The AI plugin's code signature was incorrect: \(problem). Remove and resinstall it.",
                                              actions: ["Install", "Cancel"],
                                              accessory: nil,
                                              identifier: nil,
                                              silenceable: .kiTermWarningTypePersistent,
                                              heading: "Feature Unavailable",
                                              window: nil)
            if selection == .kiTermWarningSelection0 {
                NSWorkspace.shared.open(URL(string: "https://iterm2.com/ai-plugin.html")!)
            }
            return false
        }
        return true
    }

    @objc
    static var allowed: Bool {
        DLog("allowed")
        return iTermAdvancedSettingsModel.generativeAIAllowed() && SecureUserDefaults.instance.enableAI.value
    }
}

class AITermControllerRegistrationHelper {
    static var instance = AITermControllerRegistrationHelper()
    private static let apiKeyUserDefaultsKey = "NoSyncOpenAIAPIKey"

    var registration: AITermController.Registration? {
        if !iTermAITermGatekeeper.allowed {
            return nil
        }
        let maybeApiKey = UserDefaults.standard.string(forKey: Self.apiKeyUserDefaultsKey)
        return AITermController.Registration(apiKey: maybeApiKey)
    }

    func setKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: Self.apiKeyUserDefaultsKey)
    }

    func requestRegistration(in window: NSWindow, completion: @escaping (AITermController.Registration?) -> ()) {
        if !iTermAITermGatekeeper.check() {
            completion(nil)
            return
        }
        let windowController = AITermRegistrationWindowController.create()
        window.beginSheet(windowController.window!) { [weak self] response in
            windowController.window?.orderOut(nil)
            if response == .OK, let key = windowController.apiKey {
                self?.setKey(key)
            }
            if response == .OK, let registration = AITermController.Registration(apiKey: windowController.apiKey) {
                completion(registration)
            } else {
                completion(nil)
            }
        }
    }
}

@objc
class AITermControllerObjC: NSObject, AITermControllerDelegate, iTermObject {
    private let controller: AITermController
    private let handler: ([String]?, String?) -> ()
    private let ownerWindow: NSWindow
    private let query: String
    private let pleaseWait: PleaseWaitWindow

    // handler([…], nil): Valid response
    // handler(nil, …): Error
    // handler(nil, nil): User canceled
    @objc(initWithQuery:scope:inWindow:completion:)
    init(query: String,
         scope: iTermVariableScope,
         window: NSWindow,
         handler: @escaping ([String]?, String?) -> ()) {
        let pleaseWait = PleaseWaitWindow(owningWindow: window,
                                          message: "Thinking…",
                                          image: NSImage.it_imageNamed("aiterm", for: AITermControllerObjC.self))
        self.pleaseWait = pleaseWait
        var cancel: (() -> ())?
        var shouldCancel = false
        self.handler = { choices, error in
            if !pleaseWait.canceled {
                handler(choices, error)
            } else {
                shouldCancel = true
                cancel?()
            }
        }
        pleaseWait.didCancel = {
            shouldCancel = true
            cancel?()
        }
        self.ownerWindow = window
        self.query = query

        let registration = AITermControllerRegistrationHelper.instance.registration
        controller = AITermController(registration: registration)
        super.init()

        controller.delegate = self

        let template = iTermPreferences.string(forKey: kPreferenceKeyAIPrompt) ?? ""
        let sanitizedPrompt = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let myScope = scope.copy() as! iTermVariableScope
        let frame = iTermVariables(context: [], owner: self)
        myScope.add(frame, toScopeNamed: "ai")
        myScope.setValue(sanitizedPrompt, forVariableNamed: "ai.prompt")
        let swiftyString = iTermSwiftyString(string: template, scope: myScope)
        swiftyString.evaluateSynchronously(false, with: myScope) { maybeResult, maybeError, _ in
            if let prompt = maybeResult {
                Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
                    if !shouldCancel {
                        cancel = { [weak self] in
                            self?.controller.cancel()
                        }
                        self.controller.request(query: prompt)
                    }
                }
            }
        }
    }

    func aitermControllerWillSendRequest(_ sender: AITermController) {
        pleaseWait.run()
    }

    func aitermController(_ sender: AITermController, offerChoices choices: [String]) {
        pleaseWait.stop()
        DispatchQueue.main.async {
            self.handler(choices, nil)
        }
    }

    func aitermController(_ sender: AITermController, didFailWithErrorMessage errorMessage: String) {
        pleaseWait.stop()
        DispatchQueue.main.async {
            self.handler(nil, errorMessage)
        }
    }

    func aitermControllerRequestRegistration(_ sender: AITermController,
                                             completion: @escaping (AITermController.Registration) -> ()) {
        AITermControllerRegistrationHelper.instance.requestRegistration(in: ownerWindow) { [weak self] registration in
            guard let self else {
                return
            }
            if let registration {
                completion(registration)
            } else {
                handler(nil, nil)
            }
        }
    }

    func objectMethodRegistry() -> iTermBuiltInFunctions? {
        return nil
    }

    func objectScope() -> iTermVariableScope? {
        return nil
    }

}

protocol AnyOptional {
    static var wrappedType: Any.Type { get }
}

extension Optional: AnyOptional {
    static var wrappedType: Any.Type {
        return Wrapped.self
    }
}

struct JSONSchema: Codable {
    var type = "object"
    var properties: [String: Property] = [:]
    var required: [String] = []

    struct Property: Codable {
        var type: String  // e.g., "string"
        var description: String?  // Documentation
        var `enum`: [String]?
    }

    init<T>(for instance: T,
            descriptions: [String: String]) {
        let mirror = Mirror(reflecting: instance)

        for child in mirror.children {
            guard let label = child.label else { continue }

            let type = Swift.type(of: child.value)
            let fieldType = JSONSchema.extractFieldType(type)

            var property = Property(type: fieldType)
            property.description = descriptions[label]

            properties[label] = property
            if !(child.value is AnyOptional.Type) {
                required.append(label)
            }
        }
    }

    private static func extractFieldType(_ type: Any.Type) -> String {
        if type == Int.self || type == UInt.self || type == Int8.self || type == UInt8.self ||
            type == Int16.self || type == UInt16.self || type == Int32.self || type == UInt32.self ||
            type == Int64.self || type == UInt64.self || type == Float.self || type == Double.self {
            return "number"
        } else if type == String.self {
            return "string"
        } else if type == Bool.self {
            return "boolean"
        } else if let optionalType = type as? AnyOptional.Type {
            return extractFieldType(optionalType.wrappedType)
        } else {
            return "object"
        }
    }

}

struct ChatGPTFunctionDeclaration: Codable {
    var name: String
    var description: String
    var parameters: JSONSchema
}

fileprivate protocol AnyFunction {
    var typeErasedParameterType: Any.Type { get }
    var decl: ChatGPTFunctionDeclaration { get }
    func invoke(json: Data, llm: AITermController, completion: @escaping (Result<String, Error>) -> ())
}

struct Function<T: Codable>: AnyFunction {
    typealias Impl = (T, AITermController, @escaping (Result<String, Error>) -> ()) -> ()

    var decl: ChatGPTFunctionDeclaration
    var call: Impl
    var parameterType: T.Type

    var typeErasedParameterType: Any.Type { parameterType }
    func invoke(json: Data, llm: AITermController, completion: @escaping (Result<String, Error>) -> ()) {
        do {
            let value = try JSONDecoder().decode(parameterType, from: json)
            call(value, llm, completion)
        } catch {
            completion(.failure(error))
        }
    }
}

enum AIPluginStatus {
    case pluginNotFound
    case executionError
    case status(Int)
    case badOutput
    case runtimeError
    case canceled
}

class AITermController {
    var representedObject: String?
    private(set) fileprivate var functions = [AnyFunction]()
    var truncate: (([Message]) -> ([Message]))?

    struct Registration {
        var apiKey: String

        init?(apiKey: String?) {
            guard let apiKey else {
                return nil
            }
            guard !apiKey.trimmingLeadingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            self.apiKey = apiKey
        }
    }

    enum State: Equatable, CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .ground: return "ground"
            case .initialized(query: let query): return "initialized(\(query))"
            case .initializedMessages(messages: let messages): return "initializedMessages(\(messages.count) messages)"
            case .querySent: return "querySent"
            }
        }
        case ground
        case initialized(query: String)
        case initializedMessages(messages: [Message])
        case querySent(messages: [Message])
    }

    enum Event: CustomDebugStringConvertible {
        var debugDescription: String {
            switch self {
            case .begin: return "begin"
            case .error(reason: let reason): return "error(\(reason))"
            case .apiError(reason: let reason): return "apiError(\(reason))"
            case let .apiResponse(status: status, data: data):
                switch status {
                case .pluginNotFound:
                    return "apiResponse(plugin not found)"
                case .executionError:
                    return "apiResponse(execution error: \(data.stringOrHex))"
                case .status(let status):
                    return "apiResponse(status=\(status): \(data.stringOrHex))"
                case .badOutput:
                    return "apiResponse(badOutput: \((data ?? Data()).stringOrHex))"
                case .runtimeError:
                    return "apiResponse(runtimeError: \((data ?? Data()).stringOrHex))"
                case .canceled:
                    return "apiResponse(canceled)"
                }
            }
        }
        case begin
        case error(reason: String)
        case apiError(reason: String)
        case apiResponse(status: AIPluginStatus, data: Data?)
    }

    private var state: State {
        didSet {
            DLog("\(oldValue) -> \(self)")
        }
    }

    var registration: Registration?
    weak var delegate: AITermControllerDelegate?

    init(registration: Registration?) {
        state = .ground
        self.registration = registration
    }

    func request(query: String) {
        precondition(state == .ground)
        state = .initialized(query: query)
        handle(event: .begin, legacy: false)
    }

    func request(messages: [Message]) {
        precondition(state == .ground)
        state = .initializedMessages(messages: messages)
        handle(event: .begin, legacy: false)
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration, arguments: T.Type, implementation: @escaping Function<T>.Impl) {
        functions.append(Function(decl: decl, call: implementation, parameterType: arguments))
    }

    fileprivate func define(functions: [AnyFunction]) {
        self.functions.append(contentsOf: functions)
    }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
    }

    private func handle(event: Event, legacy: Bool) {
        DLog("handle(\(event)) in state \(state)")
        switch state {
        case .ground:
            DLog("Ignore \(event) in ground state.")
            break

        case .initialized(query: let query):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    makeAPICall(query: query, registration: registration)
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .error(reason: let reason), .apiError(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
            case .apiResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            }

        case .initializedMessages(messages: let messages):
            switch event {
            case .begin:
                guard let registration else {
                    requestRegistration(continuation: state)
                    return
                }
                DispatchQueue.main.async { [self] in
                    makeAPICall(messages: messages, registration: registration)
                }
                delegate?.aitermControllerWillSendRequest(self)
            case .error(reason: let reason), .apiError(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
            case .apiResponse:
                DLog("Unexpected event \(event) in \(state)")
                state = .ground
            }

        case .querySent:
            switch event {
            case .begin:
                fatalError()
            case .apiResponse(status: let status, data: let data):
                DLog("Got event \(event) in \(state)")
                switch status {
                case .pluginNotFound:
                    handle(event: .error(reason: "The iTermAI plugin was not found"), legacy: false)
                case .executionError:
                    handle(event: .error(reason: "There was a problem running the iTermAI plugin: \(data.stringOrHex)"),
                           legacy: false)
                case .runtimeError:
                    if let data {
                        handle(event: .error(reason: data.stringOrHex), legacy: false)
                    } else {
                        handle(event: .error(reason: "Unknown runtime error"), legacy: false)
                    }
                case .status(let status):
                    if status == 0 {
                        parseResponse(data: data ?? Data(), legacy: legacy)
                        return
                    }
                    if let data {
                        handle(event: .error(reason: "Error code \(status) from iTermAI plugin: \(data.stringOrHex)"),
                               legacy: false)
                    } else {
                        handle(event: .error(reason: "Error code \(status) from iTermAI plugin"),
                               legacy: false)
                    }
                case .badOutput:
                    if let data {
                        handle(event: .error(reason: "Invalid output from iTermAI plugin: \(data.stringOrHex)"),
                               legacy: false)
                    } else {
                        handle(event: .error(reason: "Invalid output from iTermAI plugin"),
                               legacy: false)
                    }
                case .canceled:
                    state = .ground
                }
            case .error(reason: let reason):
                DLog("error: \(reason)")
                state = .ground
                delegate?.aitermController(self, didFailWithErrorMessage: "Error: \(reason)")
            case .apiError(reason: let reason):
                DLog("API error: \(reason)")
                state = .ground
                let provider =
                    if usingOpenAI {
                        "OpenAI"
                    } else {
                        modelURL?.host ?? "the API provider"
                    }
                delegate?.aitermController(self, didFailWithErrorMessage: "Error from \(provider): \(reason)")
            }
        }
    }

    func hostIsOpenAIAPI(url: URL?) -> Bool {
        return url?.host == "api.openai.com"
    }

    var usingOpenAI: Bool {
        return hostIsOpenAIAPI(url: modelURL)
    }

    private func requestRegistration(continuation: State) {
        state = .ground
        delegate?.aitermControllerRequestRegistration(self) { [weak self] registration in
            self?.registration = registration
            self?.state = continuation
            self?.handle(event: .begin, legacy: false)
        }
    }

    private var settingsURL: URL {
        var value = iTermPreferences.string(forKey: kPreferenceKeyAITermURL) ?? ""
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value = iTermPreferences.defaultObject(forKey: kPreferenceKeyAITermURL) as! String
        }
        return URL(string: value) ?? URL(string: "about:empty")!
    }

    private func url(forModel model: String) -> URL? {
        let settingsURL = self.settingsURL
        if hostIsOpenAIAPI(url: settingsURL) &&
            !openAIModelIsLegacy(model: model) {
            return URL(string: "https://api.openai.com/v1/chat/completions")
        }
        return settingsURL
    }

    private func maxTokens(model: String,
                           query: String,
                           functions: [ChatGPTFunctionDeclaration]) -> Int {
        let encodedFunctions = {
            if functions.isEmpty {
                return ""
            }
            guard let data = try? JSONEncoder().encode(functions) else {
                return ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }()
        let naiveLimit = Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit)) - OpenAIMetadata.instance.tokens(in: query) - OpenAIMetadata.instance.tokens(in: encodedFunctions)
        if let responseLimit = OpenAIMetadata.instance.maxResponseTokens(modelName: model) {
            return min(responseLimit, naiveLimit)
        }
        return naiveLimit
    }

    private func legacyRequestBody(model: String, messages: [Message]) -> Data {
        struct LegacyBody: Codable {
            var model: String  // "text-davinci-003"
            var prompt: String
            var max_tokens: Int
            var temperature = 0
        }
        let query = messages.compactMap { $0.content }.joined(separator: "\n")
        let body = LegacyBody(model: model,
                              prompt: query,
                              max_tokens: maxTokens(model: model, query: query, functions: []))
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }

    struct Message: Codable, Equatable {
        var role = "user"
        var content: String?

        // For function calling
        var name: String?
        var function_call: FunctionCall?

        struct FunctionCall: Codable, Equatable {
            var name: String
            var arguments: String
        }

        enum CodingKeys: String, CodingKey {
            case role
            case name
            case content
            case function_call
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)

            try container.encode(role, forKey: .role)

            if let name {
                try container.encode(name, forKey: .name)
            }

            try container.encode(content, forKey: .content)

            if let function_call {
                try container.encode(function_call, forKey: .function_call)
            }
        }

        var approximateTokenCount: Int { OpenAIMetadata.instance.tokens(in: (content ?? "")) + 1 }
    }

    struct Body: Codable {
        var model: String  // "text-davinci-003"
        var messages = [Message]()
        var max_tokens: Int
        var temperature = 0
        var functions: [ChatGPTFunctionDeclaration]? = nil
        var function_call: String? = nil  // "none" and "auto" also allowed
    }

    private func modernRequestBody(model: String, messages: [Message]) -> Data {
        // Tokens are about 4 letters each. Allow enough tokens to include both the query and an
        // answer the same length as the query.
        let query = messages.compactMap { $0.content }.joined(separator: "\n")
        let maybeDecls = functions.isEmpty ? nil : functions.map { $0.decl }
        let body = Body(model: model,
                        messages: messages,
                        max_tokens: maxTokens(model: model, query: query, functions: maybeDecls ?? []),
                        functions: maybeDecls,
                        function_call: functions.isEmpty ? nil : "auto")
        DLog("REQUEST:\n\(body)")
        let bodyEncoder = JSONEncoder()
        let bodyData = try! bodyEncoder.encode(body)
        return bodyData
    }

    private func shouldUseLegacyAPI(_ model: String) -> Bool {
        if usingOpenAI {
            return openAIModelIsLegacy(model: model)
        } else {
            return iTermPreferences.bool(forKey: kPreferenceKeyAITermUseLegacyAPI)
        }
    }

    private func requestBody(model: String, messages: [Message]) -> Data {
        if shouldUseLegacyAPI(model) {
            return legacyRequestBody(model: model, messages: messages)
        }
        return modernRequestBody(model: model, messages: messages)
    }

    private func makeAPICall(query: String, registration: Registration) {
        makeAPICall(messages: [Message(role: "user", content: query)], registration: registration)
    }

    private var modelURL: URL? {
        let model = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-3.5-turbo"
        return url(forModel: model)
    }

    private let client = iTermAIClient()
    private var cancellation: iTermAIClient.Cancellation?

    private func makeAPICall(messages: [Message], registration: Registration) {
        let model = iTermPreferences.string(forKey: kPreferenceKeyAIModel) ?? "gpt-3.5-turbo"
        guard let url = url(forModel: model) else {
            handle(event: .error(reason: "Invalid URL"), legacy: false)
            return
        }
        let headers = ["Content-Type": "application/json",
                       "Authorization": "Bearer " + registration.apiKey]
        let request = WebRequest(headers: headers,
                                 method: "POST",
                                 body: requestBody(model: model, messages: messages),
                                 url: url.absoluteString)
        let legacy = shouldUseLegacyAPI(model)
        cancellation = client.runiTermAIPlugin(withData: try! JSONEncoder().encode(request)) { [weak self] status, data in
            DispatchQueue.main.async {
                self?.handle(event: .apiResponse(status: status, data: data),
                             legacy: legacy)
            }
        }
        state = .querySent(messages: messages)
    }

    struct ModernResponse: Codable {
        var id: String
        var object: String
        var created: Int
        var model: String
        var choices: [Choice]
        var usage: Usage

        struct Choice: Codable {
            var index: Int
            var message: Message
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }
    }

    struct ErrorResponse: Codable {
        var error: Error

        struct Error: Codable {
            var message: String
            var type: String?
            var code: String?
        }
    }

    struct LegacyResponse: Codable {
        var id: String
        var object: String
        var created: Int
        var model: String
        var choices: [Choice]
        var usage: Usage

        struct Choice: Codable {
            var text: String
            var index: Int?
            var logprobs: Int?
            var finish_reason: String
        }

        struct Usage: Codable {
            var prompt_tokens: Int
            var completion_tokens: Int?
            var total_tokens: Int
        }
    }

    private func parseResponse(data: Data, legacy: Bool) {
        do {
            let choices = legacy ? try parseLegacyResponse(data: data) : try parseModernResponse(data: data)
            if let choices {
                state = .ground
                delegate?.aitermController(self, offerChoices: choices)
            }
        } catch {
            let decoder = JSONDecoder()
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                handle(event: .apiError(reason: errorResponse.error.message),
                       legacy: legacy)
            } else {
                handle(event: .error(reason: "Failed to decode API response: \(error). Data is: \(data.stringOrHex)"),
                       legacy: legacy)
            }
        }
    }

    private func parseLegacyResponse(data: Data) throws -> [String] {
        let decoder = JSONDecoder()
        let response = try decoder.decode(LegacyResponse.self, from: data)
        let choices = response.choices.map {
            $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return choices
    }

    private func parseModernResponse(data: Data) throws -> [String]? {
        let decoder = JSONDecoder()
        let response =  try decoder.decode(ModernResponse.self, from: data)
        DLog("RESPONSE:\n\(response)")
        let choices = response.choices.compactMap { choice -> String? in
            guard let content = choice.message.content else {
                return nil
            }
            return String(content.trimmingLeadingCharacters(in: .whitespacesAndNewlines))
        }
        if let firstChoice = response.choices.first,
           let functionCall = firstChoice.message.function_call {
            doFunctionCall(firstChoice.message, call: functionCall)
            return nil
        }
        return choices
    }

    private func doFunctionCall(_ message: Message, call functionCall: Message.FunctionCall) {
        switch state {
        case .ground, .initialized, .initializedMessages:
            DLog("Unexpected function call in state \(state)")
            return
        case .querySent(let messages):
            var amended = messages
            amended.append(message)
            if let impl = functions.first(where: { $0.decl.name == functionCall.name }) {
                DLog("Invoke function with arguments \(functionCall.arguments)")
                impl.invoke(json: functionCall.arguments.data(using: .utf8)!, llm: self) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let response):
                        DLog("Response to function call with arguments \(functionCall.arguments): \(response)")
                        amended.append(Message(role: "function",
                                               content: response,
                                               name: functionCall.name))
                        state = .ground
                        if let truncate {
                            amended = truncate(amended)
                        }
                        request(messages: amended)
                        return
                    case .failure(let error):
                        DLog("Trouble invoking a ChatGPT function: \(error.localizedDescription)")
                        handle(event: .apiError(reason: error.localizedDescription),
                               legacy: false)
                        return
                    }
                }
                return
            }
            amended.append(Message(role: "user",
                                   content: "There is no registered function by that name. Try again."))
            request(messages: amended)
        }
    }
}

@objc
class AITermRegistrationWindowController: NSWindowController {
    @IBOutlet var message: NSTextView!
    @IBOutlet var okButton: NSButton!
    @IBOutlet var textField: NSTextField!
    @IBOutlet var titleImageView: NSImageView!
    private(set) var apiKey: String?

    static func create() -> AITermRegistrationWindowController {
        return AITermRegistrationWindowController(windowNibName: NSNib.Name("AITerm"))
    }

    override func awakeFromNib() {
        var temp = message.string
        let urls = ["https://openai.com/join/",
                    "https://platform.openai.com/api-keys",
                    "https://iterm2.com/aiterm"]
        for (i, url) in urls.enumerated() {
            temp = temp.replacingOccurrences(of: "$\(i + 1)", with: url)
        }

        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        let attributes = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: NSColor.textColor,
        ]

        let attributed = NSMutableAttributedString(string: temp, attributes: attributes)
        attributed.makeLinks()
        message.textStorage?.setAttributedString(attributed)
        super.awakeFromNib()
        okButton.isEnabled = !textField.stringValue.isEmpty
        titleImageView.image?.isTemplate = true
        
        DispatchQueue.main.async { [self] in
            self.window?.makeFirstResponder(textField)
        }
    }

    @IBAction func ok(_ sender: Any) {
        apiKey = textField.stringValue
        window?.sheetParent?.endSheet(window!, returnCode: .OK)
    }

    @IBAction func cancel(_ sender: Any) {
        apiKey = nil
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }
}

extension AITermRegistrationWindowController: NSTextViewDelegate {
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        DLog("\(link)")
        return true
    }
}

extension AITermRegistrationWindowController: NSControlTextEditingDelegate {
    func controlTextDidChange(_ obj: Notification) {
        okButton.isEnabled = !textField.stringValue.isEmpty
    }
}

extension NSMutableAttributedString {
    func makeLinks() {
        let baseAttributes: [NSAttributedString.Key : Any] = [
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single,
            NSAttributedString.Key.foregroundColor: NSColor.linkColor,
            NSAttributedString.Key.cursor: NSCursor.pointingHand
        ]
        while let info = firstAnchorInfo() {
            if let url = URL(string: info.href) {
                var attributes = baseAttributes
                attributes[.link] = url
                replace(range: info.range,
                        with: info.anchorText,
                        attributes:attributes)
            }
        }
    }

    private func replace(range: Range<Int>, with replacement: String, attributes: [NSAttributedString.Key: Any]) {
        self.replaceAttributes(in: NSRange(range), withAttributes: attributes)
        self.replaceCharacters(in: NSRange(range), with: replacement)
    }

    private struct AnchorInfo {
        var range: Range<Int>
        var href: String
        var anchorText: String
    }

    private func firstAnchorInfo() -> AnchorInfo? {
        let pattern = #"(<a[^>]+href=\"(.*?)\"[^>]*>)(.*?)(</a>)"#
        guard let regex = try? RegexCache.instance.get(pattern) else {
            return nil
        }
        guard let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: string.count)) else {
            return nil
        }

        let hrefRange = match.range(at: 2)
        let anchorRange = match.range(at: 3)
        return AnchorInfo(range: Range(match.range)!,
                          href: string.substring(nsrange: hrefRange),
                          anchorText: string.substring(nsrange: anchorRange))
    }
}

class AITermRegistrationWindow: NSWindow {
    override var acceptsFirstResponder: Bool {
        true
    }
    override var canBecomeKey: Bool {
        true
    }
    override var canBecomeMain: Bool {
        true
    }
}

struct AIConversation {
    public struct AIError: Error, CustomStringConvertible {
        public internal(set) var message: String

        public init(_ message: String) {
            self.message = message
        }

        public var description: String {
            message
        }

        var localizedDescription: String {
            message
        }
    }

    private class Delegate: AITermControllerDelegate {
        private(set) var busy = false
        var completion: ((Result<String, Error>) -> ())?
        var registrationNeeded: ((@escaping (AITermController.Registration) -> ()) -> ())?

        func aitermControllerWillSendRequest(_ sender: AITermController) {
            busy = true
        }
        
        func aitermController(_ sender: AITermController, offerChoices: [String]) {
            busy = false
            if let choice = offerChoices.first {
                completion?(Result.success(choice))
            } else {
                completion?(Result.failure(AIError("Empty response from OpenAI")))
            }
        }
        
        func aitermController(_ sender: AITermController, didFailWithErrorMessage message: String) {
            busy = false
            completion?(Result.failure(AIError(message)))
        }
        
        func aitermControllerRequestRegistration(_ sender: AITermController,
                                                 completion: @escaping (AITermController.Registration) -> ()) {
            registrationNeeded?(completion)
        }
    }

    var messages: [AITermController.Message]
    private var controller: AITermController
    private var delegate = Delegate()
    private weak var window: NSWindow?
    var maxTokens: Int {
        return Int(iTermPreferences.int(forKey: kPreferenceKeyAITokenLimit) - iTermAdvancedSettingsModel.aiResponseMaxTokens())
    }
    var busy: Bool { delegate.busy }

    init(window: NSWindow,
         messages: [AITermController.Message] = []) {
        self.window = window
        self.messages = messages
        controller = AITermController(registration: AITermControllerRegistrationHelper.instance.registration)
        controller.delegate = delegate
        let maxTokens = self.maxTokens
        controller.truncate = { truncate(messages: $0, maxTokens: maxTokens) }
    }

    func define<T: Codable>(function decl: ChatGPTFunctionDeclaration, 
                            arguments: T.Type,
                            implementation: @escaping Function<T>.Impl) {
        controller.define(function: decl, arguments: arguments, implementation: implementation)
    }

    mutating func add(text: String, role: String = "user") {
        messages.append(AITermController.Message(role: role, content: text))
    }

    mutating func complete(_ completion: @escaping (Result<AIConversation, Error>) -> ()) {
        precondition(!messages.isEmpty)
        precondition(!delegate.busy)
        let prior = messages
        guard let window = self.window else {
            completion(.failure(AIError("No window")))
            return
        }
        let controller = self.controller
        let messages = self.truncatedMessages
        delegate.registrationNeeded = { regCompletion in
            AITermControllerRegistrationHelper.instance.requestRegistration(in: window) { registration in
                if let registration {
                    regCompletion(registration)
                    controller.request(messages: messages)
                }
            }
        }

        delegate.completion = { result in
            switch result {
            case .success(let text):
                let message = AITermController.Message(role: "assistant", content: text)
                let amended = AIConversation(window: window, messages: prior + [message])
                amended.controller.define(functions: controller.functions)
                completion(.success(amended))
            break
            case .failure(let error):
                completion(.failure(error))
            break
            }
        }
        controller.request(messages: truncatedMessages)
    }

    private var truncatedMessages: [AITermController.Message] {
        return truncate(messages: messages, maxTokens: maxTokens)
    }
}

func truncate(messages: [AITermController.Message], maxTokens: Int) -> [AITermController.Message] {
    var tokens = messages.map { $0.approximateTokenCount }.reduce(0, +)

    var messagesToSend = messages
    var j = 0
    for i in 0..<messagesToSend.count {
        defer {
            j += 1
        }
        if tokens < maxTokens {
            break
        }
        if messages[i].role == "system" {
            continue
        }
        if i == messages.count - 1 {
            var (head, tail) = (messagesToSend[j].content ?? "").halved

            while tokens >= maxTokens {
                (head, _) = head.halved
                (_, tail) = tail.halved
                tokens -= messagesToSend[j].approximateTokenCount
                messagesToSend[j].content = head + "…[truncated]…" + tail
                tokens += messagesToSend[j].approximateTokenCount
            }
        } else {
            tokens -= messages[i].approximateTokenCount
            messagesToSend.remove(at: j)
            j -= 1
        }
    }
    return messagesToSend
}

extension String {
    var halved: (String, String) {
        let middleIndex = index(startIndex, offsetBy: count / 2)
        let head = String(prefix(upTo: middleIndex))
        let tail = String(suffix(from: middleIndex))
        return (head, tail)
    }
}
