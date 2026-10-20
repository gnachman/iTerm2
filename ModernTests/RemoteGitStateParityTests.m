//
//  RemoteGitStateParityTests.m
//  ModernTests
//
//  On a host reached through SSH Integration, git state comes from it2_git_state.py, which runs
//  the git CLI there. Locally it comes from libgit2. Both feed the same status bar component and
//  workgroup toolbar, so they must agree. Each test builds a real repo with /usr/bin/git, reads
//  it both ways, and requires every field to match: the libgit2 path is the specification.
//
//  The script runs through the exact command line the remote worker sends, under /bin/sh, with
//  this Mac's python3 standing in for the remote one.
//

#import <XCTest/XCTest.h>

#import "iTermGitClient.h"
#import "iTermGitState.h"
#import "iTermGitState+MainApp.h"
#import "iTermVariableScope.h"
#import "iTermVariables.h"

// A Swift class (sources/SSH/RemoteGitState.swift). ModernTests cannot import
// iTerm2SharedARC-Swift.h, so declare what these tests call.
@interface iTermRemoteGitState : NSObject
+ (NSString *)commandLineWithPython:(NSString *)python
                               path:(NSString *)path
                            gitBase:(NSString *)gitBase
                   includeDiffStats:(BOOL)includeDiffStats
                            timeout:(NSTimeInterval)timeout;
+ (iTermGitState *)stateFromScriptOutput:(NSString *)output timedOut:(BOOL *)timedOut;
+ (BOOL)scriptOutputIsWellFormed:(NSString *)output;
@end

// Also a Swift class (sources/VT100/UserVariableAssignment.swift): the payload of SetUserVar.
@interface iTermUserVariableAssignment : NSObject
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly, nullable) NSString *value;
- (nullable instancetype)initWithPayload:(NSString *)payload;
@end

@interface RemoteGitStateParityTests : XCTestCase
@property (nonatomic, copy) NSString *repoDir;
@property (nonatomic, strong) NSMutableArray<NSString *> *tempDirs;
- (NSString *)run:(NSString *)executable arguments:(NSArray<NSString *> *)arguments inDir:(NSString *)dir status:(int *)status;
@end

@implementation RemoteGitStateParityTests

- (void)setUp {
    [super setUp];
    self.tempDirs = [NSMutableArray array];
    self.repoDir = [self makeTempDir];
    [self git:@[ @"init", @"-q", @"-b", @"main" ]];
    [self configure:self.repoDir];
}

- (void)tearDown {
    for (NSString *dir in self.tempDirs) {
        [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
    }
    [super tearDown];
}

#pragma mark - Helpers

- (NSString *)makeTempDir {
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"RemoteGitState.XXXXXX"];
    char *buffer = strdup(template.fileSystemRepresentation);
    char *result = mkdtemp(buffer);
    // realpath: /var is a symlink to /private/var, and git reports resolved paths.
    char resolved[PATH_MAX];
    NSString *path = (result && realpath(result, resolved)) ? @(resolved) : nil;
    free(buffer);
    XCTAssertNotNil(path);
    [self.tempDirs addObject:path];
    return path;
}

- (NSDictionary<NSString *, NSString *> *)cleanEnvironment {
    // The test host may run under ASan or malloc diagnostics, which children inherit and which
    // make git and python print noise or fail.
    NSMutableDictionary<NSString *, NSString *> *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    for (NSString *key in environment.allKeys) {
        if ([key hasPrefix:@"Malloc"] || [key hasPrefix:@"DYLD_"] ||
            [key hasPrefix:@"NSZombie"] || [key hasPrefix:@"ASAN_"]) {
            [environment removeObjectForKey:key];
        }
    }
    // A user's global config (signing, hooks, aliases) must not leak into the fixtures.
    environment[@"GIT_CONFIG_GLOBAL"] = @"/dev/null";
    environment[@"GIT_CONFIG_NOSYSTEM"] = @"1";
    return environment;
}

