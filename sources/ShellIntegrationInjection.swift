//
//  ShellIntegrationInjection.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/2/22.
//

import Foundation

@objc class ShellIntegrationInjector: NSObject {
    @objc static let instance = ShellIntegrationInjector()

    enum Exception: Error {
        case unsupportedShell
    }

    @objc func serialize(path: String, env: [String: String]) throws -> String {
        if env.isEmpty {
            return ""
        }
        guard let serializer = ShellIntegrationInjectionFactory().createSerializer(path: path) else {
            throw Exception.unsupportedShell
        }
        return serializer.serialize(env: env)
    }

    @objc func modifyShellEnvironment(shellIntegrationDir: String,
                                      env: [String: String],
                                      argv: [String],
                                      completion: @escaping ([String: String], [String]) -> ()) {
        let injector = ShellIntegrationInjectionFactory().createInjector(
            shellIntegrationDir: shellIntegrationDir,
            path: argv[0])
        guard let injector = injector else {
            completion(env, argv)
            return
        }
        injector.computeModified(env: env, argv: argv, completion: completion)
    }
}

fileprivate class ShellIntegrationInjectionFactory {
    private enum Shell: String {
        case fish = "fish"
        case zsh = "zsh"
        case bash = "bash"

        init?(path: String) {
            let name = path.lastPathComponent.lowercased().removing(prefix: "-")
            guard let shell = Shell(rawValue: String(name)) else {
                return nil
            }
            self = shell
        }
    }

    func createInjector(shellIntegrationDir: String, path: String) -> ShellIntegrationInjecting? {
        switch Shell(path: path) {
        case .none:
            return nil
        case .fish:
            return FishShellIntegrationInjection(shellIntegrationDir: shellIntegrationDir)
        case .bash:
            return BashShellIntegrationInjection(shellIntegrationDir: shellIntegrationDir)
        case .zsh:
            return ZshShellIntegrationInjection(shellIntegrationDir: shellIntegrationDir)
        }
    }

    func createSerializer(path: String) -> ShellIntegrationSerializing? {
        switch Shell(path: path) {
        case .none:
            return nil
        case .fish:
            return FishShellIntegrationSerialization()
        case .bash:
            return BashShellIntegrationSerialization()
        case .zsh:
            return ZshShellIntegrationSerialization()
        }
    }

    // -bash -> bash, /BIN/ZSH -> zsh
    fileprivate func supportedShellName(path: String) -> String? {
        let name = path.lastPathComponent.lowercased().removing(prefix: "-")
        return Shell(rawValue: String(name))?.rawValue
    }
}


fileprivate protocol ShellIntegrationInjecting {
    func computeModified(env: [String: String],
                         argv: [String],
                         completion: @escaping ([String: String], [String]) -> ())
}

fileprivate protocol ShellIntegrationSerializing {
    func serialize(env: [String: String]) -> String
}

fileprivate struct Env {
    static let XDG_DATA_DIRS = "XDG_DATA_DIRS"
    static let HOME = "HOME"
    static let PATH = "PATH"
}

fileprivate class BaseShellIntegrationInjection {
    fileprivate let shellIntegrationDir: String

    init(shellIntegrationDir: String) {
        self.shellIntegrationDir = shellIntegrationDir
    }
}

fileprivate class FishShellIntegrationSerialization: ShellIntegrationSerializing {
    // {a:b, c:d} -> "set -gx 'a' 'b'\nset -gx 'c' 'd'"
    func serialize(env: [String: String]) -> String {
        return env.map { (k, v) in
            "set -gx \(k.asFishStringLiteral) \(v.asFishStringLiteral)"
        }.joined(separator: "\n")
    }
}

