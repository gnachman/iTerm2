//
//  TarJob.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/13/22.
//

import Foundation

struct TarJob: CustomDebugStringConvertible {
    var debugDescription: String {
        return "<TarJob sources=\(sources.map { $0.path }) localBase=\(localBase.path) destinationBase=\(destinationBase.path)>"
    }
    var sources: [URL]
    var localBase: URL
    var destinationBase: URL

    init(local: URL, destination: URL) {
        sources = [local]
        localBase = local.deletingLastPathComponent()
        destinationBase = destination
    }

    init(sources: [URL],
         localBase: URL,
         destinationBase: URL) {
        self.sources = sources
        self.localBase = localBase
        self.destinationBase = destinationBase
    }

    private var sourceParents: [URL] {
        return sources.map { $0.deletingLastPathComponent() }
    }

    private var relativeSourcePaths: [String] {
        let prefixCount = localBase.pathComponents.count
        return sources.splitPaths.map { $0.dropFirst(prefixCount).joined(separator: "/") }
    }

    func canAdd(local: URL, destination destinationParent: URL) -> Bool {
        return adding(local: local, destination: destinationParent) != nil
    }

    mutating func add(local: URL, destination destinationParent: URL) -> Bool {
        if let replacement = adding(local: local, destination: destinationParent) {
            self = replacement
            return true
        }
        return false
    }

    func tarballData() throws -> Data? {
        return try NSData(tgzContainingFiles: relativeSourcePaths,
                          relativeToPath: localBase.path) as Data?
    }

    private func adding(local: URL, destination destinationParent: URL) -> TarJob? {
        let destination = destinationParent.appendingPathComponent(local.lastPathComponent)
        DLog("Want to add \(local.path) at \(destination.path) to \(self)")
        guard sourceParents.hasCommonPathPrefix else {
            DLog("Source parents lack common prefix \(sourceParents)")
            return nil
        }
        let sourcePrefix = (sourceParents + [local.deletingLastPathComponent()]).commonPathPrefix
        DLog("sourcePrefix=\(sourcePrefix)")
        do {
            let destinations = try sources.map { (url: URL) -> URL in
                let suffix: String = try url.pathByRemovingPrefix(localBase.path)
                DLog("Transform source \(url.path) into destination by appending its suffix after the localBase (\(localBase.path)) of \(suffix) to the destinationBase of \(destinationBase.path) giving \(destinationBase.appendingPathComponent(suffix).path)")
                return destinationBase.appendingPathComponent(suffix)
            } + [destination]
            DLog("destinations:")
            DLog("\(destinations)")

            let destinationPrefixCount = destinations.splitPaths.lengthOfLongestCommonPrefix

            let splitDestinations = destinations.map { $0.pathComponents }
            let splitSources = (sources + [local]).map { $0.pathComponents }
            let sourcePrefixCount = sourcePrefix.components(separatedBy: "/").count

            DLog("splitDestinations (amended):")
            DLog("\(splitDestinations)")
            DLog("")
            DLog("splitSources (amended):")
            DLog("\(splitSources)")
            DLog("")
            DLog("sourcePrefixCount (based on amended source parents):")
            DLog("\(sourcePrefixCount)")
            DLog("")

            for (source, dest) in zip(splitSources, splitDestinations) {
                DLog("Check source=\(source), dest=\(dest), preserving source prefix \(sources[0].pathComponents.prefix(sourcePrefixCount))")
                let sourceSuffix = Array(source.dropFirst(sourcePrefixCount))
                if !dest.endsWith(sourceSuffix) {
                    DLog("FAIL - destination \(dest) does not end with source suffix \(sourceSuffix)")
                    return nil
                }
                if dest.count - sourceSuffix.count > destinationPrefixCount {
                    DLog("FAIL - destination (\(dest)) after stripping source suffix (\(sourceSuffix)), yielding \(dest[0..<(dest.count - sourceSuffix.count)]) is longer than the common destination prefix \(destinations[0].pathComponents[0..<destinationPrefixCount])")
                    return nil
                }
                DLog("OK - destination \(dest) ends with source suffix \(sourceSuffix)")
            }
            precondition(splitSources[0].count >= sourcePrefixCount, "Split sources \(splitSources[0]) count (\(splitSources[0].count)) > sourcePrefixCount \(sourcePrefixCount). source prefix is \(sourcePrefix) based on sourceParents=\(sourceParents) and local=\(local).")
            let replacement = TarJob(sources: sources + [local],
                                     localBase: URL(fileURLWithPath: sourcePrefix),
                                     destinationBase: URL(fileURLWithPath: splitDestinations[0].dropFirst().dropLast(splitSources[0].count - sourcePrefixCount).joined(separator: "/")))
            DLog("Upon success replacement is \(replacement)")
            return replacement
        } catch {
            DLog("FAIL - exception \(error)")
            return nil
        }
    }
}
