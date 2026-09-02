//
//  AILiveAppleIntelligenceTabTitle.swift
//  iTerm2 AI live harness
//
//  Live, opt-in probe of the on-device (Apple Intelligence) tab-title
//  generator that backs the `iTermTitleComponentsAI` title component. Like the
//  classifier probe it spends no money (the model runs on-device) but needs
//  macOS 26 with Apple Intelligence enabled. It exercises the exact seam the
//  feature uses: AppleIntelligenceRunner.generate(..., as: TabTitle.self) with
//  guided generation + greedy sampling.
//
//  Three things are checked, because they are the claims the feature rests on:
//    1. Integration: the on-device guided-generation path returns a title.
//    2. Quality (reported, not asserted): the title names the work, is short,
//       and is single-line.
//    3. Stability (asserted): the SAME screen yields the SAME title across
//       repeated runs. This is the whole reason for greedy sampling; without
//       it a tab renames itself while you are reading it.
//
//  Run via: tools/run_ai_live.sh appleIntelligenceTabTitle
//

import XCTest
import FoundationModels
@testable import iTerm2SharedARC

// Mirrors the app's private GeneratedTabTitle schema so the harness drives the
// same guided-generation shape without exposing the app type.
@available(macOS 26, *)
@Generable
private struct HarnessTabTitle {
    @Guide(description: "A 2-to-4 word Title Case name for the task in progress. No quotes, no trailing punctuation.")
    var title: String
}

// The issue author's original schema from carloshpdoc/iTerm2@054e30fd0c: same
// shape but a 2-to-5 word guide (ours was later tightened to 2-to-4 to fit the
// app's 40-char sanitize cap). Kept verbatim so his prompt can be graded faithfully.
@available(macOS 26, *)
@Generable
private struct AuthorTabTitle {
    @Guide(description: "A 2-to-5 word Title Case name for the task in progress. No quotes, no trailing punctuation.")
    var title: String
}

extension AILiveHarness {
    // A: the reporter-style prompt with a concrete "Code Review" example.
    private static let instructionsA = """
        You name terminal tabs. You are given context about a terminal session \
        and the visible contents of its screen. Name the work the user is doing, \
        not the program they are using: a session paging through a diff is \
        "Code Review", not "less". Prefer the task over the tool.
        """

    // B: no concrete example (which we suspect the small model over-applies), \
    // with an explicit push toward specificity.
    private static let instructionsB = """
        You name terminal tabs. You are given context about a terminal session \
        and the visible contents of its screen. Reply with a short Title Case \
        label for the specific task on this screen. Name the activity, not the \
        tool: describe the file, project, data, or operation visible, not the \
        program hosting it. Be specific to what is shown; avoid generic labels.
        """

    // C: like B but anchored on the concrete subject (filenames, tables, \
    // commands) that appears in the context/screen.
    private static let instructionsC = """
        You name terminal tabs from the visible screen and the session context. \
        Reply with a short Title Case label naming the specific subject of the \
        work: prefer the concrete thing on screen (the file being edited, the \
        table being queried, the server or project running) over the tool. If a \
        filename or command is present, name what it is for. Avoid vague labels.
        """

    // N: the goal-inference revision - reframes from "describe the specific task
    // on this screen" (which made titles thrash per command and over-index on the
    // latest output) toward inferring the session's overall goal from the whole
    // screen, and prefers a stable name. Kept in sync with the shipping prompt.
    private static let instructionsN = """
        You name terminal tabs. You are given context about a terminal session \
        and the visible contents of its screen. Work out what the user is trying \
        to accomplish in this session and reply with a Title Case label of at \
        most four words for that goal. Read the whole screen, not just the latest \
        output: the sequence of commands and the files, services, or projects \
        they touch reveal the goal better than any single line does. Name the \
        goal or activity, not the tool hosting it and not merely the most recent \
        command or its output, and prefer a name that stays stable while the user \
        keeps working toward the same thing. Keep it short; avoid generic labels.
        """

    private static var instructionVariants: [(String, String)] {
        // OLD is the exact prompt that shipped before the goal-inference revision
        // (== instructionsB); NEW is the revision. Side by side on each record.
        return [("OLD", instructionsB), ("NEW", instructionsN)]
    }

    // The variant adopted by the shipping generator (kept in sync for the
    // stability assertion below). Now the goal-inference revision.
    private static let tabTitleInstructions = instructionsN

    private struct TabTitleSample {
        var label: String
        var context: String
        var screen: String
    }

