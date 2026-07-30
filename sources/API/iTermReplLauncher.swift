//
//  iTermReplLauncher.swift
//  iTerm2SharedARC
//
//  Phase 2 of the uv Python-runtime migration. Chooses the interactive Python REPL
//  arguments. A uv venv has no apython shim, so it uses the stdlib asyncio REPL
//  (`python -m asyncio`), which has provided top-level await since Python 3.8. The
//  legacy runtime uses aioconsole's apython with its own banner suppressed so
//  iTerm2's injected banner shows instead. See docs/uv-python-runtime-migration.md.
//

import Foundation

@objc(iTermReplLauncher)
class iTermReplLauncher: NSObject {
    @objc static func arguments(usesUV: Bool) -> [String] {
        return usesUV ? ["-m", "asyncio"] : [#"--banner=\"\""#]
    }
}
