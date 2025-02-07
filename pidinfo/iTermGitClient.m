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

// git status --porcelain --ignore-submodules -unormal
- (BOOL)repoIsDirty {
    git_status_list *status_list = NULL;
    git_status_options status_options = GIT_STATUS_OPTIONS_INIT;
    status_options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    status_options.flags = (GIT_STATUS_OPT_INCLUDE_UNTRACKED |
                            GIT_STATUS_OPT_EXCLUDE_SUBMODULES);
    const int error = git_status_list_new(&status_list, _repo, &status_options);
    if (error) {
        return NO;
    }

    const BOOL dirty = git_status_list_entrycount(status_list) > 0;
    git_status_list_free(status_list);
    return dirty;
}

// git ls-files --others --exclude-standard | wc -l
- (BOOL)getDeletions:(NSInteger *)deletionsPtr untracked:(NSInteger *)untrackedPtr {
    git_status_list *status_list = NULL;
    git_status_options status_options = GIT_STATUS_OPTIONS_INIT;
    status_options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    status_options.flags = (GIT_STATUS_OPT_INCLUDE_UNTRACKED |
                            GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX);
    const int error = git_status_list_new(&status_list, _repo, &status_options);
    if (error) {
        return NO;
    }

    NSInteger deletions = 0;
    NSInteger untracked = 0;

    const size_t count = git_status_list_entrycount(status_list);
    for (size_t i = 0; i < count; i++) {
        const git_status_entry *status_entry = git_status_byindex(status_list, i);
        if (status_entry->status & GIT_STATUS_WT_DELETED) {
            deletions += 1;
        }
        if (status_entry->status & GIT_STATUS_WT_NEW) {
            untracked += 1;
        }
    }
    git_status_list_free(status_list);

    *deletionsPtr = deletions;
    *untrackedPtr = untracked;

    return YES;
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
    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:path];

    if (!client.repo) {
        NSString *parent = [path stringByDeletingLastPathComponent];
        if ([parent isEqualToString:path] || parent.length == 0) {
            return nil;
        }
        return [self gitStateForRepoAtPath:parent];
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

    // Get dirty
    state.dirty = [client repoIsDirty];

    // Untracked files & deleted but tracked files
    NSInteger deletions = 0;
    NSInteger untracked = 0;
    if ([client getDeletions:&deletions untracked:&untracked]) {
        state.adds = untracked;
        state.deletes = deletions;
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
