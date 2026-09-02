//
//  AppleIntelligenceRunner.swift
//  iTerm2
//
//  Runs a one-shot, non-streaming completion against Apple's on-device
//  Foundation Models. This is the implementation behind the
//  `.appleIntelligence` AI backend, which AITermController dispatches to
//  directly rather than building an HTTP request (Apple Intelligence has no
//  wire format). Feature-limited on purpose: no streaming, tool calling, or
//  attachments. See AISafetyClassifierBackend for the main caller.
//

import Foundation
import FoundationModels

enum AppleIntelligenceRunnerError: Error {
    // The token budget left no room for the screen (over-large instructions/schema
    // or a too-small maxContextTokens). A deterministic, best-effort-degrade error:
    // generate() maps it to "no title" rather than crashing.
    case tokenBudgetTooSmall
}

// Token counts for the (constant) instructions and generation schema are process-
// invariant, so cache them instead of paying two serial on-device XPC round-trips per
// generation (every ~5s per idle AI session; tens of ms each on a throttled machine).
// Keyed by the instructions string / schema type, so a future caller with a different
// pair still recomputes; the tab-title feature always passes the same pair, so after the
// first generation these are free. A FAILED count is not cached, so it retries and the
// caller's estimate fallback applies until a real count lands.
@available(macOS 26.4, *)
private actor TokenCountCache {
    static let shared = TokenCountCache()
    private var instructionCounts: [String: Int] = [:]
    private var schemaCounts: [ObjectIdentifier: Int] = [:]

    func instructionCount(_ instructions: String, model: SystemLanguageModel) async -> Int? {
        if let cached = instructionCounts[instructions] {
            return cached
        }
        guard let count = try? await model.tokenCount(for: Instructions(instructions)) else {
            return nil
        }
        instructionCounts[instructions] = count
        return count
    }

    func schemaCount<Content: Generable>(_ type: Content.Type, model: SystemLanguageModel) async -> Int? {
        let key = ObjectIdentifier(type)
        if let cached = schemaCounts[key] {
            return cached
        }
        guard let count = try? await model.tokenCount(for: type.generationSchema) else {
            return nil
        }
        schemaCounts[key] = count
        return count
    }
}

@available(macOS 26, *)
enum AppleIntelligenceRunner {
    /// Sends `system` as the session instructions and `user` as the prompt,
    /// returning the model's text. `maxTokens` is accepted for parity with the
    /// HTTP backends but is advisory here: the on-device session manages its
    /// own response length, and classification replies are short.
    static func complete(system: String?, user: String, maxTokens: Int) async throws -> String {
        let session = LanguageModelSession(model: .default,
                                           instructions: system ?? "")
        return try await session.respond(to: user).content
    }

    /// Guided, greedy on-device generation. Unlike `complete`, this forces the
    /// model to emit a value conforming to `Content` (FoundationModels guided
    /// generation via `@Generable`) and pins sampling to `.greedy` so an
    /// unchanged prompt yields an identical result rather than a fresh variant
    /// on every pass. Both properties turned out to be load-bearing for the AI
    /// tab-title feature: free-text prompting returns multi-line replies and
    /// occasional bare failure tokens, and the default sampler renames a tab
    /// while you are reading it. Still feature-limited like `complete`: one
    /// shot, no streaming, tool calling, or attachments.
    static func generate<Content: Generable>(system: String?,
                                             user: String,
                                             as type: Content.Type) async throws -> Content {
        let session = LanguageModelSession(model: .default,
                                           instructions: system ?? "")
        let options = GenerationOptions(sampling: .greedy)
        return try await session.respond(to: user,
                                         generating: type,
                                         options: options).content
    }

