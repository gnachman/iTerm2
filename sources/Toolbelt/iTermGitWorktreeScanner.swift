import Foundation
import Darwin

@objcMembers
final class iTermGitWorktree: NSObject {
    let rootDirectory: String
    let branch: String?
    let head: String
    let isMain: Bool
    let locked: Bool
    let prunable: Bool
    let available: Bool
    var identifier: String { rootDirectory }

    init(rootDirectory: String, branch: String?, head: String, isMain: Bool,
         locked: Bool = false, prunable: Bool = false, available: Bool = true) {
        self.rootDirectory = rootDirectory
        self.branch = branch.map { $0.hasPrefix("refs/heads/") ? String($0.dropFirst(11)) : $0 }
        self.head = head
        self.isMain = isMain
        self.locked = locked
        self.prunable = prunable
        self.available = available
    }
}

@objcMembers
final class iTermGitRepositorySnapshot: NSObject {
    let commonDirectory: String
    let rootDirectory: String
    let worktrees: [iTermGitWorktree]
    var identifier: String { commonDirectory }
    var rootWorktree: iTermGitWorktree? { worktrees.first { $0.rootDirectory == rootDirectory } }

    init(commonDirectory: String, rootDirectory: String, worktrees: [iTermGitWorktree]) {
        self.commonDirectory = commonDirectory
        self.rootDirectory = rootDirectory
        self.worktrees = worktrees
    }
}

protocol iTermGitWorktreeScanning: AnyObject {
    func scan(directory: String, completion: @escaping (iTermGitRepositorySnapshot?, NSError?) -> Void)
}

struct iTermGitWorktreeCommandResult {
    let output: Data
    let status: Int32
    let timedOut: Bool
    let truncated: Bool
    init(output: Data, status: Int32, timedOut: Bool = false, truncated: Bool = false) {
        self.output = output
        self.status = status
        self.timedOut = timedOut
        self.truncated = truncated
    }
}

protocol iTermGitWorktreeCommandExecuting: AnyObject {
    func run(arguments: [String], directory: String, timeout: TimeInterval) -> iTermGitWorktreeCommandResult
}

struct iTermGitWorktreeRecord {
    var path: String
    var head = ""
    var branch: String?
    var bare = false
    var locked = false
    var prunable = false
    var isMain = false
}

enum iTermGitWorktreePorcelainParser {
    static func parse(_ data: Data, nulDelimited: Bool) throws -> [iTermGitWorktreeRecord] {
        guard let text = String(data: data, encoding: .utf8) else { throw malformed() }
        let fields = nulDelimited ? text.components(separatedBy: "\0") : legacyFields(text)
        var rows = [iTermGitWorktreeRecord]()
        var record: iTermGitWorktreeRecord?
        func finish() {
            if var value = record {
                value.isMain = rows.isEmpty
                rows.append(value)
            }
            record = nil
        }
        for field in fields {
            if field.isEmpty { finish(); continue }
            if field.hasPrefix("worktree ") {
                // A new record can follow an unterminated block in old Git output.
                finish()
                let raw = String(field.dropFirst(9))
                let path = try nulDelimited ? raw : decodeQuotedPath(raw)
                guard !path.isEmpty else { throw malformed() }
                record = iTermGitWorktreeRecord(path: path)
            } else if field.hasPrefix("HEAD ") {
                record?.head = String(field.dropFirst(5))
            } else if field.hasPrefix("branch ") {
                record?.branch = String(field.dropFirst(7))
            } else if field == "bare" {
                record?.bare = true
            } else if field == "locked" || field.hasPrefix("locked ") {
                record?.locked = true
            } else if field == "prunable" || field.hasPrefix("prunable ") {
                record?.prunable = true
            }
        }
        finish()
        guard !rows.isEmpty, rows.allSatisfy({ $0.bare || !$0.head.isEmpty }) else { throw malformed() }
        return rows
    }