    private static func tabTitleSamples() -> [TabTitleSample] {
        return [
            TabTitleSample(
                label: "git-diff-in-less",
                context: "Foreground program: less\nCommand line: git diff\nDirectory: /Users/dev/webapp",
                screen: """
                    diff --git a/sources/auth/Login.swift b/sources/auth/Login.swift
                    index 3f9a1c2..b7e4d90 100644
                    --- a/sources/auth/Login.swift
                    +++ b/sources/auth/Login.swift
                    @@ -42,7 +42,9 @@ final class LoginController {
                    -        let token = try await api.authenticate(user, password)
                    +        let token = try await api.authenticate(user, password,
                    +                                               mfaCode: mfaCode)
                    +        try keychain.store(token)
                             session.begin(with: token)
                    :
                    """),
            TabTitleSample(
                label: "vim-editing-config",
                context: "Foreground program: vim\nCommand line: vim nginx.conf\nDirectory: /etc/nginx",
                screen: """
                    server {
                        listen 443 ssl;
                        server_name example.com;
                        ssl_certificate     /etc/ssl/example.crt;
                        ssl_certificate_key /etc/ssl/example.key;
                        location /api/ {
                            proxy_pass http://127.0.0.1:8080;
                        }
                    }
                    -- INSERT --                                          12,18         Top
                    """),
            TabTitleSample(
                label: "node-dev-server",
                context: "Foreground program: node\nCommand line: npm run dev\nDirectory: /Users/dev/webapp",
                screen: """
                    > webapp@1.0.0 dev
                    > vite

                      VITE v5.2.0  ready in 412 ms

                      ➜  Local:   http://localhost:5173/
                      ➜  Network: use --host to expose
                      12:04:31 PM [vite] hmr update /src/App.tsx
                      12:04:39 PM [vite] page reload src/main.tsx
                    """),
            TabTitleSample(
                label: "psql-query",
                context: "Foreground program: psql\nDirectory: /Users/dev",
                screen: """
                    analytics=# SELECT country, count(*) FROM users GROUP BY country ORDER BY 2 DESC LIMIT 5;
                     country | count
                    ---------+-------
                     US      | 41203
                     DE      |  9821
                     GB      |  7654
                     FR      |  5210
                     JP      |  4933
                    (5 rows)
                    analytics=#
                    """),
        ]
    }

    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")

        var rows: [String] = []
        rows.append("label                | variant | latency | title")
        rows.append("---------------------+---------+---------+------------------------------")

        // Compare instruction variants side by side across all samples. Which
        // one gives specific, diverse titles (not the same generic label for
        // every screen) is the empirical question this probe answers.
        for sample in Self.tabTitleSamples() {
            let prompt = sample.context + "\n\nVisible screen:\n" + sample.screen
            for (name, instructions) in Self.instructionVariants {
                let start = Date()
                let title = try await AppleIntelligenceRunner.generate(
                    system: instructions,
                    user: prompt,
                    as: HarnessTabTitle.self).title
                let latency = Date().timeIntervalSince(start)

                let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertFalse(clean.isEmpty, "\(sample.label)/\(name): empty title")
                XCTAssertFalse(clean.contains("\n"), "\(sample.label)/\(name): newline in title: \(clean)")
                let wordCount = clean.split(whereSeparator: { $0 == " " }).count
                let flag = wordCount > 6 ? "⚠︎long " : ""
                rows.append("\(sample.label.padded(20)) |    \(name)    | \(String(format: "%5.0fms", latency * 1000)) | \(flag)\(clean)")
            }
            rows.append("---------------------+---------+---------+------------------------------")
        }

        // Stability: greedy sampling must give the SAME title for the SAME
        // input. Run the first sample several times and require identical
        // output. This is the load-bearing assertion.
        let stabilitySample = Self.tabTitleSamples()[0]
        let stabilityPrompt = stabilitySample.context + "\n\nVisible screen:\n" + stabilitySample.screen
        var titles: [String] = []
        for _ in 0..<3 {
            let t = try await AppleIntelligenceRunner.generate(
                system: Self.tabTitleInstructions,
                user: stabilityPrompt,
                as: HarnessTabTitle.self).title
            titles.append(t.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        rows.append("")
        rows.append("stability (\(stabilitySample.label)) x3: \(titles.joined(separator: " | "))")

        print("\n=== Apple Intelligence tab titles ===")
        print(rows.joined(separator: "\n"))
        print("=====================================\n")

        let allEqual = titles.allSatisfy { $0 == titles.first }
        XCTAssertTrue(allEqual,
                      "Greedy sampling should be stable but produced: \(titles)")
    }

    // Replays a corpus of real captured generations (collected in the app with
    // the `logAITabTitleCorpus` advanced setting on) through each prompt variant
    // on-device. This is the loop for improving prompts: hit a bad title in real
    // use, then run this to see whether a candidate prompt fixes that exact input
    // without regressing the others. Skipped when no corpus has been collected.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_gradeCorpus() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(
            !corpus.isEmpty,
            "No corpus. Enable the `logAITabTitleCorpus` advanced setting, use AI tab titles, then re-run. Path: \(AITabTitleCorpus.corpusFileURL(createDirectory: false)?.path ?? "?")")

