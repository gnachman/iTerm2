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

// git rev-list --left-right --count HEAD...@'{u}'
// aheadCount:  commits on HEAD not in upstream (commits you would push).
// behindCount: commits on upstream not in HEAD (commits you would pull).
- (BOOL)getCountsFromRef:(git_reference *)ref
                   ahead:(NSInteger *)aheadCount
                  behind:(NSInteger *)behindCount {
    const git_oid *local_head_oid = [self oidAtRef:ref];
    if (!local_head_oid) {
        return NO;
    }

    git_reference *upstream_ref = NULL;
    if (git_branch_upstream(&upstream_ref, ref)) {
        return NO;
    }
    [_defers addObject:^{ git_reference_free(upstream_ref); }];

    const git_oid *remote_oid = git_reference_target(upstream_ref);
    if (remote_oid == NULL) {
        return NO;
    }

    size_t ahead = 0;
    size_t behind = 0;
    if (git_graph_ahead_behind(&ahead, &behind, _repo, local_head_oid, remote_oid)) {
        return NO;
    }

    *aheadCount = (NSInteger)ahead;
    *behindCount = (NSInteger)behind;

    return YES;
}

// Map a single git_status_entry to an iTermGitFileStatus, or nil if
// the entry has nothing reportable (an ignored file slipping in, or a
// path that isn't valid UTF-8). Shared by the count pass's sibling
// fileStatuses pass below.
static iTermGitFileStatus *iTermGitFileStatusForEntry(const git_status_entry *e) {
    if (!e) {
        return nil;
    }
    const unsigned int s = e->status;
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
    if (!cpath) {
        return nil;
    }
    NSString *path = [NSString stringWithUTF8String:cpath];
    // -stringWithUTF8String: returns nil if the C string isn't
    // valid UTF-8. Skipping is the right move here — passing a
    // nil path through to Swift would crash on the NSString
    // bridge, and the file isn't actionable anyway since the
    // per-file restart can't reference a name we can't print.
    if (!path) {
        return nil;
    }
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
        return nil;
    }
    iTermGitFileStatus *fs = [[iTermGitFileStatus alloc] init];
    fs.path = path;
    fs.indexStatus = indexStatus;
    fs.workdirStatus = workdirStatus;
    return fs;
}

// One git_status_list pass for the count fields: dirty (any entry),
// adds (workdir-new count), deletes (workdir-deleted count). Mirrors
// `git status --porcelain` and includes untracked files because the
// status bar surfaces the untracked count. Rename detection is NOT
// enabled here; it's only useful for the per-file fileStatuses array,
// and the similarity scan it forces hashes file contents (including
// every untracked file under the tree), which can blow past the git
// timeout in a working copy littered with large untracked files. When
// the caller needs fileStatuses, populateHeadFileStatusesOnState: runs
// a second, untracked-free pass.
- (BOOL)populateFromStatusListOnState:(iTermGitState *)state
                  includeFileStatuses:(BOOL)includeFileStatuses {
    git_status_list *status_list = NULL;
    git_status_options opts = GIT_STATUS_OPTIONS_INIT;
    opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = (GIT_STATUS_OPT_INCLUDE_UNTRACKED |
                  GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS |
                  GIT_STATUS_OPT_EXCLUDE_SUBMODULES);
    if (git_status_list_new(&status_list, _repo, &opts) != 0) {
        return NO;
    }
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
    }
    git_status_list_free(status_list);
    state.dirty = (count > 0);
    state.adds = untracked;
    state.deletes = deletions;
    if (includeFileStatuses) {
        [self populateHeadFileStatusesOnState:state];
    }
    return YES;
}

// Build the per-file fileStatuses array (HEAD base) consumed by the
// workgroup diff menu. Deliberately excludes untracked files: the menu
// filters them out anyway (see CCDiffSelectorItem.set(fileStatuses:)),
// and leaving GIT_STATUS_OPT_INCLUDE_UNTRACKED off means rename
// detection only has to hash the (typically few) tracked add/delete
// pairs instead of every untracked file in the tree. Rename detection
// stays on so the menu labels match what the user sees in
// `git status`. The staged/unstaged distinction (index vs workdir
// columns) is preserved, unlike the non-HEAD
// populateFileStatusesAgainstBase: path.
- (BOOL)populateHeadFileStatusesOnState:(iTermGitState *)state {
    git_status_list *status_list = NULL;
    git_status_options opts = GIT_STATUS_OPTIONS_INIT;
    opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = (GIT_STATUS_OPT_EXCLUDE_SUBMODULES |
                  GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX |
                  GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR);
    if (git_status_list_new(&status_list, _repo, &opts) != 0) {
        return NO;
    }
    NSMutableArray<iTermGitFileStatus *> *result = [NSMutableArray array];
    const size_t count = git_status_list_entrycount(status_list);
    for (size_t i = 0; i < count; i++) {
        iTermGitFileStatus *fs =
            iTermGitFileStatusForEntry(git_status_byindex(status_list, i));
        if (fs) {
            [result addObject:fs];
        }
    }
    git_status_list_free(status_list);
    state.fileStatuses = result;
    return YES;
}

