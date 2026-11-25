//
//  NSLocale+iTerm.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/23/16.
//

import Foundation

extension NSLocale {
    // Is the locale one that writes "foo." instead of "foo".?
    // No thread assertion: it reads only the receiver's identifier, and
    // NSLocale is immutable.
    @objc(commasAndPeriodsGoInsideQuotationMarks)
    func commasAndPeriodsGoInsideQuotationMarks() -> Bool {
        // A receiver whose -localeIdentifier returns nil, against the SDK's
        // nonnull claim, bridges to an empty string and gives false, as
        // messaging nil did.
        return localeIdentifier == "en_US"
    }
}