    /// Names the visible screen for a tab title, fitting the on-device model's
    /// ~4096-token context window. Terminal screens are heavily space-padded
    /// (column alignment, TUI chrome), so the screen is first whitespace-
    /// condensed, then trimmed from the top - keeping the most recent lines,
    /// which carry the current work - until instructions + schema + prompt +
    /// an output reserve all fit the budget. Without this a large screen throws
    /// `exceededContextWindowSize` and the tab gets no title at all.
    ///
    /// Token counts come from the model's own tokenizer (`tokenCount(for:)`),
    /// so the budget is exact for this model rather than a character estimate.
    static func generateTabTitle<Content: Generable>(instructions: String,
                                                     context: String,
                                                     screen: String,
                                                     as type: Content.Type,
                                                     maxContextTokens: Int = 4096,
                                                     outputReserve: Int = 256,
                                                     onProgress: @escaping @Sendable () -> Void = {}) async throws -> Content {
        // Signal progress at every token-count XPC hop and before respond(), so the
        // caller's watchdog can time out on IDLE (no forward progress) rather than a
        // fixed total-time cap. On a throttled Mac the token-count fan-out below can sum
        // past a wall-clock cap while healthy; touching onProgress keeps that from being
        // mistaken for a hang.
        let session = LanguageModelSession(model: .default, instructions: instructions)

        // Scan `instructions` for its estimated token cost once: it feeds the 26.4
        // tokenCount fallback, the pre-26.4 reserve, and the budget assert below,
        // and there is no reason to walk the whole string three times. (The per-
        // chunk estimates in `count` take a different argument and stay inline.)
        let instructionEstimate = Self.estimatedTokenUpperBound(instructions)

        // Pick the token counter and derive the budget once, then use it for BOTH the
        // context pre-trim and the screen fit, so the exact (26.4) and estimate (pre-26.4)
        // paths can't drift and a CJK-heavy context isn't over-trimmed by the estimate when
        // an exact count is available.
        // NOTE: budget derivation and its viability check live in promptBudget /
        // budgetLeavesRoomForScreen so the assert below tests the REAL budget (with exact
        // schema tokens) rather than a fixed-96 estimate that can pass while the true budget
        // is floored to nothing.
        let budget: Int
        let count: (String) async throws -> Int
        if #available(macOS 26.4, *) {
            let model = SystemLanguageModel.default
            // Fall back to a conservative estimate, not 0, when a count is
            // unavailable: 0 over-allocates the budget by the real instruction+
            // schema cost (~250 tokens), so the prompt then overflows.
            onProgress()
            let instructionTokens = await TokenCountCache.shared.instructionCount(instructions, model: model)
                ?? instructionEstimate
            onProgress()
            let schemaTokens = await TokenCountCache.shared.schemaCount(type, model: model) ?? 96
            budget = Self.promptBudget(maxContextTokens: maxContextTokens,
                                       outputReserve: outputReserve,
                                       instructionTokens: instructionTokens,
                                       schemaTokens: schemaTokens)
            // Fall back to the estimate if a mid-search tokenCount throws, rather
            // than letting the throw abort the whole generation - which generate()
            // would misclassify as a deterministic failure and stamp the screen as
            // permanently untitleable. The budget calc already falls back this way.
            count = { onProgress(); return (try? await model.tokenCount(for: $0)) ?? Self.estimatedTokenUpperBound($0) }
        } else {
            // Reserve the estimated instruction tokens (which alone can exceed the
            // old flat 160) plus a schema allowance.
            let reserve = max(160, instructionEstimate + 96)
            budget = Self.promptBudget(maxContextTokens: maxContextTokens,
                                       outputReserve: outputReserve,
                                       instructionTokens: reserve,
                                       schemaTokens: 0)
            count = { onProgress(); return Self.estimatedTokenUpperBound($0) }
        }
        let fits: (String) async throws -> Bool = { try await count($0) <= budget }

