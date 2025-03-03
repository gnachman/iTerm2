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
            return "prefix=\(prefix) fullPrefix=\(fullPrefix) fullSuffix=\(fullSuffix) dirs=\(directories.joined(separator: ", ")) pwd=\(workingDirectory ?? "none") executable=\(executable)"
        }

        var prefix: String
        var fullPrefix: String
        var fullSuffix: String
        var directories: [String]
        var workingDirectory: String?
        var executable: Bool
        var limit: Int

        fileprivate var moreGeneralVariants: [Inputs] {
            if prefix.isEmpty {
                return []
            }
            return [self] + inputsByTruncatingPrefix.moreGeneralVariants
        }

        private var inputsByTruncatingPrefix: Inputs {
            precondition(!prefix.isEmpty)
            return Inputs(prefix: String(prefix.dropLast(1)),
                          fullPrefix: fullPrefix,
                          fullSuffix: fullSuffix,
                          directories: directories,
                          workingDirectory: workingDirectory,
                          executable: executable,
                          limit: limit)
        }
    }
    let inputs: Inputs

    // Word before cursor
    @objc var prefix: String { inputs.prefix }

    // Everything before cursor
    @objc var fullPrefix: String { inputs.fullPrefix }
    // Everything after cursor
    @objc var fullSuffix: String { inputs.fullSuffix }

    @objc var directories: [String] { inputs.directories }
    @objc var workingDirectory: String? { inputs.workingDirectory }
    @objc var executable: Bool { inputs.executable }
    @objc var limit: Int { inputs.limit }
    @objc var completion: (Bool, [CompletionItem]) -> ()
    @objc var startActivityIndicator: () -> ()
    @objc var earlyResult: ([CompletionItem]) -> (CompletionItem?)

    @objc
    convenience init(prefix: String,
                     fullPrefix: String,
                     fullSuffix: String,
                     directories: [String],
                     workingDirectory: String?,
                     executable: Bool,
                     limit: Int,
                     startActivityIndicator: @escaping () -> (),
                     earlyResult: @escaping ([CompletionItem]) -> (CompletionItem?),
                     completion: @escaping (Bool, [CompletionItem]) -> ()) {
        self.init(inputs: Inputs(prefix: prefix,
                                 fullPrefix: fullPrefix,
                                 fullSuffix: fullSuffix,
                                 directories: directories,
                                 workingDirectory: workingDirectory,
                                 executable: executable,
                                 limit: limit),
                  startActivityIndicator: startActivityIndicator,
                  earlyResult: earlyResult,
                  completion: completion)
    }

    private init(inputs: Inputs,
                 startActivityIndicator: @escaping () -> (),
                 earlyResult: @escaping ([CompletionItem]) -> (CompletionItem?),
                 completion: @escaping (Bool, [CompletionItem]) -> ()) {
        self.inputs = inputs
        self.startActivityIndicator = startActivityIndicator
        self.earlyResult = earlyResult
        self.completion = completion

    }

    @objc(requestWithReducedLimitBy:)
    func requestWithReducedLimit(by factor: Int) -> SuggestionRequest {
        var inputs = self.inputs
        inputs.limit = max(1, inputs.limit / max(1, factor))
        return SuggestionRequest(inputs: inputs,
                                 startActivityIndicator: startActivityIndicator,
                                 earlyResult: earlyResult,
                                 completion: completion)
    }

    @objc(requestWrappingCompletion:)
    func requestWrappingCompletion(with closure: @escaping (Bool, [CompletionItem], @escaping (Bool, [CompletionItem]) -> ()) -> ()) -> SuggestionRequest {
        let completion = self.completion
        return SuggestionRequest(inputs: inputs,
                                 startActivityIndicator: startActivityIndicator) { [earlyResult] early in
            return earlyResult(early)
        } completion: { suggestionOnly, phrases in
            closure(suggestionOnly, phrases, completion)
        }
    }
}

class SuggestionCache {
    private struct Entry {
        var values: [CompletionItem]
        var creationTime = NSDate.it_timeSinceBoot()

        var age: TimeInterval {
            return NSDate.it_timeSinceBoot() - creationTime
        }

        func narrowedValues(forPrefix longerPrefix: String, lengthDifference: Int) -> [CompletionItem] {
            return values.filter {
                $0.value.hasPrefix(longerPrefix)
            }.map {
                $0.mapValue {
                    String($0.dropFirst(lengthDifference))
                }
            }
        }
    }

    private var dict = [SuggestionRequest.Inputs: Entry]()
    private let maxAge = 5.0

    func get(_ inputs: SuggestionRequest.Inputs) -> [CompletionItem]? {
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
                    DLog("Return cached values from \(variantInputs.prefix) for longer query \(inputs.prefix): \(values.map { $0.description }.joined(separator: ","))")
                    return values
                } else {
                    dict.removeValue(forKey: variantInputs)
                }
            }
        }
        return nil
    }

    private var haveScheduledPurge = false
    func insert(inputs: SuggestionRequest.Inputs, suggestions: [CompletionItem]) {
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
