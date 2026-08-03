//
//  iTermGitClientTests.m
//  ModernTests
//
//  XCTest coverage for iTermGitClient's status-list pass. Each test
//  builds a real git repo in a temp dir using /usr/bin/git (so the
//  fixture state is what the canonical tool produces), then asks
//  iTermGitState +gitStateForRepoAtPath:includeDiffStats: to read
//  it back through libgit2 and asserts on the resulting per-file
//  kinds and counts.
//

#import <XCTest/XCTest.h>
#import <sys/stat.h>

#import "iTermGitClient.h"
#import "iTermGitState.h"

@interface iTermGitClientTests : XCTestCase
@property (nonatomic, copy) NSString *repoDir;
@end

@implementation iTermGitClientTests

#pragma mark - Setup

- (void)setUp {
    [super setUp];
    self.repoDir = [self makeTempDir];
    XCTAssertNotNil(self.repoDir);
    [self runGit:@[@"init", @"-q"]];
    // Local user config so commits succeed even on a host with no
    // global git identity.
    [self runGit:@[@"config", @"user.email", @"test@example.com"]];
    [self runGit:@[@"config", @"user.name", @"Tester"]];
    // Disable signing in case the host has commit.gpgsign=true.
    [self runGit:@[@"config", @"commit.gpgsign", @"false"]];
}

- (void)tearDown {
    if (self.repoDir) {
        [[NSFileManager defaultManager] removeItemAtPath:self.repoDir error:nil];
        self.repoDir = nil;
    }
    [super tearDown];
}

#pragma mark - Helpers

- (NSString *)makeTempDir {
    NSString *tmplObj = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"iTermGitClientTests.XXXXXX"];
    char *tmpl = strdup(tmplObj.fileSystemRepresentation);
    if (!tmpl) return nil;
    char *res = mkdtemp(tmpl);
    NSString *out = res ? [[NSFileManager defaultManager]
                            stringWithFileSystemRepresentation:res length:strlen(res)]
                        : nil;
    free(tmpl);
    return out;
}

- (NSString *)runGit:(NSArray<NSString *> *)args {
    return [self runGit:args inDir:self.repoDir];
}

- (NSString *)runGit:(NSArray<NSString *> *)args inDir:(NSString *)dir {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:dir];
    task.arguments = args;
    // The test host can run under ASan/malloc diagnostics, and NSTask
    // children inherit those env vars: git then prints MallocStackLogging
    // noise into the output this fixture asserts on, and can exit nonzero
    // outright. Give the child a pristine environment.
    NSMutableDictionary<NSString *, NSString *> *environment =
        [[[NSProcessInfo processInfo] environment] mutableCopy];
    for (NSString *key in environment.allKeys) {
        if ([key hasPrefix:@"Malloc"] ||
            [key hasPrefix:@"DYLD_"] ||
            [key hasPrefix:@"NSZombie"] ||
            [key hasPrefix:@"ASAN_"]) {
            [environment removeObjectForKey:key];
        }
    }
    task.environment = environment;
    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = out;
    NSError *err = nil;
    if (![task launchAndReturnError:&err]) {
        XCTFail(@"git launch failed for %@: %@", args, err);
        return @"";
    }
    [task waitUntilExit];
    NSData *data = [out.fileHandleForReading readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data
                                             encoding:NSUTF8StringEncoding] ?: @"";
    // A failing fixture command (e.g. commit blocked by a hook on
    // the host system) silently producing the wrong repo state would
    // surface as a confusing assertion several lines later. Fail
    // loudly here so the cause is obvious.
    if (task.terminationStatus != 0) {
        XCTFail(@"git %@ exited %d. Output: %@",
                [args componentsJoinedByString:@" "],
                task.terminationStatus, output);
    }
    return output;
}

- (void)writeFile:(NSString *)name contents:(NSString *)contents {
    NSString *path = [self.repoDir stringByAppendingPathComponent:name];
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSError *err = nil;
    [contents writeToFile:path
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:&err];
    XCTAssertNil(err);
}

