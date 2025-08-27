//
//  TabularFormatter.swift
//  iTerm2
//
//  Created by George Nachman on 8/26/25.
//

@objc(iTermTabularFormatter)
class TabularFormatter: NSObject {
    private struct Column {
        let label: String
        let leftAligned: Bool
        var reservedWidth = 0
    }
    private var columns = [Column]()
    private var rows = [[String]]()

    @objc
    func defineColumn(label: String, leftAligned: Bool) {
        columns.append(Column(label: label, leftAligned: leftAligned))
    }

    @objc
    func add(row: [String]) {
        rows.append(row)
    }

    @objc
    func formattedAsText() -> String {
        var maxLengths = columns.map { $0.label.count }
        for row in rows {
            let lengths = row.map { $0.count }
            maxLengths = zip(maxLengths, lengths).map {
                max($0.0, $0.1)
            }
        }
        for (i, length) in maxLengths.enumerated() {
            columns[i].reservedWidth = length
        }
        var parts = [String]()
        parts.append(pad(strings: columns.map { $0.label }))
        for row in rows {
            parts.append(pad(strings: row))
        }
        return parts.joined(separator: "\n")
    }

    private func pad(strings: [String]) -> String {
        return columns.enumerated().map { i, column in
            pad(strings[i], to: column.reservedWidth, leftAligned: column.leftAligned)
        }.joined(separator: "  ")
    }

    private func pad(_ string: String, to width: Int, leftAligned: Bool) -> String {
        if string.count >= width {
            return string
        }
        let padding = String(repeating: " ", count: width - string.count)
        if leftAligned {
            return string + padding
        } else {
            return padding + string
        }
    }
}