        print("\n=== Corpus grade (\(corpus.count) records) ===")
        var leakCounts: [String: Int] = [:]
        for (index, record) in corpus.enumerated() {
            let userPrompt: String
            if record.context.isEmpty {
                userPrompt = record.screen
            } else {
                userPrompt = record.context + "\n\nVisible screen:\n" + record.screen
            }
            let subject = [record.job, record.cwd].compactMap { $0 }.joined(separator: " @ ")
            print("\n[\(index)] \(subject.isEmpty ? "(no context)" : subject)  (logged: \(record.title ?? "nil"))")
            for (name, instructions) in Self.instructionVariants {
                let title = try await AppleIntelligenceRunner.generate(
                    system: instructions,
                    user: userPrompt,
                    as: HarnessTabTitle.self).title
                let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let leaked = Self.looksLikeScreenLeak(title: clean, screen: record.screen)
                if leaked {
                    leakCounts[name, default: 0] += 1
                }
                print("    \(name): \(leaked ? "⚠︎leak " : "")\(clean)")
            }
        }
        print("\nfilename-leak counts by variant: \(leakCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        print("=== end corpus grade ===\n")
    }

    // Ablation: what does the shipping (goal-inference) prompt produce with the
    // screen removed entirely - only the structured context (job, command line,
    // recent command history, cwd, host)? Isolates how much of each title comes
    // from the screen vs. the context, and shows where the context alone is too
    // thin to name the work (e.g. inside ssh, where history doesn't cross the
    // remote and the context collapses to "ssh HOST"). Prints WITH-screen and
    // NO-screen side by side. Skipped when no corpus has been collected.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_noScreen() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(!corpus.isEmpty, "No corpus collected.")

        func title(_ user: String) async throws -> String {
            return try await AppleIntelligenceRunner.generate(
                system: Self.instructionsN, user: user, as: HarnessTabTitle.self)
                .title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("\n=== No-screen ablation (\(corpus.count) records, prompt=NEW) ===")
        for (index, record) in corpus.enumerated() {
            let subject = [record.job, record.cwd].compactMap { $0 }.joined(separator: " @ ")
            print("\n[\(index)] \(subject.isEmpty ? "(no context)" : subject)")
            print("    context: \(record.context.replacingOccurrences(of: "\n", with: " / "))")
            let withScreen = record.context.isEmpty ? record.screen
                : record.context + "\n\nVisible screen:\n" + record.screen
            print("    with-screen: \(try await title(withScreen))")
            if record.context.isEmpty {
                print("    no-screen:   (no context to work from)")
            } else {
                print("    no-screen:   \(try await title(record.context))")
            }
        }
        print("=== end no-screen ablation ===\n")
    }

    // Follow-up to the ablation: the command history often already names the
    // subject (e.g. `journalctl -u iterm2-companion-relay`), yet the model names
    // the activity but drops the entity and lets navigation commands (`cd git`)
    // mis-anchor the title. Commands-only (no screen), this compares three levers
    // per record: the baseline prompt; a prompt nudged to name the specific
    // service/project/host the commands act on; and the baseline with pure
    // navigation commands (cd/ls/pwd/...) filtered out of the history. Shows
    // whether the entity is recoverable from the commands alone.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_historyEntity() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(!corpus.isEmpty, "No corpus collected.")

        // Pure navigation / no-op shell commands carry no task signal; their only
        // effect on the title is to anchor it on a directory name (cd git -> Git).
        let navHeads: Set<String> = ["cd", "ls", "pwd", "clear", "exit", "logout", "cd-", "pushd", "popd"]
        func isNavigation(_ command: String) -> Bool {
            let head = command.split(separator: " ").first.map(String.init) ?? command
            return navHeads.contains(head)
        }

        let entityNudge = Self.instructionsN
            + " If the recent commands name a specific service, project, file, or "
            + "host they act on, put that subject in the title rather than a bare "
            + "verb."

        func title(system: String, user: String) async throws -> String {
            guard !user.isEmpty else { return "(no context)" }
            return try await AppleIntelligenceRunner.generate(
                system: system, user: user, as: HarnessTabTitle.self)
                .title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("\n=== History-entity extraction (\(corpus.count) records, no screen) ===")
        for (index, record) in corpus.enumerated() {
            let commands = record.recentCommands ?? []
            guard !commands.isEmpty else { continue }
            let filtered = commands.filter { !isNavigation($0) }
            // Rebuild the context text from the filtered command list so the
            // model sees the same shape, minus the navigation noise.
            let filteredContext = AITabTitleContext.assembleText(
                job: record.job, commandLine: record.commandLine,
                atPrompt: record.atPrompt ?? false, lastCommand: filtered.last,
                recentCommands: filtered, cwd: record.cwd,
                user: record.user, host: record.host, home: nil)

            print("\n[\(index)] commands: \(commands.joined(separator: " ; "))")
            print("    baseline:      \(try await title(system: Self.instructionsN, user: record.context))")
            print("    entity-nudge:  \(try await title(system: entityNudge, user: record.context))")
            print("    nav-filtered:  \(try await title(system: Self.instructionsN, user: filteredContext))")
        }
        print("=== end history-entity extraction ===\n")
    }

