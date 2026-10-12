//
//  ContextMenuProviderTests.m
//  ModernTests
//
//  Tests for the submenu and visible_when attributes of API-registered
//  context menu providers.
//

#import <XCTest/XCTest.h>

#import "Api.pbobjc.h"
#import "iTermAPIHelper.h"
#import "iTermObject.h"
#import "iTermTextViewContextMenuHelper.h"
#import "iTermVariableScope.h"
#import "iTermVariables.h"

@interface ContextMenuProviderTests : XCTestCase<iTermObject>
@end

@implementation ContextMenuProviderTests {
    iTermVariableScope *_scope;
}

- (void)setUp {
    [super setUp];
    _scope = [[iTermVariableScope alloc] init];
    iTermVariables *variables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                                  owner:self];
    [_scope addVariables:variables toScopeNamed:nil];

    // Mirror how a session exposes user-writable variables.
    iTermVariables *userVariables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                                      owner:self];
    userVariables.isUserWritable = YES;
    [_scope setValue:userVariables forVariableNamed:@"user"];
}

- (iTermBuiltInFunctions *)objectMethodRegistry {
    return nil;
}

- (iTermVariableScope *)objectScope {
    return nil;
}

- (ITMRPCRegistrationRequest *)requestNamed:(NSString *)displayName
                                    submenu:(NSString *)submenu
                                visibleWhen:(NSString *)visibleWhen {
    ITMRPCRegistrationRequest *req = [[ITMRPCRegistrationRequest alloc] init];
    req.name = @"handler";
    req.role = ITMRPCRegistrationRequest_Role_ContextMenu;
    req.contextMenuAttributes.displayName = displayName;
    req.contextMenuAttributes.uniqueIdentifier = [@"com.example." stringByAppendingString:displayName];
    if (submenu) {
        req.contextMenuAttributes.submenu = submenu;
    }
    if (visibleWhen) {
        req.contextMenuAttributes.visibleWhen = visibleWhen;
    }
    return req;
}

- (NSArray<NSString *> *)titlesForRequests:(NSArray<ITMRPCRegistrationRequest *> *)reqs {
    NSArray<NSMenuItem *> *items = [iTermTextViewContextMenuHelper menuItemsForAPIRegistrationRequests:reqs
                                                                                                 scope:_scope
                                                                                                target:nil
                                                                                                action:nil];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSMenuItem *item in items) {
        [titles addObject:item.title];
    }
    return titles;
}

#pragma mark - Registration

- (void)testRegistrationAcceptsVariableExpression {
    ITMRPCRegistrationRequest *req = [self requestNamed:@"A" submenu:nil visibleWhen:@"user.bound == 1"];
    NSError *error = nil;
    XCTAssertTrue([req it_rpcRegistrationRequestValidWithError:&error], @"%@", error);
}

- (void)testRegistrationRejectsFunctionCall {
    ITMRPCRegistrationRequest *req = [self requestNamed:@"A" submenu:nil visibleWhen:@"foo(x: 1)"];
    NSError *error = nil;
    XCTAssertFalse([req it_rpcRegistrationRequestValidWithError:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"may not call functions"]);
}

- (void)testRegistrationRejectsSyntaxError {
    ITMRPCRegistrationRequest *req = [self requestNamed:@"A" submenu:nil visibleWhen:@"user.bound =="];
    NSError *error = nil;
    XCTAssertFalse([req it_rpcRegistrationRequestValidWithError:&error]);
}

#pragma mark - Visibility

- (void)testItemWithoutVisibleWhenIsAlwaysShown {
    NSArray *reqs = @[ [self requestNamed:@"A" submenu:nil visibleWhen:nil] ];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"A" ]);
}

- (void)testVisibleWhenFollowsVariable {
    NSArray *reqs = @[ [self requestNamed:@"A" submenu:nil visibleWhen:@"user.bound"] ];
    [_scope setValue:@YES forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"A" ]);
    [_scope setValue:@NO forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[]);
}

// User variables set from the shell (iterm2_set_user_var / SetUserVar) are
// always strings. A bare string is not truthy, so the item stays hidden and
// the script must compare explicitly.
- (void)testStringValuedVariableIsNotTruthy {
    NSArray *bare = @[ [self requestNamed:@"A" submenu:nil visibleWhen:@"user.bound"] ];
    NSArray *compared = @[ [self requestNamed:@"A" submenu:nil visibleWhen:@"user.bound == \"1\""] ];
    [_scope setValue:@"1" forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:bare], @[]);
    XCTAssertEqualObjects([self titlesForRequests:compared], @[ @"A" ]);
}

// Comparing with == 1 works whether the variable came from Python (a
// boolean) or from the shell (a string), since == converts numeric strings.
- (void)testEqualsOneMatchesBooleanAndNumericString {
    NSArray *reqs = @[ [self requestNamed:@"A" submenu:nil visibleWhen:@"user.bound == 1"] ];
    [_scope setValue:@YES forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"A" ]);
    [_scope setValue:@"1" forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"A" ]);
    [_scope setValue:@NO forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[]);
    [_scope setValue:@"0" forVariableNamed:@"user.bound"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[]);
}

- (void)testUndefinedVariableHidesItem {
    NSArray *reqs = @[ [self requestNamed:@"A" submenu:nil visibleWhen:@"user.neverSet"] ];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[]);
}

- (void)testComparisonExpression {
    NSArray *reqs = @[ [self requestNamed:@"A" submenu:nil visibleWhen:@"user.provider == \"codex\""] ];
    [_scope setValue:@"codex" forVariableNamed:@"user.provider"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"A" ]);
    [_scope setValue:@"claude" forVariableNamed:@"user.provider"];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[]);
}

#pragma mark - Submenus

- (void)testItemsSharingSubmenuAreGrouped {
    NSArray *reqs = @[ [self requestNamed:@"Edit" submenu:@"EzBoot" visibleWhen:nil],
                       [self requestNamed:@"Plain" submenu:nil visibleWhen:nil],
                       [self requestNamed:@"Restart" submenu:@"EzBoot" visibleWhen:nil] ];
    NSArray<NSMenuItem *> *items = [iTermTextViewContextMenuHelper menuItemsForAPIRegistrationRequests:reqs
                                                                                                 scope:_scope
                                                                                                target:nil
                                                                                                action:nil];
    XCTAssertEqual(items.count, 2);
    XCTAssertEqualObjects(items[0].title, @"EzBoot");
    XCTAssertEqualObjects(items[1].title, @"Plain");
    XCTAssertNil(items[1].submenu);
    NSMutableArray<NSString *> *children = [NSMutableArray array];
    for (NSMenuItem *child in items[0].submenu.itemArray) {
        [children addObject:child.title];
    }
    XCTAssertEqualObjects(children, (@[ @"Edit", @"Restart" ]));
}

- (void)testSubmenuWithNoVisibleItemsIsOmitted {
    NSArray *reqs = @[ [self requestNamed:@"Edit" submenu:@"EzBoot" visibleWhen:@"user.bound"],
                       [self requestNamed:@"Plain" submenu:nil visibleWhen:nil] ];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"Plain" ]);
}

- (void)testSubmenuWithOneVisibleItemIsKept {
    NSArray *reqs = @[ [self requestNamed:@"Edit" submenu:@"EzBoot" visibleWhen:nil] ];
    XCTAssertEqualObjects([self titlesForRequests:reqs], @[ @"EzBoot" ]);
}

@end
