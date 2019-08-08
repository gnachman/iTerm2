//
//  iTermGitState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitState.h"

#import "DebugLogging.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"

static NSString *const iTermGitStateVariableNameGitBranch = @"user.gitBranch";
static NSString *const iTermGitStateVariableNameGitPushCount = @"user.gitPushCount";
static NSString *const iTermGitStateVariableNameGitPullCount = @"user.gitPullCount";
static NSString *const iTermGitStateVariableNameGitDirty = @"user.gitDirty";
static NSString *const iTermGitStateVariableNameGitAdds = @"user.gitAdds";
static NSString *const iTermGitStateVariableNameGitDeletes = @"user.gitDeletes";

static NSArray<NSString *> *iTermGitStatePaths(void) {
    return @[ iTermGitStateVariableNameGitBranch,
              iTermGitStateVariableNameGitPushCount,
              iTermGitStateVariableNameGitPullCount,
              iTermGitStateVariableNameGitDirty,
              iTermGitStateVariableNameGitAdds,
              iTermGitStateVariableNameGitDeletes ];
}

@implementation iTermGitState {
    NSTimeInterval _creationTime;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope {
    self = [self init];
    if (self) {
        for (NSString *path in iTermGitStatePaths()) {
            if (![scope valueForVariableName:path]) {
                DLog(@"%@ is not set; cannot construct git state from scope", path);
                return nil;
            }
        }
        _directory = [scope valueForVariableName:iTermVariableKeySessionID] ?: @"(null)";
        _branch = [scope valueForVariableName:iTermGitStateVariableNameGitBranch];
        _pushArrow = [scope valueForVariableName:iTermGitStateVariableNameGitPushCount];
        _pullArrow = [scope valueForVariableName:iTermGitStateVariableNameGitPullCount];
        _dirty = [[scope valueForVariableName:iTermGitStateVariableNameGitDirty] boolValue];
        _adds = [[scope valueForVariableName:iTermGitStateVariableNameGitAdds] integerValue];
        _deletes = [[scope valueForVariableName:iTermGitStateVariableNameGitDeletes] integerValue];
        _creationTime = [NSDate it_timeSinceBoot];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    iTermGitState *theCopy = [[iTermGitState alloc] init];
    theCopy.xcode = self.xcode.copy;
    theCopy.pushArrow = self.pushArrow.copy;
    theCopy.pullArrow = self.pullArrow.copy;
    theCopy.branch = self.branch.copy;
    theCopy.dirty = self.dirty;
    theCopy.adds = self.adds;
    theCopy.deletes = self.deletes;
    return theCopy;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p dir=%@ xcode=%@ push=%@ pull=%@ branch=%@ dirty=%@ adds=%@ deletes=%@>",
            self.class, self,
            _directory, _xcode, _pushArrow, _pullArrow, _branch, @(_dirty), @(_adds), @(_deletes)];
}

- (NSTimeInterval)age {
    return [NSDate it_timeSinceBoot] - _creationTime;
}

@end

@implementation iTermRemoteGitStateObserver {
    NSArray<iTermVariableReference *> *_refs;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope
                        block:(void (^)(void))block {
    self = [super init];
    if (self) {
        NSArray<NSString *> *paths = iTermGitStatePaths();
        _refs = [paths mapWithBlock:^id(NSString *path) {
            iTermVariableReference *ref = [[iTermVariableReference alloc] initWithPath:path vendor:scope];
            ref.onChangeBlock = block;
            return ref;
        }];
    }
    return self;
}

@end
