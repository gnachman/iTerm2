//
//  iTermIntervalTreeObserver.h
//  iTerm2
//
//  Created by George Nachman on 4/2/20.
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermIntervalTreeObjectType) {
    iTermIntervalTreeObjectTypeSuccessMark,
    iTermIntervalTreeObjectTypeOtherMark,
    iTermIntervalTreeObjectTypeErrorMark,
    iTermIntervalTreeObjectTypeManualMark,
    iTermIntervalTreeObjectTypeAnnotation,
    iTermIntervalTreeObjectTypePorthole,
    iTermIntervalTreeObjectTypeUnknown,
};

@protocol iTermIntervalTreeObserver<NSObject>
- (void)intervalTreeDidReset;
- (void)intervalTreeDidAddObjectOfType:(iTermIntervalTreeObjectType)type
                                onLine:(NSInteger)line;
- (void)intervalTreeDidRemoveObjectOfType:(iTermIntervalTreeObjectType)type
                                   onLine:(NSInteger)line;
- (void)intervalTreeDidUnhideObject:(id<IntervalTreeImmutableObject>)object
                             ofType:(iTermIntervalTreeObjectType)type
                             onLine:(NSInteger)line;
- (void)intervalTreeDidHideObject:(id<IntervalTreeImmutableObject>)object
                           ofType:(iTermIntervalTreeObjectType)type
                           onLine:(NSInteger)line;
// A hidden object (such as a porthole inside a fold) had its container
// permanently removed - via Clear Buffer or scrollback overflow rather than
// unfold - so it will never be unhidden and must be reclaimed.
- (void)intervalTreeDidPermanentlyRemoveHiddenObject:(id<IntervalTreeImmutableObject>)object
                                              ofType:(iTermIntervalTreeObjectType)type;
- (void)intervalTreeVisibleRangeDidChange;
- (void)intervalTreeDidMoveObjects:(NSArray<id<IntervalTreeImmutableObject>> *)objects;
@end

iTermIntervalTreeObjectType iTermIntervalTreeObjectTypeForObject(id<IntervalTreeImmutableObject> object);

NS_ASSUME_NONNULL_END
