import ArgumentParser
import Foundation

struct Auth: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auth",
        abstract: "Manage authentication with iTerm2.",
        subcommands: [
            Cookie.self,
        ]
    )
}

extension Auth {
    // RemoteForbiddenCommand: minting/printing a reusable ITERM2_COOKIE/ITERM2_KEY hands a
    // durable, off-device local API credential to whoever reads stdout. That must never
    // happen over SSH integration, where stdout streams to the remote host and would escape
    // the per-session, revocable grant. Refused centrally in runParsedCommand when isRemote.
    struct Cookie: ParsableCommand, IT2Runnable, RemoteForbiddenCommand {
        static let configuration = CommandConfiguration(
            commandName: "cookie",
            abstract: "Request a cookie and key from iTerm2.",
            discussion: """
                Prints ITERM2_COOKIE=... ITERM2_KEY=... to stdout.

                By default, requests a reusable cookie. An announcement in iTerm2
                lets the user choose the duration (24 hours, forever, etc.).

                Usage:
                  export $(it2 auth cookie)
                """
        )

        @Flag(help: "Request a single-use cookie instead of a reusable one.")
        var singleUse = false

        func run(_ ctx: IT2Context) throws {
            let (cookie, key): (String?, String?)
            if singleUse {
                (cookie, key) = CookieAuth.requestCookie()
            } else {
                (cookie, key) = CookieAuth.requestReusableCookie()
            }
            guard let cookie = cookie, let key = key else {
                throw IT2Error.connectionError(
                    "Failed to get cookie from iTerm2. Ensure iTerm2 is running and Python API is enabled.")
            }
            ctx.out("ITERM2_COOKIE=\(cookie) ITERM2_KEY=\(key)")
        }
    }
}
