//
//  iTermSSHConfigIncludeExpander.swift
//  iTerm2SharedARC
//
//  NMSSH's config parser ignores the Include directive, so hosts defined in included files
//  (e.g., Lima's ~/.lima/*/ssh.config) are invisible to SCP. This expands Include lines into a
//  single config text that NMSSH can parse, following OpenSSH's readconf.c where NMSSH can
//  express the result:
//
//  - Only unconditional includes are expanded: at the top of a file or inside a “Host *”
//    block. An Include inside any other Host block or inside a Match block would need
//    host-aware evaluation, so it is skipped rather than risk applying settings to the
//    wrong host.
//  - NMSSH ignores Match conditions, so Match blocks inside included files are dropped.
//  - NMSSH ignores everything before a top-level file's first Host line. Those lines are
//    dropped so an included file's last Host block can't capture them. An included file's
//    leading options are global in OpenSSH, so they go under a synthetic “Host *”.
//  - Host headers from included files are rewritten as “Host <patterns>”, because NMSSH
//    ignores forms like “Host=backup”.
//  - Errors are more lenient than OpenSSH: a bad include is skipped instead of failing the
//    whole config, because before this existed every include was ignored. The total number
//    of included files is capped so overlapping globs can't hang.
//

import Foundation

@objc(iTermSSHConfigIncludeExpander)
final class iTermSSHConfigIncludeExpander: NSObject {
    static let maxDepth = 16

    private let homeDirectory: String
    private let userName: String
    private let uid: uid_t
    // Called only when a %l or %L token is expanded, since the lookup isn't free.
    private let localHostname: () -> String
    private let environment: [String: String]
    private let systemConfigDirectory: String
    private let maxIncludedFiles: Int

    init(homeDirectory: String,
         userName: String,
         uid: uid_t,
         localHostname: @escaping () -> String,
         environment: [String: String],
         systemConfigDirectory: String = "/etc/ssh",
         maxIncludedFiles: Int = 1000) {
        self.homeDirectory = homeDirectory
        self.userName = userName
        self.uid = uid
        self.localHostname = localHostname
        self.environment = environment
        self.systemConfigDirectory = systemConfigDirectory
        self.maxIncludedFiles = maxIncludedFiles
    }

    @objc convenience override init() {
        self.init(homeDirectory: NSHomeDirectory(),
                  userName: NSUserName(),
                  uid: getuid(),
                  localHostname: Self.gethostname,
                  environment: ProcessInfo.processInfo.environment)
    }

    /// Contents of `path` with supported Includes expanded, or nil if `path` itself can't be read.
    @objc(expandedContentsOfFile:isUserConfig:)
    func expandedContents(ofFile path: String, isUserConfig: Bool) -> String? {
        guard let contents = Self.read(path) else {
            return nil
        }
        var output = [String]()
        var budget = maxIncludedFiles
        expand(contents: contents,
               path: path,
               isUserConfig: isUserConfig,
               depth: 0,
               enclosing: .topLevel,
               isIncluded: false,
               stack: [Self.canonical(path)],
               budget: &budget,
               output: &output)
        return output.map { $0 + "\n" }.joined()
    }

    // MARK: - Expansion

    private enum BlockState {
        // No Host line yet. NMSSH ignores lines here.
        case topLevel
        // Inside “Host *”, or the global part of an included file. “Host *” is re-emitted
        // after each included file.
        case hostStar
        case otherHost
        // Inside a Match block. `dropping` means its lines are omitted from the output.
        case match(dropping: Bool)
    }