- (NSString *)run:(NSString *)executable arguments:(NSArray<NSString *> *)arguments inDir:(NSString *)dir status:(int *)status {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.currentDirectoryURL = [NSURL fileURLWithPath:dir];
    task.arguments = arguments;
    task.environment = [self cleanEnvironment];
    NSPipe *out = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = out;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        XCTFail(@"%@ failed to launch: %@", executable, error);
        return @"";
    }
    NSData *data = [out.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    *status = task.terminationStatus;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

- (NSString *)git:(NSArray<NSString *> *)args inDir:(NSString *)dir {
    int status = 0;
    NSString *output = [self run:@"/usr/bin/git" arguments:args inDir:dir status:&status];
    XCTAssertEqual(status, 0, @"git %@: %@", [args componentsJoinedByString:@" "], output);
    return output;
}

- (NSString *)git:(NSArray<NSString *> *)args {
    return [self git:args inDir:self.repoDir];
}

// For commands expected to fail, such as a merge that conflicts.
- (void)gitAllowingFailure:(NSArray<NSString *> *)args {
    int status = 0;
    [self run:@"/usr/bin/git" arguments:args inDir:self.repoDir status:&status];
}

- (void)configure:(NSString *)dir {
    [self git:@[ @"config", @"user.email", @"test@example.com" ] inDir:dir];
    [self git:@[ @"config", @"user.name", @"Tester" ] inDir:dir];
    [self git:@[ @"config", @"commit.gpgsign", @"false" ] inDir:dir];
}

- (void)write:(NSString *)name contents:(NSString *)contents {
    NSString *path = [self.repoDir stringByAppendingPathComponent:name];
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    XCTAssertTrue([contents writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil]);
}

- (void)remove:(NSString *)name {
    [[NSFileManager defaultManager] removeItemAtPath:[self.repoDir stringByAppendingPathComponent:name] error:nil];
}

- (void)commitAll:(NSString *)message {
    [self git:@[ @"add", @"-A" ]];
    [self git:@[ @"commit", @"-q", @"-m", message ]];
}

// Ten lines, so a rename with a one-line edit stays above git's 50% similarity threshold.
- (NSString *)lines:(NSString *)prefix {
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 10; i++) {
        [s appendFormat:@"%@ line %d\n", prefix, i];
    }
    return s;
}

- (iTermGitState *)remoteStateForPath:(NSString *)path gitBase:(NSString *)gitBase stats:(BOOL)stats {
    NSString *command = [iTermRemoteGitState commandLineWithPython:@"/usr/bin/python3"
                                                              path:path
                                                           gitBase:gitBase
                                                  includeDiffStats:stats
                                                           timeout:20];
    int status = 0;
    NSString *output = [self run:@"/bin/sh" arguments:@[ @"-c", command ] inDir:NSTemporaryDirectory() status:&status];
    BOOL timedOut = NO;
    iTermGitState *state = [iTermRemoteGitState stateFromScriptOutput:output timedOut:&timedOut];
    XCTAssertFalse(timedOut, @"%@", output);
    XCTAssertTrue([iTermRemoteGitState scriptOutputIsWellFormed:output], @"status=%d output=%@", status, output);
    return state;
}

