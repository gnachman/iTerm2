//
//  iTermGitClient.h
//  pidinfo
//
//  Created by George Nachman on 1/11/21.
//

#import <Foundation/Foundation.h>

#import "iTermGitState.h"

#import "git2.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermGitClient : NSObject
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) git_repository *repo;

+ (BOOL)name:(NSString *)name matchesPattern:(NSString *)pattern;

- (instancetype)initWithRepoPath:(NSString *)path NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (git_reference * _Nullable)head;

- (const git_oid * _Nullable)oidAtRef:(git_reference *)ref;

- (NSString * _Nullable)branchAt:(git_reference *)ref;

- (NSString *)shortNameForReference:(git_reference *)ref;

- (NSString * _Nullable)fullNameForReference:(git_reference *)ref;

- (NSDate * _Nullable)commiterDateAt:(git_reference *)ref;

- (BOOL)getCountsFromRef:(git_reference *)ref
                    pull:(NSInteger *)pullCount
                    push:(NSInteger *)pushCount;

// Single git_status_list_new walk feeding the on-state fields that
// were previously computed by three separate walks (repoIsDirty +
// getDeletions:untracked: + a fileStatuses pass). Always populates
// dirty, adds (untracked count), and deletes (workdir-deleted
// count). When `includeFileStatuses` is YES, also builds the
// per-file fileStatuses array; callers that don't need it (the
// status-bar git component) skip the allocation cost by passing NO.
//
// Behavior note vs the older code path: this walk uses
// RECURSE_UNTRACKED_DIRS, so a directory of N untracked files
// contributes N to `adds` instead of the directory rollup of 1.
// The status bar's adds/deletes counts shift accordingly — more
// accurate, matches what `git status` actually reports.
- (BOOL)populateFromStatusListOnState:(iTermGitState *)state
                  includeFileStatuses:(BOOL)includeFileStatuses;

// Populate on state: linesInserted, linesDeleted, filesAdded, filesModified,
// filesDeleted by diffing HEAD's tree against workdir-with-index. Returns NO
// if diffing fails or there is no HEAD commit.
- (BOOL)populateDiffStatsOnState:(iTermGitState *)state;

- (void)forEachReference:(void (^)(git_reference *ref, BOOL *stop))block;

@end

@interface iTermGitState(GitClient)

// Basic state (branch, push/pull, dirty, untracked/deleted file counts).
+ (instancetype _Nullable)gitStateForRepoAtPath:(NSString *)path;

// Same as above, but if includeDiffStats is YES also populates linesInserted,
// linesDeleted, filesAdded, filesModified, filesDeleted via git_diff. Skip it
// when not needed — diffing can touch many files on slow repos/filesystems.
+ (instancetype _Nullable)gitStateForRepoAtPath:(NSString *)path
                               includeDiffStats:(BOOL)includeDiffStats;

@end

NS_ASSUME_NONNULL_END
