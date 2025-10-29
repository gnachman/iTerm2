//
//  iTermSetting.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/28/25.
//

import Foundation

@objc
class iTermSetting: NSObject {
    @objc let info: PreferenceInfo
    @objc let pathComponents: [String]
    @objc let isProfile: Bool

    @objc
    init(info: PreferenceInfo,
         isProfile: Bool,
         pathComponents: [String]) {
        self.info = info
        self.isProfile = isProfile
        self.pathComponents = pathComponents
    }
}