- (NSArray<NSString *> *)describeFiles:(NSArray<iTermGitFileStatus *> *)files {
    if (!files) {
        return nil;
    }
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (iTermGitFileStatus *file in files) {
        [result addObject:[NSString stringWithFormat:@"%@ index=%@ workdir=%@",
                           file.path, @(file.indexStatus), @(file.workdirStatus)]];
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

- (void)assertParityForPath:(NSString *)path gitBase:(NSString *)gitBase stats:(BOOL)stats {
    iTermGitState *local = [iTermGitState gitStateForRepoAtPath:path gitBase:gitBase includeDiffStats:stats];
    iTermGitState *remote = [self remoteStateForPath:path gitBase:gitBase stats:stats];
    NSString *context = [NSString stringWithFormat:@"path=%@ base=%@ stats=%@", path, gitBase, @(stats)];
    if (!local) {
        XCTAssertNil(remote, @"%@: libgit2 found no repo but the script did: %@", context, remote.prettyDescription);
        return;
    }
    XCTAssertNotNil(remote, @"%@", context);
    XCTAssertEqualObjects(remote.branch, local.branch, @"%@", context);
    XCTAssertEqualObjects(remote.ahead, local.ahead, @"%@", context);
    XCTAssertEqualObjects(remote.behind, local.behind, @"%@", context);
    XCTAssertEqual(remote.dirty, local.dirty, @"%@", context);
    XCTAssertEqual(remote.adds, local.adds, @"%@", context);
    XCTAssertEqual(remote.deletes, local.deletes, @"%@", context);
    XCTAssertEqual(remote.linesInserted, local.linesInserted, @"%@", context);
    XCTAssertEqual(remote.linesDeleted, local.linesDeleted, @"%@", context);
    XCTAssertEqual(remote.filesAdded, local.filesAdded, @"%@", context);
    XCTAssertEqual(remote.filesModified, local.filesModified, @"%@", context);
    XCTAssertEqual(remote.filesDeleted, local.filesDeleted, @"%@", context);
    XCTAssertEqual(remote.repoState, local.repoState, @"%@", context);
    XCTAssertEqualObjects([self describeFiles:remote.fileStatuses], [self describeFiles:local.fileStatuses], @"%@", context);
}

// Every combination the two consumers use: the status bar (no stats) and the workgroup (stats,
// with and without a base).
- (void)assertParity {
    [self assertParityForPath:self.repoDir gitBase:nil stats:NO];
    [self assertParityForPath:self.repoDir gitBase:nil stats:YES];
}

#pragma mark - Tests

- (void)testCleanRepo {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self assertParity];
}

- (void)testStagedUnstagedAndBoth {
    [self write:@"staged.txt" contents:[self lines:@"s"]];
    [self write:@"unstaged.txt" contents:[self lines:@"u"]];
    [self write:@"both.txt" contents:[self lines:@"b"]];
    [self commitAll:@"one"];
    [self write:@"staged.txt" contents:@"changed\n"];
    [self git:@[ @"add", @"staged.txt" ]];
    [self write:@"unstaged.txt" contents:[[self lines:@"u"] stringByAppendingString:@"more\nand more\n"]];
    [self write:@"both.txt" contents:@"first\n"];
    [self git:@[ @"add", @"both.txt" ]];
    [self write:@"both.txt" contents:@"second\n"];
    [self assertParity];
}

- (void)testUntrackedFilesInNestedDirectoriesAreCountedOneByOne {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"new/deep/one.txt" contents:@"1\n"];
    [self write:@"new/deep/two.txt" contents:@"2\n"];
    [self write:@"top.txt" contents:@"t\n"];
    [self assertParity];
}

- (void)testDeletedInWorkdirAndStagedDelete {
    [self write:@"gone.txt" contents:@"g\n"];
    [self write:@"staged-gone.txt" contents:@"s\n"];
    [self write:@"keep.txt" contents:@"k\n"];
    [self commitAll:@"one"];
    [self remove:@"gone.txt"];
    [self git:@[ @"rm", @"-q", @"staged-gone.txt" ]];
    [self assertParity];
}

- (void)testStagedAdd {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"added.txt" contents:@"new\n"];
    [self git:@[ @"add", @"added.txt" ]];
    [self assertParity];
}

- (void)testPureRenameAndRenameWithEdit {
    [self write:@"pure.txt" contents:[self lines:@"p"]];
    [self write:@"edited.txt" contents:[self lines:@"e"]];
    [self commitAll:@"one"];
    [self git:@[ @"mv", @"pure.txt", @"pure-renamed.txt" ]];
    [self git:@[ @"mv", @"edited.txt", @"edited-renamed.txt" ]];
    [self write:@"edited-renamed.txt" contents:[[self lines:@"e"] stringByAppendingString:@"extra\n"]];
    [self git:@[ @"add", @"edited-renamed.txt" ]];
    [self assertParity];
}

- (void)testTypeChange {
    [self write:@"link.txt" contents:@"plain\n"];
    [self write:@"target.txt" contents:@"t\n"];
    [self commitAll:@"one"];
    [self remove:@"link.txt"];
    NSString *link = [self.repoDir stringByAppendingPathComponent:@"link.txt"];
    XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:@"target.txt" error:nil]);
    [self assertParity];
}

- (void)testTypeChangeAgainstABase {
    [self write:@"link.txt" contents:@"plain\n"];
    [self write:@"target.txt" contents:@"t\n"];
    [self commitAll:@"one"];
    [self git:@[ @"branch", @"base" ]];
    [self remove:@"link.txt"];
    NSString *link = [self.repoDir stringByAppendingPathComponent:@"link.txt"];
    XCTAssertTrue([[NSFileManager defaultManager] createSymbolicLinkAtPath:link withDestinationPath:@"target.txt" error:nil]);
    [self commitAll:@"now a link"];
    [self assertParityForPath:self.repoDir gitBase:@"base" stats:YES];
}

