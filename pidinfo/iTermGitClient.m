//
//  iTermGitClient.m
//  pidinfo
//
//  Created by George Nachman on 1/11/21.
//

#import "iTermGitClient.h"

#import "iTermGitState.h"

#include <fnmatch.h>
#include <mach/mach_time.h>

static double iTermGitClientTimeSinceBoot(void) {
    const uint64_t elapsed = mach_absolute_time();
    mach_timebase_info_data_t timebase;

    mach_timebase_info(&timebase);

    const double nanoseconds = (double)elapsed * timebase.numer / timebase.denom;
    const double nanosPerSecond = 1.0e9;
    return nanoseconds / nanosPerSecond;
}

typedef void (^DeferralBlock)(void);

@implementation iTermGitClient {
    NSMutableArray<DeferralBlock> *_defers;
}

+ (BOOL)name:(NSString *)name matchesPattern:(NSString *)pattern {
    const int result = fnmatch(pattern.UTF8String, name.UTF8String, 0);
    if (result == 0) {
        return YES;
    }
    if ([name isEqualToString:pattern]) {
        return YES;
    }
    if ([name hasPrefix:[pattern stringByAppendingString:@"/"]]) {
        return YES;
    }
    return NO;
}

- (instancetype)initWithRepoPath:(NSString *)path {
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            git_libgit2_init();
        });
        _path = [path copy];
        _defers = [NSMutableArray array];
        _repo = [self repoAt:path];
    }
    return self;
}

- (void)dealloc {
    for (DeferralBlock block in _defers.reverseObjectEnumerator) {
        block();
    }
}

- (git_repository *)repoAt:(NSString *)path {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        git_libgit2_init();
    });

    git_repository *repo = NULL;
    const int error = git_repository_open(&repo, path.UTF8String);
    if (error) {
        return nil;
    }
    [_defers addObject:^{
        git_repository_free(repo);
    }];

    return repo;
}

// git symbolic-ref -q --short
- (git_reference *)head {
    git_reference *ref = NULL;
    const int error = git_repository_head(&ref, _repo);
    if (error) {
        return nil;
    }
    [_defers addObject:^{
        git_reference_free(ref);
    }];
    return ref;
}

- (const git_oid *)oidAtRef:(git_reference *)ref {
    git_reference *resolved = NULL;
    const int error = git_reference_resolve(&resolved, ref);
    if (error) {
        return NULL;
    }
    [_defers addObject:^{ git_reference_free(resolved); }];
    return git_reference_target(resolved);
}

- (NSString *)stringForOid:(const git_oid *)oid {
    if (!oid) {
        return nil;
    }
    char buffer[GIT_OID_HEXSZ + 1];
    const char *str = git_oid_tostr(buffer, sizeof(buffer), oid);
    return [NSString stringWithUTF8String:str];
}

- (NSString *)fullNameForReference:(git_reference *)ref {
    const char *name = git_reference_name(ref);
    if (!name) {
        return nil;
    }
    return [NSString stringWithUTF8String:name];
}

- (NSString *)shortNameForReference:(git_reference *)ref {
    const char *name = git_reference_shorthand(ref);
    if (!name) {
        return [self branchAt:ref];
    }
    return [NSString stringWithUTF8String:name];
}

- (NSString *)branchAt:(git_reference *)ref {
    const git_oid *oid = [self oidAtRef:ref];
    if (!oid) {
        return nil;
    }

    const char *branch_name;
    const int error = git_branch_name(&branch_name, ref);
    if (error) {
        return [self stringForOid:oid];
    }
    return [NSString stringWithUTF8String:branch_name];
}

- (NSDate *)commiterDateAt:(git_reference *)ref {
    const git_oid *oid = [self oidAtRef:ref];
    if (!oid) {
        return nil;
    }
    git_commit *commit;
    if (git_commit_lookup(&commit, _repo, oid)) {
        return nil;
    }
    [_defers addObject:^{ git_commit_free(commit); }];
    git_time_t t = git_commit_time(commit);
    return [NSDate dateWithTimeIntervalSince1970:t];
}

// Walks from newest (fromCommit) to oldest (toCommit). block is called for `fromCommit` but not
// for `toCommit`.
- (void)enumerateCommitsFrom:(const git_oid *)fromCommit
                          to:(const git_oid *)toCommit
                       block:(void (^)(const git_oid *oid))block {
    git_revwalk *walker = NULL;
    const int error = git_revwalk_new(&walker, _repo);
    if (error) {
        git_revwalk_free(walker);
        return;
    }

    git_revwalk_sorting(walker, GIT_SORT_TOPOLOGICAL);
    git_revwalk_push(walker, fromCommit);
    git_oid oid;
    while (git_revwalk_next(&oid, walker) == 0) {
        if (0 == git_oid_cmp(&oid, toCommit)) {
            break;
        }
        block(&oid);
    }
    git_revwalk_free(walker);
    walker = NULL;
}