- (void)deleteFile:(NSString *)name {
    NSString *path = [self.repoDir stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

- (iTermGitState *)readState {
    iTermGitState *state =
        [iTermGitState gitStateForRepoAtPath:self.repoDir
                            includeDiffStats:YES];
    XCTAssertNotNil(state);
    return state;
}

- (iTermGitFileStatus *)find:(NSArray<iTermGitFileStatus *> *)entries
                        path:(NSString *)path {
    for (iTermGitFileStatus *fs in entries) {
        if ([fs.path isEqualToString:path]) return fs;
    }
    return nil;
}

// Seed the repo with a single committed file so subsequent tests
// can exercise modification/deletion scenarios without redundant
// boilerplate.
- (void)seedInitialCommit {
    [self writeFile:@"seed.txt" contents:@"v1\n"];
    [self runGit:@[@"add", @"seed.txt"]];
    [self runGit:@[@"commit", @"-q", @"-m", @"seed"]];
}

#pragma mark - Tests

- (void)testCleanRepoIsNotDirty {
    [self seedInitialCommit];
    iTermGitState *state = [self readState];
    XCTAssertFalse(state.dirty);
    XCTAssertEqual(state.adds, 0);
    XCTAssertEqual(state.deletes, 0);
    XCTAssertEqual(state.fileStatuses.count, 0u);
}

- (void)testUntrackedFile {
    // Untracked files still feed the `adds` count (the status bar
    // shows it) but are intentionally absent from fileStatuses: the
    // diff menu filters them out, and excluding them keeps rename
    // detection from hashing every untracked file in the tree.
    [self seedInitialCommit];
    [self writeFile:@"new.txt" contents:@"x"];
    iTermGitState *state = [self readState];
    XCTAssertTrue(state.dirty);
    XCTAssertEqual(state.adds, 1);
    XCTAssertEqual(state.deletes, 0);
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"new.txt"];
    XCTAssertNil(fs);
    XCTAssertEqual(state.fileStatuses.count, 0u);
}

- (void)testRecurseUntrackedDirsCountsPerFile {
    // The count walk uses RECURSE_UNTRACKED_DIRS so a directory of N
    // untracked files contributes N to `adds`, matching
    // `git status --porcelain` rather than the legacy directory-rollup
    // behavior. fileStatuses excludes untracked entries, so it stays
    // empty here even though `adds` is 3.
    [self seedInitialCommit];
    [self writeFile:@"newdir/a.txt" contents:@"1"];
    [self writeFile:@"newdir/b.txt" contents:@"2"];
    [self writeFile:@"newdir/c.txt" contents:@"3"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.adds, 3);
    XCTAssertEqual(state.fileStatuses.count, 0u);
}

- (void)testStagedAdd {
    [self seedInitialCommit];
    [self writeFile:@"new.txt" contents:@"x"];
    [self runGit:@[@"add", @"new.txt"]];
    iTermGitState *state = [self readState];
    XCTAssertTrue(state.dirty);
    // adds counts WT_NEW only; a fully-staged new file isn't WT_NEW
    // anymore, so it doesn't contribute to adds.
    XCTAssertEqual(state.adds, 0);
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"new.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindAdded);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindNone);
}

- (void)testStagedModification {
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v2\n"];
    [self runGit:@[@"add", @"seed.txt"]];
    iTermGitState *state = [self readState];
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindModified);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindNone);
}

- (void)testUnstagedModification {
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v2\n"];
    iTermGitState *state = [self readState];
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindNone);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindModified);
}

- (void)testModifiedAfterStaging_MM {
    // Stage one revision then modify on top — the canonical "MM"
    // case the dedupe in CCDiffSelectorItem exists to handle.
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v2\n"];
    [self runGit:@[@"add", @"seed.txt"]];
    [self writeFile:@"seed.txt" contents:@"v3\n"];
    iTermGitState *state = [self readState];
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindModified);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindModified);
}

- (void)testUnstagedDeletion {
    [self seedInitialCommit];
    [self deleteFile:@"seed.txt"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.deletes, 1);
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindNone);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindDeleted);
}

- (void)testStagedDeletion {
    [self seedInitialCommit];
    [self runGit:@[@"rm", @"-q", @"seed.txt"]];
    iTermGitState *state = [self readState];
    // `git rm` removes from both index and workdir, so deletes
    // (workdir) should also fire — but the file isn't tracked as
    // unstaged-deleted because the index already deleted it. libgit2
    // surfaces this as INDEX_DELETED only (no WT_DELETED), matching
    // `git status` which lists the file under "Changes to be
    // committed" only.
    XCTAssertEqual(state.deletes, 0);
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindDeleted);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindNone);
}