- (void)testBinaryFileCountsNoLines {
    NSString *path = [self.repoDir stringByAppendingPathComponent:@"blob.bin"];
    unsigned char bytes1[] = { 0, 1, 2, 3, 0, 5 };
    [[NSData dataWithBytes:bytes1 length:sizeof(bytes1)] writeToFile:path atomically:NO];
    [self commitAll:@"one"];
    unsigned char bytes2[] = { 0, 9, 9, 9, 0, 5, 6 };
    [[NSData dataWithBytes:bytes2 length:sizeof(bytes2)] writeToFile:path atomically:NO];
    [self assertParity];
}

- (void)testOddFileNames {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"with space.txt" contents:@"s\n"];
    [self write:@"new\nline.txt" contents:@"n\n"];
    [self write:@"日本語.txt" contents:@"j\n"];
    [self write:@"quote\"and'tab\t.txt" contents:@"q\n"];
    [self git:@[ @"add", @"-A" ]];
    [self write:@"untracked space.txt" contents:@"u\n"];
    [self assertParity];
}

// A file added with intent to add (git add -N).
- (void)testIntentToAdd {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"later.txt" contents:@"l\n"];
    [self git:@[ @"add", @"-N", @"later.txt" ]];
    [self assertParity];
}

// A rename in the work tree, of a file added with intent to add, puts its R in the second column.
// Its original path, here one that looks like a branch header or a deletion, is not a record.
- (void)testWorkTreeRenameOfAnIntentToAddFile {
    [self write:@"## evil" contents:@"hello\n"];
    [self write:@"xDz" contents:@"q\n"];
    [self commitAll:@"one"];
    NSFileManager *fm = [NSFileManager defaultManager];
    XCTAssertTrue([fm moveItemAtPath:[self.repoDir stringByAppendingPathComponent:@"## evil"]
                              toPath:[self.repoDir stringByAppendingPathComponent:@"new1"] error:nil]);
    XCTAssertTrue([fm moveItemAtPath:[self.repoDir stringByAppendingPathComponent:@"xDz"]
                              toPath:[self.repoDir stringByAppendingPathComponent:@"new2"] error:nil]);
    [self git:@[ @"add", @"-N", @"new1", @"new2" ]];
    [self assertParity];
}

// A conflicted path holding a newline must not hide the changes of a path that matches its
// last line.
- (void)testConflictWhosePathHoldsANewline {
    [self write:@"b" contents:@"b\n"];
    [self write:@"a\nb" contents:@"base\n"];
    [self commitAll:@"base"];
    [self git:@[ @"checkout", @"-q", @"-b", @"other" ]];
    [self write:@"a\nb" contents:@"theirs\n"];
    [self commitAll:@"theirs"];
    [self git:@[ @"checkout", @"-q", @"main" ]];
    [self write:@"a\nb" contents:@"ours\n"];
    [self commitAll:@"ours"];
    [self gitAllowingFailure:@[ @"merge", @"-q", @"other" ]];
    [self write:@"b" contents:@"b\nmore\n"];
    [self assertParity];
}

- (void)testDetachedHead {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"a.txt" contents:@"b\n"];
    [self commitAll:@"two"];
    [self git:@[ @"checkout", @"-q", @"HEAD~1" ]];
    [self assertParity];
}

- (void)testAheadAndBehindUpstream {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    NSString *remote = [self makeTempDir];
    [self git:@[ @"init", @"-q", @"--bare" ] inDir:remote];
    [self git:@[ @"remote", @"add", @"origin", remote ]];
    [self git:@[ @"push", @"-q", @"-u", @"origin", @"main" ]];
    // Someone else pushes two commits.
    NSString *other = [self makeTempDir];
    [self git:@[ @"clone", @"-q", remote, other ] inDir:other];
    [self configure:other];
    for (NSString *name in @[ @"x", @"y" ]) {
        [name writeToFile:[other stringByAppendingPathComponent:name] atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [self git:@[ @"add", @"-A" ] inDir:other];
        [self git:@[ @"commit", @"-q", @"-m", name ] inDir:other];
    }
    [self git:@[ @"push", @"-q" ] inDir:other];
    [self git:@[ @"fetch", @"-q" ]];
    // And we commit one of our own.
    [self write:@"mine.txt" contents:@"m\n"];
    [self commitAll:@"mine"];
    [self assertParity];
}

- (void)testUpstreamThatIsGone {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self git:@[ @"config", @"branch.main.remote", @"origin" ]];
    [self git:@[ @"config", @"branch.main.merge", @"refs/heads/main" ]];
    [self assertParity];
}

- (void)testUnbornBranch {
    [self write:@"a.txt" contents:@"a\n"];
    [self assertParity];
}

