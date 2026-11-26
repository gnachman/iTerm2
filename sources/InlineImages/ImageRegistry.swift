//
//  ImageRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/22.
//

import Foundation

/// Supplies the values a MonotonicCounter takes. Without one, the counter counts up locally.
protocol MonotonicCounterDataSource {
    /// The value to take when advancing from `current`. Must be greater than `current`.
    func value(after current: Int) -> Int

    /// The value to take when restoring `minimum` from saved state.
    func value(restoring minimum: Int, current: Int) -> Int
}

/// Values from the shared restorable-state generation counter (see iTermGeneration.h), so they
/// never equal a generation that anything else saved or will save, including in an earlier launch.
struct SharedGenerationDataSource: MonotonicCounterDataSource {
    func value(after current: Int) -> Int {
        return iTermGenerationNext()
    }

    /// The saved value is a generation for state that is merged into the current state, so it is
    /// adopted only if the counter hasn't advanced since launch.
    func value(restoring minimum: Int, current: Int) -> Int {
        return iTermGenerationAdopt(current, minimum)
    }
}

@objc(iTermMonotonicCounter)
class MonotonicCounter: NSObject {
    private var _value = 0
    private let mutex = Mutex()
    private let dataSource: MonotonicCounterDataSource?

    init(dataSource: MonotonicCounterDataSource? = nil) {
        self.dataSource = dataSource
        super.init()
    }

    @objc var value: Int {
        return mutex.sync { _value }
    }

    @objc var next: Int {
        return mutex.sync {
            _value = dataSource?.value(after: _value) ?? _value + 1
            return _value
        }
    }

    @objc func advance() {
        _ = next
    }

    /// Used to initialize from saved state during restoration. Without a data source, the counter
    /// only moves up to `minimum`.
    @objc func setMinimum(_ minimum: Int) {
        mutex.sync {
            if let dataSource {
                _value = dataSource.value(restoring: minimum, current: _value)
            } else if _value < minimum {
                _value = minimum
            }
        }
    }
}

@objc(iTermScreenCharGeneration)
class ScreenCharGeneration: NSObject {
    @objc static let counter = MonotonicCounter(dataSource: SharedGenerationDataSource())
}

@objc(iTermImageRegistry)
class ImageRegistry: NSObject {
    private var codeToImage = [Int: iTermImageInfo]()
    private var codeToPropertyList = [NSNumber: [String: NSObjectProtocol & NSCopying]]()
    private let mutex = Mutex()
    @objc(sharedInstance) static let instance = ImageRegistry()

    @objc
    func restore(from dict: [NSNumber: [String: NSObjectProtocol & NSCopying]]) {
        mutex.sync {
            for (key, value) in dict {
                codeToPropertyList[key] = value
                guard let info = iTermImageInfo(dictionary: value) else {
                    continue
                }
                info.provisional = true
                codeToImage[key.intValue] = info
                RLog("ImageRegistry: restore code \(key.intValue) as provisional")
                DLog("Decoded restorable state for image \(key): \(info)")
                ScreenCharGeneration.counter.advance()
            }
        }
    }

    @objc(assignCode:toImageInfo:)
    func assign(code: Int, imageInfo: iTermImageInfo) {
        mutex.sync {
            if let existing = codeToImage[code] {
                DLog("ImageRegistry: code \(code) reassigned from \(existing) to \(imageInfo)")
            } else {
                DLog("ImageRegistry: assign code \(code) to \(imageInfo)")
            }
            codeToImage[code] = imageInfo
            ScreenCharGeneration.counter.advance()
        }
    }

    @objc(infoForCode:)
    func info(for code: Int) -> iTermImageInfo? {
        return mutex.sync {
            return codeToImage[code]
        }
    }

    @objc(removeCode:)
    func remove(code: Int) {
        mutex.sync {
            RLog("ImageRegistry: remove code \(code) (ReleaseImage/mark dealloc)")
            DLog("ReleaseImage(\(code))")
            codeToImage.removeValue(forKey: code)
            codeToPropertyList.removeValue(forKey: NSNumber(value: code))
            ScreenCharGeneration.counter.advance()
        }
    }

    @objc
    func collectGarbage() {
        mutex.sync {
            RLog("ImageRegistry: garbage collect")
            for (key, value) in codeToImage {
                guard value.provisional else {
                    continue
                }
                RLog("ImageRegistry: GC reap still-provisional code \(key)")
                DLog("Remove \(key)")
                codeToImage.removeValue(forKey: key)
            }
        }
    }

    @objc(clearProvisionalFlagForCode:)
    func clearProvisionalFlag(code: Int) {
        mutex.sync {
            RLog("ImageRegistry: clear provisional for code \(code)\(codeToImage[code] == nil ? " (MISSING: no registry entry)" : "")")
            DLog("Clear provisional for \(code)")
            codeToImage[code]?.provisional = false
        }
    }

    // data is nil for an image that has no encoded data, such as a native image.
    @objc(setData:forImage:code:)
    func set(data: Data?, image: iTermImage, code: Int) {
        mutex.sync {
            guard let imageInfo = codeToImage[code] else {
                return
            }
            imageInfo.setImageFrom(image, data: data)
            codeToPropertyList[NSNumber(value: code)] = imageInfo.dictionary()
            ScreenCharGeneration.counter.advance()
            DLog("set decoded image in \(imageInfo)")
        }
    }

    @objc
    var imageMap: NSDictionary {
        mutex.sync {
            return (codeToPropertyList as NSDictionary).copy() as! NSDictionary
        }
    }
}