    // Grades the issue author's original prompt (carloshpdoc/iTerm2@054e30fd0c)
    // against our corpus. His setup: a short 3-sentence instruction, a 2-to-5
    // word guide, and the RAW SCREEN as the only input (no structured context,
    // no command history - those are our additions). Three columns per record:
    //   author(screen)  = his prompt, his input shape (screen only) - faithful
    //   author(+context) = his prompt, but fed our context+screen (isolates the
    //                      prompt from the input, i.e. does his wording benefit
    //                      from the history we add?)
    //   NEW             = our shipping prompt + our context+screen, for reference
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_authorPrompt() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(!corpus.isEmpty, "No corpus collected.")

        // Verbatim from his AppleIntelligenceRunner.swift.
        let authorInstructions = """
            You name terminal tabs. You are shown the visible contents of a \
            terminal screen. Name the work the user is doing, not the program \
            they are using.
            """

        func author(_ user: String) async throws -> String {
            guard !user.isEmpty else { return "(empty)" }
            return try await AppleIntelligenceRunner.generate(
                system: authorInstructions, user: user, as: AuthorTabTitle.self)
                .title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func new(_ user: String) async throws -> String {
            return try await AppleIntelligenceRunner.generate(
                system: Self.instructionsN, user: user, as: HarnessTabTitle.self)
                .title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("\n=== Author prompt grade (\(corpus.count) records) ===")
        for (index, record) in corpus.enumerated() {
            let withContext = record.context.isEmpty ? record.screen
                : record.context + "\n\nVisible screen:\n" + record.screen
            let subject = [record.job, record.cwd].compactMap { $0 }.joined(separator: " @ ")
            print("\n[\(index)] \(subject)  (logged: \(record.title ?? "nil"))")
            print("    author(screen):   \(try await author(record.screen))")
            print("    author(+context): \(try await author(withContext))")
            print("    NEW:              \(try await new(withContext))")
        }
        print("=== end author prompt grade ===\n")
    }

    // Follow-up to the author-prompt grade: the author's terse prompt fed our
    // context is the preferred baseline, but it collapses to a generic activity
    // word ("Troubleshooting") for nearly every record. This tries minimal
    // specificity nudges bolted onto his exact wording (keeping his short style,
    // NOT swinging to our verbose prompt) to see which one recovers the specific
    // subject without losing brevity or stability. All fed context+screen, his
    // 2-to-5 word guide.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_authorNudge() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(!corpus.isEmpty, "No corpus collected.")

        let base = "You name terminal tabs. You are shown the visible contents of "
            + "a terminal screen. Name the work the user is doing, not the program "
            + "they are using."
        let variants: [(String, String)] = [
            ("base", base),
            // A: name the concrete subject rather than the activity.
            ("subject", base + " Be specific: name the particular file, service, "
                + "project, or problem involved, not a generic activity."),
            // B: framed around distinguishing this tab from others.
            ("distinguish", base + " Be specific enough that the name distinguishes "
                + "this tab from other tabs; avoid generic one-word labels."),
            // C: smallest possible nudge - just forbid the generic category.
            ("specific", "You name terminal tabs. You are shown the visible contents "
                + "of a terminal screen. Name the specific work the user is doing, "
                + "not the program they are using and not a generic category."),
        ]

        print("\n=== Author-nudge grade (\(corpus.count) records, +context, his guide) ===")
        for (index, record) in corpus.enumerated() {
            let user = record.context.isEmpty ? record.screen
                : record.context + "\n\nVisible screen:\n" + record.screen
            let subject = [record.job, record.cwd].compactMap { $0 }.joined(separator: " @ ")
            print("\n[\(index)] \(subject)  (logged: \(record.title ?? "nil"))")
            for (name, instructions) in variants {
                let title = try await AppleIntelligenceRunner.generate(
                    system: instructions, user: user, as: AuthorTabTitle.self)
                    .title.trimmingCharacters(in: .whitespacesAndNewlines)
                print("    \(name.padding(toLength: 12, withPad: " ", startingAt: 0)): \(title)")
            }
        }
        print("=== end author-nudge grade ===\n")
    }

    // Builds on the winning "subject" nudge by encouraging a verb+object title
    // shape (e.g. an action verb and the thing it acts on) to make the label
    // consistent and to fix noun-phrase outliers. No concrete example titles:
    // a worked example anchors the small model hard (it answered "Code Review"
    // for everything). All fed context+screen, his 2-to-5 word guide.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_verbObject() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(!corpus.isEmpty, "No corpus collected.")

        let subject = "You name terminal tabs. You are shown the visible contents "
            + "of a terminal screen. Name the work the user is doing, not the "
            + "program they are using. Be specific: name the particular file, "
            + "service, project, or problem involved, not a generic activity."
        let variants: [(String, String)] = [
            ("subject", subject),
            // A: spell out the grammatical shape.
            ("verb+object", subject + " Phrase the title as a verb followed by the "
                + "specific thing it acts on."),
            // B: framed as an action, imperative-leaning.
            ("action", subject + " Write it as an action: a verb plus its object."),
            // C: terse formula.
            ("form", subject + " Use the form: verb + object."),
        ]

