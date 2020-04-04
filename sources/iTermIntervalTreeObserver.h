//
//  iTermIntervalTreeObserver.h
//  iTerm2
//
//  Created by George Nachman on 4/2/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermIntervalTreeObjectType) {
    iTermIntervalTreeObjectTypeSuccessMark,
    iTermIntervalTreeObjectTypeOtherMark,
    iTermIntervalTreeObjectTypeErrorMark,
    iTermIntervalTreeObjectTypeManualMark,
    iTermIntervalTreeObjectTypeAnnotation,
    iTermIntervalTreeObjectTypeUnknown,
};

@protocol iTermIntervalTreeObserver<NSObject>
- (void)intervalTreeDidReset;
- (void)intervalTreeDidAddObjectOfType:(iTermIntervalTreeObjectType)type
                                onLine:(NSInteger)line;
- (void)intervalTreeDidRemoveObjectOfType:(iTermIntervalTreeObjectType)type
                                   onLine:(NSInteger)line;
- (void)intervalTreeVisibleRangeDidChange;
@end

NS_ASSUME_NONNULL_END