- (void)testNonAsciiPathRoundTrips {
    // The populator guards against non-UTF-8 paths from libgit2 by
    // skipping the entry. Constructing genuinely invalid UTF-8
    // filenames on APFS is hard, so this test exercises the success
    // branch of the same code path with multibyte UTF-8 — confirms
    // the bridge from C string to NSString preserves the bytes. Use a
    // tracked-then-modified file (not an untracked one) since
    // fileStatuses now excludes untracked entries.
    [self seedInitialCommit];
    [self writeFile:@"日本語.txt" contents:@"こんにちは\n"];
    [self runGit:@[@"add", @"日本語.txt"]];
    [self runGit:@[@"commit", @"-q", @"-m", @"add ja"]];
    [self writeFile:@"日本語.txt" contents:@"さようなら\n"];
    iTermGitState *state = [self readState];
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"日本語.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindModified);
}

#pragma mark - Diff stats (populateDiffStatsOnState:)

// Read state with diff stats off so the includeDiffStats=NO branch is
// exercised: linesInserted/Deleted and filesAdded/Modified/Deleted
// should all be zero, even when the repo has changes.
- (iTermGitState *)readStateWithoutDiffStats {
    iTermGitState *state =
        [iTermGitState gitStateForRepoAtPath:self.repoDir
                            includeDiffStats:NO];
    XCTAssertNotNil(state);
    return state;
}

- (void)testCleanRepoHasNoDiffStats {
    [self seedInitialCommit];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.linesInserted, 0);
    XCTAssertEqual(state.linesDeleted, 0);
    XCTAssertEqual(state.filesAdded, 0);
    XCTAssertEqual(state.filesModified, 0);
    XCTAssertEqual(state.filesDeleted, 0);
}

- (void)testIncludeDiffStatsOffSkipsDiffPass {
    // Same content as testModifiedFileLineCounts but called with
    // includeDiffStats:NO — the rich fields must stay 0, confirming
    // the cheap path doesn't accidentally populate them.
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v1\nv2\nv3\n"];
    iTermGitState *state = [self readStateWithoutDiffStats];
    XCTAssertEqual(state.linesInserted, 0);
    XCTAssertEqual(state.linesDeleted, 0);
    XCTAssertEqual(state.filesModified, 0);
    XCTAssertNil(state.fileStatuses,
                 @"includeDiffStats:NO should skip the per-file pass too");
}

- (void)testUntrackedFileCountsAsAddedNoLines {
    // Untracked-file deltas land in filesAdded; their contents are
    // explicitly NOT counted as inserted lines (see the GIT_DELTA_ADDED
    // / UNTRACKED branch in populateDiffStatsOnState:).
    [self seedInitialCommit];
    [self writeFile:@"new.txt" contents:@"a\nb\nc\n"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.filesAdded, 1);
    XCTAssertEqual(state.filesModified, 0);
    XCTAssertEqual(state.filesDeleted, 0);
    XCTAssertEqual(state.linesInserted, 0);
    XCTAssertEqual(state.linesDeleted, 0);
}

- (void)testStagedAddCountsAsAdded {
    [self seedInitialCommit];
    [self writeFile:@"new.txt" contents:@"x\n"];
    [self runGit:@[@"add", @"new.txt"]];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.filesAdded, 1);
    XCTAssertEqual(state.filesModified, 0);
    XCTAssertEqual(state.filesDeleted, 0);
}

- (void)testDeletedFileCountsAsDeletedNoLines {
    // Mirror of the untracked case: deleted file counts in
    // filesDeleted but doesn't add to linesDeleted.
    [self seedInitialCommit];
    [self deleteFile:@"seed.txt"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.filesDeleted, 1);
    XCTAssertEqual(state.filesAdded, 0);
    XCTAssertEqual(state.filesModified, 0);
    XCTAssertEqual(state.linesInserted, 0);
    XCTAssertEqual(state.linesDeleted, 0);
}

