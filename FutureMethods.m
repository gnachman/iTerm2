//
//  FutureMethods.m
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "FutureMethods.h"

const int FutureNSWindowCollectionBehaviorStationary = (1 << 4);  // value stolen from 10.6 SDK

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

- (NSRect)futureConvertRectToScreen:(NSRect)rect
{
    if ([[self window] respondsToSelector:@selector(convertRectToScreen:)]) {
        NSMethodSignature *sig = [[[self window] class] instanceMethodSignatureForSelector:@selector(convertRectToScreen:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:[self window]];
        [inv setSelector:@selector(convertRectToScreen:)];
        [inv setArgument:&rect atIndex:2];
        [inv invoke];
        NSRect result;
        [inv getReturnValue:&result];
        return result;
    } else {
        NSPoint p1 = [self convertPointToBase:rect.origin];
        NSPoint p2 = [self convertPointToBase:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.width)];
        return NSMakeRect(MIN(p1.x, p2.x), MIN(p1.y, p2.y), fabs(p1.x - p2.x), fabs(p1.y - p2.y));
    }
}

- (NSRect)futureConvertRectFromScreen:(NSRect)rect {
    if ([[self window] respondsToSelector:@selector(convertRectFromScreen:)]) {
        NSMethodSignature *sig = [[[self window] class] instanceMethodSignatureForSelector:@selector(convertRectFromScreen:)];
        NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
        [inv setTarget:[self window]];
        [inv setSelector:@selector(convertRectFromScreen:)];
        [inv setArgument:&rect atIndex:2];
        [inv invoke];
        NSRect result;
        [inv getReturnValue:&result];
        return result;
    } else {
        NSPoint p1 = [self convertPointFromBase:rect.origin];
        NSPoint p2 = [self convertPointFromBase:NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.width)];
        return NSMakeRect(MIN(p1.x, p2.x), MIN(p1.y, p2.y), fabs(p1.x - p2.x), fabs(p1.y - p2.y));
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

static FutureNSScrollerStyle GetScrollerStyle(id theObj)
{
    NSMethodSignature *sig = [[NSScroller class] instanceMethodSignatureForSelector:@selector(scrollerStyle)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:theObj];
    [inv setSelector:@selector(scrollerStyle)];
    [inv invoke];
    FutureNSScrollerStyle result;
    [inv getReturnValue:&result];
    return result;
}

@implementation NSScroller (Future)

- (FutureNSScrollerStyle)futureScrollerStyle
{
    if ([self respondsToSelector:@selector(scrollerStyle)]) {
        return GetScrollerStyle(self);
    } else {
        return FutureNSScrollerStyleLegacy;
    }
}

@end

@implementation NSScrollView (Future)

- (FutureNSScrollerStyle)futureScrollerStyle
{
    if ([self respondsToSelector:@selector(scrollerStyle)]) {
        return GetScrollerStyle(self);
    } else {
        return FutureNSScrollerStyleLegacy;
    }
}

@end

@implementation CIImage (Future)


@end

@implementation NSObject (Future)

- (BOOL)performSelectorReturningBool:(SEL)selector withObjects:(NSArray *)objects {
    NSMethodSignature *mySignature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:mySignature];
    [myInvocation setTarget:self];
    [myInvocation setSelector:selector];
    void *pointers[objects.count];
    for (int i = 0; i < objects.count; i++) {
        pointers[i] = [objects objectAtIndex:i];
        [myInvocation setArgument:&pointers[i]  // pointer to object
                          atIndex:i];
    }
    [myInvocation invoke];
    BOOL result;
    [myInvocation getReturnValue:&result];
    return result;
}

- (void)performSelector:(SEL)selector takingNSInteger:(NSInteger)arg {
    NSMethodSignature *mySignature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:mySignature];
    [myInvocation setTarget:self];
    [myInvocation setSelector:selector];
    [myInvocation setArgument:&arg
                      atIndex:2];
    [myInvocation invoke];
}

@end

@implementation NSScroller (future)

- (void)futureSetKnobStyle:(NSInteger)newKnobStyle {
    if ([self respondsToSelector:@selector(setKnobStyle:)]) {
        [self performSelector:@selector(setKnobStyle:) takingNSInteger:newKnobStyle];
    }
}

@end