- (NSInteger)numberOfCommitsFrom:(const git_oid *)fromCommit
                              to:(const git_oid *)toCommit {
    __block NSInteger count = 0;
    [self enumerateCommitsFrom:fromCommit to:toCommit block:^(const git_oid *oid) {
        count += 1;
    }];
    return count;
}

// git rev-list --left-right --count HEAD...@'{u}'
// see https://github.com/JuliaLang/julia/blob/345ce78da9aba498e4d7c2dee5f11e6fbf4ddc7c/stdlib/LibGit2/src/LibGit2.jl#L650
- (BOOL)getCountsFromRef:(git_reference *)ref
                    pull:(NSInteger *)pullCount
                    push:(NSInteger *)pushCount {
    const git_oid *local_head_oid = [self oidAtRef:ref];
    if (!local_head_oid) {
        return NO;
    }

    git_reference *upstream_ref;
    int error = git_branch_upstream(&upstream_ref, ref);
    if (error) {
        return NO;
    }
    [_defers addObject:^{ git_reference_free(upstream_ref); }];

    const git_oid *remote_oid = git_reference_target(upstream_ref);
    if (local_head_oid == NULL || remote_oid == NULL) {
        return NO;
    }
    git_oid merge_base = {0};
    error = git_merge_base(&merge_base, _repo, local_head_oid, remote_oid);
    if (error) {
        return NO;
    }

    *pullCount = [self numberOfCommitsFrom:local_head_oid to:&merge_base];
    *pushCount = [self numberOfCommitsFrom:remote_oid to:&merge_base];

    return YES;
}

// One git_status_list pass feeding everything that previously took
// three: dirty (any entry), adds (workdir-new count), deletes
// (workdir-deleted count), and the per-file fileStatuses array used
// by the workgroup menu. Mirrors `git status --porcelain` so the
// menu builder can group staged / unstaged / untracked the same way
// the user sees them in the terminal.
- (BOOL)populateFromStatusListOnState:(iTermGitState *)state
                  includeFileStatuses:(BOOL)includeFileStatuses {
    git_status_list *status_list = NULL;
    git_status_options opts = GIT_STATUS_OPTIONS_INIT;
    opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = (GIT_STATUS_OPT_INCLUDE_UNTRACKED |
                  GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS |
                  GIT_STATUS_OPT_EXCLUDE_SUBMODULES);
    // Rename detection (head→index, index→workdir) is only useful
    // when we're emitting per-file statuses; the count fields don't
    // need it. Skip the similarity scan for the cheap path.
    if (includeFileStatuses) {
        opts.flags |= (GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX |
                       GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR);
    }
    if (git_status_list_new(&status_list, _repo, &opts) != 0) {
        return NO;
    }
    NSMutableArray<iTermGitFileStatus *> *result =
        includeFileStatuses ? [NSMutableArray array] : nil;
    NSInteger untracked = 0;
    NSInteger deletions = 0;
    const size_t count = git_status_list_entrycount(status_list);
    for (size_t i = 0; i < count; i++) {
        const git_status_entry *e = git_status_byindex(status_list, i);
        if (!e) continue;
        const unsigned int s = e->status;
        if (s & GIT_STATUS_WT_NEW) {
            untracked += 1;
        }
        if (s & GIT_STATUS_WT_DELETED) {
            deletions += 1;
        }
        if (!includeFileStatuses) {
            continue;
        }
        // Pick the most-recent path: workdir's new_file when the
        // workdir side has anything to say (incl. rename), else
        // index's new_file, else index's old_file (rare).
        const char *cpath = NULL;
        if (e->index_to_workdir &&
            e->index_to_workdir->new_file.path) {
            cpath = e->index_to_workdir->new_file.path;
        } else if (e->head_to_index &&
                   e->head_to_index->new_file.path) {
            cpath = e->head_to_index->new_file.path;
        } else if (e->head_to_index &&
                   e->head_to_index->old_file.path) {
            cpath = e->head_to_index->old_file.path;
        }
        if (!cpath) continue;
        NSString *path = [NSString stringWithUTF8String:cpath];
        // -stringWithUTF8String: returns nil if the C string isn't
        // valid UTF-8. Skipping is the right move here — passing a
        // nil path through to Swift would crash on the NSString
        // bridge, and the file isn't actionable anyway since the
        // per-file restart can't reference a name we can't print.
        if (!path) continue;
        iTermGitFileChangeKind indexStatus = iTermGitFileChangeKindNone;
        iTermGitFileChangeKind workdirStatus = iTermGitFileChangeKindNone;
        if (s & GIT_STATUS_INDEX_NEW) {
            indexStatus = iTermGitFileChangeKindAdded;
        } else if (s & GIT_STATUS_INDEX_MODIFIED) {
            indexStatus = iTermGitFileChangeKindModified;
        } else if (s & GIT_STATUS_INDEX_DELETED) {
            indexStatus = iTermGitFileChangeKindDeleted;
        } else if (s & GIT_STATUS_INDEX_RENAMED) {
            indexStatus = iTermGitFileChangeKindRenamed;
        } else if (s & GIT_STATUS_INDEX_TYPECHANGE) {
            indexStatus = iTermGitFileChangeKindTypeChange;
        }
        if (s & GIT_STATUS_WT_NEW) {
            workdirStatus = iTermGitFileChangeKindUntracked;
        } else if (s & GIT_STATUS_WT_MODIFIED) {
            workdirStatus = iTermGitFileChangeKindModified;
        } else if (s & GIT_STATUS_WT_DELETED) {
            workdirStatus = iTermGitFileChangeKindDeleted;
        } else if (s & GIT_STATUS_WT_TYPECHANGE) {
            workdirStatus = iTermGitFileChangeKindTypeChange;
        } else if (s & GIT_STATUS_WT_RENAMED) {
            workdirStatus = iTermGitFileChangeKindRenamed;
        }
        if (s & GIT_STATUS_CONFLICTED) {
            // Conflict trumps both columns — surface it once on the
            // workdir side so it lands in the "unstaged" group, the
            // section users expect to find conflicts in.
            workdirStatus = iTermGitFileChangeKindConflicted;
        }
        if (indexStatus == iTermGitFileChangeKindNone &&
            workdirStatus == iTermGitFileChangeKindNone) {
            // Nothing to report (probably an ignored file slipping in).
            continue;
        }
        iTermGitFileStatus *fs = [[iTermGitFileStatus alloc] init];
        fs.path = path;
        fs.indexStatus = indexStatus;
        fs.workdirStatus = workdirStatus;
        [result addObject:fs];
    }
    git_status_list_free(status_list);
    state.dirty = (count > 0);
    state.adds = untracked;
    state.deletes = deletions;
    state.fileStatuses = result;
    return YES;
}