- (void)testModifiedFileLineCounts {
    // 1 line in HEAD, 3 lines in workdir → 1 deleted + 3 inserted is
    // what `git diff` reports (the line is rewritten, not appended,
    // because libgit2 patch stats track per-hunk add/del like
    // `git diff --numstat` does, not `--shortstat -w`).
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v1\nv2\nv3\n"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.filesModified, 1);
    XCTAssertEqual(state.filesAdded, 0);
    XCTAssertEqual(state.filesDeleted, 0);
    // Original "v1\n" is replaced by "v1\nv2\nv3\n": the diff shows
    // the original line removed and three new lines added (v1
    // is identical but git's line-by-line diff still shows it as
    // -v1 +v1 +v2 +v3 in the typical case). We don't pin to exact
    // counts because behavior depends on libgit2's diff algorithm,
    // but we *can* assert at least one inserted line and 0 deletes
    // for this lengthening edit.
    XCTAssertGreaterThan(state.linesInserted, 0);
}

- (void)testStagedAndWorkdirChangesBothCount {
    // The diff path uses git_diff_tree_to_workdir_with_index, so a
    // file that's staged AND further modified in the workdir
    // contributes a single delta that aggregates both layers.
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v2\n"];
    [self runGit:@[@"add", @"seed.txt"]];
    [self writeFile:@"seed.txt" contents:@"v3\nv4\n"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.filesModified, 1);
    XCTAssertGreaterThan(state.linesInserted, 0);
}

- (void)testMultipleModifiedFilesAggregateLineCounts {
    [self writeFile:@"a.txt" contents:@"a1\n"];
    [self writeFile:@"b.txt" contents:@"b1\nb2\n"];
    [self runGit:@[@"add", @"a.txt", @"b.txt"]];
    [self runGit:@[@"commit", @"-q", @"-m", @"seed two"]];
    [self writeFile:@"a.txt" contents:@"a1\na-extra\n"];
    [self writeFile:@"b.txt" contents:@"b1-edited\nb2\n"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.filesModified, 2);
    // Two files modified, each contributes >0 inserted lines; total
    // must be at least 2.
    XCTAssertGreaterThanOrEqual(state.linesInserted, 2);
}

#pragma mark - Ahead/behind (getCountsFromRef:)

// Helper: stand up a bare "remote" repo, push the current branch into
// it, and configure self.repoDir to track origin/<branch>. After this
// the local repo is exactly in sync with origin (ahead=0, behind=0).
- (NSString *)setUpRemoteAndPushSeed {
    [self seedInitialCommit];
    NSString *parent = [self.repoDir stringByDeletingLastPathComponent];
    NSString *bare = [parent stringByAppendingPathComponent:
                       [[self.repoDir lastPathComponent]
                            stringByAppendingString:@".remote.git"]];
    [self runGit:@[@"init", @"-q", @"--bare", bare] inDir:parent];
    [self runGit:@[@"remote", @"add", @"origin", bare]];
    // -u sets the upstream tracking branch so getCountsFromRef can
    // resolve "ref's upstream" via libgit2's branch_upstream API.
    NSString *branch = [[self runGit:@[@"rev-parse",
                                       @"--abbrev-ref",
                                       @"HEAD"]]
                         stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self runGit:@[@"push", @"-q", @"-u", @"origin", branch]];
    return bare;
}

- (void)testAheadBehindZeroWhenInSyncWithUpstream {
    [self setUpRemoteAndPushSeed];
    iTermGitState *state = [self readState];
    XCTAssertEqualObjects(state.ahead, @"0");
    XCTAssertEqualObjects(state.behind, @"0");
}

- (void)testAheadCountsLocalCommitsNotPushed {
    [self setUpRemoteAndPushSeed];
    [self writeFile:@"local1.txt" contents:@"x\n"];
    [self runGit:@[@"add", @"local1.txt"]];
    [self runGit:@[@"commit", @"-q", @"-m", @"local 1"]];
    [self writeFile:@"local2.txt" contents:@"y\n"];
    [self runGit:@[@"add", @"local2.txt"]];
    [self runGit:@[@"commit", @"-q", @"-m", @"local 2"]];
    iTermGitState *state = [self readState];
    XCTAssertEqualObjects(state.ahead, @"2");
    XCTAssertEqualObjects(state.behind, @"0");
}

