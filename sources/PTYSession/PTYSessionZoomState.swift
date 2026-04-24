//
//  PTYSessionZoomState.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/21.
//

import Foundation

@objc class PTYSessionZoomState: NSObject {
    @objc var firstVisibleAbsoluteLineNumber: Int64
    @objc var searchQuery: String?

    @objc(initWithFirstVisibleAbsoluteLineNumber:searchQuery:)
    init(firstVisibleAbsoluteLineNumber: Int64,
               searchQuery: String?) {
        self.firstVisibleAbsoluteLineNumber = firstVisibleAbsoluteLineNumber
        self.searchQuery = searchQuery
    }
}
