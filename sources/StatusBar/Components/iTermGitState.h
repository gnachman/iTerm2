//
//  iTermGitState.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/7/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSArray<NSString *> *iTermGitStatePaths(void);
// Paths that may or may not be set; a remote session with an older it2git
// script won't populate these.
extern NSArray<NSString *> *iTermGitStateOptionalPaths(void);

extern NSString *const iTermGitStateVariableNameGitBranch;
extern NSString *const iTermGitStateVariableNameGitPushCount;
extern NSString *const iTermGitStateVariableNameGitPullCount;
extern NSString *const iTermGitStateVariableNameGitDirty;
extern NSString *const iTermGitStateVariableNameGitAdds;
extern NSString *const iTermGitStateVariableNameGitDeletes;

// Optional — populated by newer it2git scripts only. When absent the
// corresponding iTermGitState fields stay 0 and the minimal rendering path
// is used.
extern NSString *const iTermGitStateVariableNameGitLinesInserted;
extern NSString *const iTermGitStateVariableNameGitLinesDeleted;
extern NSString *const iTermGitStateVariableNameGitFilesAdded;
extern NSString *const iTermGitStateVariableNameGitFilesModified;
extern NSString *const iTermGitStateVariableNameGitFilesDeleted;

typedef NS_ENUM(NSInteger, iTermGitRepoState) {
    iTermGitRepoStateNone,
    iTermGitRepoStateMerge,
    iTermGitRepoStateRevert,
    iTermGitRepoStateCherrypick,
    iTermGitRepoStateBisect,
    iTermGitRepoStateRebase,
    iTermGitRepoStateApply,
};

@interface iTermGitState : NSObject<NSCopying, NSSecureCoding>
@property (nullable, nonatomic, copy) NSString *directory;
@property (nullable, nonatomic, copy) NSString *xcode;
@property (nullable, nonatomic, copy) NSString *pushArrow;
@property (nullable, nonatomic, copy) NSString *pullArrow;
@property (nullable, nonatomic, copy) NSString *branch;
@property (nonatomic) BOOL dirty;
@property (nonatomic) NSInteger adds;  // unstaged count
@property (nonatomic) NSInteger deletes;  // unstaged count
// Richer change stats computed via git_diff against HEAD (workdir + index).
@property (nonatomic) NSInteger linesInserted;
@property (nonatomic) NSInteger linesDeleted;
@property (nonatomic) NSInteger filesAdded;  // staged + unstaged
@property (nonatomic) NSInteger filesModified;
@property (nonatomic) NSInteger filesDeleted;  // staged + unstaged
// Repo-root-relative paths of files that differ from HEAD (workdir + index +
// untracked). Only populated when diff stats were requested.
@property (nullable, nonatomic, copy) NSArray<NSString *> *dirtyFiles;
@property (nonatomic) NSTimeInterval creationTime;
@property (nonatomic) iTermGitRepoState repoState;

- (NSString *)prettyDescription;
@end


NS_ASSUME_NONNULL_END
