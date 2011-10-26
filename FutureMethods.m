//
//  FutureMethods.m
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "FutureMethods.h"

@implementation NSWindow (Future)

- (void)futureSetRestorable:(BOOL)value
{
    if ([self respondsToSelector:@selector(setRestorable:)]) {
        NSMethodSignature *sig = [[self class] instanceMethodSignatureForSelector:@selector(setRestorable:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:self];
        [inv setSelector:@selector(setRestorable:)];
        [inv setArgument:&value atIndex:2];
        [inv invoke];
    }
}

- (void)futureSetRestorationClass:(Class)class
{
    if ([self respondsToSelector:@selector(setRestorationClass:)]) {
        [self performSelector:@selector(setRestorationClass:) withObject:class];
    }
}

- (void)futureInvalidateRestorableState
{
    if ([self respondsToSelector:@selector(invalidateRestorableState)]) {
        [self performSelector:@selector(invalidateRestorableState)];
    }
}

@end
@implementation NSView (Future)
- (void)futureSetAcceptsTouchEvents:(BOOL)value
{
    if ([self respondsToSelector:@selector(setAcceptsTouchEvents:)]) {
        NSMethodSignature *sig = [[self class] instanceMethodSignatureForSelector:@selector(setAcceptsTouchEvents:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:self];
        [inv setSelector:@selector(setAcceptsTouchEvents:)];
        [inv setArgument:&value atIndex:2];
        [inv invoke];
    }
}

- (void)futureSetWantsRestingTouches:(BOOL)value
{
    if ([self respondsToSelector:@selector(setWantsRestingTouches:)]) {
        NSMethodSignature *sig = [[self class] instanceMethodSignatureForSelector:@selector(setWantsRestingTouches:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:self];
        [inv setSelector:@selector(setWantsRestingTouches:)];
        [inv setArgument:&value atIndex:2];
        [inv invoke];
    }
}
@end

@implementation NSEvent (Future)
- (NSArray *)futureTouchesMatchingPhase:(int)phase inView:(NSView *)view
{
    if ([self respondsToSelector:@selector(touchesMatchingPhase:inView:)]) {
        NSMethodSignature *sig = [[self class] instanceMethodSignatureForSelector:@selector(touchesMatchingPhase:inView:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:self];
        [inv setSelector:@selector(touchesMatchingPhase:inView:)];
        [inv setArgument:&phase atIndex:2];
        [inv setArgument:&view atIndex:3];
        [inv invoke];
        NSArray *result;
        [inv getReturnValue:&result];
        return result;
    } else {
        return [NSArray array];
    }
}
@end
