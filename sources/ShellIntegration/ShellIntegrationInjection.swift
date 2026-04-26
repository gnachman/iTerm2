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
            // Login Shell:           /usr/bin/login -f[q]pl $USER /path/to/ShellLauncher --launch_shell
            // Custom Shell:          /usr/bin/login -f[q]pl $USER /path/to/ShellLauncher --launch_shell SHELL=$SHELL
            // Command via shell:     /usr/bin/login -f[q]pl $USER /path/to/ShellLauncher --launch_shell - -i -c <cmd>
            // Custom Command:        literally anything at all
            //
            // The "Command via shell" form (KEY_RUN_COMMAND_IN_LOGIN_SHELL) deliberately
            // classifies as .command below — argv[5] is "-" (not "SHELL=…") and argv.count > 5
            // so neither match arm fires. That's the intended outcome: we don't try to inject
            // shell integration into a wrapper whose terminal target is a user-typed command,
            // and the .command path's createInjector(path: "/usr/bin/login") returns nil so
            // env/argv are returned unchanged.
            //
            // NOTE: This must be kept in sync with -[ITAddressBookMgr shellLauncherCommandWithCustomShell:]
            // and the wrap branch in -[ITAddressBookMgr bookmarkCommandSwiftyString:forObjectType:].
            let arg1 = argv.get(1, default: "")
            if argv.get(0, default: "") != "/usr/bin/login" {
                self = .command
                return
            }
            if ["-fqp", "-fp"].contains(arg1) && argv.count == 3 {
                // Login shell in home directory
                if let shell = iTermOpenDirectory.userShell() {
                    self = .loginShell(shell)
                    return
                }
                self = .command
                return
            }
            if ["-fqpl", "-fpl"].contains(arg1) &&
                argv.get(3, default: "").lastPathComponent == "ShellLauncher" &&
                argv.get(4, default: "") == "--launch_shell" {
                // Either login shell + custom dir or custom shell
                if argv.get(5, default: "").hasPrefix("SHELL="),
                   let (_, shell) = argv[5].split(onFirst: "=") {
                    // Custom shell
                    self = .customShell(String(shell))
                    return
                } else if argv.count == 5, let shell = iTermOpenDirectory.userShell() {
                    // Login Shell + Custom Dir
                    self = .loginShell(shell)
                    return
                }
            }
            self = .command
        }
    }

    @objc func modifyShellEnvironment(shellIntegrationDir: String,
                                      env: [String: String],
                                      argv: [String],
                                      completion: @escaping ([String: String], [String]) -> ()) {
        DLog("shellIntegrationDir=\(shellIntegrationDir), env=\(env) argv=\(argv)")
        let (env, args) = modifyShellEnvironment(shellIntegrationDir: shellIntegrationDir,
                                                 env: env,
                                                 argv: argv)
        completion(env, args)
    }

    func modifyShellEnvironment(shellIntegrationDir: String,
                                env: [String: String],
                                argv: [String]) -> ([String: String], [String]) {
        DLog("shellIntegrationDir=\(shellIntegrationDir), env=\(env) argv=\(argv)")
        switch ShellLauncherInfo(argv) {
        case .command:
            DLog("Is regular command")
            guard let injector = ShellIntegrationInjectionFactory().createInjector(
                shellIntegrationDir: shellIntegrationDir,
                path: argv[0]) else {
                DLog("Failed to create injector")
                return (env, argv)
            }
            // Keep injector from getting dealloced
            DLog("Using \(injector)")
            let result = injector.computeModified(env: env, argv: argv)
            DLog("Returning \(result)")
            return result
        case .customShell(let shell):
            DLog("Is custom shell - WILL RECURSE")
            let (newEnv, newArgs) = modifyShellEnvironment(
                shellIntegrationDir: shellIntegrationDir,
                env: env,
                argv: [shell])
            return (newEnv, Array(argv + newArgs.dropFirst()))
        case .loginShell(let shell):
            DLog("Is login shell - WILL RECURSE")
            let (newEnv, newArgs) = modifyShellEnvironment(
                shellIntegrationDir: shellIntegrationDir,
                env: env,
                argv: [shell])
            if newArgs.count == 1 {
                return (newEnv, argv)
            }
            // The injector added args (e.g., bash's --posix). These can only ride through to the
            // shell via ShellLauncher's argv[3+]. In the plain `/usr/bin/login -f[q]p $USER` form
            // there's no ShellLauncher to route them through — macOS login(1) without -l doesn't
            // pass trailing args to the shell, it tries to exec them — so skip injection in that
            // case rather than produce a broken command. iTerm's own profiles never emit this
            // shape (see +loginShellCommandForBookmark:forObjectType:); this only fires when a
            // user types the plain form as a custom command.
            guard argv.count >= 5 else {
                DLog("Plain login shell form can't transport extra args; skipping injection")
                return (env, argv)
            }
            // "-" is a placeholder meaning "use $SHELL", followed by extra args (e.g., "--posix")
            return (newEnv, Array(argv + ["-"] + newArgs.dropFirst()))
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
            (local("iterm2_shell_integration.xonsh"),
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
        case bash = "bash"
        case fish = "fish"
        case xonsh = "xonsh"
        case zsh = "zsh"

        init?(path: String) {
            if path == "/bin/bash" {
                // Refuse to work with macOS’s bash. See note in ProfilesGeneralPreferencesViewController.
                return nil
            }
            let name = path.lastPathComponent.lowercased().removing(prefix: "-")
            guard let shell = Shell(rawValue: String(name)) else {
                return nil
            }
            self = shell
        }
    }

    func createInjector(shellIntegrationDir: String, path: String) -> ShellIntegrationInjecting? {
        let login = "login"
        if path == login {
            DLog("Want to create injector for `login`")
            if let shell = iTermOpenDirectory.userShell(), shell != login {
                DLog("User shell is\(shell)")
                return createInjector(shellIntegrationDir: shellIntegrationDir, path: shell)
            }
            return nil
        }
        switch Shell(path: path) {
        case .none:
            DLog("Don't know what shell \(path) is")
            return nil
        case .bash:
            DLog("bash")
            return BashShellIntegrationInjection(shellIntegrationDir: shellIntegrationDir)
        case .fish:
            DLog("fish")
            return FishShellIntegrationInjection(shellIntegrationDir: shellIntegrationDir)
        case .xonsh:
            DLog("xonsh")
            return XonshShellIntegrationInjection(shellIntegrationDir: shellIntegrationDir)
        case .zsh:
            DLog("zsh")
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

fileprivate class XonshShellIntegrationInjection: BaseShellIntegrationInjection, ShellIntegrationInjecting {
    fileprivate struct XonshEnv {
        static let XONSHRC = "XONSHRC"
    }

    func computeModified(env: [String: String],
                         argv: [String]) -> ([String: String], [String]) {
        return (modifiedEnvironment(env, argv: argv), argv)
    }

    private func modifiedEnvironment(_ originalEnv: [String: String],
                                     argv: [String]) -> [String: String] {
        var env = originalEnv
        // XONSHRC is colon-separated list of rc files to load
        let script = "\(shellIntegrationDir)/iterm2_shell_integration.xonsh"
        if let existing = env[XonshEnv.XONSHRC], !existing.isEmpty {
            env[XonshEnv.XONSHRC] = "\(script):\(existing)"
        } else {
            env[XonshEnv.XONSHRC] = script
        }
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
