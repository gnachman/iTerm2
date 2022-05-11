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
    private let sshargs: String
    private let vars: [String: String]
    private var payloads: [(path: String, destination: String)] = []
    private let initialDirectory: String?

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
            case .write(let data, let dest):
                return "writing payload to \(dest)"
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

    @objc init(_ sshargs: String,
               vars: [String: String],
               initialDirectory: String?) {
        self.sshargs = sshargs
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
        delegate.conductorWrite(string: pending.command.stringValue + "\n")
    }

    private var currentOperationDescription: String {
        switch state {
        case .ground:
            return "waiting"
        case .executing(let context):
            return context.command.operationDescription
        case .willExecute(let context):
            return "preparing to " + context.command.operationDescription
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

extension RandomAccessCollection {
    var reversedArray: [Element] {
        var rev = [Element]()
        for subel in reversed() {
            rev.append(subel)
        }
        return rev
    }
}

extension Array where Element: RandomAccessCollection, Element.Index == Int, Element.Element: Comparable {
    var lengthOfLongestCommonSuffix: Int {
        let backwards = map { $0.reversedArray }
        return backwards.lengthOfLongestCommonPrefix
    }

    var lengthOfLongestCommonPrefix: Int {
        if isEmpty {
            return 0
        }
        var i = 0
        while true {
            let trying = i + 1
            guard allSatisfy({ $0.count >= trying }) else {
                return i
            }
            let prefix = self.first![0..<trying]
            guard allSatisfy({ $0.starts(with: prefix) }) else {
                return i
            }
            i = trying
        }
    }

    var longestCommonSuffix: [Element.Element] {
        if isEmpty {
            return []
        }
        let length = lengthOfLongestCommonSuffix
        let exemplar = self[0]
        if length == 0 {
            return []
        }
        let subsequence: Element.SubSequence = exemplar[(exemplar.count - length) ..< exemplar.count]
        return Array<Element.Element>(subsequence)
    }

    var longestCommonPrefix: [Element.Element] {
        if isEmpty {
            return []
        }
        let length = lengthOfLongestCommonPrefix
        if length == 0 {
            return []
        }
        let subsequence: Element.SubSequence = self[0][0..<length]
        return Array<Element.Element>(subsequence)
    }
}

extension Array where Element == URL {
    var splitPaths: [[String]] {
        return map { (url: URL) -> [String] in return url.pathComponents }
    }

    var hasCommonPathPrefix: Bool {
        return splitPaths.lengthOfLongestCommonPrefix > 1
    }

    var hasCommonPathSuffix: Bool {
        return splitPaths.lengthOfLongestCommonSuffix > 0
    }
    var commonPathPrefix: String {
        let components = splitPaths.longestCommonPrefix
        return components.reduce(URL(fileURLWithPath: "")) { (partialResult, component) -> URL in
            if component == "/" {
                return partialResult
            }
            return partialResult.appendingPathComponent(component)
        }.path
    }
    var commonPathSuffix: String {
        let components = splitPaths.longestCommonSuffix
        return components.reduce(URL(fileURLWithPath: "")) { (partialResult, component) -> URL in
            if component == "/" {
                return partialResult
            }
            return partialResult.appendingPathComponent(component)
        }.path
    }
}

extension URL {
    enum PathArithmeticException: Error {
        case invalidPrefix
    }
    func pathByRemovingPrefix(_ prefix: String) throws -> String {
        if !path.hasPrefix(prefix) {
            throw PathArithmeticException.invalidPrefix
        }
        return String(path.dropFirst(prefix.count))
    }
}

extension Array where Element: Comparable {
    func endsWith(_ other: [Element]) -> Bool {
        if other.isEmpty {
            return true
        }
        if other.count > count {
            return false
        }
        var i = count - 1
        var j = other.count - 1
        while i >= 0 && j >= 0 {
            if self[i] != other[j] {
                return false
            }
            i -= 1
            j -= 1
        }
        return true
    }
}

struct TarJob: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<TarJob sources=\(sources.map { $0.path }) localBase=\(localBase.path) destinationBase=\(destinationBase.path)>"
    }
    var sources: [URL]
    var localBase: URL
    var destinationBase: URL

    init(local: URL, destination: URL) {
        sources = [local]
        localBase = local.deletingLastPathComponent()
        destinationBase = destination
    }

    init(sources: [URL],
         localBase: URL,
         destinationBase: URL) {
        self.sources = sources
        self.localBase = localBase
        self.destinationBase = destinationBase
    }

    private var sourceParents: [URL] {
        return sources.map { $0.deletingLastPathComponent() }
    }

    private var relativeSourcePaths: [String] {
        let prefixCount = localBase.pathComponents.count
        return sources.splitPaths.map { $0.dropFirst(prefixCount).joined(separator: "/") }
    }

    func canAdd(local: URL, destination destinationParent: URL) -> Bool {
        return adding(local: local, destination: destinationParent) != nil
    }

    mutating func add(local: URL, destination destinationParent: URL) -> Bool {
        if let replacement = adding(local: local, destination: destinationParent) {
            self = replacement
            return true
        }
        return false
    }

    func tarballData() throws -> Data? {
        return try NSData(tgzContainingFiles: relativeSourcePaths,
                          relativeToPath: localBase.path) as Data?
    }

    private func adding(local: URL, destination destinationParent: URL) -> TarJob? {
        let destination = destinationParent.appendingPathComponent(local.lastPathComponent)
        DLog("Want to add \(local.path) at \(destination.path) to \(self)")
        guard sourceParents.hasCommonPathPrefix else {
            DLog("Source parents lack common prefix \(sourceParents)")
            return nil
        }
        let sourcePrefix = (sourceParents + [local.deletingLastPathComponent()]).commonPathPrefix
        DLog("sourcePrefix=\(sourcePrefix)")
        do {
            let destinations = try sources.map { (url: URL) -> URL in
                let suffix: String = try url.pathByRemovingPrefix(localBase.path)
                DLog("Transform source \(url.path) into destination by appending its suffix after the localBase (\(localBase.path)) of \(suffix) to the destinationBase of \(destinationBase.path) giving \(destinationBase.appendingPathComponent(suffix).path)")
                return destinationBase.appendingPathComponent(suffix)
            } + [destination]
            DLog("destinations:")
            DLog("\(destinations)")

            let destinationPrefixCount = destinations.splitPaths.lengthOfLongestCommonPrefix

            let splitDestinations = destinations.map { $0.pathComponents }
            let splitSources = (sources + [local]).map { $0.pathComponents }
            let sourcePrefixCount = sourcePrefix.components(separatedBy: "/").count

            DLog("splitDestinations (amended):")
            DLog("\(splitDestinations)")
            DLog("")
            DLog("splitSources (amended):")
            DLog("\(splitSources)")
            DLog("")
            DLog("sourcePrefixCount (based on amended source parents):")
            DLog("\(sourcePrefixCount)")
            DLog("")

            for (source, dest) in zip(splitSources, splitDestinations) {
                DLog("Check source=\(source), dest=\(dest), preserving source prefix \(sources[0].pathComponents[0..<sourcePrefixCount])")
                let sourceSuffix = Array(source[sourcePrefixCount...])
                if !dest.endsWith(sourceSuffix) {
                    DLog("FAIL - destination \(dest) does not end with source suffix \(sourceSuffix)")
                    return nil
                }
                if dest.count - sourceSuffix.count >= destinationPrefixCount {
                    DLog("FAIL - destination (\(dest)) after stripping source suffix (\(sourceSuffix)), yielding \(dest[0..<(dest.count - sourceSuffix.count)]) is longer than the common destination prefix \(destinations[0].pathComponents[0..<destinationPrefixCount])")
                    return nil
                }
                DLog("OK - destination \(dest) ends with source suffix \(sourceSuffix)")
            }
            let replacement = TarJob(sources: sources + [local],
                                     localBase: URL(fileURLWithPath: sourcePrefix),
                                     destinationBase: URL(fileURLWithPath: splitDestinations[0].dropFirst().dropLast(splitSources[0].count - sourcePrefixCount).joined(separator: "/")))
            DLog("Upon success replacement is \(replacement)")
            return replacement
        } catch {
            DLog("FAIL - exception \(error)")
            return nil
        }
    }
}

@objc
class ConductorPayloadBuilder: NSObject {
    private var tarJobs = [TarJob]()

    @objc
    func add(localPath: URL, destination: URL) {
        for var job in tarJobs {
            if job.add(local: localPath, destination: destination) {
                return
            }
        }
        tarJobs.append(TarJob(local: localPath, destination: destination))
    }

    @objc
    func enumeratePayloads(_ closure: (Data, String) -> ()) {
        for job in tarJobs {
            if let data = try? job.tarballData() {
                closure(data, job.destinationBase.path)
            }
        }
    }
}
