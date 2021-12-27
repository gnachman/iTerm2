//
//  PTYAnnotation.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/26/21.
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

NS_ASSUME_NONNULL_BEGIN

@class PTYAnnotation;

@protocol PTYAnnotationDelegate<NSObject>
- (void)annotationDidRequestHide:(PTYAnnotation *)annotation;
- (void)annotationStringDidChange:(PTYAnnotation *)annotation;
- (void)annotationWillBeRemoved:(PTYAnnotation *)annotation;
@end

@interface PTYAnnotation : NSObject<IntervalTreeObject>
@property(nonatomic, weak) id<PTYAnnotationDelegate> delegate;
@property(nonatomic, copy) NSString *stringValue;

- (void)hide;
- (void)setStringValueWithoutSideEffects:(NSString *)value;
- (void)willRemove;

@end

NS_ASSUME_NONNULL_END
