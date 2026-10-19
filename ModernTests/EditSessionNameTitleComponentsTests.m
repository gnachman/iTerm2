//
//  EditSessionNameTitleComponentsTests.m
//  ModernTests
//
//  QA finding F-492: with a profile whose Title is “AI-generated name” and no AI title, a session
//  name set with Session > Edit Session… did not reach the tab label when the program had set an
//  icon name with OSC 1. The AI-empty fallback prefers the icon name over the session name, and
//  editing the name left the title components alone for an AI profile, so the deliberate name
//  never out-ranked the program's. Editing the name must turn on TemporarySessionName, as a
//  manual rename or Set Title trigger does.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "ProfilesGeneralPreferencesViewController.h"
#import "iTermSessionTitleBuiltInFunction.h"

@interface EditSessionNameTitleComponentsTests : XCTestCase
@end

@implementation EditSessionNameTitleComponentsTests

- (NSUInteger)componentsAfterEditingName:(NSUInteger)components {
    return [ProfilesGeneralPreferencesViewController titleComponentsShowingSessionName:components];
}

- (NSString *)tabTitleWithComponents:(NSUInteger)components
                         sessionName:(NSString *)sessionName
                            iconName:(NSString *)iconName
                             aiTitle:(NSString *)aiTitle {
    return [iTermSessionTitleBuiltInFunction titleForSessionName:sessionName
                                                     profileName:@"Prof"
                                                             job:@""
                                                     commandLine:@""
                                                             pwd:@""
                                                             tty:@""
                                                            user:@""
                                                            host:@""
                                                         aiTitle:aiTitle
                                                   homeDirectory:nil
                                                        tmuxPane:nil
                                                        iconName:iconName
                                                      windowName:nil
                                                  tmuxWindowName:nil
                                                 tmuxWindowTitle:nil
                                                            rows:@24
                                                         columns:@80
                                                      components:components
                                                   isWindowTitle:NO];
}

- (void)testEditedSessionNameOutranksIconNameForAIProfile {
    const NSUInteger components = [self componentsAfterEditingName:iTermTitleComponentsAI];
    XCTAssertEqualObjects([self tabTitleWithComponents:components
                                           sessionName:@"Pinned"
                                              iconName:@"IconA"
                                               aiTitle:nil],
                          @"Pinned");
}

- (void)testEditedSessionNameOutranksAITitle {
    const NSUInteger components = [self componentsAfterEditingName:iTermTitleComponentsAI];
    XCTAssertEqualObjects([self tabTitleWithComponents:components
                                           sessionName:@"Pinned"
                                              iconName:nil
                                               aiTitle:@"Model guess"],
                          @"Pinned");
}

- (void)testAIProfileKeepsAIComponentAndDoesNotAddSessionName {
    const NSUInteger components = [self componentsAfterEditingName:iTermTitleComponentsAI | iTermTitleComponentsJob];
    XCTAssertEqual(components, iTermTitleComponentsAI | iTermTitleComponentsJob | iTermTitleComponentsTemporarySessionName);
}

- (void)testNonAIProfilesAreUnchanged {
    XCTAssertEqual([self componentsAfterEditingName:iTermTitleComponentsSessionName],
                   iTermTitleComponentsSessionName);
    XCTAssertEqual([self componentsAfterEditingName:iTermTitleComponentsJob],
                   iTermTitleComponentsJob | iTermTitleComponentsSessionName);
    XCTAssertEqual([self componentsAfterEditingName:iTermTitleComponentsProfileName | iTermTitleComponentsJob],
                   iTermTitleComponentsProfileAndSessionName | iTermTitleComponentsJob);
    XCTAssertEqual([self componentsAfterEditingName:iTermTitleComponentsCustom],
                   iTermTitleComponentsCustom);
    XCTAssertEqual([self componentsAfterEditingName:iTermTitleComponentsProfileAndSessionName],
                   iTermTitleComponentsProfileAndSessionName);
}

@end
