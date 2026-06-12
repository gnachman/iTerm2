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

NSString *const iTermGitStateVariableNameGitLinesInserted = @"user.gitLinesInserted";
NSString *const iTermGitStateVariableNameGitLinesDeleted = @"user.gitLinesDeleted";
NSString *const iTermGitStateVariableNameGitFilesAdded = @"user.gitFilesAdded";
NSString *const iTermGitStateVariableNameGitFilesModified = @"user.gitFilesModified";
NSString *const iTermGitStateVariableNameGitFilesDeleted = @"user.gitFilesDeleted";

NSArray<NSString *> *iTermGitStatePaths(void) {
    return @[ iTermGitStateVariableNameGitBranch,
              iTermGitStateVariableNameGitPushCount,
              iTermGitStateVariableNameGitPullCount,
              iTermGitStateVariableNameGitDirty,
              iTermGitStateVariableNameGitAdds,
              iTermGitStateVariableNameGitDeletes ];
}

NSArray<NSString *> *iTermGitStateOptionalPaths(void) {
    return @[ iTermGitStateVariableNameGitLinesInserted,
              iTermGitStateVariableNameGitLinesDeleted,
              iTermGitStateVariableNameGitFilesAdded,
              iTermGitStateVariableNameGitFilesModified,
              iTermGitStateVariableNameGitFilesDeleted ];
}

@implementation iTermGitFileStatus

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.path forKey:@"path"];
    [coder encodeInteger:self.indexStatus forKey:@"indexStatus"];
    [coder encodeInteger:self.workdirStatus forKey:@"workdirStatus"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _path = [[coder decodeObjectOfClass:[NSString class] forKey:@"path"] copy];
        _indexStatus = (iTermGitFileChangeKind)[coder decodeIntegerForKey:@"indexStatus"];
        _workdirStatus = (iTermGitFileChangeKind)[coder decodeIntegerForKey:@"workdirStatus"];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    iTermGitFileStatus *theCopy = [[iTermGitFileStatus alloc] init];
    theCopy.path = self.path.copy;
    theCopy.indexStatus = self.indexStatus;
    theCopy.workdirStatus = self.workdirStatus;
    return theCopy;
}

@end

@implementation iTermGitState

#pragma mark NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.xcode forKey:@"xcode"];
    [coder encodeObject:self.ahead forKey:@"ahead"];
    [coder encodeObject:self.behind forKey:@"behind"];
    [coder encodeObject:self.branch forKey:@"branch"];
    [coder encodeBool:self.dirty forKey:@"dirty"];
    [coder encodeInteger:self.adds forKey:@"adds"];
    [coder encodeInteger:self.deletes forKey:@"deletes"];
    [coder encodeInteger:self.linesInserted forKey:@"linesInserted"];
    [coder encodeInteger:self.linesDeleted forKey:@"linesDeleted"];
    [coder encodeInteger:self.filesAdded forKey:@"filesAdded"];
    [coder encodeInteger:self.filesModified forKey:@"filesModified"];
    [coder encodeInteger:self.filesDeleted forKey:@"filesDeleted"];
    [coder encodeObject:self.fileStatuses forKey:@"fileStatuses"];
    [coder encodeInteger:self.creationTime forKey:@"creationTime"];
    [coder encodeInteger:self.repoState forKey:@"repoState"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _xcode = [coder decodeObjectOfClass:[NSString class] forKey:@"xcode"];
        _ahead = [coder decodeObjectOfClass:[NSString class] forKey:@"ahead"];
        _behind = [coder decodeObjectOfClass:[NSString class] forKey:@"behind"];
        _branch = [coder decodeObjectOfClass:[NSString class] forKey:@"branch"];
        _dirty = [coder decodeBoolForKey:@"dirty"];
        _adds = [coder decodeIntegerForKey:@"adds"];
        _deletes = [coder decodeIntegerForKey:@"deletes"];
        _linesInserted = [coder decodeIntegerForKey:@"linesInserted"];
        _linesDeleted = [coder decodeIntegerForKey:@"linesDeleted"];
        _filesAdded = [coder decodeIntegerForKey:@"filesAdded"];
        _filesModified = [coder decodeIntegerForKey:@"filesModified"];
        _filesDeleted = [coder decodeIntegerForKey:@"filesDeleted"];
        _fileStatuses = [[coder decodeObjectOfClasses:[NSSet setWithObjects:[NSArray class], [iTermGitFileStatus class], nil]
                                               forKey:@"fileStatuses"] copy];
        _creationTime = [coder decodeIntegerForKey:@"creationTime"];
        _repoState = [coder decodeIntegerForKey:@"repoState"];
    }
    return self;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone {
    iTermGitState *theCopy = [[iTermGitState alloc] init];
    theCopy.xcode = self.xcode.copy;
    theCopy.ahead = self.ahead.copy;
    theCopy.behind = self.behind.copy;
    theCopy.branch = self.branch.copy;
    theCopy.dirty = self.dirty;
    theCopy.adds = self.adds;
    theCopy.deletes = self.deletes;
    theCopy.linesInserted = self.linesInserted;
    theCopy.linesDeleted = self.linesDeleted;
    theCopy.filesAdded = self.filesAdded;
    theCopy.filesModified = self.filesModified;
    theCopy.filesDeleted = self.filesDeleted;
    theCopy.fileStatuses = [[NSArray alloc] initWithArray:self.fileStatuses
                                                 copyItems:YES];
    return theCopy;
}

#pragma mark NSObject

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p dir=%@ xcode=%@ ahead=%@ behind=%@ branch=%@ dirty=%@ adds=%@ deletes=%@ lines=+%@/-%@ files=+%@/~%@/-%@>",
            self.class, self,
            _directory, _xcode, _ahead, _behind, _branch, @(_dirty),
            @(_adds), @(_deletes),
            @(_linesInserted), @(_linesDeleted),
            @(_filesAdded), @(_filesModified), @(_filesDeleted)];
}

- (NSString *)prettyDescription {
    return [NSString stringWithFormat:@"dir=%@ xcode=%@ ahead=%@ behind=%@ branch=%@ dirty=%@ adds=%@ deletes=%@ lines=+%@/-%@ files=+%@/~%@/-%@",
            _directory, _xcode, _ahead, _behind, _branch, @(_dirty),
            @(_adds), @(_deletes),
            @(_linesInserted), @(_linesDeleted),
            @(_filesAdded), @(_filesModified), @(_filesDeleted)];
}
@end

