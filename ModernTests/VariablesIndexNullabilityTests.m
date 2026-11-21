//
//  VariablesIndexNullabilityTests.m
//  ModernTests
//
//  -[iTermVariablesIndex setVariables:forKey:] receives a nil key from
//  iTermVariables when its primary key variable has no value (unit N7 of
//  docs/swift-migration/nullability-triage.md). The key only reaches
//  -[NSMapTable setObject:forKey:], which Apple declares nullable and which
//  ignores a nil key. The header is not visible to Swift, so the claim is
//  pinned here in Objective-C.
//

#import <XCTest/XCTest.h>

#import "iTermVariables.h"
#import "iTermVariablesIndex.h"

@interface VariablesIndexNullabilityTests : XCTestCase
@end

@implementation VariablesIndexNullabilityTests

- (void)testSetVariablesForNilKeyStoresNothing {
    iTermVariables *variables = [iTermVariables globalInstance];
    NSString *key = [NSUUID UUID].UUIDString;
    NSString *const missingKey = nil;

    [[iTermVariablesIndex sharedInstance] setVariables:variables forKey:missingKey];

    XCTAssertNil([[iTermVariablesIndex sharedInstance] variablesForKey:key]);
}

@end