    private static func legacyFields(_ text: String) -> [String] {
        var fields = [String]()
        var pendingPath: String?
        for line in text.components(separatedBy: "\n") {
            if let path = pendingPath {
                // Legacy Git can emit either C-quoted paths or raw multiline
                // paths. HEAD/bare is the first metadata field after the path.
                if line.hasPrefix("HEAD ") || line == "bare" {
                    fields.append(path)
                    fields.append(line)
                    pendingPath = nil
                } else {
                    pendingPath = path + "\n" + line
                }
            } else if line.hasPrefix("worktree ") {
                pendingPath = line
            } else {
                fields.append(line)
            }
        }
        if let pendingPath { fields.append(pendingPath) }
        return fields
    }

    private static func malformed() -> NSError {
        NSError(domain: "iTermGitWorktreeScanner", code: 3,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "GitWorktrees.InvalidOutput",
                    defaultValue: "Git returned invalid worktree information.",
                    comment: "Error tooltip when Git worktree output cannot be parsed")])
    }

    private static func decodeQuotedPath(_ path: String) throws -> String {
        guard path.first == "\"" else { return path }
        guard path.last == "\"", path.utf8.count >= 2 else { throw malformed() }
        let bytes = Array(path.utf8.dropFirst().dropLast())
        var decoded = [UInt8]()
        var index = 0
        let escapes: [UInt8: UInt8] = [97: 7, 98: 8, 116: 9, 110: 10, 118: 11,
                                       102: 12, 114: 13, 92: 92, 34: 34]
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte != 92 { decoded.append(byte); continue }
            guard index < bytes.count else { throw malformed() }
            let escaped = bytes[index]
            if (48...55).contains(escaped) {
                var value = 0
                var count = 0
                while index < bytes.count, count < 3, (48...55).contains(bytes[index]) {
                    value = value * 8 + Int(bytes[index] - 48)
                    index += 1
                    count += 1
                }
                guard value <= 255 else { throw malformed() }
                decoded.append(UInt8(value))
            } else {
                guard let replacement = escapes[escaped] else { throw malformed() }
                decoded.append(replacement)
                index += 1
            }
        }
        guard let result = String(bytes: decoded, encoding: .utf8) else { throw malformed() }
        return result
    }
}

// Weak executor keys bound capability cache lifetime to the native boundary,
// including when more than one scanner instance shares an executor.
private final class iTermGitWorktreeCapabilities {
    private static let registryLock = NSLock()
    private static let registry = NSMapTable<AnyObject, iTermGitWorktreeCapabilities>(
        keyOptions: [.weakMemory, .objectPointerPersonality], valueOptions: .strongMemory)
    private let lock = NSLock()
    private var nul = true

    static func forExecutor(_ executor: iTermGitWorktreeCommandExecuting) -> iTermGitWorktreeCapabilities {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let capabilities = registry.object(forKey: executor) { return capabilities }
        let capabilities = iTermGitWorktreeCapabilities()
        registry.setObject(capabilities, forKey: executor)
        return capabilities
    }

    var supportsNul: Bool {
        lock.lock()
        defer { lock.unlock() }
        return nul
    }

    func rememberUnsupportedNul() {
        lock.lock()
        nul = false
        lock.unlock()
    }
}

final class iTermGitWorktreeScanner: NSObject, iTermGitWorktreeScanning {
    private typealias Completion = (iTermGitRepositorySnapshot?, NSError?) -> Void
    private struct MainCheckout {
        let directory: String
        let available: Bool
    }

    private final class Job {
        let directory: String
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var completions: [Completion]
        var paths: Set<String>
        var common: String?
        var followers = [Job]()
        var finished = false
        var pendingLocations = 0
        var mainCheckout: MainCheckout?
        var pendingSnapshot: iTermGitRepositorySnapshot?
        init(directory: String, completion: @escaping Completion) {
            self.directory = directory
            completions = [completion]
            paths = [directory]
        }
    }

    private let executor: iTermGitWorktreeCommandExecuting
    private let state = DispatchQueue(label: "com.iterm2.git-worktree-scanner.state")
    private let workers: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.iterm2.git-worktree-scanner.workers"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    // Mutable flight state is confined to `state`. Workers never
    // wait for another scan; a joined scan gives its worker slot back immediately.
    private var paths = [String: Job]()
    private var repositories = [String: Job]()
    private let capabilities: iTermGitWorktreeCapabilities

