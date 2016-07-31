//
//  iTermDrawingShard.h
//  iTerm2
//
//  Created by George Nachman on 7/28/16.
//
//

#import <Cocoa/Cocoa.h>

extern dispatch_queue_t gCompositingQueue;

@interface iTermDrawingShard : NSObject
@property(nonatomic, assign) CGContextRef bitmapContext;
@property(nonatomic, assign) NSRange range;
@property(nonatomic, assign) NSRect rect;
@property(nonatomic, copy) void (^compositingBlock)();
@property(nonatomic, readonly) dispatch_group_t group;
@property(nonatomic, readonly) NSArray *events;
@property(nonatomic, readonly) int shardNumber;
@property(nonatomic, readonly) NSSize capacity;
@property(nonatomic, readonly) CGLayerRef layer;

- (instancetype)initWithRect:(NSRect)rect
                       scale:(CGFloat)scale
                       range:(NSRange)range
               bitmapContext:(CGContextRef)bitmapContext
                       queue:(dispatch_queue_t)queue;

- (instancetype)initWithRect:(NSRect)rect
                       scale:(CGFloat)scale
                       range:(NSRange)range
                 shardNumber:(int)shardNumber;

- (void)addEvent:(NSString *)event;
- (void)addDebugEvent:(NSString *)event;
- (void)removeAllEvents;
- (void)drawWithBlock:(void (^)())block;
- (void)compositeWhenReady;
- (void)setLayerContextFromContext:(CGContextRef)context;

@end

@interface iTermSynchronousDrawingShard : iTermDrawingShard
@end

NSTimeInterval MillisSinceDrawingEpoch();
void ResetDrawingEpoch();