- (void)testNotARepository {
    NSString *dir = [self makeTempDir];
    [self assertParityForPath:dir gitBase:nil stats:YES];
}

- (void)testSubdirectoryAndMissingDirectory {
    [self write:@"sub/dir/a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"sub/dir/a.txt" contents:@"b\n"];
    [self assertParityForPath:[self.repoDir stringByAppendingPathComponent:@"sub/dir"] gitBase:nil stats:YES];
    // A directory that was removed since the shell reported it: both walk up to the repo.
    [self assertParityForPath:[self.repoDir stringByAppendingPathComponent:@"sub/dir/gone/deeper"] gitBase:nil stats:YES];
}

- (void)testAgainstABase {
    [self write:@"stays.txt" contents:[self lines:@"s"]];
    [self write:@"moves.txt" contents:[self lines:@"m"]];
    [self write:@"dies.txt" contents:@"d\n"];
    [self commitAll:@"base"];
    [self git:@[ @"branch", @"base" ]];
    [self git:@[ @"mv", @"moves.txt", @"moved.txt" ]];
    [self git:@[ @"rm", @"-q", @"dies.txt" ]];
    [self write:@"born.txt" contents:@"b\n"];
    [self commitAll:@"committed changes"];
    [self write:@"stays.txt" contents:@"edited after the commit\n"];
    [self write:@"untracked.txt" contents:@"u\n"];
    for (NSString *base in @[ @"base", @"HEAD~1", @"HEAD" ]) {
        [self assertParityForPath:self.repoDir gitBase:base stats:YES];
        [self assertParityForPath:self.repoDir gitBase:base stats:NO];
    }
}

// A base that does not resolve leaves the HEAD-relative list rather than blanking it.
- (void)testUnresolvableBase {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"a.txt" contents:@"b\n"];
    [self assertParityForPath:self.repoDir gitBase:@"no-such-ref" stats:YES];
    [self assertParityForPath:self.repoDir gitBase:@"no-such-ref" stats:NO];
}

- (void)testMergeConflict {
    [self write:@"c.txt" contents:@"base\n"];
    [self commitAll:@"base"];
    [self git:@[ @"checkout", @"-q", @"-b", @"other" ]];
    [self write:@"c.txt" contents:@"theirs\n"];
    [self commitAll:@"theirs"];
    [self git:@[ @"checkout", @"-q", @"main" ]];
    [self write:@"c.txt" contents:@"ours\n"];
    [self commitAll:@"ours"];
    [self gitAllowingFailure:@[ @"merge", @"-q", @"other" ]];
    [self assertParity];
    [self assertParityForPath:self.repoDir gitBase:@"other" stats:YES];
}

- (void)testRebaseInProgress {
    [self write:@"c.txt" contents:@"base\n"];
    [self commitAll:@"base"];
    [self git:@[ @"checkout", @"-q", @"-b", @"other" ]];
    [self write:@"c.txt" contents:@"theirs\n"];
    [self commitAll:@"theirs"];
    [self git:@[ @"checkout", @"-q", @"main" ]];
    [self write:@"c.txt" contents:@"ours\n"];
    [self commitAll:@"ours"];
    [self gitAllowingFailure:@[ @"rebase", @"other" ]];
    [self assertParity];
}

- (void)testCherryPickAndRevertInProgress {
    [self write:@"c.txt" contents:@"base\n"];
    [self commitAll:@"base"];
    [self git:@[ @"checkout", @"-q", @"-b", @"other" ]];
    [self write:@"c.txt" contents:@"theirs\n"];
    [self commitAll:@"theirs"];
    [self git:@[ @"checkout", @"-q", @"main" ]];
    [self write:@"c.txt" contents:@"ours\n"];
    [self commitAll:@"ours"];
    [self gitAllowingFailure:@[ @"cherry-pick", @"other" ]];
    [self assertParity];
    [self git:@[ @"cherry-pick", @"--abort" ]];
    [self write:@"c.txt" contents:@"later\n"];
    [self commitAll:@"later"];
    [self gitAllowingFailure:@[ @"revert", @"--no-edit", @"HEAD~1" ]];
    [self assertParity];
}

- (void)testBisect {
    [self write:@"a.txt" contents:@"a\n"];
    [self commitAll:@"one"];
    [self write:@"a.txt" contents:@"b\n"];
    [self commitAll:@"two"];
    [self git:@[ @"bisect", @"start" ]];
    [self assertParity];
}

@end

