//
//  DynamicProfileRewriteCrashTests.m
//  ModernTests
//
//  Reproduces the 3.7.1 crash where -[iTermDynamicProfileManager
//  writeModifiedProfile:toFile:] aborted on assert(rewritable).
//  markProfileRewritableWithGuid: called onDiskEntryForProfile:, which returns
//  nil when the on-disk dynamic-profile file no longer contains the GUID (the
//  user edited the file out from under us). That nil flowed into
//  writeModifiedProfile: as a nil profile, and the assert on
//  KEY_DYNAMIC_PROFILE_REWRITABLE fired (asserts are enabled in release).
//
//  The fix makes a nil or non-rewritable profile a no-op instead of a crash.
//

#import <XCTest/XCTest.h>

#import "iTermDynamicProfileManager.h"
#import "ITAddressBookMgr.h"

// Redeclare the (privately-implemented) method under test so it can be called
// directly, which is where the assert used to fire.
@interface iTermDynamicProfileManager (Testing)
- (void)writeModifiedProfile:(Profile *)profile toFile:(NSString *)filename;
@end

@interface DynamicProfileRewriteCrashTests : XCTestCase
@end

@implementation DynamicProfileRewriteCrashTests {
    NSString *_path;
}

- (void)setUp {
    _path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DynamicProfileRewriteCrashTests.json"];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_path error:nil];
}

// Before the fix this aborted via assert(). Now it must return without writing.
- (void)testNilProfileDoesNotCrashOrWrite {
    iTermDynamicProfileManager *mgr = [iTermDynamicProfileManager sharedInstance];
    [mgr writeModifiedProfile:nil toFile:_path];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:_path]);
}

// A profile missing (or with a false) KEY_DYNAMIC_PROFILE_REWRITABLE is the
// same recoverable condition and must not crash either.
- (void)testNonRewritableProfileDoesNotCrashOrWrite {
    iTermDynamicProfileManager *mgr = [iTermDynamicProfileManager sharedInstance];
    Profile *notRewritable = @{ KEY_GUID: @"guid-1" };
    [mgr writeModifiedProfile:notRewritable toFile:_path];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:_path]);

    Profile *explicitlyFalse = @{ KEY_GUID: @"guid-2",
                                  KEY_DYNAMIC_PROFILE_REWRITABLE: @NO };
    [mgr writeModifiedProfile:explicitlyFalse toFile:_path];
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:_path]);
}

@end
