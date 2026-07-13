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
    let context = IT2Context.standalone
    do {
        let command = try IT2.parseAsRoot()
        try runParsedCommand(command, context)
    } catch let exit as IT2Exit {
        Foundation.exit(exit.code)
    } catch let error as IT2Error {
        context.err(error.displayMessage)
        Foundation.exit(error.exitCode)
    } catch {
        IT2.exit(withError: error)
    }
}

/// Run an already-parsed command with the given context: prefer the
/// explicit-context path (`IT2Runnable`) and fall back to `ParsableCommand.run()`
/// for commands not yet migrated. Used by the top-level driver and by commands
/// that delegate to another command (shortcuts, `alias`).
func runParsedCommand(_ command: ParsableCommand, _ context: IT2Context) throws {
    if var runnable = command as? IT2Runnable {
        try runnable.run(context)
    } else {
        var mutable = command
        try mutable.run()
    }
}
