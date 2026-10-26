import Foundation

// A shim for installs whose hook command still names cc-status. The hook program is now
// `it2 handle-agent-hook`; this execs the it2 beside this executable with that subcommand and
// its own arguments (so `--agent codex` passes through), leaving stdin and the environment
// untouched. Nothing else lives here: every decision the hook makes is in it2core.
//
// cc-status is invoked through a stable symlink in iTerm2's dot dir that points at
// <bundle>/Contents/Resources/utilities/cc-status, and it2 ships right next to it in that same
// directory. Resolving it2 relative to our own realpath is robust against $PATH not containing
// the utilities dir. If the sibling is missing, fall back to a PATH lookup so a hand-installed
// it2 still works.
func main() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let argv0 = CommandLine.arguments.first ?? "cc-status"
    let sibling = URL(fileURLWithPath: argv0).resolvingSymlinksInPath()
        .deletingLastPathComponent()
        .appendingPathComponent("it2")
    let executable: String
    let leading: [String]
    if FileManager.default.isExecutableFile(atPath: sibling.path) {
        executable = sibling.path
        leading = [sibling.path, "handle-agent-hook"]
    } else {
        executable = "/usr/bin/env"
        leading = ["/usr/bin/env", "it2", "handle-agent-hook"]
    }
    let cArguments = (leading + arguments).map { strdup($0) } + [nil]
    execv(executable, cArguments)
    // Only reached when exec failed. A status update is cosmetic and must never fail the hook.
    FileHandle.standardError.write(Data("cc-status: could not run \(executable): \(String(cString: strerror(errno)))\n".utf8))
    return 0
}

exit(main())
