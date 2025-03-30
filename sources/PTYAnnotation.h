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
@protocol PTYAnnotationReading;

@protocol PTYAnnotationDelegate<NSObject>
- (void)annotationDidRequestHide:(id<PTYAnnotationReading>)annotation;
- (void)annotationStringDidChange:(id<PTYAnnotationReading>)annotation;
- (void)annotationWillBeRemoved:(id<PTYAnnotationReading>)annotation;
- (BOOL)setNoteHidden:(BOOL)hidden;
- (void)highlight;
@end

@protocol PTYAnnotationReading<NSObject, IntervalTreeImmutableObject>
@property(nonatomic, copy, readonly) NSString *stringValue;
@property(nonatomic, nullable, weak) id<PTYAnnotationDelegate> delegate;
@property(nonatomic, nullable, weak, readonly) id<PTYAnnotationReading> progenitor;  // The doppelganger's creator
@property(nonatomic, readonly) NSString *uniqueID;

- (id<PTYAnnotationReading>)doppelganger;
@end

@interface PTYAnnotation : NSObject<IntervalTreeObject, PTYAnnotationReading>
@property(nonatomic, copy, readwrite) NSString *stringValue;

+ (NSString *)textForAnnotationForNamedMarkWithName:(NSString *)name;

- (void)hide;
- (void)setStringValueWithoutSideEffects:(NSString *)value;
- (void)willRemove;

- (id<PTYAnnotationReading>)doppelganger;
@end

NS_ASSUME_NONNULL_END