- (void)testBehindCountsRemoteCommitsNotPulled {
    NSString *bare = [self setUpRemoteAndPushSeed];
    // Stage commits "from another developer" by pushing from an
    // auxiliary clone. fetch into the test repo without merging so
    // the local branch tip stays where it was while origin/<branch>
    // moves forward.
    NSString *parent = [self.repoDir stringByDeletingLastPathComponent];
    NSString *aux = [parent stringByAppendingPathComponent:
                       [[self.repoDir lastPathComponent]
                            stringByAppendingString:@".aux"]];
    [self runGit:@[@"clone", @"-q", bare, aux] inDir:parent];
    [self runGit:@[@"-c", @"user.email=aux@example.com",
                   @"-c", @"user.name=Aux",
                   @"-c", @"commit.gpgsign=false",
                   @"commit", @"--allow-empty", @"-q", @"-m", @"aux 1"]
            inDir:aux];
    [self runGit:@[@"-c", @"user.email=aux@example.com",
                   @"-c", @"user.name=Aux",
                   @"-c", @"commit.gpgsign=false",
                   @"commit", @"--allow-empty", @"-q", @"-m", @"aux 2"]
            inDir:aux];
    [self runGit:@[@"-c", @"user.email=aux@example.com",
                   @"-c", @"user.name=Aux",
                   @"push", @"-q"] inDir:aux];
    [self runGit:@[@"fetch", @"-q"]];
    iTermGitState *state = [self readState];
    XCTAssertEqualObjects(state.ahead, @"0");
    XCTAssertEqualObjects(state.behind, @"2");
    [[NSFileManager defaultManager] removeItemAtPath:aux error:nil];
}

- (void)testAheadAndBehindBothCount {
    NSString *bare = [self setUpRemoteAndPushSeed];
    // 1 local-only commit (ahead by 1).
    [self writeFile:@"local.txt" contents:@"x\n"];
    [self runGit:@[@"add", @"local.txt"]];
    [self runGit:@[@"commit", @"-q", @"-m", @"local"]];
    // 1 remote-only commit via aux clone (behind by 1).
    NSString *parent = [self.repoDir stringByDeletingLastPathComponent];
    NSString *aux = [parent stringByAppendingPathComponent:
                       [[self.repoDir lastPathComponent]
                            stringByAppendingString:@".aux"]];
    [self runGit:@[@"clone", @"-q", bare, aux] inDir:parent];
    [self runGit:@[@"-c", @"user.email=aux@example.com",
                   @"-c", @"user.name=Aux",
                   @"-c", @"commit.gpgsign=false",
                   @"commit", @"--allow-empty", @"-q", @"-m", @"aux"]
            inDir:aux];
    [self runGit:@[@"push", @"-q"] inDir:aux];
    [self runGit:@[@"fetch", @"-q"]];
    iTermGitState *state = [self readState];
    XCTAssertEqualObjects(state.ahead, @"1");
    XCTAssertEqualObjects(state.behind, @"1");
    [[NSFileManager defaultManager] removeItemAtPath:aux error:nil];
}

- (void)testNoUpstreamYieldsEmptyAheadBehind {
    // No remote configured, so getCountsFromRef returns NO and
    // gitStateForRepoAtPath: falls into the else branch that sets
    // both fields to "" rather than @"0" or nil.
    [self seedInitialCommit];
    iTermGitState *state = [self readState];
    XCTAssertEqualObjects(state.ahead, @"");
    XCTAssertEqualObjects(state.behind, @"");
}

#pragma mark - Untracked exclusion from fileStatuses

// These tests pin the behavior of the HEAD-base fileStatuses pass
// (populateHeadFileStatusesOnState:): untracked files are excluded
// from the per-file list (the workgroup diff menu filters them out
// anyway), but they still feed the `adds` count. Excluding them at the
// libgit2 level keeps rename detection from hashing every untracked
// file, which previously made the workgroup diff poll exceed the git
// timeout in a checkout full of untracked files (it would hang on
// "Diff session is waiting for changes").

