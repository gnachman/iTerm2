//
//  ScriptsMenuControllerNullabilityTests.m
//  ModernTests
//
//  -[iTermScriptsMenuController scriptItems] returns the root folder item's
//  children, which are nil when nothing was added to it, under a nonnull
//  claim (unit N4 of docs/swift-migration/nullability-triage.md; the
//  nullability sanitizer reported it while every test host launched). Its
//  only callers pass the result to methods that tolerate nil. The header is
//  not visible to Swift, so the claim is pinned here in Objective-C.
//

#import <XCTest/XCTest.h>

#import "iTermApplicationDelegate.h"
#import "iTermScriptsMenuController.h"

@interface ScriptsMenuControllerNullabilityTests : XCTestCase
@end

@implementation ScriptsMenuControllerNullabilityTests

// Disabling enumeration, as the app does when the scripts folder is too slow
// to walk, makes the empty result deterministic.
- (void)testScriptItemsIsNilWhenNothingIsEnumerated {
    iTermApplicationDelegate *appDelegate = (iTermApplicationDelegate *)[NSApp delegate];
    XCTAssertTrue([appDelegate isKindOfClass:[iTermApplicationDelegate class]]);
    iTermScriptsMenuController *controller = appDelegate.scriptsMenuController;
    XCTAssertNotNil(controller);

    // _disableEnumeration has no accessor; key-value coding reaches the ivar.
    NSString *const key = @"disableEnumeration";
    id saved = [controller valueForKey:key];
    [controller setValue:@YES forKey:key];
    NSArray<iTermScriptItem *> *items = [controller scriptItems];
    [controller setValue:saved forKey:key];

    XCTAssertNil(items);
}

@end