// it2git (in the shell-integration submodule) is the git source for a plain ssh session with no
// SSH Integration connection: it runs at each prompt and reports through user variables. It must
// read every fixture above the way libgit2 does, for the fields it reports. It runs under
// /bin/bash, which on macOS is 3.2, the oldest bash it supports, and its variables are decoded
// as a session decodes them.
@interface It2gitParityTests : RemoteGitStateParityTests
@end

@implementation It2gitParityTests

- (NSString *)it2gitPath {
    // ModernTests/ -> the repository.
    NSString *root = [[[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent]
                      stringByDeletingLastPathComponent];
    return [root stringByAppendingPathComponent:@"submodules/iTerm2-shell-integration/utilities/it2git"];
}

// What it2git sets, as a session's user variables would hold it.
- (iTermGitState *)it2gitStateInDir:(NSString *)dir output:(NSString **)outputPtr {
    int status = 0;
    NSString *output = [self run:@"/bin/bash" arguments:@[ [self it2gitPath] ] inDir:dir status:&status];
    *outputPtr = output;
    XCTAssertEqual(status, 0, @"%@", output);
    iTermVariables *variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextSession owner:self];
    iTermVariableScope *scope = [[iTermVariableScope alloc] init];
    [scope addVariables:variables toScopeNamed:nil];
    iTermVariables *user = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self];
    user.isUserWritable = YES;
    [scope setValue:user forVariableNamed:@"user"];
    NSString *prefix = @"\033]1337;SetUserVar=";
    for (NSString *chunk in [output componentsSeparatedByString:prefix]) {
        NSRange bel = [chunk rangeOfString:@"\a"];
        if (bel.location == NSNotFound) {
            continue;
        }
        iTermUserVariableAssignment *assignment =
            [[iTermUserVariableAssignment alloc] initWithPayload:[chunk substringToIndex:bel.location]];
        if (assignment) {
            [scope setValue:assignment.value ?: @"" forVariableNamed:assignment.name];
        }
    }
    return [[iTermGitState alloc] initWithScope:scope];
}

// it2git has no base and always reports stats, so each fixture is compared once, with stats and
// against HEAD; the fields that depend on a base are not among those it reports.
- (void)assertParityForPath:(NSString *)path gitBase:(NSString *)gitBase stats:(BOOL)stats {
    if (!stats || (gitBase.length > 0 && ![gitBase isEqualToString:@"HEAD"])) {
        return;
    }
    // A shell can't start in a directory that is gone; its nearest ancestor stands in.
    NSString *dir = path;
    BOOL isDirectory = NO;
    while (![[NSFileManager defaultManager] fileExistsAtPath:dir isDirectory:&isDirectory] || !isDirectory) {
        dir = [dir stringByDeletingLastPathComponent];
    }
    iTermGitState *local = [iTermGitState gitStateForRepoAtPath:path gitBase:nil includeDiffStats:YES];
    NSString *output = nil;
    iTermGitState *remote = [self it2gitStateInDir:dir output:&output];
    NSString *context = [NSString stringWithFormat:@"path=%@ it2git output=%@", path,
                         [output stringByReplacingOccurrencesOfString:@"\033" withString:@"ESC"]];
    XCTAssertNotNil(remote, @"%@", context);
    if (!local) {
        // Not a repository, or HEAD is unborn: it2git clears every variable.
        XCTAssertEqualObjects(remote.branch, @"", @"%@", context);
        XCTAssertFalse(remote.dirty, @"%@", context);
        return;
    }
    XCTAssertEqualObjects(remote.branch, local.branch, @"%@", context);
    XCTAssertEqualObjects(remote.ahead, local.ahead, @"%@", context);
    XCTAssertEqualObjects(remote.behind, local.behind, @"%@", context);
    XCTAssertEqual(remote.dirty, local.dirty, @"%@", context);
    XCTAssertEqual(remote.adds, local.adds, @"%@", context);
    XCTAssertEqual(remote.deletes, local.deletes, @"%@", context);
    XCTAssertEqual(remote.linesInserted, local.linesInserted, @"%@", context);
    XCTAssertEqual(remote.linesDeleted, local.linesDeleted, @"%@", context);
    XCTAssertEqual(remote.filesAdded, local.filesAdded, @"%@", context);
    XCTAssertEqual(remote.filesModified, local.filesModified, @"%@", context);
    XCTAssertEqual(remote.filesDeleted, local.filesDeleted, @"%@", context);
}

@end
