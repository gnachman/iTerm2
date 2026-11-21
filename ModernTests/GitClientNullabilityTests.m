//
//  GitClientNullabilityTests.m
//  ModernTests
//
//  -[iTermGitClient repo] is NULL when the client's path is not in a
//  repository, an expected outcome (the git poller reports "not a repository"),
//  under a nonnull claim that also made the backing ivar _Nonnull (unit N13 of
//  docs/swift-migration/nullability-triage.md). Its readers test it before use.
//  Before the claim was made nullable, making this client was a nullability
//  sanitizer report (NULL bound to a _Nonnull ivar).
//

#import <XCTest/XCTest.h>

// libgit2's headers have doc comments that -Wdocumentation flags; they are
// third-party code.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdocumentation"
#pragma clang diagnostic ignored "-Wdocumentation-deprecated-sync"
#import "iTermGitClient.h"
#pragma clang diagnostic pop

@interface GitClientNullabilityTests : XCTestCase
@end

@implementation GitClientNullabilityTests

- (void)testRepoIsNullOutsideARepository {
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"GitClientNullability.XXXXXX"];
    char *path = strdup(template.fileSystemRepresentation);
    XCTAssertTrue(mkdtemp(path) != NULL);
    NSString *directory = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path
                                                                                       length:strlen(path)];
    free(path);

    iTermGitClient *client = [[iTermGitClient alloc] initWithRepoPath:directory];
    XCTAssertTrue(client.repo == NULL);

    [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
}

@end