- (BOOL)populateFileStatusesAgainstBase:(NSString *)gitBase
                                onState:(iTermGitState *)state {
    if (gitBase.length == 0) {
        return NO;
    }
    // All non-trivial declarations are hoisted above the first
    // `goto cleanup` so the gotos don't jump past their inits —
    // Clang refuses that even for POD aggregates initialized with
    // libgit2's _OPTIONS_INIT macros (they call `version`-aware
    // helpers under the hood).
    git_object *base_obj = NULL;
    git_diff *diff = NULL;
    BOOL ok = NO;
    git_tree *base_tree = NULL;
    git_diff_options opts = GIT_DIFF_OPTIONS_INIT;
    git_diff_find_options find_opts = GIT_DIFF_FIND_OPTIONS_INIT;
    NSMutableArray<iTermGitFileStatus *> *result = nil;
    size_t numDeltas = 0;

    // "<spec>^{tree}" peels the resolved object down to a tree —
    // works for branches/tags/commits/SHAs alike. If the spec is
    // ambiguous or unknown libgit2 returns non-zero and we leave
    // fileStatuses untouched.
    NSString *treeSpec = [gitBase stringByAppendingString:@"^{tree}"];
    if (git_revparse_single(&base_obj, _repo, treeSpec.UTF8String) != 0) {
        return NO;
    }
    // base_tree aliases base_obj — `git_revparse_single` returns
    // an owned object, and the cleanup block frees it via
    // git_object_free. Do NOT switch this to git_object_peel(...,
    // GIT_OBJECT_TREE, ...) without also adding a separate
    // git_tree_free(base_tree) — peel returns a NEW owned tree
    // and would leak under the current cleanup.
    base_tree = (git_tree *)base_obj;

    // Default flags only — deliberately *not* setting
    // GIT_DIFF_INCLUDE_UNTRACKED. The picker excludes untracked
    // files from `git status` output via CCDiffSelectorItem's
    // workdirStatus filter; this path mirrors that behavior by
    // never having libgit2 surface UNTRACKED deltas in the first
    // place. Files that are tracked in the working tree but absent
    // from the base still come through as ADDED, which is what
    // the user wants — "files that differ from the base ref".
    if (git_diff_tree_to_workdir_with_index(&diff, _repo, base_tree, &opts) != 0) {
        goto cleanup;
    }

    // Detect renames so the popup labels match what the user sees
    // in `git status`. find_similar mutates `diff` in place to
    // collapse paired add+delete deltas into a single rename delta.
    find_opts.flags = (GIT_DIFF_FIND_RENAMES |
                       GIT_DIFF_FIND_RENAMES_FROM_REWRITES);
    git_diff_find_similar(diff, &find_opts);

    result = [NSMutableArray array];
    numDeltas = git_diff_num_deltas(diff);
    for (size_t i = 0; i < numDeltas; i++) {
        const git_diff_delta *delta = git_diff_get_delta(diff, i);
        if (!delta) {
            continue;
        }
        const char *cpath = NULL;
        // For deletes the new_file path is empty — fall back to old.
        if (delta->new_file.path && delta->new_file.path[0] != '\0') {
            cpath = delta->new_file.path;
        } else if (delta->old_file.path && delta->old_file.path[0] != '\0') {
            cpath = delta->old_file.path;
        }
        if (!cpath) {
            continue;
        }
        NSString *path = [NSString stringWithUTF8String:cpath];
        if (!path) {
            continue;
        }
        iTermGitFileChangeKind kind = iTermGitFileChangeKindNone;
        switch (delta->status) {
            case GIT_DELTA_ADDED:
                kind = iTermGitFileChangeKindAdded;
                break;
            case GIT_DELTA_DELETED:
                kind = iTermGitFileChangeKindDeleted;
                break;
            case GIT_DELTA_MODIFIED:
                kind = iTermGitFileChangeKindModified;
                break;
            case GIT_DELTA_RENAMED:
                kind = iTermGitFileChangeKindRenamed;
                break;
            case GIT_DELTA_TYPECHANGE:
                kind = iTermGitFileChangeKindTypeChange;
                break;
            case GIT_DELTA_CONFLICTED:
                kind = iTermGitFileChangeKindConflicted;
                break;
            // GIT_DELTA_UNTRACKED, _IGNORED, _COPIED, _UNREADABLE
            // all fall through here — untracked files are
            // intentionally excluded from the picker.
            default:
                continue;
        }
        if (kind == iTermGitFileChangeKindNone) {
            continue;
        }
        // The dropdown bins entries by which column is non-none:
        // indexStatus → "Staged" group, workdirStatus → "Unstaged".
        // For a non-HEAD base, that distinction is meaningless — the
        // diff merges committed and uncommitted changes — so route
        // every entry through workdirStatus and let it land under
        // a single "Unstaged" header. The `Self.allFilesMarker`-
        // headed "All Files" entry above remains the escape hatch
        // back to the unfiltered diff command.
        iTermGitFileStatus *fs = [[iTermGitFileStatus alloc] init];
        fs.path = path;
        fs.indexStatus = iTermGitFileChangeKindNone;
        fs.workdirStatus = kind;
        [result addObject:fs];
    }
    state.fileStatuses = result;
    ok = YES;

cleanup:
    if (diff) git_diff_free(diff);
    if (base_obj) git_object_free(base_obj);
    return ok;
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
    return [self gitStateForRepoAtPath:path
                               gitBase:nil
                      includeDiffStats:includeDiffStats];
}

