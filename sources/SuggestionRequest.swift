//
//  SuggestionRequest.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/12/23.
//

import Foundation

@objc(iTermSuggestionRequest)
class SuggestionRequest: NSObject {
    override var debugDescription: String {
        return "<SuggestionRequest \(inputs)>"
    }

    struct Inputs: Codable, CustomDebugStringConvertible, Hashable {
        var debugDescription: String {
            return "prefix=\(prefix) dirs=\(directories.joined(separator: ", ")) pwd=\(workingDirectory ?? "none") executable=\(executable)"
        }

        var prefix: String
        var directories: [String]
        var workingDirectory: String?
        var executable: Bool

        fileprivate var moreGeneralVariants: [Inputs] {
            if prefix.isEmpty {
                return []
            }
            return [self] + inputsByTruncatingPrefix.moreGeneralVariants
        }

        private var inputsByTruncatingPrefix: Inputs {
            precondition(!prefix.isEmpty)
            return Inputs(prefix: String(prefix.dropLast(1)),
                          directories: directories,
                          workingDirectory: workingDirectory,
                          executable: executable)
        }
    }
    let inputs: Inputs

    @objc var prefix: String { inputs.prefix }
    @objc var directories: [String] { inputs.directories }
    @objc var workingDirectory: String? { inputs.workingDirectory }
    @objc var executable: Bool { inputs.executable }

    @objc var completion: ([String]) -> ()

    @objc
    init(prefix: String,
         directories: [String],
         workingDirectory: String?,
         executable: Bool,
         completion: @escaping ([String]) -> ()) {
        inputs = Inputs(prefix: prefix,
                        directories: directories,
                        workingDirectory: workingDirectory,
                        executable: executable)
        self.completion = completion

    }
}

class SuggestionCache {
    private struct Entry {
        var values: [String]
        var creationTime = NSDate.it_timeSinceBoot()

        var age: TimeInterval {
            return NSDate.it_timeSinceBoot() - creationTime
        }

        func narrowedValues(forPrefix longerPrefix: String, lengthDifference: Int) -> [String] {
            return values.filter {
                $0.hasPrefix(longerPrefix)
            }.map {
                String($0.dropFirst(lengthDifference))
            }
        }
    }

    private var dict = [SuggestionRequest.Inputs: Entry]()
    private let maxAge = 5.0

    func get(_ inputs: SuggestionRequest.Inputs) -> [String]? {
        for variantInputs in inputs.moreGeneralVariants {
            if let cached = dict[variantInputs] {
                if cached.age < maxAge {
                    let values = cached.narrowedValues(
                        forPrefix: String(
                            inputs.prefix.dropFirst(variantInputs.prefix.count)),
                        lengthDifference: inputs.prefix.count - variantInputs.prefix.count)
                    if values.isEmpty && variantInputs.prefix != inputs.prefix {
                        // Can't use a more general query's results because it might have truncated
                        // a large number of results, excluding this one.
                        return nil
                    }
                    DLog("Return cached values from \(variantInputs.prefix) for longer query \(inputs.prefix): \(values.joined(separator: ","))")
                    return values
                } else {
                    dict.removeValue(forKey: variantInputs)
                }
            }
        }
        return nil
    }

    private var haveScheduledPurge = false
    func insert(inputs: SuggestionRequest.Inputs, suggestions: [String]) {
        dict[inputs] = Entry(values: suggestions)
        schedulePurgeIfNeeded()
    }

    private func schedulePurgeIfNeeded() {
        if !haveScheduledPurge && !dict.isEmpty {
            haveScheduledPurge = true
            DispatchQueue.main.asyncAfter(deadline: .now() + maxAge * 2) { [weak self] in
                self?.purge()
            }
        }
    }

    private func purge() {
        haveScheduledPurge = false
        dict = dict.filter { $0.value.age < maxAge }
        schedulePurgeIfNeeded()
    }
}
