//
//  iTermIntervalTreeObserver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/28/21.
//

#import "iTermIntervalTreeObserver.h"
#import "PTYAnnotation.h"
#import "VT100ScreenMark.h"

iTermIntervalTreeObjectType iTermIntervalTreeObjectTypeForObject(id<IntervalTreeObject> object) {
    if ([object isKindOfClass:[VT100ScreenMark class]]) {
        VT100ScreenMark *mark = (VT100ScreenMark *)object;
        if (!mark.hasCode) {
            return iTermIntervalTreeObjectTypeManualMark;
        }
        if (mark.code == 0) {
            return iTermIntervalTreeObjectTypeSuccessMark;
        }
        if (mark.code >= 128 && mark.code <= 128 + 32) {
            return iTermIntervalTreeObjectTypeOtherMark;
        }
        return iTermIntervalTreeObjectTypeErrorMark;
    }

    if ([object isKindOfClass:[PTYAnnotation class]]) {
        return iTermIntervalTreeObjectTypeAnnotation;
    }
    return iTermIntervalTreeObjectTypeUnknown;
}