    private func expand(contents: String,
                        path: String,
                        isUserConfig: Bool,
                        depth: Int,
                        enclosing: BlockState,
                        isIncluded: Bool,
                        stack: [String],
                        budget: inout Int,
                        output: inout [String]) {
        var state = enclosing
        var seenHost = false
        // Set when the “Host *” for an included file's leading options hasn't been written
        // yet. It's written only if there are such options, so a file that starts with a
        // Host line doesn't add an empty block that matches every host.
        var needsStarHeader = false
        if isIncluded, case .topLevel = enclosing {
            // OpenSSH treats options before an included file's first Host line as global,
            // which is what a Host * block in the same place means to NMSSH. (NMSSH itself
            // ignores options before the first Host line, so the top-level files keep that
            // behavior.)
            state = .hostStar
            needsStarHeader = true
        }
        for rawLine in contents.components(separatedBy: "\n") {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
            guard let (keyword, arguments) = tokenize(line: line) ?? Self.malformedLine(line) else {
                // Blank or comment.
                continue
            }
            switch keyword.lowercased() {
            case "host":
                seenHost = true
                needsStarHeader = false
                state = arguments == ["*"] ? .hostStar : .otherHost
                // NMSSH only splits keywords on whitespace, so it would ignore a header like
                // “Host=backup” and attach the options that follow to the previous block in
                // the output. Write included headers in a form NMSSH reads.
                output.append(isIncluded ? (["Host"] + arguments).joined(separator: " ") : line)
            case "match":
                // NMSSH ignores Match conditions. In an included file, or before this file's
                // first Host (where NMSSH would ignore it anyway), drop the whole block so it
                // can't leak into the preceding Host block in the output.
                let dropping = isIncluded || !seenHost
                needsStarHeader = false
                state = .match(dropping: dropping)
                if dropping {
                    DLog("Dropping Match block in \(path): \(line)")
                } else {
                    output.append(line)
                }
            case "include":
                switch state {
                case .topLevel, .hostStar:
                    // If this file's “Host *” hasn't been written yet, nothing global is open
                    // in the output, so the included file starts as if at top level and
                    // writes its own “Host *” only if it has leading options.
                    include(arguments: arguments,
                            from: path,
                            isUserConfig: isUserConfig,
                            depth: depth,
                            enclosing: needsStarHeader ? .topLevel : state,
                            stack: stack,
                            budget: &budget,
                            output: &output)
                case .otherHost, .match:
                    DLog("Skipping conditional Include in \(path): \(line)")
                }
            default:
                switch state {
                case .topLevel, .match(dropping: true):
                    break
                case .hostStar, .otherHost, .match(dropping: false):
                    if needsStarHeader {
                        output.append("Host *")
                        needsStarHeader = false
                    }
                    output.append(line)
                }
            }
        }
    }

    private func include(arguments: [String],
                         from path: String,
                         isUserConfig: Bool,
                         depth: Int,
                         enclosing: BlockState,
                         stack: [String],
                         budget: inout Int,
                         output: inout [String]) {
        guard depth < Self.maxDepth else {
            DLog("Include nested too deeply in \(path); skipping \(arguments)")
            return
        }
        for argument in arguments {
            for includedPath in resolvedPaths(forArgument: argument, isUserConfig: isUserConfig) {
                let canonicalPath = Self.canonical(includedPath)
                if stack.contains(canonicalPath) {
                    DLog("Skipping cyclic Include of \(includedPath) from \(path)")
                    continue
                }
                // Cycle detection only covers the current chain, so files that all include
                // the same glob would otherwise be expanded once per ordering (about e·n!).
                guard budget > 0 else {
                    DLog("Included too many files; skipping \(includedPath) from \(path)")
                    return
                }
                budget -= 1
                guard let contents = Self.read(includedPath) else {
                    DLog("Could not read included file \(includedPath) from \(path)")
                    continue
                }
                expand(contents: contents,
                       path: includedPath,
                       isUserConfig: isUserConfig,
                       depth: depth + 1,
                       enclosing: enclosing,
                       isIncluded: true,
                       stack: stack + [canonicalPath],
                       budget: &budget,
                       output: &output)
                // Lines following the Include (and the next included file's leading lines)
                // belong to the enclosing block again, as OpenSSH restores its state after
                // each file.
                if case .hostStar = enclosing {
                    output.append("Host *")
                }
            }
        }
    }

    // MARK: - Paths

    /// Expands tokens, environment variables, and `~`, anchors relative paths, then globs.
    /// Returns [] for an argument that can't be resolved.
    func resolvedPaths(forArgument argument: String, isUserConfig: Bool) -> [String] {
        guard var path = expandTokens(argument) else {
            DLog("Can't expand Include argument \(argument)")
            return []
        }
        if path.hasPrefix("~") {
            guard isUserConfig else {
                DLog("Ignoring ~ Include path in system config: \(argument)")
                return []
            }
            if path == "~" || path.hasPrefix("~/") {
                path = homeDirectory + path.dropFirst()
            } else {
                DLog("Ignoring Include path with another user’s home: \(argument)")
                return []
            }
        } else if !path.hasPrefix("/") {
            let base = isUserConfig ? homeDirectory + "/.ssh" : systemConfigDirectory
            path = base + "/" + path
        }
        return Self.glob(path)
    }

