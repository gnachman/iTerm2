//
//  iTermGitState+MainApp.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/21.
//

#import "iTermGitState+MainApp.h"

#import "DebugLogging.h"
#import "iTermVariableReference.h"
#import "iTermVariableScope.h"
#import "NSArray+iTerm.h"
#import "NSDate+iTerm.h"

@interface NSString(GitState)
@property (nonatomic, readonly) BOOL gitDirtyBoolValue;
@end

@implementation NSString(GitState)
- (BOOL)gitDirtyBoolValue {
    if ([self isEqualToString:@"dirty"]) {
        return YES;
    }
    if ([self isEqualToString:@"clean"]) {
        return NO;
    }
    return [self boolValue];
}
@end

@implementation iTermGitState (MainApp)

- (instancetype)initWithScope:(iTermVariableScope *)scope {
    self = [self init];
    if (self) {
        for (NSString *path in iTermGitStatePaths()) {
            if (![scope valueForVariableName:path]) {
                DLog(@"%@ is not set; cannot construct git state from scope", path);
                return nil;
            }
        }
        self.directory = [scope valueForVariableName:iTermVariableKeySessionID] ?: @"(null)";
        self.branch = [scope valueForVariableName:iTermGitStateVariableNameGitBranch];
        self.ahead = [scope valueForVariableName:iTermGitStateVariableNameGitPushCount];
        self.behind = [scope valueForVariableName:iTermGitStateVariableNameGitPullCount];
        self.dirty = [[scope valueForVariableName:iTermGitStateVariableNameGitDirty] gitDirtyBoolValue];
        self.adds = [[scope valueForVariableName:iTermGitStateVariableNameGitAdds] integerValue];
        self.deletes = [[scope valueForVariableName:iTermGitStateVariableNameGitDeletes] integerValue];
        // Optional richer stats — left at 0 when the remote it2git doesn't emit them.
        self.linesInserted = [[scope valueForVariableName:iTermGitStateVariableNameGitLinesInserted] integerValue];
        self.linesDeleted = [[scope valueForVariableName:iTermGitStateVariableNameGitLinesDeleted] integerValue];
        self.filesAdded = [[scope valueForVariableName:iTermGitStateVariableNameGitFilesAdded] integerValue];
        self.filesModified = [[scope valueForVariableName:iTermGitStateVariableNameGitFilesModified] integerValue];
        self.filesDeleted = [[scope valueForVariableName:iTermGitStateVariableNameGitFilesDeleted] integerValue];
        self.creationTime = [NSDate it_timeSinceBoot];
    }
    return self;
}

- (NSTimeInterval)age {
    return [NSDate it_timeSinceBoot] - self.creationTime;
}

@end

@implementation iTermRemoteGitStateObserver {
    NSArray<iTermVariableReference *> *_refs;
}

- (instancetype)initWithScope:(iTermVariableScope *)scope
                        block:(void (^)(void))block {
    self = [super init];
    if (self) {
        NSArray<NSString *> *paths = [iTermGitStatePaths() arrayByAddingObjectsFromArray:iTermGitStateOptionalPaths()];
        _refs = [paths mapWithBlock:^id(NSString *path) {
            iTermVariableReference *ref = [[iTermVariableReference alloc] initWithPath:path vendor:scope];
            ref.onChangeBlock = block;
            return ref;
        }];
    }
    return self;
}

@end
