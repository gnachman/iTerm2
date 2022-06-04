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

    private enum ShellLauncherInfo {
        case customShell(String)
        case loginShell(String)
        case command

        init(_ argv: [String]) {
            guard argv.starts(with: ["/usr/bin/login", "-fpl"]),
                  argv.get(3, default: "").lastPathComponent == "ShellLauncher",
                  argv.get(4, default: "") == "--launch_shell" else {
                self = .command
                return
            }
            guard argv.get(5, default: "").hasPrefix("SHELL="),
                  let (_, shell) = argv[5].split(onFirst: "=") else {
                guard let shell = iTermOpenDirectory.userShell() else {
                    self = .command
                    return
                }
                self = .loginShell(shell)
                return
            }
            self = .customShell(String(shell))
        }
    }

    @objc func modifyShellEnvironment(shellIntegrationDir: String,
                                      env: [String: String],
                                      argv: [String],
                                      completion: @escaping ([String: String], [String]) -> ()) {
        let (env, args) = modifyShellEnvironment(shellIntegrationDir: shellIntegrationDir,
                                                 env: env,
                                                 argv: argv)
        completion(env, args)
    }

    func modifyShellEnvironment(shellIntegrationDir: String,
                                env: [String: String],
                                argv: [String]) -> ([String: String], [String]) {
        switch ShellLauncherInfo(argv) {
        case .command:
            guard let injector = ShellIntegrationInjectionFactory().createInjector(
                shellIntegrationDir: shellIntegrationDir,
                path: argv[0]) else {
                return (env, argv)
            }
            // Keep injector from getting dealloced
            return injector.computeModified(env: env, argv: argv)
        case .customShell(let shell):
            let (newEnv, newArgs) = modifyShellEnvironment(
                shellIntegrationDir: shellIntegrationDir,
                env: env,
                argv: [shell])
            return (newEnv, Array(argv + newArgs.dropFirst()))
        case .loginShell(let shell):
            let (newEnv, newArgs) = modifyShellEnvironment(
                shellIntegrationDir: shellIntegrationDir,
                env: env,
                argv: [shell])
            return (newEnv, Array(argv + newArgs.dropFirst()))
        }
    }

    func modifyRemoteShellEnvironment(shellIntegrationDir: String,
                                      env: [String: String],
                                      shell: String,
                                      argv: [String]) -> ([String: String], [String]) {
        guard let injector = ShellIntegrationInjectionFactory().createInjector(
            shellIntegrationDir: shellIntegrationDir,
            path: shell) else {
            return (env, argv)
        }
        // Keep injector from getting dealloced
        let (modifiedEnv, modifiedArgs) = injector.computeModified(env: env, argv: [shell] + argv)
        // Remove the shell as argv[0] because framer doesn't expect it (framer knows the shell's
        // path)
        return (modifiedEnv, Array(modifiedArgs.dropFirst()))
    }

    func files(destinationBase: URL) -> [URL: URL] {
        let bundle = Bundle(for: PTYSession.self)
        let local = { (name: String) -> URL? in
            guard let path = bundle.path(forResource: name.deletingPathExtension,
                                         ofType: name.pathExtension) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        let tuples = [
            (local("iterm2_shell_integration.bash"),
             destinationBase),
            (local("iterm2_shell_integration.zsh"),
             destinationBase),
            (local("iterm2_shell_integration.fish"),
             destinationBase),
            (local("bash-si-loader"),
             destinationBase),
            (local(".zshenv"),
             destinationBase),
            (local("iterm2-shell-integration-loader.fish"),
             destinationBase.appendingPathComponents(["fish", "vendor_conf.d"]))
        ].filter { $0.0 != nil }
        return Dictionary(uniqueKeysWithValues: tuples as! [(URL, URL)])
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

    // -bash -> bash, /BIN/ZSH -> zsh
    fileprivate func supportedShellName(path: String) -> String? {
        let name = path.lastPathComponent.lowercased().removing(prefix: "-")
        return Shell(rawValue: String(name))?.rawValue
    }
}


fileprivate protocol ShellIntegrationInjecting {
    func computeModified(env: [String: String],
                         argv: [String]) -> ([String: String], [String])
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

fileprivate class FishShellIntegrationInjection: BaseShellIntegrationInjection, ShellIntegrationInjecting {
    fileprivate struct FishEnv {
        static let IT2_FISH_XDG_DATA_DIRS = "IT2_FISH_XDG_DATA_DIRS"
    }
    func computeModified(env: [String: String],
                         argv: [String]) -> ([String: String], [String]) {
        return (modifiedEnvironment(env, argv: argv), argv)
    }

    private func modifiedEnvironment(_ originalEnv: [String: String],
                                     argv: [String]) -> [String: String] {
        var env = originalEnv
        // If there was a preexisting XDG_DATA_DIRS we'd want to set this to shellIntegrationDir:$XDG_DATA_DIRS
        env[Env.XDG_DATA_DIRS] = shellIntegrationDir
        env[FishEnv.IT2_FISH_XDG_DATA_DIRS] = shellIntegrationDir
        return env
    }
}

fileprivate class ZshShellIntegrationInjection: BaseShellIntegrationInjection, ShellIntegrationInjecting {
    fileprivate struct ZshEnv {
        static let ZDOTDIR = "ZDOTDIR"
        static let IT2_ORIG_ZDOTDIR = "IT2_ORIG_ZDOTDIR"
        // Nonempty to load shell integration automatically.
        static let ITERM_INJECT_SHELL_INTEGRATION = "ITERM_INJECT_SHELL_INTEGRATION"
    }

    // Runs the completion block with a modified environment.
    func computeModified(env inputEnv: [String: String],
                         argv: [String]) -> ([String: String], [String]) {
        var env = inputEnv
        let zdotdir = env[ZshEnv.ZDOTDIR]
        if let zdotdir = zdotdir {
            env[ZshEnv.IT2_ORIG_ZDOTDIR] = zdotdir
        } else {
            env.removeValue(forKey: ZshEnv.IT2_ORIG_ZDOTDIR)
        }
        env[ZshEnv.ZDOTDIR] = shellIntegrationDir
        env[ZshEnv.ITERM_INJECT_SHELL_INTEGRATION] = "1"
        return (env, argv)
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
                         argv argvIn: [String]) -> ([String: String], [String]) {
        var env = envIn
        var argv = argvIn
        computeModified(env: &env, argv: &argv)
        return (env, argv)
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
            if i == 0 {
                continue
            }
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
                    // Non-interactive shell. Also skip `bash -ic` interactive mode with
                    // command string.
                    return
                }
                if options.contains("s") {
                    // Read from stdin and follow with args.
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
        env[BashEnv.ENV] = shellIntegrationDir.appending(pathComponent: "bash-si-loader")
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
