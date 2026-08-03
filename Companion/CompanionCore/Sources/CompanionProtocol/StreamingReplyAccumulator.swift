//
//  StreamingReplyAccumulator.swift
//  CompanionCore
//
//  Assembles the preview text of a streamed agent reply for the session-view
//  notification. The Mac streams a reply as a `.begin(initialMessage)` snapshot
//  (the FIRST chunk, delivered as a whole message) followed by `.append` /
//  `.appendAttachment` deltas that reuse the begin message's id. So the first
//  chunk must SEED the accumulation, or later deltas concatenate onto empty and
//  the leading chunk is dropped ("don't have a reliable way" instead of "I don't
//  have a reliable way").
//

import Foundation

public struct StreamingReplyAccumulator {
    public enum Chunk: Equatable {
        /// The first chunk of a reply (a `.begin` snapshot / a whole non-streamed
        /// message). `isLabel` distinguishes a raw-text seed (plainText/markdown -
        /// later text deltas concatenate onto it) from a RENDERED LABEL preview
        /// (a multipart/attachment "📄 name" - later raw text must NOT be glued
        /// onto the label; it replaces it). A single streamed reply reuses one id
        /// across chunk types, so an attachment-first reply that then streams text
        /// would otherwise produce "📄 report.pdfHere is the summary".
        case begin(id: String, preview: String, isLabel: Bool)
        /// A streamed text delta reusing the begin id.
        case appendText(id: String, delta: String)
        /// A streamed attachment delta reusing the begin id (no text of its own).
        /// `isLabel` is the attachment's label-ness: true for a rendered "📄 name"
        /// (a following text delta REPLACES it), false for real text like a .code
        /// attachment's body (a following delta EXTENDS it) - matching the
        /// whole-message multipart path.
        case appendAttachment(id: String, previewIfEmpty: String, isLabel: Bool)

        /// The message id this chunk assembles under (all chunk types reuse it).
        public var id: String {
            switch self {
            case .begin(let id, _, _), .appendText(let id, _), .appendAttachment(let id, _, _):
                return id
            }
        }
    }

    private struct Entry {
        var text: String
        /// True while `text` is a rendered label (not real streamed text), so the
        /// next text delta replaces it rather than concatenating.
        var isLabel: Bool
        /// Whether a `.begin` snapshot has EVER seeded this id (sticky - append
        /// deltas do not clear it). Distinguishes two whole-message snapshots that
        /// don't share a prefix (a begin already seeded, so a non-prefix begin is a
        /// revised/re-rendered snapshot -> REPLACE with newest) from a reordered
        /// LEADING chunk assembled purely from append deltas with no begin yet
        /// (-> PREPEND so it isn't dropped). Using "ever seeded" not "last set by"
        /// so a begin followed by appends still REPLACES on the next begin, rather
        /// than concatenating ("The answer is 6The answer is 5 maybe").
        var seededByBegin: Bool
    }
    private var byID: [String: Entry] = [:]

    public init() {}

