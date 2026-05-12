//
//  MomentermGitGraphModel.swift
//  iTerm2
//
//  Models the `git log --all` DAG for the bottom Git Graph panel and
//  assigns each commit to a column ("lane") using a streaming
//  first-fit algorithm. Edges are emitted as commit → parent pairs so
//  the view can render the graph by drawing a Bezier between two
//  positioned points without keeping its own lane state.
//

import Foundation

struct MomentermGitCommit: Equatable {
    let sha: String           // full sha
    let parents: [String]     // full parent shas
    let refs: [String]        // decorated refs, e.g. "HEAD -> master", "origin/master"
    let summary: String
    let author: String
    let date: Date

    var shortSha: String { String(sha.prefix(7)) }
    var hasHEAD: Bool { refs.contains { $0.contains("HEAD") } }
}

struct MomentermGitGraphLayout {
    struct Node {
        let commit: MomentermGitCommit
        let column: Int
        let row: Int
    }

    struct Edge {
        let from: (column: Int, row: Int)
        let to: (column: Int, row: Int)
    }

    let nodes: [Node]
    let edges: [Edge]
    /// 0-based maximum column index actually used, or -1 if empty.
    let maxColumn: Int

    static let empty = MomentermGitGraphLayout(nodes: [], edges: [], maxColumn: -1)
}

enum MomentermGitGraphLayouter {

    /// Lay out commits in the order received (already topologically sorted by
    /// `git log`, newest first). Each commit's column is assigned greedily:
    ///  1. If any active lane was expecting this sha, take the leftmost one.
    ///  2. Otherwise, reuse the first free lane, or open a new one.
    ///  3. After placing, declare the commit's first parent into the same
    ///     lane (continuation), and additional parents into new lanes.
    /// Edges are emitted as commit→parent pairs.
    static func layout(commits: [MomentermGitCommit]) -> MomentermGitGraphLayout {
        guard !commits.isEmpty else { return .empty }

        var lanes: [String?] = []          // expected next sha per lane
        var positionBySha: [String: (column: Int, row: Int)] = [:]
        var nodes: [MomentermGitGraphLayout.Node] = []

        for (row, commit) in commits.enumerated() {
            // 1. Pick a column.
            var column: Int
            if let idx = lanes.firstIndex(where: { $0 == commit.sha }) {
                column = idx
                lanes[idx] = nil
            } else if let idx = lanes.firstIndex(where: { $0 == nil }) {
                column = idx
            } else {
                column = lanes.count
                lanes.append(nil)
            }

            // 2. Any other lanes still expecting this sha are converged into our column.
            for i in 0..<lanes.count where lanes[i] == commit.sha {
                lanes[i] = nil
            }

            nodes.append(.init(commit: commit, column: column, row: row))
            positionBySha[commit.sha] = (column, row)

            // 3. Place each parent.
            for (pIdx, parent) in commit.parents.enumerated() {
                if lanes.contains(parent) {
                    continue  // already expected somewhere; no change needed
                }
                if pIdx == 0 && lanes.indices.contains(column) && lanes[column] == nil {
                    lanes[column] = parent
                } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[free] = parent
                } else {
                    lanes.append(parent)
                }
            }
        }

        // Edges are simply commit → parent. Skip parents we never positioned
        // (parents outside the queried window).
        var edges: [MomentermGitGraphLayout.Edge] = []
        for node in nodes {
            guard let from = positionBySha[node.commit.sha] else { continue }
            for parent in node.commit.parents {
                guard let to = positionBySha[parent] else { continue }
                edges.append(.init(from: from, to: to))
            }
        }

        let maxColumn = (nodes.map { $0.column }.max() ?? -1)
        return MomentermGitGraphLayout(nodes: nodes, edges: edges, maxColumn: maxColumn)
    }
}

// MARK: - git log parser

enum MomentermGitLogParser {
    /// Each input line is the output of `git log --all --format='%H|%P|%D|%an|%at|%s' --topo-order -200`.
    /// Pipes are safe field separators because git never emits them in those fields literally for these formats.
    static func parse(_ text: String) -> [MomentermGitCommit] {
        var commits: [MomentermGitCommit] = []
        for raw in text.split(whereSeparator: { $0 == "\n" }) {
            let parts = raw.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 6 else { continue }
            let sha = parts[0]
            let parents = parts[1].split(whereSeparator: { $0 == " " }).map(String.init)
            let refs: [String] = parts[2].isEmpty ? [] : parts[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let author = parts[3]
            let date = Date(timeIntervalSince1970: TimeInterval(parts[4]) ?? 0)
            let summary = parts[5]
            commits.append(MomentermGitCommit(
                sha: sha,
                parents: parents,
                refs: refs,
                summary: summary,
                author: author,
                date: date
            ))
        }
        return commits
    }
}
