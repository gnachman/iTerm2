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

// Per-column change kind matching the letters used by `git status
// --porcelain`. iTermGitFileChangeKindNone means no change in that
// column; ignored entries are excluded entirely by the poller so the
// `!` code is intentionally absent. Copies (C) aren't surfaced —
// libgit2's status_list flags don't separate copy from rename in the
// index column, and we'd produce false positives if we tried.
typedef NS_ENUM(NSInteger, iTermGitFileChangeKind) {
    iTermGitFileChangeKindNone        = 0,
    iTermGitFileChangeKindModified,   // M
    iTermGitFileChangeKindAdded,      // A (index only)
    iTermGitFileChangeKindDeleted,    // D
    iTermGitFileChangeKindRenamed,    // R
    iTermGitFileChangeKindTypeChange, // T
    iTermGitFileChangeKindUntracked,  // ? (workdir only)
    iTermGitFileChangeKindConflicted, // U-style conflict, either column
};

// One entry per file reported by `git status`, mirroring porcelain's
// two-column form. `indexStatus` is the staged side ("changes to be
// committed"); `workdirStatus` is the unstaged side ("changes not
// staged for commit") — except untracked files, which set workdir to
// .untracked and leave index as .none.
//
// A file modified after staging shows up with both columns non-.none
// (e.g. .modified / .modified, "MM" in porcelain); the menu builder
// renders it once per non-empty group.
@interface iTermGitFileStatus : NSObject<NSCopying, NSSecureCoding>
@property (nonatomic, copy) NSString *path;
@property (nonatomic) iTermGitFileChangeKind indexStatus;
@property (nonatomic) iTermGitFileChangeKind workdirStatus;
@end

@interface iTermGitState : NSObject<NSCopying, NSSecureCoding>
@property (nullable, nonatomic, copy) NSString *directory;
@property (nullable, nonatomic, copy) NSString *xcode;
// Stringified count of commits ahead of upstream (would be pushed), or "error" on failure.
@property (nullable, nonatomic, copy) NSString *ahead;
// Stringified count of commits behind upstream (would be pulled), or "error" on failure.
@property (nullable, nonatomic, copy) NSString *behind;
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
// Per-file status entries — one per file reported by `git status`.
// Populated by populateFromStatusListOnState: when its
// includeFileStatuses argument is YES (which gitStateForRepoAtPath:
// wires to the includeDiffStats parameter). Nil otherwise.
@property (nullable, nonatomic, copy) NSArray<iTermGitFileStatus *> *fileStatuses;
@property (nonatomic) NSTimeInterval creationTime;
@property (nonatomic) iTermGitRepoState repoState;

- (NSString *)prettyDescription;
@end


NS_ASSUME_NONNULL_END