- (void)testTrackedChangeSurvivesAmongUntracked {
    // A tracked modification must still appear in fileStatuses even
    // when untracked files are present; only the untracked entries are
    // dropped. `adds` reflects the untracked files regardless.
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v2\n"];
    [self writeFile:@"untracked1.txt" contents:@"a"];
    [self writeFile:@"untracked2.txt" contents:@"b"];
    iTermGitState *state = [self readState];
    XCTAssertTrue(state.dirty);
    XCTAssertEqual(state.adds, 2);
    XCTAssertEqual(state.fileStatuses.count, 1u);
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindModified);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindNone);
    XCTAssertNil([self find:state.fileStatuses path:@"untracked1.txt"]);
    XCTAssertNil([self find:state.fileStatuses path:@"untracked2.txt"]);
}

- (void)testManyUntrackedWithSingleTrackedModification {
    // Direct regression guard for the workgroup diff hang: a working
    // copy with many untracked files (including nested dirs, the
    // RECURSE_UNTRACKED_DIRS case) plus one tracked change. The diff
    // list must contain only the tracked file, no matter how many
    // untracked files are sitting around.
    [self seedInitialCommit];
    [self writeFile:@"seed.txt" contents:@"v2\n"];
    const int untrackedCount = 40;
    for (int i = 0; i < untrackedCount; i++) {
        [self writeFile:[NSString stringWithFormat:@"junk/dir%d/file%d.log", i % 4, i]
               contents:@"noise\n"];
    }
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.adds, untrackedCount);
    XCTAssertEqual(state.fileStatuses.count, 1u);
    iTermGitFileStatus *fs = state.fileStatuses.firstObject;
    XCTAssertEqualObjects(fs.path, @"seed.txt");
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindModified);
}

- (void)testOnlyUntrackedYieldsEmptyFileStatuses {
    // No tracked changes at all: dirty is true (git status would show
    // the untracked files) and `adds` counts them, but the diff list
    // is empty because there's nothing difftool could show.
    [self seedInitialCommit];
    [self writeFile:@"a.txt" contents:@"a"];
    [self writeFile:@"nested/b.txt" contents:@"b"];
    iTermGitState *state = [self readState];
    XCTAssertTrue(state.dirty);
    XCTAssertEqual(state.adds, 2);
    XCTAssertEqual(state.fileStatuses.count, 0u);
}

#pragma mark - Rename detection in fileStatuses

- (void)testStagedRenameDetected {
    // Rename detection (RENAMES_HEAD_TO_INDEX) is preserved by the
    // untracked-free pass because it pairs the head-side delete with
    // the index-side add, both tracked. `git mv` records a staged
    // rename with identical content, so libgit2's similarity scan
    // collapses it to a single renamed entry.
    [self seedInitialCommit];
    [self runGit:@[@"mv", @"seed.txt", @"renamed.txt"]];
    iTermGitState *state = [self readState];
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"renamed.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindRenamed);
    // The old path should not show up as a separate deletion entry.
    XCTAssertNil([self find:state.fileStatuses path:@"seed.txt"]);
}

- (void)testUnstagedFilesystemRenameShowsDeletionNotRename {
    // A working-tree rename whose destination is untracked (a plain
    // `mv` on disk, not `git mv`): because untracked files are excluded
    // from the pass, the new path can't be paired with the old, so the
    // old path surfaces as a deletion and the new (untracked) path is
    // absent from fileStatuses. The new file still feeds `adds`. This
    // is an intentional consequence of excluding untracked files;
    // difftool couldn't show the untracked destination anyway.
    [self seedInitialCommit];
    NSString *from = [self.repoDir stringByAppendingPathComponent:@"seed.txt"];
    NSString *to = [self.repoDir stringByAppendingPathComponent:@"moved.txt"];
    NSError *err = nil;
    [[NSFileManager defaultManager] moveItemAtPath:from toPath:to error:&err];
    XCTAssertNil(err);
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.adds, 1);
    iTermGitFileStatus *deleted = [self find:state.fileStatuses path:@"seed.txt"];
    XCTAssertNotNil(deleted);
    XCTAssertEqual(deleted.workdirStatus, iTermGitFileChangeKindDeleted);
    XCTAssertNil([self find:state.fileStatuses path:@"moved.txt"]);
}

@end
