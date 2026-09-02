//
//  AITabTitleCorpus.swift
//  iTerm2
//
//  A local, opt-in corpus of AI tab-title generations. When the
//  `logAITabTitleCorpus` advanced setting is on, every on-device generation
//  appends one JSON line capturing the exact inputs (context + visible screen),
//  the system prompt used, the model, the produced title, and timing to
//  <app-support>/AITabTitleCorpus/corpus.jsonl, where <app-support> respects the
//  running -suite (the real app writes to .../iTerm2/, a `-suite foo` dev build to
//  .../foo/).
//
//  The point is iteration: real sessions produce real failure cases (running
//  `ls` and getting a random filename as the title, say). Capturing the input
//  that produced a bad title lets us replay it against a new prompt or model
//  offline and see whether the fix actually helps, without waiting to stumble
//  on the same screen again. The grader in AILiveAppleIntelligenceTabTitle
//  reads this file back.
//
//  Off by default, never synced, and local only, but it writes screen contents
//  verbatim: it is a developer tool, not something to leave running.
//

import Foundation

// One generation. Codable so a line round-trips through the grader unchanged.
// Optional fields are absent when the session didn't have that signal (no
// remote host, model returned nothing, etc.).
struct AITabTitleRecord: Codable {
    var timestamp: TimeInterval
    var trigger: String            // what prompted this generation: "first" |
                                   // "osc" | "frame" | "content" | "apiSnapshot"
    var job: String?
    var commandLine: String?
    var atPrompt: Bool?            // idle at a shell prompt (shell integration)
    var lastCommand: String?      // the previously run command, when atPrompt
    // Recent shell command history, oldest first. Fed to the model outside the
    // alternate screen so it can infer the task from a sequence of commands
    // instead of over-indexing on the single last one. At a prompt it ends with
    // the last finished command; with a command running in the foreground the
    // running command is shown separately and this holds the ones before it.
    // Optional with a nil default so older corpus lines still decode.
    var recentCommands: [String]? = nil
    var cwd: String?
    var user: String?
    var host: String?
    // The program-set OSC 2 window title at generation time, captured for offline A/B
    // in the harness (does including the window title improve the generated name?) but
    // not fed to the model. Optional with a nil default so older corpus lines still
    // decode. (Other candidate metadata - icon name, git branch, tmux names - is not
    // captured until a harness experiment actually consumes it.)
    var windowName: String? = nil
    var screen: String
    var context: String            // the assembled context block fed to the model
    var instructions: String       // the system prompt used
    var model: String              // e.g. "apple-on-device"
    var title: String?             // the generated title (nil if the model failed)
    var latencyMs: Int
}

final class AITabTitleCorpus {
    static let shared = AITabTitleCorpus()

    // Serializes appends so concurrent sessions don't interleave partial lines.
    private let queue = DispatchQueue(label: "com.googlecode.iterm2.ai-tab-title-corpus")

    var isEnabled: Bool {
        return iTermAdvancedSettingsModel.logAITabTitleCorpus()
    }

