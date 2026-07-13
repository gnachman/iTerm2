import Foundation
import ArgumentParser

// The root command tree. Lives in the library (not the executable's main.swift)
// so it can be driven both by the standalone binary and, in the future, embedded
// in-process inside iTerm2.
struct IT2: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "it2",
        abstract: "iTerm2 CLI - Control iTerm2 from the command line.",
        discussion: """
            A powerful command-line interface for controlling iTerm2 using its API.

            Examples:
              # Send text to current session
              it2 session send "Hello, World!"

              # Run command in all sessions
              it2 session run "ls -la" --all

              # Split current session vertically
              it2 session split --vertical

              # Create new window with specific profile
              it2 window new --profile "Development"
            """,
        version: "1.0.0",
        subcommands: [
            // Alphabetical order to match Python CLI
            AliasCommand.self,
            App.self,
            Auth.self,
            ClearShortcut.self,
            ConfigPath.self,
            ConfigReload.self,
            LoadCommand.self,
            LsShortcut.self,
            Monitor.self,
            NewShortcut.self,
            NewTabShortcut.self,
            Profile.self,
            RunShortcut.self,
            SendShortcut.self,
            Session.self,
            SetStatusShortcut.self,
            SplitShortcut.self,
            Tab.self,
            VSplitShortcut.self,
            Window.self,
        ]
    )
}

/// Entry point for the standalone `it2` binary: parses `CommandLine.arguments`,
/// runs the selected command, and exits the process on error.
///
/// Commands that have adopted the explicit-context model (`IT2Runnable`) are
/// run with the standalone context; the rest fall back to `ParsableCommand.run()`
/// until they are migrated.
public func it2CLIMain() {
    let code = runToExitCode(Array(CommandLine.arguments.dropFirst()), .standalone)
    Foundation.exit(code)
}

/// Parse and run the command tree, mapping its outcome to a process-style exit
/// code and routing all output through the context. Shared by the standalone
/// driver and the in-process embedding so exit codes and messages stay identical.
/// `arguments` excludes the executable name.
func runToExitCode(_ arguments: [String], _ context: IT2Context) -> Int32 {
    // Defense in depth for the embedded/over-SSH path: block the whole `auth` subtree by
    // name before parsing, so even a future `auth` subcommand that forgets to conform to
    // RemoteForbiddenCommand cannot be reached by a direct `it2 auth ...` from the remote.
    // (Delegated paths -- alias / shortcuts -- are covered by the runParsedCommand gate.)
    // Help/usage requests are exempt: they mint nothing, so a remote user should still be able
    // to read what a command does rather than get a security error implying the docs are secret.
    if context.isRemote, !it2IsHelpRequest(arguments),
       let denied = it2TopLevelSubcommand(in: arguments),
       it2RemoteForbiddenCommands.contains(denied) {
        let error = IT2Error.invalidArgument(it2RemoteForbiddenMessage(denied))
        context.err(error.displayMessage)
        return error.exitCode
    }
    do {
        let command = try IT2.parseAsRoot(arguments)
        try runParsedCommand(command, context)
        return 0
    } catch let exit as IT2Exit {
        return exit.code
    } catch let error as IT2Error {
        context.err(error.displayMessage)
        return error.exitCode
    } catch {
        // ArgumentParser outcomes: --help, --version, validation, unknown command.
        let message = IT2.fullMessage(for: error)
        let exitCode = IT2.exitCode(for: error)
        if !message.isEmpty {
            if exitCode == .success {
                context.out(message)
            } else {
                context.err(message)
            }
        }
        return exitCode.rawValue
    }
}

/// Run an already-parsed command with the given context: prefer the
/// explicit-context path (`IT2Runnable`) and fall back to `ParsableCommand.run()`
/// for commands not yet migrated. Used by the top-level driver and by commands
/// that delegate to another command (shortcuts, `alias`).
func runParsedCommand(_ command: ParsableCommand, _ context: IT2Context) throws {
    // The single choke point for running any parsed command, including those reached by
    // delegation (alias, shortcuts). Enforce the remote credential gate here so it holds no
    // matter how the command was reached: a command that mints/exports durable local
    // credentials must never run on behalf of a remote it2 over SSH.
    if context.isRemote, command is RemoteForbiddenCommand {
        // Name the ROOT subcommand the user typed (e.g. "auth"), not the leaf ("cookie"). When
        // reached via an alias resolving to `auth cookie`, the leaf commandName would print
        // "`it2 cookie` ..." -- a command that does not exist at top level. Fall back to the
        // leaf only if the command is somehow not found in the tree.
        let name = it2RootSubcommandName(for: command)
            ?? type(of: command).configuration.commandName ?? "this command"
        throw IT2Error.invalidArgument(it2RemoteForbiddenMessage(name))
    }
    if var runnable = command as? IT2Runnable {
        try runnable.run(context)
    } else {
        var mutable = command
        try mutable.run()
    }
}

/// Marks a command that mints or exports durable LOCAL credentials (e.g. a reusable
/// ITERM2_COOKIE/ITERM2_KEY), or otherwise escapes the per-session, revocable API grant, and
/// so must never run on the embedded / over-SSH path where its output streams to the remote
/// host. Enforced centrally in `runParsedCommand`, so it holds for direct invocation, aliases,
/// and shortcuts alike. Conform every such leaf command.
protocol RemoteForbiddenCommand {}

/// Top-level it2 subcommands blocked wholesale on the embedded/over-SSH path, matched by name
/// before parsing. `auth` mints and prints reusable local API credentials by driving osascript
/// on the Mac; streaming those to a remote hands it an off-device, non-revocable credential
/// that escapes the session-scoped grant. Denying the whole subtree by name means a new `auth`
/// subcommand cannot silently reopen the hole even if it forgets RemoteForbiddenCommand.
let it2RemoteForbiddenCommands: Set<String> = ["auth"]

/// The single user-facing message for a command rejected by either remote gate (by-name or
/// RemoteForbiddenCommand), so the two gates cannot drift in wording. `name` is the command.
func it2RemoteForbiddenMessage(_ name: String) -> String {
    "`it2 \(name)` is not available over SSH integration; run it locally on your Mac."
}

/// The chosen top-level subcommand, if any: the first token that names one of IT2's
/// subcommands. An option value that merely equals a subcommand name appears only after its
/// own subcommand token, so it is never mistaken for the chosen command.
func it2TopLevelSubcommand(in arguments: [String]) -> String? {
    let names = Set(IT2.configuration.subcommands.compactMap { $0.configuration.commandName })
    return arguments.first(where: names.contains)
}

/// Whether `arguments` is a help/usage request (the `help` subcommand or a `--help`/`-h` flag),
/// which mints nothing and so should be exempt from the remote credential gate.
func it2IsHelpRequest(_ arguments: [String]) -> Bool {
    if arguments.first == "help" {
        return true
    }
    return arguments.contains("--help") || arguments.contains("-h")
}

/// The name of the TOP-LEVEL subcommand whose subtree contains `command` (e.g. "auth" for
/// `Auth.Cookie`), by searching IT2's command tree. Used so a forbidden-command message names
/// the real command the user typed rather than a leaf that is not a top-level command.
func it2RootSubcommandName(for command: ParsableCommand) -> String? {
    let target = ObjectIdentifier(type(of: command))
    func subtreeContains(_ root: ParsableCommand.Type) -> Bool {
        if ObjectIdentifier(root) == target {
            return true
        }
        return root.configuration.subcommands.contains(where: subtreeContains)
    }
    return IT2.configuration.subcommands.first(where: subtreeContains)?.configuration.commandName
}
