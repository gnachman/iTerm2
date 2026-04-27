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
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:self.repoDir];
    task.arguments = args;
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
    [self seedInitialCommit];
    [self writeFile:@"new.txt" contents:@"x"];
    iTermGitState *state = [self readState];
    XCTAssertTrue(state.dirty);
    XCTAssertEqual(state.adds, 1);
    XCTAssertEqual(state.deletes, 0);
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"new.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindNone);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindUntracked);
}

- (void)testRecurseUntrackedDirsCountsPerFile {
    // The unified status walk uses RECURSE_UNTRACKED_DIRS so a
    // directory of N untracked files contributes N to `adds`,
    // matching `git status --porcelain` rather than the legacy
    // directory-rollup behavior.
    [self seedInitialCommit];
    [self writeFile:@"newdir/a.txt" contents:@"1"];
    [self writeFile:@"newdir/b.txt" contents:@"2"];
    [self writeFile:@"newdir/c.txt" contents:@"3"];
    iTermGitState *state = [self readState];
    XCTAssertEqual(state.adds, 3);
    XCTAssertEqual(state.fileStatuses.count, 3u);
    for (iTermGitFileStatus *fs in state.fileStatuses) {
        XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindUntracked);
        XCTAssertEqual(fs.indexStatus, iTermGitFileChangeKindNone);
    }
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
    // the bridge from C string to NSString preserves the bytes.
    [self seedInitialCommit];
    [self writeFile:@"日本語.txt" contents:@"こんにちは"];
    iTermGitState *state = [self readState];
    iTermGitFileStatus *fs = [self find:state.fileStatuses path:@"日本語.txt"];
    XCTAssertNotNil(fs);
    XCTAssertEqual(fs.workdirStatus, iTermGitFileChangeKindUntracked);
}

@end