        print("\n=== Verb+object grade (\(corpus.count) records, +context, his guide) ===")
        for (index, record) in corpus.enumerated() {
            let user = record.context.isEmpty ? record.screen
                : record.context + "\n\nVisible screen:\n" + record.screen
            let subj = [record.job, record.cwd].compactMap { $0 }.joined(separator: " @ ")
            print("\n[\(index)] \(subj)  (logged: \(record.title ?? "nil"))")
            for (name, instructions) in variants {
                let title = try await AppleIntelligenceRunner.generate(
                    system: instructions, user: user, as: AuthorTabTitle.self)
                    .title.trimmingCharacters(in: .whitespacesAndNewlines)
                print("    \(name.padding(toLength: 12, withPad: " ", startingAt: 0)): \(title)")
            }
        }
        print("=== end verb+object grade ===\n")
    }

    // The bare verb+object nudge ran long, dropped Title Case, and occasionally
    // leaked a bare command. This retries it with the brevity + Title-Case
    // guardrails restored, to see if the shape survives once those are pinned.
    // Fed context+screen; his 2-to-5 word guide.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_verbObjectTight() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here (needs macOS 26 with Apple Intelligence enabled).")
        let corpus = AITabTitleCorpus.load()
        try XCTSkipUnless(!corpus.isEmpty, "No corpus collected.")

        let subject = "You name terminal tabs. You are shown the visible contents "
            + "of a terminal screen. Name the work the user is doing, not the "
            + "program they are using. Be specific: name the particular file, "
            + "service, project, or problem involved, not a generic activity."
        let variants: [(String, String)] = [
            ("subject", subject),
            // A: verb+object, with brevity + Title Case pinned back.
            ("vo-tight", subject + " Phrase it as a verb and its object, in Title "
                + "Case, at most three words."),
            // B: same but imperative verb, and forbid a bare command as the title.
            ("vo-imper", subject + " Phrase it as an action verb and its object in "
                + "Title Case, at most three words. Never answer with a bare "
                + "command name."),
        ]

        print("\n=== Verb+object (tight) grade (\(corpus.count) records) ===")
        for (index, record) in corpus.enumerated() {
            let user = record.context.isEmpty ? record.screen
                : record.context + "\n\nVisible screen:\n" + record.screen
            let subj = [record.job, record.cwd].compactMap { $0 }.joined(separator: " @ ")
            print("\n[\(index)] \(subj)  (logged: \(record.title ?? "nil"))")
            for (name, instructions) in variants {
                let title = try await AppleIntelligenceRunner.generate(
                    system: instructions, user: user, as: AuthorTabTitle.self)
                    .title.trimmingCharacters(in: .whitespacesAndNewlines)
                let len = title.count
                print("    \(name.padding(toLength: 10, withPad: " ", startingAt: 0)): \(title)  (\(len)c\(len > 40 ? " ⚠︎nil" : ""))")
            }
        }
        print("=== end verb+object (tight) grade ===\n")
    }

    // First input experiment for the pairwise-judge harness: does stripping
    // cross-record boilerplate (chrome/status lines that recur across many
    // captured screens and therefore can't distinguish one tab from another)
    // improve the on-device title? For each corpus record this generates two
    // titles - one from the raw screen, one from the boilerplate-stripped screen
    // - and writes pairs.jsonl for the Opus judge (judge_pairs.py). The context
    // is assembled through the shipping code path (home-abbreviated), so only
    // the screen differs between the two.
    @available(macOS 26, *)
    func test_appleIntelligence_boilerplateExperiment() async throws {
        try XCTSkipUnless(AIAvailabilityProbe.check(), "Apple Intelligence unavailable.")
        let records = AITabTitleCorpus.load()
        try XCTSkipUnless(records.count >= 5, "Need a corpus; collect captures first.")

        // A screen line is boilerplate if it recurs across many records. Purely
        // frequency-based so nothing is hardcoded per program (no "strip Claude
        // Code's status line") - that would overfit to this corpus.
        func lines(_ s: String) -> [String] {
            return s.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var recordCount: [String: Int] = [:]
        for r in records {
            for l in Set(lines(r.screen)) where !l.isEmpty {
                recordCount[l, default: 0] += 1
            }
        }
        let threshold = max(2, Int((Double(records.count) * 0.15).rounded()))
        let boilerplate = Set(recordCount.filter { $0.value >= threshold }.map { $0.key })

        func strip(_ s: String) -> String {
            return lines(s).filter { $0.isEmpty || !boilerplate.contains($0) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func context(_ r: AITabTitleRecord) -> String {
            let home = r.user.map { "/Users/\($0)" }
            return AITabTitleContext.assembleText(job: r.job, commandLine: r.commandLine,
                                                  atPrompt: r.atPrompt ?? false,
                                                  lastCommand: r.lastCommand,
                                                  recentCommands: r.recentCommands ?? [],
                                                  cwd: r.cwd,
                                                  user: r.user, host: r.host, home: home)
        }
        func title(_ ctx: String, _ screen: String) async throws -> String {
            let prompt = ctx.isEmpty ? screen : ctx + "\n\nVisible screen:\n" + screen
            return try await AppleIntelligenceRunner.generate(
                system: Self.instructionsB, user: prompt, as: HarnessTabTitle.self).title
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let corpusURL = AITabTitleCorpus.corpusFileURL(createDirectory: false) else {
            throw XCTSkip("No corpus dir")
        }
        let pairsURL = corpusURL.deletingLastPathComponent().appendingPathComponent("pairs.jsonl")
        var out = ""
        var totalStripFrac = 0.0
        for (i, r) in records.enumerated() {
            let ctx = context(r)
            let raw = r.screen
            let stripped = strip(raw)
            let rawLines = lines(raw).filter { !$0.isEmpty }.count
            let strippedLines = lines(stripped).filter { !$0.isEmpty }.count
            let frac = rawLines == 0 ? 0 : Double(rawLines - strippedLines) / Double(rawLines)
            totalStripFrac += frac
            let baseline: String
            let treatment: String
            do {
                baseline = try await title(ctx, raw)
                treatment = try await title(ctx, stripped)
            } catch {
                // The on-device model has a ~4096-token context; oversized
                // screens throw here (and in the app, silently produce no
                // title). Skip so the experiment completes; the count of skips
                // is itself a finding.
                print("[\(i)] skipped (\(error))")
                continue
            }
            // titleA = baseline (raw), titleB = treatment (stripped). The judge
            // sees the FULL raw context+screen and both titles anonymized.
            let record: [String: Any] = [
                "idx": i,
                "context": ctx,
                "screen": raw,
                "titleA": baseline,
                "titleB": treatment,
                "stripFrac": frac,
            ]
            let data = try JSONSerialization.data(withJSONObject: record)
            out += String(data: data, encoding: .utf8)! + "\n"
            print("[\(i)] strip=\(Int(frac*100))%  A=\(baseline)  B=\(treatment)")
        }
        try out.write(to: pairsURL, atomically: true, encoding: .utf8)
        print("\nboilerplate lines: \(boilerplate.count) (threshold \(threshold)/\(records.count) records)")
        print("avg screen lines stripped: \(Int(totalStripFrac / Double(records.count) * 100))%")
        print("wrote \(records.count) pairs -> \(pairsURL.path)")
    }

    // windowName-as-hint: does feeding the program's own (cleaned) title into
    // the context help the model, versus not? Both candidates are the on-device
    // model on the same screen; the only difference is whether the context
    // includes a "Window title:" line. Emits `job` so the judge segments Claude
    // vs non-Claude. The judge is shown only the real context+screen (no
    // windowName), so it can't be biased toward a title that parrots it.
    @available(macOS 26, *)
    func test_appleIntelligence_windowHintExperiment() async throws {
        try XCTSkipUnless(AIAvailabilityProbe.check(), "Apple Intelligence unavailable.")
        let records = AITabTitleCorpus.load()
        let candidates = records.enumerated().filter {
            !(($0.element.windowName ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        }
        try XCTSkipUnless(candidates.count >= 5, "Need records with a program-set windowName.")
        guard let corpusURL = AITabTitleCorpus.corpusFileURL(createDirectory: false) else {
            throw XCTSkip("No corpus dir")
        }
        let pairsURL = corpusURL.deletingLastPathComponent().appendingPathComponent("pairs_hint.jsonl")

        func context(_ r: AITabTitleRecord) -> String {
            let home = r.user.map { "/Users/\($0)" }
            return AITabTitleContext.assembleText(job: r.job, commandLine: r.commandLine,
                                                  atPrompt: r.atPrompt ?? false,
                                                  lastCommand: r.lastCommand,
                                                  recentCommands: r.recentCommands ?? [],
                                                  cwd: r.cwd,
                                                  user: r.user, host: r.host, home: home)
        }
        func clean(_ s: String) -> String {
            var t = Substring(s)
            while let f = t.first, !f.isLetter, !f.isNumber { t = t.dropFirst() }
            return t.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
                .joined(separator: " ")
        }
        func title(_ ctx: String, _ screen: String) async -> String {
            return ((try? await AppleIntelligenceRunner.generateTabTitle(
                instructions: Self.instructionsB, context: ctx, screen: screen,
                as: HarnessTabTitle.self).title)?
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        }

        var out = ""
        for (idx, r) in candidates {
            let base = context(r)
            let hinted = base.isEmpty
                ? "Window title: \(clean(r.windowName ?? ""))"
                : base + "\nWindow title: \(clean(r.windowName ?? ""))"
            let a = await title(base, r.screen)
            let b = await title(hinted, r.screen)
            // Judge sees the real (unhinted) context + screen only.
            let rec: [String: Any] = ["idx": idx, "job": r.job ?? "",
                                      "context": base, "screen": r.screen,
                                      "titleA": a, "titleB": b]
            out += String(data: try JSONSerialization.data(withJSONObject: rec), encoding: .utf8)! + "\n"
            print("[\(idx)] \(r.job ?? "?")  base=\(a)  +hint=\(b)")
        }
        try out.write(to: pairsURL, atomically: true, encoding: .utf8)
        print("wrote \(candidates.count) pairs -> \(pairsURL.path)")
    }

    // Tests whether the best algorithm differs by session type: for records
    // where the program set its own title (windowName), compares the on-device
    // model-on-screen title (titleA) against the cleaned program title (titleB).
    // Emits `job` per pair so the judge can report Claude vs non-Claude
    // separately - the hypothesis being that Claude/vim sessions want the
    // program title while title-less shells want the model.
    @available(macOS 26, *)
    func test_appleIntelligence_windowNameExperiment() async throws {
        try XCTSkipUnless(AIAvailabilityProbe.check(), "Apple Intelligence unavailable.")
        let records = AITabTitleCorpus.load()
        let candidates = records.enumerated().filter {
            !(($0.element.windowName ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        }
        try XCTSkipUnless(candidates.count >= 5, "Need records with a program-set windowName.")
        guard let corpusURL = AITabTitleCorpus.corpusFileURL(createDirectory: false) else {
            throw XCTSkip("No corpus dir")
        }
        let pairsURL = corpusURL.deletingLastPathComponent().appendingPathComponent("pairs_window.jsonl")

        func context(_ r: AITabTitleRecord) -> String {
            let home = r.user.map { "/Users/\($0)" }
            return AITabTitleContext.assembleText(job: r.job, commandLine: r.commandLine,
                                                  atPrompt: r.atPrompt ?? false,
                                                  lastCommand: r.lastCommand,
                                                  recentCommands: r.recentCommands ?? [],
                                                  cwd: r.cwd,
                                                  user: r.user, host: r.host, home: home)
        }
        // Minimal, general cleaning: drop leading non-alphanumeric junk (the
        // Braille/spinner glyphs Claude Code prepends) and collapse whitespace.
        // No per-program rules.
        func clean(_ s: String) -> String {
            var t = Substring(s)
            while let f = t.first, !f.isLetter, !f.isNumber { t = t.dropFirst() }
            return t.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
                .joined(separator: " ")
        }

        var out = ""
        for (idx, r) in candidates {
            let model = ((try? await AppleIntelligenceRunner.generateTabTitle(
                instructions: Self.instructionsB, context: context(r), screen: r.screen,
                as: HarnessTabTitle.self).title)?
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            let programTitle = clean(r.windowName ?? "")
            let rec: [String: Any] = ["idx": idx, "job": r.job ?? "",
                                      "context": context(r), "screen": r.screen,
                                      "titleA": model, "titleB": programTitle]
            out += String(data: try JSONSerialization.data(withJSONObject: rec), encoding: .utf8)! + "\n"
            print("[\(idx)] \(r.job ?? "?")  model=\(model)  window=\(programTitle)")
        }
        try out.write(to: pairsURL, atomically: true, encoding: .utf8)
        print("wrote \(candidates.count) pairs -> \(pairsURL.path)")
    }

    // Measures the token-budgeted trim: baseline is the raw path (whole screen,
    // which throws exceededContextWindowSize on oversized screens -> no title),
    // treatment is generateTabTitle (whitespace-condensed + trimmed to fit).
    // Writes pairs_trim.jsonl for the pairwise judge. Overflow baselines are
    // recorded as an empty title so the judge auto-awards the treatment.
    @available(macOS 26, *)
    func test_appleIntelligence_trimExperiment() async throws {
        try XCTSkipUnless(AIAvailabilityProbe.check(), "Apple Intelligence unavailable.")
        let records = AITabTitleCorpus.load()
        try XCTSkipUnless(records.count >= 5, "Need a corpus; collect captures first.")
        guard let corpusURL = AITabTitleCorpus.corpusFileURL(createDirectory: false) else {
            throw XCTSkip("No corpus dir")
        }
        let pairsURL = corpusURL.deletingLastPathComponent().appendingPathComponent("pairs_trim.jsonl")

        func context(_ r: AITabTitleRecord) -> String {
            let home = r.user.map { "/Users/\($0)" }
            return AITabTitleContext.assembleText(job: r.job, commandLine: r.commandLine,
                                                  atPrompt: r.atPrompt ?? false,
                                                  lastCommand: r.lastCommand,
                                                  recentCommands: r.recentCommands ?? [],
                                                  cwd: r.cwd,
                                                  user: r.user, host: r.host, home: home)
        }
        var out = ""
        var overflowCount = 0
        for (i, r) in records.enumerated() {
            let ctx = context(r)
            // Baseline: the current raw path.
            var baseline = ""
            do {
                let p = ctx.isEmpty ? r.screen : ctx + "\n\nVisible screen:\n" + r.screen
                baseline = try await AppleIntelligenceRunner.generate(
                    system: Self.instructionsB, user: p, as: HarnessTabTitle.self).title
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                overflowCount += 1  // large screen: raw path yields no title
            }
            // Treatment: condensed + token-budget trimmed.
            let treatment = ((try? await AppleIntelligenceRunner.generateTabTitle(
                instructions: Self.instructionsB, context: ctx, screen: r.screen,
                as: HarnessTabTitle.self).title)?
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
            let rec: [String: Any] = ["idx": i, "context": ctx, "screen": r.screen,
                                      "titleA": baseline, "titleB": treatment]
            out += String(data: try JSONSerialization.data(withJSONObject: rec), encoding: .utf8)! + "\n"
            print("[\(i)] base=\(baseline.isEmpty ? "<overflow>" : baseline)  trim=\(treatment)")
        }
        try out.write(to: pairsURL, atomically: true, encoding: .utf8)
        print("\noverflowed raw path (no title): \(overflowCount)/\(records.count)")
        print("wrote \(records.count) pairs -> \(pairsURL.path)")
    }

    // Generates the on-device title for each record in sample20.jsonl (written by
    // scratchpad/opus_titles.py) using the shipping instructions, so its output
    // can be compared head-to-head with Opus 4.8 on the same 20 real inputs.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_sample20() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here.")
        guard let corpus = AITabTitleCorpus.corpusFileURL(createDirectory: false) else {
            throw XCTSkip("No corpus dir")
        }
        let sampleURL = corpus.deletingLastPathComponent().appendingPathComponent("sample20.jsonl")
        guard let content = try? String(contentsOf: sampleURL, encoding: .utf8) else {
            throw XCTSkip("No sample20.jsonl; run scratchpad/opus_titles.py first.")
        }

        print("\n=== Apple Intelligence sample20 ===")
        var i = 0
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let context = obj["context"] as? String ?? ""
            let screen = obj["screen"] as? String ?? ""
            let prompt = context.isEmpty ? screen : context + "\n\nVisible screen:\n" + screen
            let title = try await AppleIntelligenceRunner.generate(
                system: Self.instructionsB, user: prompt, as: HarnessTabTitle.self).title
                .trimmingCharacters(in: .whitespacesAndNewlines)
            print("AISAMPLE\t\(i)\t\(title)")
            i += 1
        }
        print("=== end sample20 ===\n")
    }

    // Directly tests the idea that when idle at a shell prompt, telling the model
    // which command produced the screen stops it from lifting a filename. Same
    // directory listing, generated with and without a "last command run" line.
    @available(macOS 26, *)
    func test_appleIntelligence_tabTitle_lastCommandHelps() async throws {
        try XCTSkipUnless(
            AIAvailabilityProbe.check(),
            "Apple Intelligence is not available here.")

        // A bare `ls -F` style listing: no verbs, just decorated filenames. This
        // is the shape that made the live model answer "xgettext.pl".
        let screen = """
            z[255] applmiddle*   iconutil*     pip3.12*      splain5.36*
            afconvert*           ifconfig*     pmset*        sqlite3*
            afinfo*              install*      pod*          ssh*
            banner*              java*         postfix*      xgettext.pl*
            basename*            jobs*         printf*       xml2-config*
            bc*                  join*         profiles*     xmllint*
            cat*                 keychain*     python3*      zip*
            ~ %
            """
        let variant = Self.instructionsB
        let dir = "Directory: /usr/bin"

        let withoutLast = "At a shell prompt.\n\(dir)\n\nVisible screen:\n\(screen)"
        let withLast = "At a shell prompt. The last command run was: ls -F /usr/bin\n\(dir)\n\nVisible screen:\n\(screen)"

        let a = try await AppleIntelligenceRunner.generate(
            system: variant, user: withoutLast, as: HarnessTabTitle.self).title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let b = try await AppleIntelligenceRunner.generate(
            system: variant, user: withLast, as: HarnessTabTitle.self).title
            .trimmingCharacters(in: .whitespacesAndNewlines)

        print("\n=== last-command A/B ===")
        print("without last command: \(Self.looksLikeScreenLeak(title: a, screen: screen) ? "⚠︎leak " : "")\(a)")
        print("with last command:    \(Self.looksLikeScreenLeak(title: b, screen: screen) ? "⚠︎leak " : "")\(b)")
        print("=== end last-command A/B ===\n")

        // Reported, not asserted: the on-device model is not fully deterministic
        // across prompts, and this probe's job is to show the effect, not gate CI.
    }

    // Heuristic for the "ran ls, got a random filename as the title" failure: a
    // single-token title (no spaces) that appears as a substring of the screen
    // is almost certainly copied text, not a name for the work. Substring rather
    // than exact-token because ls -F decorates names (xgettext.pl -> xgettext.pl*)
    // and columns are tab-padded. Multi-word Title Case labels are exempt: they
    // are paraphrases, not lifted tokens.
    private static func looksLikeScreenLeak(title: String, screen: String) -> Bool {
        guard !title.contains(" "), title.count >= 3 else {
            return false
        }
        return screen.lowercased().contains(title.lowercased())
    }
}

private extension String {
    func padded(_ width: Int) -> String {
        if count >= width {
            return self
        }
        return self + String(repeating: " ", count: width - count)
    }
}
