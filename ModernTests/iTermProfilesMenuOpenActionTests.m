//
//  iTermProfilesMenuOpenActionTests.m
//  ModernTests
//
//  Created by OpenAI on 7/23/26.
//

#import <XCTest/XCTest.h>

#import "iTermController.h"

@interface iTermController (iTermProfilesMenuOpenActionTests)
- (void)openProfileFromProfilesMenuWithGuid:(NSString *)guid action:(SEL)action;
@end

@interface iTermProfilesMenuOpenActionTestController : iTermController
@property(nonatomic, copy) NSString *openedGuid;
@property(nonatomic, assign) SEL openedAction;
@end

@implementation iTermProfilesMenuOpenActionTestController

- (void)newSessionInTabAtIndex:(id)sender {
    self.openedAction = _cmd;
    self.openedGuid = [sender representedObject];
}

- (void)newSessionInWindowAtIndex:(id)sender {
    self.openedAction = _cmd;
    self.openedGuid = [sender representedObject];
}

@end

@interface iTermProfilesMenuOpenActionTests : XCTestCase
@end

@implementation iTermProfilesMenuOpenActionTests

- (void)testProfilesMenuOpensTabByDefault {
    SEL action = [iTermController profilesMenuActionForOpenProfilesInNewWindow:NO
                                                                 modifierFlags:0];
    XCTAssertEqual(action, @selector(newSessionInTabAtIndex:));
}

- (void)testProfilesMenuOpensWindowWhenOptionIsPressed {
    SEL action = [iTermController profilesMenuActionForOpenProfilesInNewWindow:NO
                                                                 modifierFlags:NSEventModifierFlagOption];
    XCTAssertEqual(action, @selector(newSessionInWindowAtIndex:));
}

- (void)testProfilesMenuOpensWindowByDefaultWhenConfigured {
    SEL action = [iTermController profilesMenuActionForOpenProfilesInNewWindow:YES
                                                                 modifierFlags:0];
    XCTAssertEqual(action, @selector(newSessionInWindowAtIndex:));
}

- (void)testProfilesMenuOpensTabWhenConfiguredForWindowAndOptionIsPressed {
    SEL action = [iTermController profilesMenuActionForOpenProfilesInNewWindow:YES
                                                                 modifierFlags:NSEventModifierFlagOption];
    XCTAssertEqual(action, @selector(newSessionInTabAtIndex:));
}

- (void)testOpeningProfilePassesGuidToExistingTabAction {
    NSString *guid = @"profile-guid";
    iTermProfilesMenuOpenActionTestController *controller =
        [[iTermProfilesMenuOpenActionTestController alloc] init];
    [controller openProfileFromProfilesMenuWithGuid:guid
                                            action:@selector(newSessionInTabAtIndex:)];
    XCTAssertEqualObjects(controller.openedGuid, guid);
    XCTAssertEqual(controller.openedAction, @selector(newSessionInTabAtIndex:));
}

- (void)testOpeningProfilePassesGuidToExistingWindowAction {
    NSString *guid = @"profile-guid";
    iTermProfilesMenuOpenActionTestController *controller =
        [[iTermProfilesMenuOpenActionTestController alloc] init];
    [controller openProfileFromProfilesMenuWithGuid:guid
                                            action:@selector(newSessionInWindowAtIndex:)];
    XCTAssertEqualObjects(controller.openedGuid, guid);
    XCTAssertEqual(controller.openedAction, @selector(newSessionInWindowAtIndex:));
}

@end
