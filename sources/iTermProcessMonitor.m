//
//  iTermProcessMonitor.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/21/19.
//

#import "iTermProcessMonitor.h"

#import "DebugLogging.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSArray+iTerm.h"

@interface iTermProcessMonitor()
@property (nonatomic, weak, readwrite) iTermProcessMonitor *parent;
@end

@implementation iTermProcessMonitor {
    dispatch_source_t _source;
    NSMutableArray<iTermProcessMonitor *> *_children;
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue
                     callback:(void (^)(iTermProcessMonitor *, dispatch_source_proc_flags_t))callback {
    self = [super init];
    if (self) {
        _callback = [callback copy];
        _queue = queue;
        _children = [NSMutableArray array];
    }
    return self;
}

- (BOOL)setProcessInfo:(iTermProcessInfo *)processInfo {
    return [self setProcessInfo:processInfo depth:0];
}

- (BOOL)setProcessInfo:(iTermProcessInfo *)processInfo depth:(NSInteger)depth {
    if (![iTermAdvancedSettingsModel fastForegroundJobUpdates]) {
        return NO;
    }
    if (processInfo == _processInfo) {
        return NO;
    }
    if (depth > 50) {
        // Avoid running out of stack for really tall process trees like fork bombs.
        return NO;
    }
    if (processInfo == nil) {
        [self invalidate];
        _processInfo = nil;
        return YES;
    }
    __block BOOL changed = NO;
    if (_processInfo != nil && processInfo.processID != _processInfo.processID) {
        [self invalidate];
        changed = YES;
    }

    if (_processInfo == nil) {
        changed = YES;
        DLog(@"Monitor process %@", processInfo);
        _source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC,
                                         processInfo.processID,
                                         DISPATCH_PROC_EXIT | DISPATCH_PROC_FORK | DISPATCH_PROC_EXEC | DISPATCH_PROC_SIGNAL,
                                         _queue);
        if (!_source) {
            [self invalidate];
            return NO;
        }
        __weak __typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(_source, ^{
            [weakSelf handleEvent];
        });
        dispatch_resume(_source);
    }

    NSMutableArray<iTermProcessMonitor *> *childrenToAdd = [NSMutableArray array];;
    NSMutableArray<iTermProcessMonitor *> *childrenToRemove = [_children mutableCopy];

    [processInfo.children enumerateObjectsUsingBlock:
     ^(iTermProcessInfo * _Nonnull childInfo, NSUInteger idx, BOOL * _Nonnull stop) {
        // See if we already have this child.
        iTermProcessMonitor *child = [self childForProcessInfo:childInfo];
        if (child != nil) {
            // It is. Keep it.
            [childrenToRemove removeObject:child];
            if ([child setProcessInfo:childInfo depth:depth + 1]) {
                changed = YES;
            }
            return;
        }

        // Create a new one.
        child = [[iTermProcessMonitor alloc] initWithQueue:_queue callback:_callback];;
        [child setProcessInfo:childInfo depth:depth + 1];
        [childrenToAdd addObject:child];
    }];
    [childrenToAdd enumerateObjectsUsingBlock:^(iTermProcessMonitor * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
        [self addChild:child];
    }];
    [childrenToRemove enumerateObjectsUsingBlock:^(iTermProcessMonitor * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
        [self removeChild:child];
    }];
    if (childrenToAdd.count || childrenToRemove.count) {
        changed = YES;
    }
    _processInfo = processInfo;
    return changed;
}

- (iTermProcessMonitor *)childForProcessInfo:(iTermProcessInfo *)info {
    const pid_t pid = info.processID;
    return [_children objectPassingTest:^BOOL(iTermProcessMonitor *element, NSUInteger index, BOOL *stop) {
        return element.processInfo.processID == pid;
    }];
}

// Called on _queue
- (void)handleEvent {
    const dispatch_source_proc_flags_t flags = (dispatch_source_proc_flags_t)dispatch_source_get_data(_source);
    _callback(self, flags);
    if (flags & DISPATCH_PROC_EXIT) {
        [self invalidate];
    }
}

// Called on _queue
- (void)invalidate {
    if (_source == nil) {
        return;
    }
    DLog(@"Stop monitoring process %@", _processInfo);
    dispatch_source_cancel(_source);
    _source = nil;
    [_parent removeChild:self];

    NSArray<iTermProcessMonitor *> *children = [_children copy];
    [children enumerateObjectsUsingBlock:^(iTermProcessMonitor * _Nonnull child, NSUInteger idx, BOOL * _Nonnull stop) {
        [child invalidate];
    }];
    _processInfo = nil;
}

// Called on _queue
- (void)addChild:(iTermProcessMonitor *)child {
    [_children addObject:child];
    child.parent = self;
}

// Called on _queue
- (void)removeChild:(iTermProcessMonitor *)child {
    if (child.parent == self) {
        [_children removeObject:child];
        child.parent = nil;
    }
}

@end