    init(executor: iTermGitWorktreeCommandExecuting) {
        self.executor = executor
        capabilities = .forExecutor(executor)
    }

    func scan(directory: String, completion: @escaping (iTermGitRepositorySnapshot?, NSError?) -> Void) {
        let job = Job(directory: directory, completion: completion)
        state.async {
            if let existing = self.paths[directory] {
                existing.completions.append(completion)
                return
            }
            self.paths[directory] = job
            self.state.asyncAfter(deadline: .now() + max(0, job.deadline - ProcessInfo.processInfo.systemUptime)) { [weak self, weak job] in
                guard let self, let job else { return }
                self.finish(job, snapshot: nil, error: Self.timeoutError())
            }
            self.workers.addOperation { self.perform(job) }
        }
    }

    private func finish(_ job: Job, snapshot: iTermGitRepositorySnapshot?, error: NSError?) {
        guard !job.finished else { return }
        job.finished = true
        job.pendingSnapshot = nil
        for path in job.paths where paths[path] === job { paths.removeValue(forKey: path) }
        if let common = job.common, repositories[common] === job { repositories.removeValue(forKey: common) }
        let completions = job.completions
        job.completions.removeAll()
        let followers = job.followers
        job.followers.removeAll()
        DispatchQueue.main.async { completions.forEach { $0(snapshot, error) } }
        followers.forEach { finish($0, snapshot: snapshot, error: error) }
    }

    private func join(_ job: Job, to owner: Job) {
        owner.followers.append(job)
    }

    // Caller metadata is independent of the shared listing. An owner can finish
    // its worker operation while a joining caller resolves a main checkout; the
    // state queue publishes once those reads settle, without a worker wait.
    private func resolveLocation(_ job: Job, owner: Job, mainCheckout: MainCheckout?, error: NSError? = nil) {
        guard !owner.finished else { return }
        owner.pendingLocations -= 1
        if !job.finished, let mainCheckout { owner.mainCheckout = mainCheckout }
        if let error {
            finish(job, snapshot: nil, error: error)
        }
        publishRepositoryIfReady(owner)
    }

    private func publishRepositoryIfReady(_ owner: Job) {
        guard !owner.finished, owner.pendingLocations == 0, let snapshot = owner.pendingSnapshot else { return }
        var result = snapshot
        if let main = owner.mainCheckout, let first = snapshot.worktrees.first,
           first.isMain, first.rootDirectory == snapshot.commonDirectory {
            let replacement = iTermGitWorktree(rootDirectory: main.directory, branch: first.branch,
                                               head: first.head, isMain: true, locked: first.locked,
                                               prunable: first.prunable, available: main.available)
            result = iTermGitRepositorySnapshot(commonDirectory: snapshot.commonDirectory,
                                                rootDirectory: main.directory,
                                                worktrees: [replacement] + snapshot.worktrees.dropFirst())
        }
        finish(owner, snapshot: result, error: nil)
    }