+ (instancetype)gitStateForRepoAtPath:(NSString *)path
                              gitBase:(NSString * _Nullable)gitBase
                     includeDiffStats:(BOOL)includeDiffStats {
    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:path];

    if (!client.repo) {
        NSString *parent = [path stringByDeletingLastPathComponent];
        if ([parent isEqualToString:path] || parent.length == 0) {
            return nil;
        }
        return [self gitStateForRepoAtPath:parent
                                   gitBase:gitBase
                          includeDiffStats:includeDiffStats];
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

    // Get ahead/behind counts vs upstream
    NSInteger aheadCount = 0;
    NSInteger behindCount = 0;
    if ([client getCountsFromRef:headRef
                           ahead:&aheadCount
                          behind:&behindCount]) {
        state.ahead = [@(aheadCount) stringValue];
        state.behind = [@(behindCount) stringValue];
    } else {
        state.ahead = @"";
        state.behind = @"";
    }

    // Count fields from one status_list pass: dirty, adds (untracked
    // count), deletes (workdir-deleted count). Replaces the old
    // repoIsDirty + getDeletions:untracked: walks. When includeDiffStats
    // is YES, populateFromStatusListOnState: also runs a SEPARATE second
    // pass (populateHeadFileStatusesOnState:) for the per-file
    // fileStatuses array the workgroup menu consumes. That pass excludes
    // untracked files so rename detection doesn't hash them. The cheap
    // path (includeDiffStats NO) skips the second pass entirely.
    [client populateFromStatusListOnState:state
                      includeFileStatuses:includeDiffStats];

    // Richer diff stats: only if the caller explicitly asked. Can be expensive.
    // Adds linesInserted/Deleted and filesAdded/Modified/Deleted by
    // walking diff deltas with patches; fileStatuses was already
    // populated by the call above.
    if (includeDiffStats) {
        [client populateDiffStatsOnState:state];
    }

    // gitBase override: when the caller asked for files relative to
    // a non-HEAD ref, replace fileStatuses with the diff-against-base
    // result. Counts (dirty/adds/deletes/diffstats) keep their HEAD-
    // relative meaning — they're consumed by the status bar, which
    // wants `git status` semantics regardless of what the workgroup
    // toolbar picked. If the gitBase ref doesn't resolve, leave the
    // HEAD-relative fileStatuses in place rather than blanking the
    // menu — the user typed something invalid and a stale list is
    // more useful than nothing.
    if (gitBase.length > 0 && ![gitBase isEqualToString:@"HEAD"]) {
        [client populateFileStatusesAgainstBase:gitBase onState:state];
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
