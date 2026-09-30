//
//  iTermSemanticHistoryXcodeTests.m
//  ModernTests
//
//  Covers how Semantic History picks the xed binary used to open a file in Xcode (issue 13091).
//

#import <XCTest/XCTest.h>

#import "iTermSemanticHistoryController.h"
#import "iTermSemanticHistoryPrefsController.h"
#import "iTermVariables.h"
#import "iTermVariableScope.h"

@interface iTermSemanticHistoryXcodeTestsFakeFileManager : NSFileManager
@property (nonatomic, readonly) NSMutableSet<NSString *> *files;
// Symlink path -> destination.
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSString *> *symlinks;
@end

@implementation iTermSemanticHistoryXcodeTestsFakeFileManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _files = [NSMutableSet set];
        _symlinks = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if (isDirectory) {
        *isDirectory = NO;
    }
    return [_files containsObject:path];
}

- (BOOL)fileExistsAtPath:(NSString *)path {
    return [self fileExistsAtPath:path isDirectory:NULL];
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path error:(NSError **)error {
    NSString *destination = _symlinks[path];
    if (!destination && error) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
    }
    return destination;
}

@end

@interface iTermSemanticHistoryXcodeTestsController : iTermSemanticHistoryController
@property (nonatomic, readonly) iTermSemanticHistoryXcodeTestsFakeFileManager *fakeFileManager;
// When NO, the bundle lookup reports that Xcode is not installed.
@property (nonatomic) BOOL xcodeInstalled;
@property (nonatomic, copy) NSString *launchedPath;
@property (nonatomic, copy) NSArray *launchedArguments;
@end

@implementation iTermSemanticHistoryXcodeTestsController

- (instancetype)init {
    self = [super init];
    if (self) {
        _fakeFileManager = [[iTermSemanticHistoryXcodeTestsFakeFileManager alloc] init];
        _xcodeInstalled = YES;
    }
    return self;
}

- (NSFileManager *)fileManager {
    return _fakeFileManager;
}

// Maps a bundle ID to /Applications/<bundle ID> so tests can predict where the bundled xed would be.
- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)bundleId {
    if (!_xcodeInstalled) {
        return nil;
    }
    return [@"/Applications" stringByAppendingPathComponent:bundleId];
}

- (void)launchTaskWithPath:(NSString *)path arguments:(NSArray *)arguments completion:(void (^)(void))completion {
    self.launchedPath = path;
    self.launchedArguments = arguments;
    if (completion) {
        completion();
    }
}

- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier path:(NSString *)path {
    XCTFail(@"Unexpected app launch of %@ for %@", bundleIdentifier, path);
}

- (BOOL)defaultAppForFileIsEditor:(NSString *)file {
    return NO;
}

- (NSTimeInterval)evaluationTimeout {
    return 0;
}

@end

@interface iTermSemanticHistoryXcodeTests : XCTestCase
@end

@implementation iTermSemanticHistoryXcodeTests {
    iTermSemanticHistoryXcodeTestsController *_controller;
    iTermVariableScope *_scope;
}

static NSString *const kShim = @"/usr/bin/xed";
static NSString *const kFile = @"/file/that/exists";
static NSString *const kXcodeSelectLink = @"/var/db/xcode_select_link";
static NSString *const kCommandLineTools = @"/Library/Developer/CommandLineTools";
static NSString *const kSelectedXcodeDeveloperDir = @"/Applications/Xcode-beta.app/Contents/Developer";

- (void)setUp {
    [super setUp];
    _scope = [[iTermVariableScope alloc] init];
    _controller = [[iTermSemanticHistoryXcodeTestsController alloc] init];
    _controller.prefs = @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
                           kSemanticHistoryEditorKey: kXcodeAppIdentifier };
    [_controller.fakeFileManager.files addObject:kFile];
}

- (NSString *)bundledXedPath {
    return [NSString stringWithFormat:@"/Applications/%@/Contents/Developer/usr/bin/xed", kXcodeAppIdentifier];
}

- (void)installBundledXed {
    [_controller.fakeFileManager.files addObject:[self bundledXedPath]];
}

- (void)installXedInDeveloperDirectory:(NSString *)developerDirectory {
    [_controller.fakeFileManager.files addObject:[developerDirectory stringByAppendingPathComponent:@"usr/bin/xed"]];
}

- (void)pointXcodeSelectAt:(NSString *)developerDirectory {
    _controller.fakeFileManager.symlinks[kXcodeSelectLink] = developerDirectory;
}

// Opens kFile at line 12 in Xcode and returns the path of the xed that was launched.
- (NSString *)launchedXedPath {
    XCTestExpectation *expectation = [self expectationWithDescription:@"open completes"];
    [_controller openPath:kFile
            orRawFilename:[kFile stringByAppendingString:@":12"]
                 fragment:nil
                   target:nil
            substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"",
                             kSemanticHistorySuffixSubstitutionKey: @"",
                             kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }
                    scope:_scope
               lineNumber:@"12"
             columnNumber:nil
                   window:nil
               completion:^(BOOL ok) {
        XCTAssertTrue(ok);
        [expectation fulfill];
    }];
    [self waitForExpectations:@[ expectation ] timeout:5];
    NSArray *expectedArguments = @[ @"--line", @"12", kFile ];
    XCTAssertEqualObjects(expectedArguments, _controller.launchedArguments);
    return _controller.launchedPath;
}

- (void)testUsesShimWhenSelectedDeveloperDirectoryHasXed {
    // xcode-select points at an Xcode, possibly not the one LaunchServices prefers. The shim
    // honors that choice, so it must be used even though a bundled xed is also available.
    [self pointXcodeSelectAt:kSelectedXcodeDeveloperDir];
    [self installXedInDeveloperDirectory:kSelectedXcodeDeveloperDir];
    [self installBundledXed];
    XCTAssertEqualObjects(kShim, [self launchedXedPath]);
}

- (void)testUsesBundledXedWhenSelectedDeveloperDirectoryIsCommandLineTools {
    [self pointXcodeSelectAt:kCommandLineTools];
    [self installBundledXed];
    XCTAssertEqualObjects([self bundledXedPath], [self launchedXedPath]);
}

- (void)testUsesBundledXedWhenSelectedXcodeWasDeleted {
    // The developer directory looks like an Xcode but has no xed, so the shim would fail.
    [self pointXcodeSelectAt:kSelectedXcodeDeveloperDir];
    [self installBundledXed];
    XCTAssertEqualObjects([self bundledXedPath], [self launchedXedPath]);
}

- (void)testUsesBundledXedWhenNothingIsSelected {
    [self installBundledXed];
    XCTAssertEqualObjects([self bundledXedPath], [self launchedXedPath]);
}

- (void)testFallsBackToShimWhenBundledXedIsMissing {
    [self pointXcodeSelectAt:kCommandLineTools];
    XCTAssertEqualObjects(kShim, [self launchedXedPath]);
}

- (void)testFallsBackToShimWhenXcodeIsNotInstalled {
    [self pointXcodeSelectAt:kCommandLineTools];
    _controller.xcodeInstalled = NO;
    XCTAssertEqualObjects(kShim, [self launchedXedPath]);
}

- (void)testNonAbsoluteSymlinkDestinationIsIgnored {
    // xcode-select only writes absolute destinations, so anything else is treated as unset.
    [self pointXcodeSelectAt:@"../../Applications/Xcode-beta.app/Contents/Developer"];
    [self installXedInDeveloperDirectory:kSelectedXcodeDeveloperDir];
    [self installBundledXed];
    XCTAssertEqualObjects([self bundledXedPath], [self launchedXedPath]);
}

@end