fileprivate class FishShellIntegrationInjection: BaseShellIntegrationInjection, ShellIntegrationInjecting {
    fileprivate struct FishEnv {
        static let IT2_FISH_XDG_DATA_DIRS = "IT2_FISH_XDG_DATA_DIRS"
    }
    func computeModified(env: [String: String],
                         argv: [String],
                         completion: @escaping ([String: String], [String]) -> ()) {
        completion(modifiedEnvironment(env, argv: argv), argv)
    }

    private func modifiedEnvironment(_ originalEnv: [String: String],
                                     argv: [String]) -> [String: String] {
        let pathSeparator = ":"
        var env = originalEnv
        env[FishEnv.IT2_FISH_XDG_DATA_DIRS] = shellIntegrationDir
        if let val = env[Env.XDG_DATA_DIRS] {
            var dirs = val.components(separatedBy: pathSeparator)
            dirs.insert(shellIntegrationDir, at: 0)
            env[Env.XDG_DATA_DIRS] = dirs.joined(separator: pathSeparator)
        } else {
            env[Env.XDG_DATA_DIRS] = shellIntegrationDir
        }
        return env
    }
}

fileprivate class ZshShellIntegrationSerialization: ShellIntegrationSerializing {
    func serialize(env: [String : String]) -> String {
        return serialize(env: env, prefix: "builtin export", separator: "=")
    }
    func serialize(env: [String: String],
                   prefix: String,
                   separator: String) -> String {
        return posixSerialize(env: env, prefix: prefix, separator: separator)
    }
}

fileprivate class ZshShellIntegrationInjection: BaseShellIntegrationInjection, ShellIntegrationInjecting {
    fileprivate struct ZshEnv {
        static let ZDOTDIR = "ZDOTDIR"
        static let IT2_ORIG_ZDOTDIR = "IT2_ORIG_ZDOTDIR"
    }

    // Runs the completion block with a modified environment.
    func computeModified(env: [String: String],
                         argv: [String],
                         completion: @escaping ([String: String], [String]) -> ()) {
        let zdotdir = env[ZshEnv.ZDOTDIR]
        if !isNewZshInstall(env: env, zdotdir: zdotdir) {
            finishZSHSetup(env: env, zdotdir: zdotdir, argv: argv, completion: completion)
            return
        }
        // Not a new install
        if zdotdir != nil {
            // Don't prevent zsh-newuser-install from running.
            // zsh-newuser-install never runs as root, but we assume that it does.
            completion(env, argv)
            return
        }
        // Try to get ZDOTDIR from /etc/zshenv, when all startup files are not present
        getZshZDotdirFromGlobalZshenv(env: env, argv0: argv[0]) { [weak self] globalZDotdir in
            guard let self = self else {
                return
            }
            if let globalZDotdir = globalZDotdir {
                if self.isNewZshInstall(env: env, zdotdir: globalZDotdir) {
                    completion(env, argv)
                    return
                }
            } else {
                completion(env, argv)
                return
            }
            self.finishZSHSetup(env: env, zdotdir: globalZDotdir, argv: argv, completion: completion)
        }
    }

    private func finishZSHSetup(env inputEnv: [String: String],
                                zdotdir: String?,
                                argv: [String],
                                completion: ([String: String], [String]) -> ()) {
        var env = inputEnv
        if let zdotdir = zdotdir {
            env[ZshEnv.IT2_ORIG_ZDOTDIR] = zdotdir
        } else {
            env.removeValue(forKey: ZshEnv.IT2_ORIG_ZDOTDIR)
        }
        env[ZshEnv.ZDOTDIR] = shellIntegrationDir.appending(pathComponent: "zsh")
        completion(env, argv)
    }

    private func isNewZshInstall(env: [String: String], zdotdir maybeZDotDir: String?) -> Bool {
        let zdotdir: String
        if let providedDir = maybeZDotDir {
            zdotdir = providedDir
        } else {
            // In this case zsh reads from root. If no dotfiles it'll run zsh-newuser-install,
            // which fails if there are rc files in $HOME
            zdotdir = env[Env.HOME] ?? NSHomeDirectory()
            if zdotdir == "~" {
                return true
            }
        }
        for q in [".zshrc", ".zshenv", ".zprofile", ".zlogin"] {
            if FileManager.default.fileExists(atPath: zdotdir.appending(pathComponent: q)) {
                return false
            }
        }
        return true
    }

    private func getZshZDotdirFromGlobalZshenv(env: [String: String],
                                       argv0: String,
                                       completion: @escaping (String?) -> ()) {
        let exe = FileManager.default.which(argv0, env: env) ?? "zsh"
        iTermSlowOperationGateway.sharedInstance().executeShellCommand(
            exe,
            args: [argv0.lastPathComponent, "--norcs", "--interactive", "-c", "echo -n $ZDOTDIR"],
            dir: "/",
            env: env) { stdout, stderr, status, reason in
                completion(status == 0 ? String(data: stdout, encoding: .utf8) : nil)
            }
    }
}

