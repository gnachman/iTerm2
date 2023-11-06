//
//  VT100ScreenStateSanitizingAdapter.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/29/22.
//

#import "VT100ScreenStateSanitizingAdapter.h"
#import "VT100ScreenMutableState+Private.h"
#import "VT100ScreenState+Private.h"
#import "VT100RemoteHost.h"

@interface VT100ScreenStateSanitizingAdapterImpl: NSObject
@property (nonatomic, weak) VT100ScreenMutableState *source;
@end

// Methods this class implements take precedence over those in VT100ScreenMutableState when accessed through VT100ScreenSanitizingAdapter.
@implementation VT100ScreenStateSanitizingAdapterImpl {
    iTermIntervalTreeSanitizingAdapter *_intervalTreeSanitizingAdapter;
    iTermIntervalTreeSanitizingAdapter *_savedIntervalTreeSanitizingAdapter;
}

- (instancetype)initWithSource:(VT100ScreenMutableState *)source {
    self = [super init];
    if (self) {
        _source = source;
        _intervalTreeSanitizingAdapter = [[iTermIntervalTreeSanitizingAdapter alloc] initWithSource:source.mutableIntervalTree];
        _savedIntervalTreeSanitizingAdapter = [[iTermIntervalTreeSanitizingAdapter alloc] initWithSource:source.mutableSavedIntervalTree];
    }
    return self;
}

- (void)mergeFrom:(VT100ScreenMutableState *)source {
    // You'd get here with reentrant joined threads. Only the real state should do a merge.
}

- (id<iTermMarkCacheReading>)markCache {
    return [[_source markCache] sanitizingAdapter];
}

- (id<IntervalTreeReading>)intervalTree {
    return _intervalTreeSanitizingAdapter;
}

- (id<IntervalTreeReading>)savedIntervalTree {
    return _savedIntervalTreeSanitizingAdapter;
}

- (id<VT100ScreenMarkReading>)lastCommandMark {
    return [[_source lastCommandMark] doppelganger];
}

- (__kindof id<IntervalTreeImmutableObject>)objectOnOrBeforeLine:(int)line ofClass:(Class)cls {
    return [[_source objectOnOrBeforeLine:line ofClass:cls] doppelganger];
}

- (id<VT100RemoteHostReading>)lastRemoteHost {
    VT100RemoteHost *remoteHost = (VT100RemoteHost *)[_source lastRemoteHost];
    return (id<VT100RemoteHostReading>)[remoteHost doppelganger];
}

- (id<VT100ScreenMarkReading>)lastPromptMark {
    return [[_source lastPromptMark] doppelganger];
}

- (id<VT100ScreenMarkReading> _Nullable)markOnLine:(int)line {
    return [[_source markOnLine:line] doppelganger];
}

- (id<VT100ScreenMarkReading>)commandMarkAt:(VT100GridCoord)coord range:(out nonnull VT100GridWindowedRange *)range {
    return [[_source commandMarkAt:coord range:range] doppelganger];
}

- (id<IntervalTreeImmutableObject>)lastMarkMustBePrompt:(BOOL)wantPrompt class:(Class)theClass {
    return [[_source lastMarkMustBePrompt:wantPrompt class:theClass] doppelganger];
}

- (id<VT100RemoteHostReading>)remoteHostOnLine:(int)line {
    return (id<VT100RemoteHostReading>)[(VT100RemoteHost *)[_source remoteHostOnLine:line] doppelganger];
}

- (id<iTermColorMapReading>)colorMap {
    return [_source.mutableColorMap sanitizingAdapter];
}

@end

@implementation VT100ScreenStateSanitizingAdapter {
    VT100ScreenStateSanitizingAdapterImpl *_impl;
}

- (instancetype)initWithSource:(VT100ScreenMutableState *)source {
    _impl = [[VT100ScreenStateSanitizingAdapterImpl alloc] initWithSource:source];
    return self;
}

- (id)forwardingTargetForSelector:(SEL)aSelector {
    if ([_impl respondsToSelector:aSelector]) {
        return _impl;
    }
    return _impl.source;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [_impl respondsToSelector:aSelector] || [_impl.source respondsToSelector:aSelector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [_impl.source methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    anInvocation.target = [_impl respondsToSelector:anInvocation.selector] ? _impl : _impl.source;
    [anInvocation invoke];
}

@end
