//
//  iTermProfilePreferenceObserver.swift
//  iTerm2
//
//  Created by George Nachman on 7/15/25.
//

import Foundation

@objc
@MainActor
class iTermProfilePreferenceObserver: NSObject {
    private var closures = [String: (NSObject?, NSObject?) -> ()]()
    private let guid: String
    private var lastValue = [String: NSObject]()
    private let model: ProfileModel

    @objc(initWithGUID:model:)
    init(guid: String, model: ProfileModel) {
        self.guid = guid
        self.model = model
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileDidChange(_:)),
                                               name: NSNotification.Name(iTermProfileDidChange),
                                               object: nil)
    }

    @objc(observeKey:block:)
    func objcObserve(key: String, closure: @escaping (AnyObject?, AnyObject?) -> ()) {
        lastValue[key] = value(for: key)
        closures[key] = { oldValue, newValue in
            closure(oldValue, newValue)
        }
    }

    func observe<T>(key: String, closure: @MainActor @escaping (T?, T?) -> ()) {
        lastValue[key] = value(for: key)
        closures[key] = { oldValue, newValue in
            let oldTyped: T? = if let oldValue {
                oldValue as? T
            } else {
                nil
            }
            let newTyped: T? = if let newValue {
                newValue as? T
            } else {
                nil
            }
            Task { @MainActor in
                closure(oldTyped, newTyped)
            }
        }
    }

    func observeDouble(key: String, closure: @MainActor @escaping (Double, Double) -> ()) {
        lastValue[key] = value(for: key)
        closures[key] = { oldValue, newValue in
            let oldTyped: Double? = if let oldValue {
                oldValue as? Double
            } else {
                nil
            }
            let newTyped: Double? = if let newValue {
                newValue as? Double
            } else {
                nil
            }
            Task { @MainActor in
                closure(oldTyped ?? 0.0, newTyped ?? 0.0)
            }
        }
    }

    func observeBool(key: String, closure: @MainActor @escaping (Bool, Bool) -> ()) {
        lastValue[key] = value(for: key)
        closures[key] = { oldValue, newValue in
            let oldTyped: Bool? = if let oldValue {
                oldValue as? Bool
            } else {
                nil
            }
            let newTyped: Bool? = if let newValue {
                newValue as? Bool
            } else {
                nil
            }
            Task { @MainActor in
                closure(oldTyped ?? false, newTyped ?? false)
            }
        }
    }

    func observeString(key: String, closure: @MainActor @escaping (String?, String?) -> ()) {
        observe(key: key, closure: closure)
    }
    
    func observeStringArray(key: String, closure: @MainActor @escaping ([String]?, [String]?) -> ()) {
        observe(key: key, closure: closure)
    }

    func observeDictionary(key: String, closure: @MainActor @escaping ([AnyHashable: Any]?, [AnyHashable: Any]?) -> ()) {
        observe(key: key, closure: closure)
    }

    func value(_ key: String) -> [[AnyHashable: Any]]? {
        return iTermProfilePreferences.object(forKey: key, inProfile: model.bookmark(withGuid: guid)) as? [[AnyHashable: Any]]
    }
    func value(_ key: String) -> [String]? {
        return iTermProfilePreferences.object(forKey: key, inProfile: model.bookmark(withGuid: guid)) as? [String]
    }
    func value(_ key: String) -> String? {
        return iTermProfilePreferences.string(forKey: key, inProfile: model.bookmark(withGuid: guid))
    }
    func value(_ key: String) -> Double {
        return iTermProfilePreferences.double(forKey: key, inProfile: model.bookmark(withGuid: guid))
    }
    func value(_ key: String) -> Bool {
        return iTermProfilePreferences.bool(forKey: key, inProfile: model.bookmark(withGuid: guid))
    }
}

extension iTermProfilePreferenceObserver {
    private func value(for key: String) -> NSObject? {
        return iTermProfilePreferences.object(forKey: key, inProfile: model.bookmark(withGuid: guid) ?? [:]) as? NSObject
    }

    @objc
    private func profileDidChange(_ notification: Notification) {
        guard let guid = notification.object as? String, guid == self.guid else {
            return
        }
        let saved = closures
        for (key, closure) in saved {
            let newValue = value(for: key)
            let oldValue = lastValue[key]
            if !NSObject.object(oldValue, isEqualTo: newValue) {
                closure(oldValue, newValue)
                if let newValue {
                    lastValue[key] = newValue
                } else {
                    lastValue.removeValue(forKey: key)
                }
            }
        }
    }
}