- (BOOL)populateDiffStatsOnState:(iTermGitState *)state {
    git_object *head_tree_obj = NULL;
    git_diff *diff = NULL;
    BOOL ok = NO;

    // "HEAD^{tree}" peels HEAD down to the commit's tree.
    if (git_revparse_single(&head_tree_obj, _repo, "HEAD^{tree}") != 0) {
        goto cleanup;
    }
    git_tree *head_tree = (git_tree *)head_tree_obj;

    git_diff_options opts = GIT_DIFF_OPTIONS_INIT;
    // Include untracked files so newly-created files count as added.
    opts.flags = (GIT_DIFF_INCLUDE_UNTRACKED |
                  GIT_DIFF_RECURSE_UNTRACKED_DIRS);

    if (git_diff_tree_to_workdir_with_index(&diff, _repo, head_tree, &opts) != 0) {
        goto cleanup;
    }

    NSInteger filesAdded = 0;
    NSInteger filesDeleted = 0;
    NSInteger filesModified = 0;
    NSInteger linesInserted = 0;
    NSInteger linesDeleted = 0;

    const size_t numDeltas = git_diff_num_deltas(diff);
    for (size_t i = 0; i < numDeltas; i++) {
        const git_diff_delta *delta = git_diff_get_delta(diff, i);
        if (!delta) {
            continue;
        }
        switch (delta->status) {
            case GIT_DELTA_ADDED:
            case GIT_DELTA_UNTRACKED:
                // New file: only increments filesAdded. Its contents are not
                // counted as inserted lines.
                filesAdded += 1;
                break;

            case GIT_DELTA_DELETED:
                // File actually removed from disk. Doesn't contribute to
                // linesDeleted.
                filesDeleted += 1;
                break;

            case GIT_DELTA_MODIFIED:
            case GIT_DELTA_RENAMED:
            case GIT_DELTA_TYPECHANGE: {
                filesModified += 1;
                git_patch *patch = NULL;
                if (git_patch_from_diff(&patch, diff, i) == 0 && patch) {
                    size_t additions = 0;
                    size_t deletions = 0;
                    if (git_patch_line_stats(NULL, &additions, &deletions, patch) == 0) {
                        linesInserted += (NSInteger)additions;
                        linesDeleted += (NSInteger)deletions;
                    }
                    git_patch_free(patch);
                }
                break;
            }

            default:
                // COPIED, IGNORED, UNREADABLE, CONFLICTED — skip.
                break;
        }
    }

    state.filesAdded = filesAdded;
    state.filesDeleted = filesDeleted;
    state.filesModified = filesModified;
    state.linesInserted = linesInserted;
    state.linesDeleted = linesDeleted;

    ok = YES;

cleanup:
    if (diff) git_diff_free(diff);
    if (head_tree_obj) git_object_free(head_tree_obj);
    return ok;
}