    private func mainCheckout(directory: String, common: String, gitDirectory: String, job: Job) throws -> MainCheckout? {
        // Administrative-directory callers cannot provide a toplevel even
        // though Git can list their checkouts. Enrichment is optional for them;
        // the authoritative listing still determines the main/root rows.
        guard gitDirectory == common, !Self.contains(common, directory: directory) else { return nil }
        let bare = try command(["rev-parse", "--is-bare-repository"], directory: directory, job: job)
        guard bare.status == 0 else { throw Self.commandError(bare.status) }
        if bare.output == Data("true\n".utf8) { return nil }
        guard bare.output == Data("false\n".utf8) else { throw Self.commandError(bare.status) }
        let root = try gitPath("--show-toplevel", directory: directory, job: job)
        var isDirectory: ObjCBool = false
        let available = FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory) && isDirectory.boolValue
        return MainCheckout(directory: root, available: available)
    }

    private func remaining(_ job: Job) throws -> TimeInterval {
        let time = job.deadline - ProcessInfo.processInfo.systemUptime
        guard time > 0, state.sync(execute: { !job.finished }) else { throw Self.timeoutError() }
        return time
    }

    private func command(_ arguments: [String], directory: String, job: Job) throws -> iTermGitWorktreeCommandResult {
        let result = executor.run(arguments: arguments, directory: directory, timeout: try remaining(job))
        if result.timedOut { throw Self.timeoutError() }
        if result.truncated {
            throw NSError(domain: "iTermGitWorktreeScanner", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: String(localized: "GitWorktrees.OutputTooLarge",
                            defaultValue: "Git returned too much worktree information.",
                            comment: "Error tooltip when Git output exceeds the scanner limit")])
        }
        _ = try remaining(job)
        return result
    }

    private func gitPath(_ option: String, directory: String, job: Job) throws -> String {
        let result = try command(["rev-parse", option], directory: directory, job: job)
        guard result.status == 0, var path = String(data: result.output, encoding: .utf8), path.hasSuffix("\n") else {
            throw Self.commandError(result.status)
        }
        // Each path is queried individually. Only remove Git's single terminating
        // LF: whitespace and even a final newline can belong to the filename.
        path.removeLast()
        guard !path.isEmpty else { throw Self.commandError(result.status) }
        return Self.normalizedPath(path, relativeTo: directory)
    }

    private func perform(_ job: Job) {
        var repositoryOwner: Job?
        var locationResolved = false
        do {
            _ = try remaining(job)
            let directory = Self.normalizedPath(job.directory)
            let shouldContinue = state.sync { () -> Bool in
                guard !job.finished else { return false }
                if let other = paths[directory], other !== job {
                    join(job, to: other)
                    return false
                }
                paths[directory] = job
                job.paths.insert(directory)
                return true
            }
            guard shouldContinue else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw Self.commandError(-1)
            }
            // stderr is deliberately excluded from machine output at the native
            // boundary. Check repository markers instead of treating exit 128 as
            // non-Git (it can also mean unsafe ownership or unreadable metadata).
            guard try Self.hasRepositoryMarker(directory) else {
                state.async { self.finish(job, snapshot: nil, error: nil) }
                return
            }
            let common = try gitPath("--git-common-dir", directory: directory, job: job)
            let owner = state.sync { () -> Job? in
                guard !job.finished else { return nil }
                let owner: Job
                if let other = repositories[common], other !== job {
                    join(job, to: other)
                    owner = other
                } else {
                    repositories[common] = job
                    job.common = common
                    owner = job
                }
                owner.pendingLocations += 1
                return owner
            }
            guard let owner else { return }
            repositoryOwner = owner
            let gitDirectory = try gitPath("--absolute-git-dir", directory: directory, job: job)
            let main = try mainCheckout(directory: directory, common: common, gitDirectory: gitDirectory, job: job)
            state.sync { resolveLocation(job, owner: owner, mainCheckout: main) }
            locationResolved = true
            guard owner === job else { return }
            var nul = capabilities.supportsNul
            var arguments = ["worktree", "list", "--porcelain"]
            if nul { arguments.append("-z") }
            var result = try command(arguments, directory: directory, job: job)
            // Unsupported options exit 129. Real worktree failures are retained;
            // they must not silently downgrade the output contract.
            if nul && result.status == 129 {
                capabilities.rememberUnsupportedNul()
                nul = false
                result = try command(["worktree", "list", "--porcelain"], directory: directory, job: job)
            }
            guard result.status == 0 else { throw Self.commandError(result.status) }
            var records = try iTermGitWorktreePorcelainParser.parse(result.output, nulDelimited: nul)
            for index in records.indices {
                records[index].path = Self.normalizedPath(records[index].path, relativeTo: directory)
            }
            // A main caller's location is merged on the state queue before
            // publication. A linked owner can also recover core.worktree where
            // configured, but its own toplevel must not replace the main row.
            if let first = records.first, !first.bare, first.path == common, gitDirectory != common {
                let config = try command(["config", "--path", "--get", "core.worktree"], directory: common, job: job)
                if config.status == 0, var path = String(data: config.output, encoding: .utf8), path.hasSuffix("\n") {
                    path.removeLast()
                    records[0].path = Self.normalizedPath(path, relativeTo: common)
                }
            }
            let root = records.first?.path ?? common
            // Select the longest matching root so a nested registration never
            // borrows its parent's identity when canonicalizing the current root.
            let matching = records.filter { !($0.bare) && Self.contains($0.path, directory: directory) }
                .max { $0.path.utf8.count < $1.path.utf8.count }
            if let matching, matching.isMain, gitDirectory == common {
                records[0].path = matching.path
            }
            let worktrees = records.filter { !$0.bare }.map { record -> iTermGitWorktree in
                var directoryFlag: ObjCBool = false
                let unresolvedMain = record.isMain && record.path == common
                let available = !unresolvedMain && FileManager.default.fileExists(atPath: record.path, isDirectory: &directoryFlag) && directoryFlag.boolValue
                return iTermGitWorktree(rootDirectory: record.path, branch: record.branch, head: record.head,
                                        isMain: record.isMain, locked: record.locked, prunable: record.prunable,
                                        available: available)
            }.sorted { lhs, rhs in
                if lhs.isMain != rhs.isMain { return lhs.isMain }
                let leftBranch = lhs.branch ?? ""
                let rightBranch = rhs.branch ?? ""
                if leftBranch != rightBranch { return leftBranch < rightBranch }
                return lhs.rootDirectory < rhs.rootDirectory
            }
            _ = try remaining(job)
            let snapshot = iTermGitRepositorySnapshot(commonDirectory: common, rootDirectory: root, worktrees: worktrees)
            state.async {
                guard !job.finished else { return }
                job.pendingSnapshot = snapshot
                self.publishRepositoryIfReady(job)
            }
        } catch {
            let failure = error as NSError
            if let owner = repositoryOwner, !locationResolved {
                state.async { self.resolveLocation(job, owner: owner, mainCheckout: nil, error: failure) }
            } else {
                state.async { self.finish(job, snapshot: nil, error: failure) }
            }
        }
    }

    private static func contains(_ root: String, directory: String) -> Bool {
        directory == root || directory.hasPrefix(root == "/" ? root : root + "/")
    }

    private static func normalizedPath(_ path: String, relativeTo base: String? = nil) -> String {
        let absolute = path.hasPrefix("/") ? path :
            (base ?? FileManager.default.currentDirectoryPath) + "/" + path
        // Foundation rewrites physical /private paths to /var or /tmp aliases.
        // Use the same POSIX identity as the catalog, and resolve the original
        // path before collapsing components so symlink/.. traverses physically.
        if let resolved = absolute.withCString({ Darwin.realpath($0, nil) }) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        // Unavailable registrations retain their absolute spelling. Do not
        // resolve only an existing prefix or let NSURL rewrite /private aliases.
        var components = [Substring]()
        for component in absolute.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
            } else {
                components.append(component)
            }
        }
        return "/" + components.joined(separator: "/")
    }

    private static func hasRepositoryMarker(_ directory: String) throws -> Bool {
        var path = directory
        while true {
            // Listing also reports permissions errors. fileExists alone returns
            // false for unreadable metadata and would incorrectly clear old data.
            let names = try FileManager.default.contentsOfDirectory(atPath: path)
            if names.contains(".git") || (names.contains("HEAD") && names.contains("objects") && names.contains("refs")) {
                return true
            }
            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty { return false }
            path = parent
        }
    }

    private static func timeoutError() -> NSError {
        NSError(domain: "iTermGitWorktreeScanner", code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "GitWorktrees.Timeout",
                    defaultValue: "Git worktree discovery timed out.",
                    comment: "Error tooltip when scanning a Git repository exceeds its deadline")])
    }

    private static func commandError(_ status: Int32) -> NSError {
        NSError(domain: "iTermGitWorktreeScanner", code: 1,
                userInfo: ["GitExitStatus": status, NSLocalizedDescriptionKey: String(localized: "GitWorktrees.ReadFailed",
                    defaultValue: "Git worktree information could not be read.",
                    comment: "Error tooltip when Git repository discovery or a read command fails")])
    }
}
