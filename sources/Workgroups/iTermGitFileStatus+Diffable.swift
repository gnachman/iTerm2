//
//  iTermGitFileStatus+Diffable.swift
//  iTerm2SharedARC
//
//  Shared "is this entry something git difftool would actually show"
//  predicate. Used by the workgroup .diff-mode deferred-launch gate
//  and (eventually) by CCDiffSelectorItem's hasChanges computation;
//  keeping the rule in one place prevents the two from drifting.
//

import Foundation

extension iTermGitFileStatus {
    // Mirrors the selector's filter rule: a status row is diffable iff
    // it has a staged change OR an unstaged change that is NOT just
    // "untracked". Untracked-only entries are excluded because
    // git difftool does not show untracked content.
    var representsDiffableChange: Bool {
        if indexStatus != .none {
            return true
        }
        return workdirStatus != .none && workdirStatus != .untracked
    }
}

extension Sequence where Element == iTermGitFileStatus {
    var containsDiffableChange: Bool {
        return contains { $0.representsDiffableChange }
    }
}
