//
//  iTermIntervalTreeObserver.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/28/21.
//

#import "iTermIntervalTreeObserver.h"

#import "iTerm2SharedARC-Swift.h"
#import "PTYAnnotation.h"
#import "VT100ScreenMark.h"

iTermIntervalTreeObjectType iTermIntervalTreeObjectTypeForObject(id<IntervalTreeImmutableObject> object) {
    if ([object isKindOfClass:[VT100ScreenMark class]]) {
        id<VT100ScreenMarkReading> mark = (id<VT100ScreenMarkReading>)object;
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
    if ([object isKindOfClass:[PortholeMark class]]) {
        return iTermIntervalTreeObjectTypePorthole;
    }
    return iTermIntervalTreeObjectTypeUnknown;
}