fileprivate class BashShellIntegrationSerialization: ShellIntegrationSerializing {
    func serialize(env: [String: String]) -> String {
        return posixSerialize(env: env, prefix: "builtin export", separator: "=")
    }
}

fileprivate class BashShellIntegrationInjection: BaseShellIntegrationInjection, ShellIntegrationInjecting {
    private struct BashEnv {
        static let IT2_BASH_INJECT = "IT2_BASH_INJECT"
        static let IT2_BASH_POSIX_ENV = "IT2_BASH_POSIX_ENV"
        static let IT2_BASH_RCFILE = "IT2_BASH_RCFILE"
        static let IT2_BASH_UNEXPORT_HISTFILE = "IT2_BASH_UNEXPORT_HISTFILE"
        static let HISTFILE = "HISTFILE"
        static let ENV = "ENV"
    }

    func computeModified(env envIn: [String: String],
                         argv argvIn: [String],
                         completion: @escaping ([String: String], [String]) -> ()) {
        var env = envIn
        var argv = argvIn
        computeModified(env: &env, argv: &argv)
        completion(env, argv)
    }

    private func computeModified(env: inout [String: String], argv: inout [String]) {
        var inject = Set(["1"])
        var posixEnv = ""
        var rcFile = ""
        var removeArgs = Set<Int>()
        var expectingMultiCharsOpt = true
        var expectingOptionArg = false
        var interactiveOpt = false
        var expectingFileArg = false
        var fileArgSet = false
        var options = ""

        for (i, arg) in argv.enumerated() {
            if expectingFileArg {
                fileArgSet = true
                break
            }
            if expectingOptionArg {
                expectingOptionArg = false
                continue
            }
            if ["-", "--"].contains(arg) {
                expectingFileArg = true
                continue
            }
            if !arg.isEmpty && !arg.dropFirst().hasPrefix("-") && (arg.hasPrefix("-") || arg.hasPrefix("+O")) {
                expectingMultiCharsOpt = false
                options = String(arg.trimmingLeadingCharacters(in: CharacterSet(charactersIn: "-+")))
                if let (lhs, rhs) = options.split(onFirst: "O") {
                    // shopt
                    if rhs.isEmpty {
                        expectingOptionArg = true
                    }
                    options = String(lhs)
                }
                if options.contains("c") {
                    // non-interactive shell. Also skip `bash -ic` interactive mode with
                    // command string.
                    return
                }
                if options.contains("s") {
                    // read from stdin and follow with args
                    break
                }
                if options.contains("i") {
                    interactiveOpt = true
                }
            } else if arg.hasPrefix("--") && expectingMultiCharsOpt {
                if arg == "--posix" {
                    inject.insert("posix")
                    posixEnv = env[BashEnv.ENV, default: ""]
                    removeArgs.remove(i)
                } else if arg == "--norc" {
                    inject.insert("no-rc")
                    removeArgs.insert(i)
                } else if arg == "--noprofile" {
                    inject.insert("no-profile")
                    removeArgs.insert(i)
                } else if ["--rcfile", "--init-file"].contains(arg) && i + 1 < argv.count {
                    expectingOptionArg = true
                    rcFile = argv[i + 1]
                    removeArgs.insert(i)
                    removeArgs.insert(i + 1)
                }
            } else {
                fileArgSet = true
                break
            }
        }
        if fileArgSet && !interactiveOpt {
            // Non-interactive shell.
            return
        }
        env[BashEnv.ENV] = shellIntegrationDir.appending(
            pathComponent: ".iterm2_shell_integration.bash")
        env[BashEnv.IT2_BASH_INJECT] = inject.joined(separator: " ")
        if !posixEnv.isEmpty {
            env[BashEnv.IT2_BASH_POSIX_ENV] = posixEnv
        }
        if !rcFile.isEmpty {
            env[BashEnv.IT2_BASH_RCFILE] = rcFile
        }
        argv.remove(at: IndexSet(removeArgs))
        if env[BashEnv.HISTFILE] == nil && !inject.contains("posix") {
            // In POSIX mode the default history file is ~/.sh_history instead of ~/.bash_history
            env[BashEnv.HISTFILE] = "~/.bash_history".expandingTildeInPath
            env[BashEnv.IT2_BASH_UNEXPORT_HISTFILE] = "1"
        }
        argv.insert("--posix", at: 1)
    }
}