    static func corpusFileURL(createDirectory: Bool) -> URL? {
        // Respects the running -suite: applicationSupportDirectory is namespaced
        // by the app's defaults suite, so a `-suite iterm2-alt7` dev build keeps
        // its corpus under .../iterm2-alt7/ and the real app (no suite) writes to
        // .../iTerm2/. That isolates dogfood runs from the daily driver instead of
        // silently interleaving them.
        guard let appSupport = FileManager.default.applicationSupportDirectory() else {
            return nil
        }
        let dir = URL(fileURLWithPath: appSupport).appendingPathComponent("AITabTitleCorpus")
        if createDirectory {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("corpus.jsonl")
    }

    // The canonical (no-suite) corpus the real app and the AutoLaunch capture
    // script write to. The offline grader runs under the iterm2-tests suite, so
    // its own suite path is empty; it falls back to this so it can still grade the
    // daily-driver corpus without anyone copying files around.
    static func canonicalCorpusFileURL() -> URL {
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/iTerm2/AITabTitleCorpus/corpus.jsonl")
    }

    // Outcome of a single atomic-append attempt. See atomicAppend(totalBytes:writeOnce:).
    enum AtomicAppendOutcome: Equatable {
        case complete        // the whole record was written in one atomic O_APPEND write
        case partial(Int)    // wrote 0..<total; see the data-loss note in atomicAppend
        case failed          // write() reported an unrecoverable error
    }

    // Bound on EINTR retries. On a regular file write() essentially never returns
    // EINTR, so this only guards against a pathological busy-loop; it is not an
    // expected path.
    static let maxInterruptedRetries = 100

    // Writes a record with a SINGLE atomic O_APPEND write. Concurrent cross-process
    // correctness (the shipping app and tests/ai_tab_title_capture.py append to the
    // same file) rests on each line being exactly one write: retrying a partial write
    // re-appends the leftover bytes at the NEW end-of-file, where a concurrent writer
    // may already have appended its own full line, splicing one record into the middle
    // of another. So retry ONLY when the call was interrupted before writing anything
    // (EINTR, nothing written, bounded by maxInterruptedRetries); a genuine partial
    // write returns .partial and the caller drops the record.
    //
    // Data-loss note: on a partial write we leave `n` bytes with no trailing newline on
    // disk, and under the concurrent multi-writer use above the NEXT writer's complete
    // "{...}\n" is appended right after them, so load() sees one fused physical line
    // "<partial>{...}\n" that fails to decode - dropping not just this record but the
    // following writer's valid one too. We do NOT try to recover (truncating back to the
    // last newline is itself racy against concurrent appenders and could clobber a good
    // line). Partial writes on a regular file only arise from ENOSPC/RLIMIT_FSIZE, i.e.
    // catastrophic conditions, and this is an off-by-default developer tool, so the
    // window is accepted rather than papered over. `writeOnce` returns (n, interrupted):
    // n < 0 on error, interrupted == true iff EINTR. Pure and injectable so the policy
    // is testable.
    static func atomicAppend(totalBytes: Int,
                             writeOnce: () -> (n: Int, interrupted: Bool)) -> AtomicAppendOutcome {
        var interruptedRetries = 0
        while true {
            let result = writeOnce()
            if result.n < 0 {
                if result.interrupted && interruptedRetries < maxInterruptedRetries {
                    interruptedRetries += 1
                    continue   // nothing was written; a clean retry cannot splice
                }
                return .failed
            }
            if result.n >= totalBytes {
                return .complete
            }
            return .partial(result.n)
        }
    }

    func log(_ record: AITabTitleRecord) {
        guard isEnabled else {
            return
        }
        queue.async {
            guard let url = Self.corpusFileURL(createDirectory: true) else {
                return
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            guard var data = try? encoder.encode(record) else {
                return
            }
            data.append(0x0A)  // newline delimiter for JSONL
            // Open with O_APPEND (kernel-atomic append), NOT a seek-then-write. By
            // design the canonical corpus.jsonl is written by BOTH the shipping app and
            // the Python capture script (tests/ai_tab_title_capture.py, which appends
            // with O_APPEND) concurrently. A FileHandle seekToEnd()+write is a
            // cross-process lost-update race: another writer can append between our
            // seek and write, and we overwrite it at the now-stale offset. O_CREAT here
            // (not fileExists-then-createFile, which TRUNCATES and would discard a
            // file another writer just created) makes creation atomic too. Each
            // O_APPEND write of a single line is atomic up to PIPE_BUF/filesystem
            // limits, so lines never interleave.
            let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard fd >= 0 else {
                return
            }
            defer { close(fd) }
            data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                guard let base = buffer.baseAddress, buffer.count > 0 else {
                    return
                }
                let outcome = Self.atomicAppend(totalBytes: buffer.count) {
                    let n = write(fd, base, buffer.count)
                    return (n, n < 0 && errno == EINTR)
                }
                switch outcome {
                case .complete:
                    break
                case .partial(let n):
                    DLog("AI corpus: short write \(n)/\(buffer.count); dropped record to preserve append atomicity")
                case .failed:
                    DLog("AI corpus: write failed: \(String(cString: strerror(errno)))")
                }
            }
        }
    }

    // Reads the corpus back for offline grading. Tolerates malformed lines
    // (a partially written tail line, a hand-edited file) by skipping them.
    static func load() -> [AITabTitleRecord] {
        // Prefer this suite's own corpus; fall back to the canonical location so
        // the grader (a different suite) still finds the daily-driver corpus.
        let suiteURL = corpusFileURL(createDirectory: false)
        let content: String
        if let suiteURL, let s = try? String(contentsOf: suiteURL, encoding: .utf8) {
            content = s
        } else if let s = try? String(contentsOf: canonicalCorpusFileURL(), encoding: .utf8) {
            content = s
        } else {
            return []
        }
        let decoder = JSONDecoder()
        var records: [AITabTitleRecord] = []
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let record = try? decoder.decode(AITabTitleRecord.self, from: data) else {
                continue
            }
            records.append(record)
        }
        return records
    }
}