static int GitForEachCallback(git_reference *ref, void *data) {
    typedef void (^UserCallback)(git_reference *, BOOL *);
    UserCallback block = (__bridge UserCallback)data;
    BOOL stop = NO;
    block(ref, &stop);
    return stop == YES;
}

- (void)forEachReference:(void (^)(git_reference * _Nonnull, BOOL *))block {
    git_reference_foreach(_repo, GitForEachCallback, (__bridge void *)block);
}

@end

@implementation iTermGitState(GitClient)

+ (instancetype)gitStateForRepoAtPath:(NSString *)path {
    return [self gitStateForRepoAtPath:path includeDiffStats:NO];
}

+ (instancetype)gitStateForRepoAtPath:(NSString *)path
                     includeDiffStats:(BOOL)includeDiffStats {
    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:path];

    if (!client.repo) {
        NSString *parent = [path stringByDeletingLastPathComponent];
        if ([parent isEqualToString:path] || parent.length == 0) {
            return nil;
        }
        return [self gitStateForRepoAtPath:parent includeDiffStats:includeDiffStats];
    }

    git_reference *headRef = [client head];
    if (!headRef) {
        return nil;
    }

    // Get branch
    iTermGitState *state = [[iTermGitState alloc] init];
    state.creationTime = iTermGitClientTimeSinceBoot();
    state.branch = [client branchAt:headRef];
    if (!state.branch) {
        return nil;
    }

    // Get pull/push count
    NSInteger left_count = -1;
    NSInteger right_count = -1;
    if ([client getCountsFromRef:headRef
                            pull:&left_count
                            push:&right_count]) {
        state.pushArrow = [@(left_count) stringValue];
        state.pullArrow = [@(right_count) stringValue];
    } else {
        state.pushArrow = @"";
        state.pullArrow = @"";
    }

    // Single status_list pass: dirty, adds (untracked count), deletes
    // (workdir-deleted count). Replaces the old repoIsDirty +
    // getDeletions:untracked: walks. fileStatuses comes from the same
    // pass when includeDiffStats is YES (the workgroup menu is the
    // only consumer); the cheap path skips the per-file array
    // allocation and the rename-detection similarity scan entirely.
    [client populateFromStatusListOnState:state
                      includeFileStatuses:includeDiffStats];

    // Richer diff stats: only if the caller explicitly asked. Can be expensive.
    // Adds linesInserted/Deleted and filesAdded/Modified/Deleted by
    // walking diff deltas with patches; fileStatuses already came from
    // the status_list pass above.
    if (includeDiffStats) {
        [client populateDiffStatsOnState:state];
    }

    // Current operation
    const git_repository_state_t repoState = git_repository_state(client.repo);
    switch (repoState) {
        case GIT_REPOSITORY_STATE_NONE:
            state.repoState = iTermGitRepoStateNone;
            break;
        case GIT_REPOSITORY_STATE_MERGE:
            state.repoState = iTermGitRepoStateMerge;
            break;
        case GIT_REPOSITORY_STATE_REVERT:
        case GIT_REPOSITORY_STATE_REVERT_SEQUENCE:
            state.repoState = iTermGitRepoStateRevert;
            break;
        case GIT_REPOSITORY_STATE_CHERRYPICK:
        case GIT_REPOSITORY_STATE_CHERRYPICK_SEQUENCE:
            state.repoState = iTermGitRepoStateCherrypick;
            break;
        case GIT_REPOSITORY_STATE_BISECT:
            state.repoState = iTermGitRepoStateBisect;
            break;
        case GIT_REPOSITORY_STATE_REBASE:
        case GIT_REPOSITORY_STATE_REBASE_INTERACTIVE:
        case GIT_REPOSITORY_STATE_REBASE_MERGE:
            state.repoState = iTermGitRepoStateRebase;
            break;
        case GIT_REPOSITORY_STATE_APPLY_MAILBOX:
        case GIT_REPOSITORY_STATE_APPLY_MAILBOX_OR_REBASE:
            state.repoState = iTermGitRepoStateApply;
            break;
    }

    return state;
}

@end
