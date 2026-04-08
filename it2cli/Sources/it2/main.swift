import Foundation
import ArgumentParser
import ProtobufRuntime

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
            SplitShortcut.self,
            Tab.self,
            VSplitShortcut.self,
            Window.self,
        ]
    )
}

do {
    var command = try IT2.parseAsRoot()
    try command.run()
} catch let error as IT2Error {
    FileHandle.standardError.write(Data("Error: \(error.description)\n".utf8))
    Foundation.exit(error.exitCode)
} catch {
    IT2.exit(withError: error)
}