    /// Update the accumulation for a chunk and return the current preview text
    /// for its message.
    public mutating func accumulate(_ chunk: Chunk) -> String {
        switch chunk {
        case .begin(let id, let preview, let isLabel):
            // A `.begin` reusing an existing id is one of a few things:
            //  - a GROWING WHOLE-MESSAGE SNAPSHOT (the common Mac mode): repeated
            //    full-text deliveries under one uniqueID, each a superset of the
            //    last ("I", "I don't", "I don't know"). REPLACE with the newer.
            //  - a SHORTER/EQUAL replay (or a substance-free reasoning snapshot
            //    that strips to ""). KEEP the longer accumulation, don't truncate
            //    or wipe it.
            //  - an attachment-first reply whose next snapshot adds text: the
            //    accumulation is a rendered LABEL ("📄 name") and the new preview
            //    is real text. REPLACE (the same label->text rule appendText
            //    uses), never glue "Here is the summary📄 name".
            //  - a reordered/replayed LEADING chunk that arrived after its append
            //    deltas (rare, non-label). PREPEND so it isn't dropped.
            if let existing = byID[id], !existing.text.isEmpty {
                if preview.hasPrefix(existing.text) {
                    byID[id] = Entry(text: preview, isLabel: isLabel, seededByBegin: true)   // grew
                    return preview
                }
                if existing.text.hasPrefix(preview) {
                    return existing.text                                // shorter/equal (or empty) replay
                }
                if existing.isLabel, !isLabel {
                    byID[id] = Entry(text: preview, isLabel: false, seededByBegin: true)     // label -> real text
                    return preview
                }
                if !existing.isLabel, isLabel {
                    // Real text already accumulated, and this snapshot is only an
                    // attachment LABEL ("📄 name"). Keep the text - the label must
                    // not replace it or glue on ("📄 report.pdfHere is the
                    // summary"). Mirrors the appendAttachment rule (label only when
                    // empty).
                    return existing.text
                }
                if !existing.seededByBegin, !isLabel {
                    // existing was assembled purely from append deltas (no begin has
                    // seeded it); this begin is the reordered LEADING chunk that
                    // arrived late. Prepend so it isn't dropped. Only for NON-label
                    // begins: two attachment LABELS (existing label from an
                    // appendAttachment, then a differing label begin) would otherwise
                    // reach here and concatenate reversed ("[file] b[file] a"); a label
                    // begin has no leading-chunk semantics, so it falls through to the
                    // newest-wins replace below.
                    let merged = Entry(text: preview + existing.text, isLabel: isLabel, seededByBegin: true)
                    byID[id] = merged
                    return merged.text
                }
                // A begin has already seeded this id, so a non-prefix begin is a
                // revised/re-rendered snapshot (a revised token / re-normalized
                // punctuation). Newest wins; never concatenate.
                byID[id] = Entry(text: preview, isLabel: isLabel, seededByBegin: true)
                return preview
            }
            byID[id] = Entry(text: preview, isLabel: isLabel, seededByBegin: true)
            return preview
        case .appendText(let id, let delta):
            if var entry = byID[id], !entry.isLabel {
                // Append IN PLACE: drop the dictionary's reference first so `entry`
                // uniquely owns the string buffer, making append amortized O(1)
                // instead of copying the whole accumulation each token (the Mac
                // streams one delta per vendor chunk, so `existing.text + delta`
                // was O(N) per token / O(N^2) per reply on the main actor).
                // Preserve seededByBegin: an append after a begin must NOT make a
                // later non-prefix begin look like a reorder (it's a revision).
                byID[id] = nil
                entry.text.append(delta)
                byID[id] = entry
            } else {
                // No prior text, or the seed was a LABEL that this text replaces.
                // Preserve seededByBegin: if a .begin seeded this id (even as a
                // label), a later non-prefix begin is a revision, not a reordered
                // leading chunk - so it must still REPLACE, not prepend.
                let wasSeededByBegin = byID[id]?.seededByBegin ?? false
                byID[id] = Entry(text: delta, isLabel: false, seededByBegin: wasSeededByBegin)
            }
            return byID[id]?.text ?? ""
        case .appendAttachment(let id, let previewIfEmpty, let isLabel):
            let existing = byID[id]?.text ?? ""
            if existing.isEmpty {
                // Preserve seededByBegin (mirror appendText): if a .begin already
                // seeded this id - even to empty (reasoning-only) - a later non-prefix
                // begin is a REVISION, not a reordered leading chunk, and must REPLACE
                // rather than prepend ("Revised textcode body").
                byID[id] = Entry(text: previewIfEmpty, isLabel: isLabel,
                                 seededByBegin: byID[id]?.seededByBegin ?? false)
                return previewIfEmpty
            }
            return existing
        }
    }

    /// The assembled text for a message id, or nil if none has been seen.
    public func text(for id: String) -> String? {
        byID[id]?.text
    }

    public mutating func reset() {
        byID.removeAll()
    }
}
