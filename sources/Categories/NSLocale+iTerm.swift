//
//  NSLocale+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/16.
//

import Foundation

extension NSLocale {
    // Is the locale one that writes "foo." instead of "foo".?
    @objc(commasAndPeriodsGoInsideQuotationMarks)
    func commasAndPeriodsGoInsideQuotationMarks() -> Bool {
        // A locale whose localeIdentifier is nil, against the SDK's nonnull
        // claim, bridges to an empty string and gives false.
        return localeIdentifier == "en_US"
    }
}
