import ArgumentParser
import Foundation

/// The hook program for Claude Code and Codex CLI. Each hook event arrives as JSON on stdin, and
/// the command turns it into a session status update for the session the agent is running in,
/// addressed from the hook's environment: a tmux pane by $TMUX/$TMUX_PANE, otherwise
/// TERM_SESSION_ID, otherwise (over SSH Integration) the session the call arrived on. Nothing is
/// printed on stdout, and failures never fail the hook.
///
/// Driven by the hook configuration iTerm2 installs into ~/.claude/settings.json, or by a Codex
/// hooks.json that passes `--agent codex`. Runs in-process inside iTerm2 when the hook is on a
/// host reached through SSH integration, which is why every input comes from the context rather
/// than from this process.
struct HandleAgentHook: ParsableCommand, IT2Runnable {
    static let configuration = CommandConfiguration(
        commandName: "handle-agent-hook",
        abstract: "Report an AI coding agent’s hook event as the session status. Reads the hook’s JSON payload from stdin.",
        discussion: """
            Meant to be named as the hook command in the agent’s hook configuration; the Claude \
            Code integration installer does that for you. Codex CLI runs the same hooks and needs \
            --agent codex. See also: it2 session set-status
            """
    )

    @Option(name: .long, help: "Which program’s hooks are calling: claude (the default) or codex.")
    var agent: AgentKind = .claude

    func run(_ ctx: IT2Context) throws {
        // Hooks fire constantly, so they must not let consent prompts pile up (issue 13175).
        // Scoped to this command so scripts running other commands keep the osascript behavior.
        try CookieAuth.$policy.withValue(.agentHook) {
            let backend = It2AgentStatusBackend(parent: ctx)
            defer { backend.finish() }
            try AgentHookHandler.handle(payload: ctx.stdin(),
                                        agent: agent,
                                        environment: ctx.environment,
                                        originSessionID: ctx.originSessionID,
                                        inProcess: ctx.isRemote,
                                        backend: backend,
                                        report: ctx.err)
        }
    }
}
