//
//  NSView+iTerm.m
//  iTerm
//
//  Created by George Nachman on 3/15/14.
//
//

#import "NSView+iTerm.h"
#import "DebugLogging.h"

@implementation NSView (iTerm)

- (NSImage *)snapshot {
    return [[[NSImage alloc] initWithData:[self dataWithPDFInsideRect:[self bounds]]] autorelease];
}

- (void)insertSubview:(NSView *)subview atIndex:(NSInteger)index {
    NSArray *subviews = [self subviews];
    if (subviews.count == 0) {
        [self addSubview:subview];
        return;
    }
    if (index == 0) {
        [self addSubview:subview positioned:NSWindowBelow relativeTo:subviews[0]];
    } else {
        [self addSubview:subview positioned:NSWindowAbove relativeTo:subviews[index - 1]];
    }
}

- (void)swapSubview:(NSView *)subview1 withSubview:(NSView *)subview2 {
    NSArray *subviews = [self subviews];
    NSUInteger index1 = [subviews indexOfObject:subview1];
    NSUInteger index2 = [subviews indexOfObject:subview2];
    assert(index1 != index2);
    assert(index1 != NSNotFound);
    assert(index2 != NSNotFound);
    
    NSRect frame1 = subview1.frame;
    NSRect frame2 = subview2.frame;
    
    NSView *filler1 = [[[NSView alloc] initWithFrame:subview1.frame] autorelease];
    NSView *filler2 = [[[NSView alloc] initWithFrame:subview2.frame] autorelease];
    
    [self replaceSubview:subview1 with:filler1];
    [self replaceSubview:subview2 with:filler2];
    
    subview1.frame = frame2;
    subview2.frame = frame1;
    
    [self replaceSubview:filler1 with:subview2];
    [self replaceSubview:filler2 with:subview1];
}

+ (iTermDelayedPerform *)animateWithDuration:(NSTimeInterval)duration
                                       delay:(NSTimeInterval)delay
                                  animations:(void (^)(void))animations
                                  completion:(void (^)(BOOL finished))completion {
    iTermDelayedPerform *delayedPerform = [[iTermDelayedPerform alloc] init];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                       if (!delayedPerform.canceled) {
                           DLog(@"Run dp %@", delayedPerform);
                           [self animateWithDuration:duration
                                          animations:animations
                                          completion:^(BOOL finished) {
                                              delayedPerform.completed = YES;
                                              completion(finished);
                                              [delayedPerform release];
                                          }];
                       } else {
                           completion(NO);
                           [delayedPerform release];
                       }
                   });
    return delayedPerform;
}

+ (void)animateWithDuration:(NSTimeInterval)duration
                 animations:(void (^)(void))animations
                 completion:(void (^)(BOOL finished))completion {
   NSAnimationContext *context = [NSAnimationContext currentContext];
   NSTimeInterval savedDuration = [context duration];
   if (duration > 0) {
       [context setDuration:duration];
   }
   animations();
   [context setDuration:savedDuration];

   if (completion) {
       dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
                          completion(YES);
                      });
   }
}

@end
