import ArgumentParser
import Foundation

/// The consent helper `handle-agent-hook` starts when macOS needs the user's permission before it2
/// may send iTerm2 AppleEvents. See AgentHookAuth. Hidden because nothing else should run it.
///
/// RemoteForbiddenCommand: over SSH integration this would run inside iTerm2 and ask for consent
/// on a remote host's behalf, which nothing needs.
struct RequestConsent: ParsableCommand, IT2Runnable, RemoteForbiddenCommand {
    static let configuration = CommandConfiguration(
        commandName: "request-consent",
        abstract: "Ask macOS for permission to send iTerm2 AppleEvents, then exit.",
        shouldDisplay: false
    )

    @Option(help: "Address the iTerm2 with this bundle identifier.")
    var bundleId: String?

    @Option(help: "Address the iTerm2 with this process ID.")
    var pid: Int32?

    func run(_ ctx: IT2Context) throws {
        let target: AgentHookAuth.Target
        if let pid {
            target = .pid(pid)
        } else {
            target = .bundleID(bundleId ?? AgentHookAuth.Target.defaultBundleID)
        }
        AgentHookAuth.requestConsent(target)
    }
}
