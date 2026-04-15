import ArgumentParser
import Foundation
import ProtobufRuntime

// Top-level shortcuts that mirror the Python it2's convenience commands.

struct SendShortcut: ParsableCommand {
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

    func run() throws {
        var args = [text]
        if let s = session { args += ["-s", s] }
        if all { args += ["-a"] }
        let cmd = try Session.Send.parse(args)
        try cmd.run()
    }
}

struct RunShortcut: ParsableCommand {
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

    func run() throws {
        var args = [command]
        if let s = session { args += ["-s", s] }
        if all { args += ["-a"] }
        let cmd = try Session.Run.parse(args)
        try cmd.run()
    }
}

struct SplitShortcut: ParsableCommand {
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

    func run() throws {
        var args: [String] = []
        if vertical { args.append("-v") }
        if let s = session { args += ["-s", s] }
        if let p = profile { args += ["-p", p] }
        let cmd = try Session.Split.parse(args)
        try cmd.run()
    }
}

struct VSplitShortcut: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vsplit",
        abstract: "Shortcut for 'it2 session split --vertical'."
    )

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    @Option(name: .shortAndLong, help: "Profile to use for new pane.")
    var profile: String?

    func run() throws {
        var args = ["-v"]
        if let s = session { args += ["-s", s] }
        if let p = profile { args += ["-p", p] }
        let cmd = try Session.Split.parse(args)
        try cmd.run()
    }
}

struct ClearShortcut: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Shortcut for 'it2 session clear'."
    )

    @Option(name: .shortAndLong, help: "Target session ID (default: active).")
    var session: String?

    func run() throws {
        var args: [String] = []
        if let s = session { args += ["-s", s] }
        let cmd = try Session.Clear.parse(args)
        try cmd.run()
    }
}

struct LsShortcut: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "Shortcut for 'it2 session list'."
    )

    @Flag(name: [.customShort("j"), .long], help: "Output as JSON.")
    var json = false

    func run() throws {
        var args: [String] = []
        if json { args.append("--json") }
        let cmd = try Session.List.parse(args)
        try cmd.run()
    }
}

struct NewShortcut: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "new",
        abstract: "Shortcut for 'it2 window new'."
    )

    @Option(name: .shortAndLong, help: "Profile to use for new window.")
    var profile: String?

    @Option(name: .shortAndLong, help: "Command to run in new window.")
    var command: String?

    func run() throws {
        var args: [String] = []
        if let p = profile { args += ["-p", p] }
        if let c = command { args += ["-c", c] }
        let cmd = try Window.New.parse(args)
        try cmd.run()
    }
}

struct NewTabShortcut: ParsableCommand {
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

    func run() throws {
        var args: [String] = []
        if let p = profile { args += ["-p", p] }
        if let w = window { args += ["-w", w] }
        if let c = command { args += ["-c", c] }
        let cmd = try Tab.New.parse(args)
        try cmd.run()
    }
}

struct SetStatusShortcut: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-status",
        abstract: "Shortcut for 'it2 session set-status'."
    )

    @Option(name: .shortAndLong, help: "Target session ID.")
    var session: String

    @Option(name: .long, help: "Status text (idle, working, or waiting).")
    var status: String?

    @Option(name: .long, help: "Dot indicator color as #rrggbb.")
    var dotColor: String?

    @Option(name: .long, help: "Text color as #rrggbb.")
    var textColor: String?

    @Option(name: .long, help: "Optional detail text shown alongside the status.")
    var detail: String?

    func run() throws {
        var args: [String] = ["-s", session]
        if let st = status { args += ["--status", st] }
        if let dc = dotColor { args += ["--dot-color", dc] }
        if let tc = textColor { args += ["--text-color", tc] }
        if let d = detail { args += ["--detail", d] }
        let cmd = try Session.SetStatus.parse(args)
        try cmd.run()
    }
}
