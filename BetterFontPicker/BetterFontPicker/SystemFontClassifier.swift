//
//  SystemFontClassifier.swift
//  BetterFontPicker
//
//  Created by George Nachman on 4/18/20.
//  Copyright © 2020 George Nachman. All rights reserved.
//

import Foundation

class SystemFontClassifier {
    static let didUpdateNotificationName = NSNotification.Name("SystemFontClassifierDidUpdate")
    static var initialized = false
    var monospace: Set<String> = []
    var variable: Set<String> = []

    private static var nextMonospace: Set<String> = []
    private static var nextVariable: Set<String> = []
    private static let queue = DispatchQueue(label: "com.iterm2.font-classifier")
    private static var needsUpdate = false

    init() {
        NotificationCenter.default.addObserver(forName: NSFont.fontSetChangedNotification,
                                               object: nil,
                                               queue: nil) { (_) in
                                                Self.setNeedsUpdate()
        }
        if Self.initialized {
            sync()
        } else {
            Self.initialized = true
            Self.update()
        }
    }

    func sync() {
        monospace = Self.nextMonospace
        variable = Self.nextVariable
    }

    static func setNeedsUpdate() {
        if needsUpdate {
            return
        }
        needsUpdate = true
        DispatchQueue.main.async {
            update()
        }
    }

    static func update() {
        needsUpdate = false
        let descriptors = NSFontCollection.withAllAvailableDescriptors.matchingDescriptors ?? []
        queue.async {
            classify(descriptors: descriptors)
        }
    }

    // queue
    private static func classify(descriptors: [NSFontDescriptor]) {
        var monospace: Set<String> = []
        var variable: Set<String> = []

        for descriptor in descriptors {
            if let name = descriptor.object(forKey: NSFontDescriptor.AttributeName.family) as? String {
                if monospace.contains(name) || variable.contains(name) {
                    // The call to symbolicTraits is slow so avoid doing it more than needed.
                    continue
                }
                if descriptor.symbolicTraits.contains(.monoSpace) {
                    monospace.insert(name)
                } else {
                    variable.insert(name)
                }
            }
        }

        DispatchQueue.main.async {
            nextMonospace = monospace
            nextVariable = variable
            NotificationCenter.default.post(name: didUpdateNotificationName, object: nil)
        }
    }
}
