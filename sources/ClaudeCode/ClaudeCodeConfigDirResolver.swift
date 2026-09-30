//
//  ClaudeCodeConfigDirResolver.swift
//  iTerm2
//
//  Decides where the Claude Code installer reads CLAUDE_CONFIG_DIR from, and reads
//  it. Claude Code takes the variable from the shell that launched it, so the
//  right source depends on how the session that triggered the install starts its
//  shell:
//
//  - A login-shell profile: the account's login shell, run the way iTerm2 runs
//    it (login and interactive). One answer, no question.
//  - A custom-shell profile: that shell could export a different value than the
//    login shell (a bash profile reads ~/.profile, zsh never does). Both are
//    offered and the user picks.
//  - A custom-command profile: the command is never run again, whatever it is.
//    The only thing that can tell us what it exported is a program it already
//    started, so the session's running job is offered next to the login shell
//    when that job is the agent itself. Only the agent's environment is
//    authoritative: a shell's exec-time environment predates its rc files, and
//    the kernel hides the environment of platform binaries (/bin/sleep, vim)
//    from other processes altogether, so an arbitrary job would read as
//    "unset" and install into the wrong place.
//  - An ssh or browser profile: local install as before; remote hosts are a
//    later phase.
//
//  Pure apart from the two injected effects, so ModernTests can drive every
//  branch without a shell or a live session.
//

import Foundation

enum ClaudeCodeConfigDirResolver {
    struct RunningJob: Equatable {
        let pid: pid_t
        let name: String
    }

    enum Source: Equatable {
        case loginShell(path: String)
        case profileShell(path: String)
        case runningJob(RunningJob)
    }

    struct Dependencies {
        /// Runs `/usr/bin/env` in the shell at the path, interactive, and as a login
        /// shell when the flag is set. Delivers the command's stdout, or nil when the
        /// shell could not be run to completion.
        let runInteractiveShell: (_ shellPath: String, _ login: Bool, _ completion: @escaping (String?) -> Void) -> Void
        /// The `KEY=VALUE` entries of a live process, or nil when it cannot be read.
        let processEnvironment: (pid_t) -> [String]?
        let homeDirectory: String
        let defaultDirectory: URL
    }

    // MARK: - Which sources a session offers

    /// Jobs whose environment is the one the hook install is for.
    static let agentJobNames: Set<String> = ["claude", "codex"]

    /// The sources worth asking for a session with this profile, most conventional
    /// first. One entry means there is nothing to ask the user.
    static func sources(loginShell: String,
                        profile: [AnyHashable: Any],
                        runningJob: RunningJob?) -> [Source] {
        let login = Source.loginShell(path: loginShell)
        let commandType = profile[KEY_CUSTOM_COMMAND as String] as? String ?? kProfilePreferenceCommandTypeLoginShellValue
        switch commandType {
        case kProfilePreferenceCommandTypeCustomShellValue:
            let path = (profile[KEY_COMMAND_LINE as String] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty || path == loginShell {
                return [login]
            }
            return [login, .profileShell(path: path)]
        case kProfilePreferenceCommandTypeCustomValue:
            if let runningJob, agentJobNames.contains(runningJob.name) {
                return [login, .runningJob(runningJob)]
            }
            return [login]
        default:
            return [login]
        }
    }

    // MARK: - Which directories to offer

    /// A directory one or more sources resolved to. The user is asked about
    /// directories, never about shells: sources that agree are one candidate and
    /// a single candidate needs no question.
    struct Candidate: Equatable {
        let directory: URL
        let sources: [Source]
    }

    /// Groups the resolved directories in source order. A source that failed (nil)
    /// contributes nothing; the caller decides what an empty result means.
    static func candidates(from results: [(source: Source, directory: URL?)]) -> [Candidate] {
        var candidates: [Candidate] = []
        for (source, directory) in results {
            guard let directory else {
                continue
            }
            let path = directory.standardizedFileURL.path
            if let index = candidates.firstIndex(where: { $0.directory.standardizedFileURL.path == path }) {
                candidates[index] = Candidate(directory: candidates[index].directory,
                                              sources: candidates[index].sources + [source])
            } else {
                candidates.append(Candidate(directory: directory, sources: [source]))
            }
        }
        return candidates
    }

    // MARK: - Resolving a chosen source

    /// nil means the lookup failed (the shell did not run, the process is gone) and
    /// the caller must not guess. A source that ran fine but has no
    /// CLAUDE_CONFIG_DIR yields the default directory, which is what Claude Code
    /// itself does.
    static func resolve(_ source: Source,
                        dependencies: Dependencies,
                        completion: @escaping (URL?) -> Void) {
        switch source {
        case .loginShell(let path), .profileShell(let path):
            let login = loginFlagSupported(shellPath: path)
            DLog("Resolving CLAUDE_CONFIG_DIR from shell \(path) login=\(login)")
            dependencies.runInteractiveShell(path, login) { output in
                guard let output else {
                    RLog("Onboarding: CLAUDE_CONFIG_DIR lookup failed (shell \(path) did not run)")
                    completion(nil)
                    return
                }
                completion(directory(fromEnvironmentOutput: output, dependencies: dependencies))
            }
        case .runningJob(let job):
            DLog("Resolving CLAUDE_CONFIG_DIR from the environment of \(job.name) (pid \(job.pid))")
            // Empty is the kernel declining, not an empty environment: every
            // process iTerm2 starts has at least PATH and HOME.
            guard let entries = dependencies.processEnvironment(job.pid), !entries.isEmpty else {
                RLog("Onboarding: CLAUDE_CONFIG_DIR lookup failed (could not read environment of pid \(job.pid))")
                completion(nil)
                return
            }
            completion(directory(fromEnvironmentOutput: environmentOutput(fromEntries: entries),
                                 dependencies: dependencies))
        }
    }

    /// `/usr/bin/env`-shaped text from a process's environment entries, so both
    /// sources go through the one parser.
    static func environmentOutput(fromEntries entries: [String]) -> String {
        return entries.joined(separator: "\n")
    }

    private static func directory(fromEnvironmentOutput output: String,
                                  dependencies: Dependencies) -> URL {
        guard let value = ClaudeCodeOnboarding.parseCLAUDE_CONFIG_DIR(from: output), !value.isEmpty else {
            DLog("CLAUDE_CONFIG_DIR not set; using default")
            return dependencies.defaultDirectory
        }
        let expanded: String
        if value == "~" {
            expanded = dependencies.homeDirectory
        } else if value.hasPrefix("~/") {
            expanded = dependencies.homeDirectory + value.dropFirst()
        } else {
            expanded = value
        }
        DLog("Resolved CLAUDE_CONFIG_DIR to \(expanded)")
        return URL(fileURLWithPath: expanded)
    }

    // MARK: - Login flag

    /// iTerm2 starts a session's shell as a login shell, and a login shell reads
    /// files an interactive-only one does not (~/.profile, ~/.zprofile), so the
    /// lookup runs the shell the same way when the shell accepts -l beside -i.
    /// tcsh takes -l only on its own and xonsh spells it --login; those keep the
    /// interactive-only run.
    static func loginFlagSupported(shellPath: String) -> Bool {
        let name = (shellPath as NSString).lastPathComponent
        return ["bash", "zsh", "sh", "ksh", "dash", "fish"].contains(name)
    }
}
