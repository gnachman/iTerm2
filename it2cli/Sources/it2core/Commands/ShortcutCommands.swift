import ArgumentParser
import Foundation
#if canImport(ProtobufRuntime)
import ProtobufRuntime  // standalone SwiftPM build; in-app the types come via the bridging header
#endif

/// Render an option as argv elements for a shortcut that re-serializes and re-parses.
///
/// "--name=value" so a value beginning with "-" survives the inner parse, except for an empty
/// value: ArgumentParser reads a bare "--name=" as a missing value, so that one goes as two
/// elements. An empty string can never be mistaken for an option name, so it is unambiguous.
func shortcutOptionArgs(_ name: String, _ value: String) -> [String] {
    return value.isEmpty ? [name, value] : ["\(name)=\(value)"]
}
// Top-level shortcuts that mirror the Python it2's convenience commands.

struct SendShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Shortcut for 'it2 session send'."
    )

    @Argument(help: "Text to send.")
    var text: String

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    @Flag(name: .shortAndLong, help: "Send to all sessions.")
    var all = false

    func run(_ ctx: IT2Context) throws {
        // Options first, then "--", then the positional: the text is arbitrary and one that begins
        // with "-" would otherwise be re-read as an option name by the inner parse.
        var args = [String]()
        if let s = session { args += shortcutOptionArgs("--session", s) }
        if all { args.append("--all") }
        args += ["--", text]
        let cmd = try Session.Send.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct RunShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Shortcut for 'it2 session run'."
    )

    @Argument(help: "Command to run.")
    var command: String

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    @Flag(name: .shortAndLong, help: "Run in all sessions.")
    var all = false

    func run(_ ctx: IT2Context) throws {
        // Options first, then "--", then the positional: the text is arbitrary and one that begins
        // with "-" would otherwise be re-read as an option name by the inner parse.
        var args = [String]()
        if let s = session { args += shortcutOptionArgs("--session", s) }
        if all { args.append("--all") }
        args += ["--", command]
        let cmd = try Session.Run.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct SplitShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "split",
        abstract: "Shortcut for 'it2 session split'."
    )

    @Flag(name: .shortAndLong, help: "Split vertically.")
    var vertical = false

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    @Option(name: .shortAndLong, help: "Profile to use for new pane.")
    var profile: String?

    func run(_ ctx: IT2Context) throws {
        var args: [String] = []
        if vertical { args.append("-v") }
        if let s = session { args += shortcutOptionArgs("--session", s) }
        if let p = profile { args += shortcutOptionArgs("--profile", p) }
        let cmd = try Session.Split.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct VSplitShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "vsplit",
        abstract: "Shortcut for 'it2 session split --vertical'."
    )

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    @Option(name: .shortAndLong, help: "Profile to use for new pane.")
    var profile: String?

    func run(_ ctx: IT2Context) throws {
        var args = ["-v"]
        if let s = session { args += shortcutOptionArgs("--session", s) }
        if let p = profile { args += shortcutOptionArgs("--profile", p) }
        let cmd = try Session.Split.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct ClearShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Shortcut for 'it2 session clear'."
    )

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    func run(_ ctx: IT2Context) throws {
        var args: [String] = []
        if let s = session { args += shortcutOptionArgs("--session", s) }
        let cmd = try Session.Clear.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct LsShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "Shortcut for 'it2 session list'."
    )

    @Flag(name: [.customShort("j"), .long], help: "Output as JSON.")
    var json = false

    func run(_ ctx: IT2Context) throws {
        var args: [String] = []
        if json { args.append("--json") }
        let cmd = try Session.List.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct NewShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Shortcut for 'it2 window new'."
    )

    @Option(name: .shortAndLong, help: "Profile to use for new window.")
    var profile: String?

    @Option(name: .shortAndLong, help: "Command to run in new window.")
    var command: String?

    func run(_ ctx: IT2Context) throws {
        var args: [String] = []
        if let p = profile { args += shortcutOptionArgs("--profile", p) }
        if let c = command { args += shortcutOptionArgs("--command", c) }
        let cmd = try Window.New.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct NewTabShortcut: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "newtab",
        abstract: "Shortcut for 'it2 tab new'."
    )

    @Option(name: .shortAndLong, help: "Profile to use for new tab.")
    var profile: String?

    @Option(name: .shortAndLong, help: "Window ID to create tab in (default: current).")
    var window: String?

    @Option(name: .shortAndLong, help: "Command to run in new tab.")
    var command: String?

    func run(_ ctx: IT2Context) throws {
        var args: [String] = []
        if let p = profile { args += shortcutOptionArgs("--profile", p) }
        if let w = window { args += shortcutOptionArgs("--window", w) }
        if let c = command { args += shortcutOptionArgs("--command", c) }
        let cmd = try Tab.New.parse(args)
        try runParsedCommand(cmd, ctx)
    }
}

struct SetStatusShortcut: ParsableCommand, IT2Runnable, TmuxAddressableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-status",
        abstract: "Shortcut for 'it2 session set-status'."
    )

    // Shared with the subcommand rather than restated, so an option added to
    // one is never missing from the other.
    @OptionGroup var options: SetStatusOptions

    var tmuxOptions: TmuxPaneOptions { return options.tmuxOptions }

    func run(_ ctx: IT2Context) throws {
        var cmd = Session.SetStatus()
        cmd.options = options
        // Still through runParsedCommand: it is the choke point that enforces
        // the remote-credential gate however a command was reached.
        try runParsedCommand(cmd, ctx)
    }
}
