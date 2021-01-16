//
//  iTermGitState.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import "iTermGitState.h"

NSString *const iTermGitStateVariableNameGitBranch = @"user.gitBranch";
NSString *const iTermGitStateVariableNameGitPushCount = @"user.gitPushCount";
NSString *const iTermGitStateVariableNameGitPullCount = @"user.gitPullCount";
NSString *const iTermGitStateVariableNameGitDirty = @"user.gitDirty";
NSString *const iTermGitStateVariableNameGitAdds = @"user.gitAdds";
NSString *const iTermGitStateVariableNameGitDeletes = @"user.gitDeletes";

NSArray<NSString *> *iTermGitStatePaths(void) {
    return @[ iTermGitStateVariableNameGitBranch,
              iTermGitStateVariableNameGitPushCount,
              iTermGitStateVariableNameGitPullCount,
              iTermGitStateVariableNameGitDirty,
              iTermGitStateVariableNameGitAdds,
              iTermGitStateVariableNameGitDeletes ];
}

@implementation iTermGitState

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.xcode forKey:@"xcode"];
    [coder encodeObject:self.pushArrow forKey:@"pushArrow"];
    [coder encodeObject:self.pullArrow forKey:@"pullArrow"];
    [coder encodeObject:self.branch forKey:@"branch"];
    [coder encodeBool:self.dirty forKey:@"dirty"];
    [coder encodeInteger:self.adds forKey:@"adds"];
    [coder encodeInteger:self.deletes forKey:@"deletes"];
    [coder encodeInteger:self.creationTime forKey:@"creationTime"];
    [coder encodeInteger:self.repoState forKey:@"repoState"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _xcode = [coder decodeObjectOfClass:[NSString class] forKey:@"xcode"];
        _pushArrow = [coder decodeObjectOfClass:[NSString class] forKey:@"pushArrow"];
        _pullArrow = [coder decodeObjectOfClass:[NSString class] forKey:@"pullArrow"];
        _branch = [coder decodeObjectOfClass:[NSString class] forKey:@"branch"];
        _dirty = [coder decodeBoolForKey:@"dirty"];
        _adds = [coder decodeIntegerForKey:@"adds"];
        _deletes = [coder decodeIntegerForKey:@"deletes"];
        _creationTime = [coder decodeIntegerForKey:@"creationTime"];
        _repoState = [coder decodeIntegerForKey:@"repoState"];
    }
    return self;
}

#pragma mark NSCopying

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

#pragma mark NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p dir=%@ xcode=%@ push=%@ pull=%@ branch=%@ dirty=%@ adds=%@ deletes=%@>",
            self.class, self,
            _directory, _xcode, _pushArrow, _pullArrow, _branch, @(_dirty), @(_adds), @(_deletes)];
}

@end