        // The max(256, ...) floor keeps budget positive, but a floored-up budget
        // silently breaks the fit guarantee (a ~256-token prompt gets fitted onto an
        // already-full window -> exceededContextWindowSize). Detect it on the REAL
        // budget (exact schema tokens already subtracted), not a fixed-96 estimate
        // that could pass while budget is floored. This only trips for a future
        // caller with over-large `instructions`/schema or a too-small
        // `maxContextTokens`; the shipping call leaves budget ~3.5k. Throw rather
        // than it_assert (which fires in release): title generation is best-effort
        // and cosmetic, so a misconfigured budget must degrade to "no title" - the
        // thrown deterministic error is mapped by generate() to .produced(nil), which
        // stamps the screen and leaves it untitled - not crash the process.
        guard Self.budgetLeavesRoomForScreen(budget) else {
            DLog("AI title: token budget too small (budget=\(budget)); skipping generation")
            throw AppleIntelligenceRunnerError.tokenBudgetTooSmall
        }

        // Pre-trim the structured context to leave room for the screen, so that
        // even after the whole screen is trimmed the prompt cannot overflow.
        let contextBudget = max(Self.minContextTokens, budget - Self.screenReserveTokens)
        var fittedContext = try await Self.truncatedContext(context, tokenBudget: contextBudget, measure: count)
        let lines = condenseWhitespace(screen).components(separatedBy: "\n")
        func promptWithScreenBody(_ body: String) -> String {
            return fittedContext.isEmpty ? body : fittedContext + "\n\nVisible screen:\n" + body
        }
        func prompt(keepingLastLines keep: Int) -> String {
            return promptWithScreenBody(lines.suffix(keep).joined(separator: "\n"))
        }

        // Largest tail of the screen that fits: one measure when the whole screen
        // already fits, ~log2(lines) when it needs trimming.
        var kept = lines.count
        let wholeScreenFits = try await fits(prompt(keepingLastLines: lines.count))
        if !wholeScreenFits {
            var lo = 0
            var hi = lines.count
            kept = 0
            while lo <= hi {
                let mid = (lo + hi) / 2
                if try await fits(prompt(keepingLastLines: mid)) {
                    kept = mid
                    lo = mid + 1
                } else {
                    hi = mid - 1
                }
            }
        }
        // The screen is fully trimmed away but the context alone still overflows:
        // shrink the context so the final prompt is guaranteed to fit.
        while kept == 0 && !fittedContext.isEmpty {
            if try await fits(prompt(keepingLastLines: 0)) {
                break
            }
            fittedContext = Self.geometricallyShrink(fittedContext)
        }

