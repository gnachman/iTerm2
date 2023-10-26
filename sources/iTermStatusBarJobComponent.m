//
//  iTermStatusBarJobComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import "iTermStatusBarJobComponent.h"

#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSImage+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermJobTreeViewController.h"
#import "iTermPreferences.h"
#import "iTermProcessCache.h"
#import "iTermVariableReference.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermStatusBarJobComponent()
@end

@implementation iTermStatusBarJobComponent {
    NSArray<NSString *> *_cached;
    NSArray<NSString *> *_chain;
    iTermVariableReference *_jobPidRef;
    iTermVariableReference *_childPidRef;

}

- (instancetype)initWithConfiguration:(NSDictionary<iTermStatusBarComponentConfigurationKey,id> *)configuration
                                scope:(nullable iTermVariableScope *)scope {
    self = [super initWithConfiguration:configuration scope:scope];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        _jobPidRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionJobPid vendor:scope];
        _jobPidRef.onChangeBlock = ^{
            [weakSelf updateTextFieldIfNeeded];
        };

        _childPidRef = [[iTermVariableReference alloc] initWithPath:iTermVariableKeySessionEffectiveSessionRootPid vendor:scope];
        _childPidRef.onChangeBlock = ^{
            [weakSelf updateTextFieldIfNeeded];
        };
    }
    return self;
}

+ (NSDictionary *)statusBarComponentDefaultKnobs {
    NSDictionary *fromSuper = [super statusBarComponentDefaultKnobs];
    return [fromSuper dictionaryByMergingDictionary:self.defaultMinMaxWidthKnobValues];
}

- (CGFloat)statusBarComponentPreferredWidth {
    return [self clampedWidth:[super statusBarComponentPreferredWidth]];
}

- (nullable NSImage *)statusBarComponentIcon {
    return [NSImage it_cacheableImageNamed:@"StatusBarIconJobs" forClass:[self class]];
}

- (NSString *)statusBarComponentShortDescription {
    return @"Job Name";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows the currently running job. If space permits, parent process names are also shown.";
}

- (id)statusBarComponentExemplarWithBackgroundColor:(NSColor *)backgroundColor
                                          textColor:(NSColor *)textColor {
    return @"vim ◂ bash";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return _cached ?: @[ @"" ];
}

- (void)updateTextFieldIfNeeded {
    int pid = [NSNumber castFrom:[self.scope valueForVariableName:iTermVariableKeySessionJobPid]].intValue;
    [self setChain:[self newAncestryChainForPid:pid]];
    [super updateTextFieldIfNeeded];
}

- (NSArray<NSString *> *)newAncestryChainForPid:(int)pid {
    iTermProcessInfo *deepestForegroundJob = [[self.delegate statusBarComponentProcessInfoProvider] processInfoForPid:pid];
    int sessionTaskPid = [NSNumber castFrom:[self.scope valueForVariableName:iTermVariableKeySessionEffectiveSessionRootPid]].intValue;

    iTermProcessInfo *current = deepestForegroundJob;
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    while (current) {
        if (current.processID == sessionTaskPid && [current.name isEqualToString:@"login"]) {
            // Don't include login.
            break;
        }
        [chain addObject:current.argv0 ?: current.name ?: @"?"];
        if (current.processID == sessionTaskPid || !sessionTaskPid) {
            break;
        }
        current = current.parent;
    }
    return chain;
}

- (void)setChain:(NSArray<NSString *> *)chain {
    if ([NSObject object:chain isEqualToObject:_chain]) {
        return;
    }
    _chain = [chain copy];
    _cached = [self variantsOfChain:chain];
}

- (NSArray<NSString *> *)variantsOfChain:(NSArray<NSString *> *)chain {
    NSMutableArray<NSString *> *temp = [NSMutableArray array];
    for (NSInteger i = 0; i < chain.count; i++) {
        NSArray<NSString *> *subarray = [chain subarrayWithRange:NSMakeRange(0, i + 1)];
        NSString *joined = [subarray componentsJoinedByString:@" ◂ "];
        [temp addObject:joined];
    }
    return [temp copy];
}

- (BOOL)statusBarComponentHandlesClicks {
    return YES;
}

- (void)statusBarComponentMouseDownWithView:(NSView *)view {
}

- (void)statusBarComponentDidClickWithView:(NSView *)view {
    NSPopover *popover = [[NSPopover alloc] init];
    popover.appearance = view.effectiveAppearance;
    pid_t pid = [[self.scope valueForVariableName:iTermVariableKeySessionEffectiveSessionRootPid] integerValue];
    iTermJobTreeViewController *viewController = [[iTermJobTreeViewController alloc] initWithProcessID:pid
                                                                                   processInfoProvider:[self.delegate statusBarComponentProcessInfoProvider]];
    viewController.font = [self font];
    popover.contentViewController = viewController;
    popover.contentSize = viewController.view.frame.size;
    popover.behavior = NSPopoverBehaviorSemitransient;
    NSRectEdge preferredEdge = NSRectEdgeMinY;
    switch ([iTermPreferences unsignedIntegerForKey:kPreferenceKeyStatusBarPosition]) {
        case iTermStatusBarPositionTop:
            preferredEdge = NSRectEdgeMaxY;
            break;
        case iTermStatusBarPositionBottom:
            preferredEdge = NSRectEdgeMinY;
            break;
    }
    NSView *relativeView = view.subviews.firstObject ?: view;
    NSRect rect = relativeView.bounds;
    rect.size.width = [self statusBarComponentMinimumWidth];
    [popover showRelativeToRect:rect
                         ofView:relativeView
                  preferredEdge:preferredEdge];
    [viewController sizeOutlineViewToFit];
}

#pragma mark - ProcessInfoProvider

- (iTermProcessInfo * _Nullable)processInfoForPid:(pid_t)pid {
    return [[self.delegate statusBarComponentProcessInfoProvider] processInfoForPid:pid];
}

- (void)setNeedsUpdate:(BOOL)needsUpdate {
    return [[self.delegate statusBarComponentProcessInfoProvider] setNeedsUpdate:needsUpdate];
}

- (void)requestImmediateUpdateWithCompletionBlock:(void (^)(void))completion {
    [[self.delegate statusBarComponentProcessInfoProvider] requestImmediateUpdateWithCompletionBlock:completion];
}

- (void)updateSynchronously {
    [[self.delegate statusBarComponentProcessInfoProvider] updateSynchronously];
}

- (iTermProcessInfo * _Nullable)deepestForegroundJobForPid:(pid_t)pid {
    return [[self.delegate statusBarComponentProcessInfoProvider] deepestForegroundJobForPid:pid];
}

- (void)registerTrackedPID:(pid_t)pid {
    [[self.delegate statusBarComponentProcessInfoProvider] registerTrackedPID:pid];
}

- (void)unregisterTrackedPID:(pid_t)pid {
    [[self.delegate statusBarComponentProcessInfoProvider] unregisterTrackedPID:pid];
}

- (BOOL)processIsDirty:(pid_t)pid {
    return [[self.delegate statusBarComponentProcessInfoProvider] processIsDirty:pid];
}

@end

NS_ASSUME_NONNULL_END
