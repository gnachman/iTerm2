//
//  PrintGuardNullabilityTests.m
//  ModernTests
//
//  -[iTermPrintGuard shouldPrintWithProfile:inWindow:willPrint:] is called by
//  PTYSession with self.profile and its view's window, both nil before the
//  session is set up, under a nonnull claim (unit N9 of
//  docs/swift-migration/nullability-triage.md). The body only reads the
//  profile with objectForKey: and hands the window to iTermWarning, which
//  accepts nil. The header is not visible to Swift, so the claim is pinned
//  here in Objective-C. Before the claim was made nullable, this call was a
//  -Wnonnull warning and a nullability sanitizer report.
//

#import <XCTest/XCTest.h>

#import "iTermPrintGuard.h"

@interface PrintGuardNullabilityTests : XCTestCase
@end

@implementation PrintGuardNullabilityTests

// A nil profile does not disable printing. willPrint is NO so that no
// warning about frequent printing can be shown.
- (void)testNilProfileAndWindowAllowPrinting {
    iTermPrintGuard *printGuard = [[iTermPrintGuard alloc] init];
    XCTAssertTrue([printGuard shouldPrintWithProfile:nil inWindow:nil willPrint:NO]);
}

@end
