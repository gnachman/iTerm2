//
//  iTermProfilePreferenceMutator.swift
//  iTerm2
//
//  Created by George Nachman on 7/15/25.
//

@objc
class iTermProfilePreferenceMutator: NSObject {
    private let model: ProfileModel
    private let guid: String

    init(model: ProfileModel,
         guid: String) {
        self.model = model
        self.guid = guid
    }

    func set(key: String, value: [String]) {
        if let profile = model.bookmark(withGuid: guid) {
            iTermProfilePreferences.setObject(value as NSArray, forKey: key, inProfile: profile, model: model)
        }
    }
}
