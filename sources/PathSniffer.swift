//
//  PathSniffer.swift
//  iTerm2
//
//  Created by George Nachman on 4/10/25.
//

@objc(iTermStatFileProtocol)
protocol StatFileProtocol {
    func stat(_ path: String,
              queue: DispatchQueue,
              completion: @escaping (Int32, UnsafePointer<stat>?) -> ())
}

@objc(iTermPathSnifferDelegate)
protocol PathSnifferDelegate: AnyObject {
    func pathSniffer(_ pathSniffer: PathSniffer,
                     didDetectPath: String,
                     inRange: VT100GridAbsCoordRange)
}

// Asynchronously detects a real existing path (even over SSH, with SSH integration) in a section of
// a text extractor's data source.
@objc(iTermPathSniffer)
class PathSniffer: NSObject {
    private let extractor: iTermTextExtractor
    private let range: VT100GridCoordRange
    private let remoteHost: VT100RemoteHostReading?
    private let offset: Int64
    private let pwd: String?
    private let width: Int32
    private var remoteCandidates = [PathExtractor.Candidate]()
    private let queue: DispatchQueue
    @objc weak var delegate: PathSnifferDelegate?
    private var acceptedRanges = [VT100GridCoordRange]()
    private static var instances = [PathSniffer]()
    var count = 0 {
        didSet {
            if oldValue == 0 && count > 0 {
                Self.instances.append(self)
            } else if oldValue > 0 && count == 0 {
                Self.instances.remove(object: self)
            }
        }
    }

    @objc
    init(extractor: iTermTextExtractor,
         range: VT100GridCoordRange,
         remoteHost: VT100RemoteHostReading?,
         offset: Int64,
         pwd: String,
         width: Int32,
         queue: DispatchQueue) {
        self.extractor = extractor
        self.range = range
        self.remoteHost = remoteHost
        self.offset = offset
        self.pwd = pwd
        self.width = width
        self.queue = queue
    }
}

// Public API
extension PathSniffer {
    @objc
    func sniff() {
        let pathExtractor = PathExtractor()
        let privateRange = ITERM2_PRIVATE_BEGIN..<ITERM2_PRIVATE_END
        extractor.enumerateChars(in: VT100GridWindowedRangeMake(range, 0, 0),
                                 supportBidi: false) { _, c, _, logicalCoord, _ in
            if c.complexChar != 0 && privateRange.contains(Int32(c.code)) {
                return false
            }
            if c.image != 0 {
                pathExtractor.newLine()
                return false
            }
            var temp = c
            pathExtractor.add(string: ScreenCharToStr(&temp), coord: logicalCoord)
            return false
        } eolBlock: { eol, _, _ in
            if eol == EOL_HARD {
                pathExtractor.newLine()
            }
            return false
        }
        pathExtractor.newLine()

        for candidate in pathExtractor.possiblePaths {
            stat(candidate)
        }
    }

    @objc var hasSideEffects: Bool { !remoteCandidates.isEmpty }

    @objc(executeSideEffectsWithStatter:)
    func executeSideEffects(statter: StatFileProtocol) {
        for candidate in remoteCandidates {
            count += 1
            statter.stat(candidate.string, queue: queue) { [weak self] rc, statbuf in
                guard rc == 0, let sb = statbuf?.pointee, let self else {
                    return
                }
                defer {
                    count -= 1
                }
                if Self.acceptable(sb) {
                    accept(candidate)
                }
            }
        }
    }
}

// Private methods
private extension PathSniffer {
    private func stat(_ candidate: PathExtractor.Candidate) {
        let path = { () -> String? in
            if candidate.string.hasPrefix("/") || candidate.string.hasPrefix("~") {
                candidate.string
            } else if let pwd {
                pwd + "/" + candidate.string
            } else {
                nil
            }
        }()
        guard let path else {
            return
        }
        var temp = candidate
        temp.expandedPath = path
        if remoteHost?.isLocalhost ?? true {
            localStat(candidate: temp)
        } else {
            remoteCandidates.append(temp)
        }
    }

    private func localStat(candidate: PathExtractor.Candidate) {
        count += 1
        iTermSlowOperationGateway.sharedInstance().statFile(candidate.expandedPath) { [weak self] sb, errorCode in
            guard let self else {
                return
            }
            defer {
                count -= 1
            }
            if errorCode != 0 {
                return
            }
            if Self.acceptable(sb) {
                accept(candidate)
            }
        }
    }

    private func accept(_ candidate: PathExtractor.Candidate) {
        // In theory they should be disjoint but prevent disaster by dropping overlapping ranges.
        for range in acceptedRanges {
            let intersection = VT100GridCoordRangeIntersection(range, candidate.range)
            if VT100GridCoordRangeLength(intersection, width) > 0 {
                return
            }
        }
        delegate?.pathSniffer(self,
                              didDetectPath: candidate.string,
                              inRange: VT100GridAbsCoordRangeFromCoordRange(candidate.range,
                                                                            offset))
    }

    private static func acceptable(_ sb: stat) -> Bool {
        let isDirectory = (sb.st_mode & S_IFMT) == S_IFDIR
        let isReadable = (sb.st_mode & (S_IRUSR | S_IRGRP | S_IROTH)) != 0
        let isExecutable = (sb.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0

        return isDirectory && isReadable && isExecutable
    }

}

extension Array where Element: AnyObject {
    mutating func remove(object: Element) {
        removeAll {
            $0 === object
        }
    }
}