        // Bound the reply to the same token count the budget reserved for it.
        // Otherwise `outputReserve` is only a guess: a prompt filled to the edge of
        // the window plus a reply longer than the reserve overflows the context
        // window, throwing exceededContextWindowSize (caught as .produced(nil), which
        // stamps the screen as permanently untitleable). A 2-to-4-word title needs far
        // fewer than 256 tokens, so this never truncates a real title.
        let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: outputReserve)
        // The whole-line fit search keeps only whole lines from the tail, so if the
        // single last visible line alone exceeds the budget (a soft-wrapped logical
        // line spanning most of a large grid, e.g. a pasted minified blob) it
        // settles on kept == 0 and the model would be titled from context alone -
        // or from nothing, on an alternate screen with no shell integration. Mirror
        // truncatedContext's last resort: hard-truncate that line by characters so
        // the prompt always carries some of the visible screen.
        if kept == 0, let lastLine = lines.last, !lastLine.isEmpty {
            let body = try await Self.truncatedLineToFit(lastLine,
                                                         fits: { try await fits(promptWithScreenBody($0)) })
            if !body.isEmpty {
                onProgress()
                return try await session.respond(to: promptWithScreenBody(body),
                                                 generating: type,
                                                 options: options).content
            }
        }
        onProgress()
        return try await session.respond(to: prompt(keepingLastLines: kept),
                                         generating: type,
                                         options: options).content
    }

    // Hard-truncates `line` by characters (dropping from the tail) to the longest
    // prefix for which `fits` is true, or "" if even one character does not fit.
    // Geometric shrink (~1/8 per step) so it converges in a few measures. Mirrors
    // the last-resort char truncation truncatedContext uses for an overlong line,
    // but for a single visible screen line so a giant soft-wrapped row still
    // contributes SOME content rather than dropping the whole screen.
    static func truncatedLineToFit(_ line: String,
                                   fits: (String) async throws -> Bool) async throws -> String {
        var truncated = line
        while !truncated.isEmpty {
            if try await fits(truncated) {
                break
            }
            truncated = Self.geometricallyShrink(truncated)
        }
        return truncated
    }

    // Trims a structured context block so its token count (per `measure`) fits
    // `tokenBudget`. `measure` is passed in so callers use the exact tokenizer
    // when available rather than the 4x-non-ASCII estimate, which would
    // over-trim a CJK-heavy context even on the exact path.
    // Drops history first; if a single line still overflows, hard-truncates by
    // characters. Guarantees the result fits.
    static func truncatedContext(_ context: String,
                                 tokenBudget: Int,
                                 measure: (String) async throws -> Int) async throws -> String {
        guard try await measure(context) > tokenBudget else {
            return context
        }
        var lines = context.components(separatedBy: "\n")
        // Drop the recent-command history first: it is the bulk and the least
        // critical, while cwd/host are compact and high-signal for naming. History
        // sits BEFORE Directory:/Host: in the assembled block, so a plain
        // removeLast() would shed cwd/host first (the inverse of the intent). Drop
        // the oldest commands first (keeping the most recent), then the header.
        func removeOldestHistoryLine() -> Bool {
            if let idx = lines.firstIndex(where: { $0.hasPrefix(AITabTitleContext.historyLinePrefix) }) {
                lines.remove(at: idx)
                return true
            }
            if let idx = lines.firstIndex(where: { $0.hasSuffix(AITabTitleContext.historyHeaderSuffix) }) {
                lines.remove(at: idx)
                return true
            }
            return false
        }
        while try await measure(lines.joined(separator: "\n")) > tokenBudget {
            if !removeOldestHistoryLine() {
                break
            }
        }
        // If still over budget with no history left to shed, the offender is one
        // oversized line - typically a very long `Command line:` in the MIDDLE of the
        // block, not the compact cwd/host at the end. Char-truncate the largest line
        // each pass rather than blindly dropping trailing lines (a plain removeLast()
        // would shed the high-signal Directory:/Host: fields while the giant middle
        // line survived, naming the tab worse). PROTECT the cwd/host lines: only
        // truncate the largest NON-cwd/host line, falling back to the largest overall
        // just in case cwd/host alone somehow exceed the budget.
        func isProtected(_ line: String) -> Bool {
            return line.hasPrefix(AITabTitleContext.directoryLinePrefix)
                || line.hasPrefix(AITabTitleContext.hostLinePrefix)
        }
        while try await measure(lines.joined(separator: "\n")) > tokenBudget {
            let unprotected = lines.indices.filter { !isProtected(lines[$0]) && !lines[$0].isEmpty }
            let target = unprotected.max(by: { lines[$0].count < lines[$1].count })
                ?? lines.indices.max(by: { lines[$0].count < lines[$1].count })
            guard let idx = target, !lines[idx].isEmpty else {
                break
            }
            lines[idx] = Self.geometricallyShrink(lines[idx])
        }
        return lines.joined(separator: "\n")
    }

    // A conservative upper bound on the token count of a prompt, for the pre-26.4 path
    // that has no exact tokenCount. ASCII terminal text runs a bit under ~3 chars/token,
    // but CJK/Japanese/emoji are roughly one-or-more tokens per grapheme, so counting
    // non-ASCII scalars at full weight keeps a non-Latin screen from being under-budgeted
    // into an oversized prompt.
    static func estimatedTokenUpperBound(_ s: String) -> Int {
        // A genuine upper bound: BPE never emits more than one token per ASCII
        // character (a single byte is at most one token), and a non-ASCII scalar
        // is at most 4 UTF-8 bytes so at most ~4 tokens. Natural-language text
        // tokenizes far below this (~3 chars/token), so on the pre-26.4 estimate
        // path this over-counts and trims a little more screen than strictly
        // needed - but a normal ~2KB visible grid still fits comfortably, and
        // over-counting only bites pathological (base64/hex/CJK-dense) screens,
        // which is exactly when under-counting would overflow the window and
        // produce no title at all. Over-count is safe; under-count is not.
        var asciiCount = 0
        var nonASCIICount = 0
        for scalar in s.unicodeScalars {
            if scalar.isASCII {
                asciiCount += 1
            } else {
                nonASCIICount += 1
            }
        }
        return asciiCount + nonASCIICount * 4
    }

    // Tokens the context pre-trim reserves for the screen after the context block:
    // contextBudget = budget - screenReserveTokens. minContextTokens is the floor that
    // keeps contextBudget positive. These three sites - the reserve subtraction, the
    // floor, and the viability threshold (minContextTokens + screenReserveTokens) - must
    // move together, so they derive from these named constants rather than repeating the
    // literals 512 / 256 / 768 across two functions. Tuning one without the others would
    // let budgetLeavesRoomForScreen pass a budget that leaves zero real room, overflow
    // the fitted prompt, and stamp the screen permanently untitleable.
    static let screenReserveTokens = 512
    static let minContextTokens = 256

    // The prompt budget: the context window minus the output, instruction, and
    // schema reserves, floored so the downstream pre-trim math (contextBudget =
    // budget - screenReserveTokens) stays positive. Extracted so the viability assert in
    // generateTabTitle checks the SAME value the budget is actually built from,
    // including the exact schema token count (which can far exceed the old flat
    // 96-token allowance).
    static func promptBudget(maxContextTokens: Int, outputReserve: Int,
                             instructionTokens: Int, schemaTokens: Int) -> Int {
        return max(Self.minContextTokens, maxContextTokens - outputReserve - instructionTokens - schemaTokens)
    }

    // Whether a derived budget leaves real room for the screen after the context
    // pre-trim and separator. Requiring budget > minContextTokens + screenReserveTokens
    // keeps contextBudget = budget - screenReserveTokens strictly above the floor, so the
    // screen always gets a positive share; a budget floored to minContextTokens (the
    // pathological case) fails this and the assert fires.
    static func budgetLeavesRoomForScreen(_ budget: Int) -> Bool {
        return budget > Self.minContextTokens + Self.screenReserveTokens
    }

    // Last-resort char truncation: drop a geometric 1/8 of the string, at least one
    // char so a 1-7 char string still shrinks and the caller's while-loop can never
    // spin forever. One definition for the three trim sites so the rate and the
    // infinite-loop guard can't drift.
    static func geometricallyShrink(_ s: String) -> String {
        return String(s.dropLast(max(1, s.count / 8)))
    }

    // Collapses runs of spaces/tabs to a single space and trims each line, drops
    // consecutive blank lines, and strips leading/trailing blank lines. Terminal
    // output pads columns with many spaces that carry no meaning for a title but
    // cost tokens; removing them is a large, safe reduction.
    //
    // Delegates to AITabTitleGenerator.condense, the SAME line walk the change digest
    // (normalize) uses, so the prompt and the digest can't drift on newline-set splitting
    // or interior-whitespace collapse. They differ ONLY in blank-line policy, passed
    // explicitly: the prompt collapses runs of blanks to one and trims the ends, while
    // the digest drops every blank line. That means a blank-line-only change leaves the
    // digest unchanged and suppresses a re-title even though the prompt body would
    // differ - an accepted missed re-title, never a wrong one (regeneration always
    // rebuilds from here). Do not rely on digest == prompt-structure equivalence.
    private static func condenseWhitespace(_ screen: String) -> String {
        return AITabTitleGenerator.condense(screen, blankLines: .collapseRuns)
    }
}