    /// Single left-to-right pass, so substituted values are never rescanned.
    private func expandTokens(_ argument: String) -> String? {
        var result = ""
        var i = argument.startIndex
        while i < argument.endIndex {
            let c = argument[i]
            let next = argument.index(after: i)
            if c == "$", next < argument.endIndex, argument[next] == "{" {
                guard let close = argument[next...].firstIndex(of: "}") else {
                    return nil
                }
                let name = String(argument[argument.index(after: next)..<close])
                guard let value = environment[name] else {
                    return nil
                }
                result += value
                i = argument.index(after: close)
                continue
            }
            if c == "%" {
                guard next < argument.endIndex else {
                    return nil
                }
                switch argument[next] {
                case "%": result += "%"
                case "d": result += homeDirectory
                case "u": result += userName
                case "i": result += String(uid)
                case "l": result += localHostname()
                case "L": result += localHostname().components(separatedBy: ".").first ?? ""
                default:
                    // Other tokens depend on the destination host, which isn't known here.
                    return nil
                }
                i = argument.index(after: next)
                continue
            }
            result.append(c)
            i = next
        }
        return result
    }

    private static func glob(_ pattern: String) -> [String] {
        var globResult = glob_t()
        defer {
            globfree(&globResult)
        }
        let rc = Darwin.glob(pattern, 0, nil, &globResult)
        guard rc == 0 else {
            if rc != GLOB_NOMATCH {
                DLog("glob failed for \(pattern): \(rc)")
            }
            return []
        }
        return (0..<Int(globResult.gl_pathc)).compactMap { i in
            globResult.gl_pathv[i].map { String(cString: $0) }
        }
    }

    // OpenSSH builds %l from gethostname(), which unlike ProcessInfo.hostName does no DNS.
    private static func gethostname() -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard Darwin.gethostname(&buffer, buffer.count - 1) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }

    // ssh_config has no declared encoding. Latin-1 decodes any bytes, so a stray non-UTF-8
    // byte (say, in a comment) doesn't make the whole file disappear.
    private static func read(_ path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else {
            return nil
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func canonical(_ path: String) -> String {
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Tokenizer

    /// For a non-blank, non-comment line that `tokenize` rejects (an unterminated quote),
    /// returns an empty keyword so the line is copied or dropped like any option line. NMSSH
    /// then sees it exactly as it would have without expansion. An Include line in this state
    /// is never expanded.
    private static func malformedLine(_ line: String) -> (keyword: String, arguments: [String])? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
            return nil
        }
        DLog("Unterminated quote: \(line)")
        return ("", [])
    }

    /// Splits a config line like OpenSSH's argv_split. Returns nil for blank lines, comments,
    /// and lines with an unterminated quote. Empty arguments are dropped.
    func tokenize(line: String) -> (keyword: String, arguments: [String])? {
        let chars = Array(line)
        var i = 0
        func skipWhitespace() {
            while i < chars.count, chars[i] == " " || chars[i] == "\t" {
                i += 1
            }
        }

        skipWhitespace()
        guard i < chars.count, chars[i] != "#" else {
            return nil
        }
        var keyword = ""
        while i < chars.count, chars[i] != " ", chars[i] != "\t", chars[i] != "=" {
            keyword.append(chars[i])
            i += 1
        }
        skipWhitespace()
        if i < chars.count, chars[i] == "=" {
            i += 1
        }

        var arguments = [String]()
        while true {
            skipWhitespace()
            guard i < chars.count, chars[i] != "#" else {
                break
            }
            var argument = ""
            var quote: Character?
            while i < chars.count {
                let c = chars[i]
                if c == "\\", i + 1 < chars.count {
                    let n = chars[i + 1]
                    if n == "\\" || n == "\"" || n == "'" || (quote == nil && n == " ") {
                        argument.append(n)
                        i += 2
                    } else {
                        argument.append(c)
                        i += 1
                    }
                    continue
                }
                if let q = quote {
                    if c == q {
                        quote = nil
                    } else {
                        argument.append(c)
                    }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == " " || c == "\t" {
                    break
                } else {
                    argument.append(c)
                }
                i += 1
            }
            if quote != nil {
                return nil
            }
            if !argument.isEmpty {
                arguments.append(argument)
            }
        }
        return (keyword, arguments)
    }
}
