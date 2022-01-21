//
//  ImageRegistry.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/22.
//

import Foundation

@objc(iTermMonotonicCounter)
class MonotonicCounter: NSObject {
    private var _value = 0
    private let mutex = Mutex()

    @objc var value: Int {
        return mutex.sync { _value }
    }

    @objc var next: Int {
        return mutex.sync {
            _value += 1
            return _value
        }
    }

    @objc func advance() {
        _ = next
    }
}

@objc(iTermScreenCharGeneration)
class ScreenCharGeneration: NSObject {
    @objc static let counter = MonotonicCounter()
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
                DLog("Decoded restorable state for image \(key): \(info)")
                ScreenCharGeneration.counter.advance()
            }
        }
    }

    @objc(assignCode:toImageInfo:)
    func assign(code: Int, imageInfo: iTermImageInfo) {
        mutex.sync {
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
            DLog("ReleaseImage(\(code))")
            codeToImage.removeValue(forKey: code)
            codeToPropertyList.removeValue(forKey: NSNumber(value: code))
            ScreenCharGeneration.counter.advance()
        }
    }

    @objc
    func collectGarbage() {
        mutex.sync {
            DLog("Garbage collect")
            for (key, value) in codeToImage {
                guard value.provisional else {
                    continue
                }
                DLog("Remove \(key)")
                codeToImage.removeValue(forKey: key)
            }
        }
    }

    @objc(clearProvisionalFlagForCode:)
    func clearProvisionalFlag(code: Int) {
        mutex.sync {
            DLog("Clear provisional for \(code)")
            codeToImage[code]?.provisional = false
        }
    }

    @objc(setData:forImage:code:)
    func set(data: Data, image: iTermImage, code: Int) {
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
