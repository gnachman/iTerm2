//
//  PathExtractor.swift
//  iTerm2
//
//  Created by George Nachman on 4/10/25.
//


// Identifies likely paths in a string.
class PathExtractor {
    struct Candidate {
        var string: String
        var range: VT100GridCoordRange
        var expandedPath: String
    }

    // Holds one composed character with its grid coordinate.
    private var currentLine: [(char: String, coord: VT100GridCoord)] = []

    // A candidate path is recorded as a tuple of the path string and its coordinate range.
    private(set) var possiblePaths: [Candidate] = []

    // Allowed characters for paths, including all Unicode letters & digits plus “/”, “_”, “.” and “-”.
    private let allowedCharacterSet: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "/_.-")
        set.insert(Unicode.Scalar(UInt8(DWC_RIGHT)))
        set.insert(Unicode.Scalar(UInt8(DWC_SKIP)))
        return set
    }()
}

// Public API
extension PathExtractor {
    // Append one composed character and its grid coordinate.
    // Each call represents the next character in the current prompt line.
    func add(string: String, coord: VT100GridCoord) {
        currentLine.append((char: string, coord: coord))
    }

    // newLine indicates the end of the current prompt line. Scan the line for candidate paths.
    func newLine() {
        let privateRange = (UInt32(ITERM2_PRIVATE_BEGIN)...UInt32(ITERM2_PRIVATE_END))
        var i = 0
        while i < currentLine.count {
            let currentChar = currentLine[i].char
            // Candidate must start with "/" or "~", and must be at a token boundary.
            if (currentChar == "/" || currentChar == "~") && (i == 0 || !characterIsValidInPath(currentLine[i - 1].char)) {
                let startIndex = i
                var j = i
                // Consume allowed characters.
                while j < currentLine.count, characterIsValidInPath(currentLine[j].char) {
                    j += 1
                }
                let candidateString = currentLine[startIndex..<j]
                    .filter {
                        !privateRange.contains($0.char.it_firstUnicodeScalarValue ?? 0)
                    }
                    .map { $0.char }
                    .joined()
                let startCoord = currentLine[startIndex].coord
                let endCoord: VT100GridCoord = {
                    if j < currentLine.count {
                        return currentLine[j].coord
                    }
                    // To get here, j==currentLine.count. We can prove that currentLine.count>0 because
                    // otherwise the outermost while loop could not have been entered. Therefore
                    // it is safe to access j - 1.
                    var penultimate = currentLine[j - 1].coord
                    penultimate.x += 1
                    return penultimate
                }()
                let range = VT100GridCoordRangeMake(startCoord.x,
                                                    startCoord.y,
                                                    endCoord.x,
                                                    endCoord.y)
                possiblePaths.append(Candidate(string: candidateString,
                                               range: range,
                                               expandedPath: candidateString))
                i = j  // Move index past the current candidate.
            } else {
                i += 1
            }
        }
        currentLine.removeAll()
    }
}

// Private methods
private extension PathExtractor {
    // Returns true only if every unicode scalar in 'char' is allowed.
    func characterIsValidInPath(_ char: String) -> Bool {
        return !char.unicodeScalars.contains {
            !allowedCharacterSet.contains($0)
        }
    }

}
