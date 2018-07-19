//
//  iTermStatusBarJobComponent.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/18.
//

#import "iTermStatusBarJobComponent.h"

#import "iTermVariables.h"
#import "NSArray+iTerm.h"
#import "NSObject+iTerm.h"
#import "iTermProcessCache.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermStatusBarJobComponent {
    NSArray<NSString *> *_cached;
    NSArray<NSString *> *_chain;
}

- (NSString *)statusBarComponentShortDescription {
    return @"Job Name";
}

- (NSString *)statusBarComponentDetailedDescription {
    return @"Shows the currently running job. If space permits, parent process names are also shown.";
}

- (id)statusBarComponentExemplar {
    return @"vim ◂ bash";
}

- (BOOL)statusBarComponentCanStretch {
    return YES;
}

- (nullable NSArray<NSString *> *)stringVariants {
    return _cached ?: @[ @"" ];
}

- (NSSet<NSString *> *)statusBarComponentVariableDependencies {
    return [NSSet setWithArray:@[ iTermVariableKeySessionJobPid,
                                  iTermVariableKeySessionChildPid ]];
}

- (NSTimeInterval)statusBarComponentUpdateCadence {
    return 1;
}

- (void)updateTextFieldIfNeeded {
    int pid = [NSNumber castFrom:[self.scope valueForVariableName:iTermVariableKeySessionJobPid]].intValue;
    [self setChain:[self newAncestryChainForPid:pid]];
    [super updateTextFieldIfNeeded];
}

- (NSArray<NSString *> *)newAncestryChainForPid:(int)pid {
    iTermProcessInfo *deepestForegroundJob = [[iTermProcessCache sharedInstance] processInfoForPid:pid];
    int sessionTaskPid = [NSNumber castFrom:[self.scope valueForVariableName:iTermVariableKeySessionChildPid]].intValue;

    iTermProcessInfo *current = deepestForegroundJob;
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    while (current) {
        if (current.processID == sessionTaskPid && [current.name isEqualToString:@"login"]) {
            // Don't include login.
            break;
        }
        [chain addObject:current.name ?: @"?"];
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

@end

NS_ASSUME_NONNULL_END