// {a:b, c:d} -> "builtin export 'a'='b'\nbuiltin export 'c'='d'"
fileprivate func posixSerialize(env: [String: String],
                                prefix: String,
                                separator: String) -> String {
    return env.map { (k, v) in
        "\(prefix) \(k.asStringLiteral)\(separator)\(v.asStringLiteral)"
    }.joined(separator: "\n")
}

fileprivate extension String {
    // x -> 'x'
    // x'y'z -> 'x'"'"'y'"'"'z'
    var asStringLiteral: String {
        let parts = components(separatedBy: "'")
        let quoted = parts.map { "'\($0)'" }
        return quoted.joined(separator: #""'""#)
    }

    var asFishStringLiteral: String {
        let escaped = replacingOccurrences(
            of: "\\",
            with: "\\\\").replacingOccurrences(
                of: "'",
                with: "\\'")
        return "'" + escaped + "'"
    }
}

extension FileManager {
    // Only checks system paths.
    func which(_ name: String, env: [String: String]) -> String? {
        if name.contains("/") {
            return name
        }
        var triedPaths = Set<String>()
        let pathComponents = env[Env.PATH]?.components(separatedBy: ":") ?? []
        let paths = pathComponents + [
            "~/.local/bin".expandingTildeInPath,
            "~/bin".expandingTildeInPath]
        if let ans = pathContaining(cmd: name, fromDirs: paths) {
            return ans
        }
        triedPaths.formUnion(Set(paths))
        let systemPaths = Self.systemPaths.filter {
            !triedPaths.contains($0)
        }
        if let ans = pathContaining(cmd: name, fromDirs: systemPaths) {
            return ans
        }
        return nil
    }

    fileprivate func pathContaining(cmd: String, fromDirs dirs: [String]) -> String? {
        if cmd.contains("/") {
            if isExecutableFile(atPath: cmd) {
                return cmd
            }
            return nil
        }
        guard !dirs.isEmpty else {
            return nil
        }
        var seen = Set<String>()
        for dir in dirs {
            guard !seen.contains(dir) else {
                continue
            }
            seen.insert(dir)
            let name = dir.appending(pathComponent: cmd)
            if isExecutableFile(atPath: name) {
                return name
            }
        }
        return nil
    }

    fileprivate static var systemPaths: [String] = {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: "/etc/paths.d") else {
            return []
        }
        var result = [String]()
        var seen = Set<String>()
        let sortedFiles = files.sorted(by: { lhs, rhs in
            return lhs.lastPathComponent < rhs.lastPathComponent
        }) + ["/etc/paths"]
        for file in sortedFiles {
            guard let allLines = try? file.linesInFileContents() else {
                continue
            }
            let lines = allLines.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter {
                !$0.isEmpty && !$0.hasPrefix("#") && !seen.contains($0)
            }
            result.append(contentsOf: lines)
            seen.formUnion(Set(lines))
        }
        return result
    }()

}
