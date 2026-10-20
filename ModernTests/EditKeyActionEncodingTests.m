//
//  EditKeyActionEncodingTests.m
//  ModernTests
//
//  End-to-end check that the key binding editor supports the new "Set
//  Character Encoding…" action: the encoding popup is populated when the
//  binding is edited, and the selected encoding round-trips through the
//  binding's parameter when the user saves it. Without the popup wiring, the
//  parameter is silently lost the same way a menu item binding could be.
//

#import <XCTest/XCTest.h>

#import "iTermEditKeyActionWindowController.h"
#import "iTermKeyBindingAction.h"
#import "iTermKeystroke.h"

// ok: is an IBAction wired up in the xib, so it isn't in the public header.
@interface iTermEditKeyActionWindowController (Testing)
- (IBAction)ok:(id)sender;
@end

@interface EditKeyActionEncodingTests : XCTestCase
@end

@implementation EditKeyActionEncodingTests

// Sets an encoding binding whose parameter is the given NSStringEncoding,
// loads its editor window (which populates the encoding popup), and hands the
// controller back with a real keystroke so calling ok: succeeds.
- (iTermEditKeyActionWindowController *)encodingControllerWithParameter:(NSString *)parameter {
    iTermEditKeyActionWindowController *controller =
        [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession
                                                              mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut
                                                       profileType:ProfileTypeTerminal];
    [controller setAction:KEY_ACTION_SET_CHARACTER_ENCODING
                parameter:parameter
                applyMode:iTermActionApplyModeCurrentSession];
    controller.currentKeystroke = [iTermKeystroke withCharacter:'e'
                                                  modifierFlags:NSEventModifierFlagControl];
    // Loads the window, which populates the encoding popup from the parameter.
    (void)controller.window;
    return controller;
}

- (void)testDisplayNameShowsTheEncodingName {
    iTermKeyBindingAction *action =
        [iTermKeyBindingAction withAction:KEY_ACTION_SET_CHARACTER_ENCODING
                                parameter:[@(NSUTF8StringEncoding) stringValue]
                                 escaping:iTermSendTextEscapingNone
                                applyMode:iTermActionApplyModeCurrentSession];
    XCTAssertNotNil(action, @"The encoding action must be constructible");
    NSString *name = action.displayName;
    XCTAssertNotNil(name);
    XCTAssertTrue([name containsString:@"UTF-8"],
                  @"Expected the encoding name in the display name: %@", name);
}

- (void)testEncodingParameterRoundTripsThroughEditor {
    NSString *parameter = [@(NSUTF8StringEncoding) stringValue];
    iTermEditKeyActionWindowController *controller = [self encodingControllerWithParameter:parameter];

    XCTAssertEqual(controller.action, KEY_ACTION_SET_CHARACTER_ENCODING);
    XCTAssertEqualObjects(controller.parameterValue, parameter,
                          @"The encoding popup must restore the stored encoding");

    // The user changes only the keystroke and clicks OK.
    controller.currentKeystroke = [iTermKeystroke withCharacter:'y'
                                                  modifierFlags:NSEventModifierFlagControl];
    [controller ok:nil];

    XCTAssertTrue(controller.ok);
    XCTAssertEqual(controller.action, KEY_ACTION_SET_CHARACTER_ENCODING);
    XCTAssertEqualObjects(controller.parameterValue, parameter,
                          @"Changing the keystroke must not disturb the encoding");
}

- (void)testSelectingAnEncodingUpdatesTheParameter {
    iTermEditKeyActionWindowController *controller =
        [self encodingControllerWithParameter:[@(NSUTF8StringEncoding) stringValue]];
    NSPopUpButton *popup = [controller valueForKey:@"encodingPopup"];
    XCTAssertNotNil(popup, @"The encoding popup must be populated by the time the window loads");
    XCTAssertGreaterThan(popup.numberOfItems, 0);
    XCTAssertEqual(popup.selectedTag, (NSInteger)NSUTF8StringEncoding,
                   @"The popup should open on the binding's stored encoding");

    NSInteger target = -1;
    for (NSMenuItem *item in popup.itemArray) {
        if (item.tag != (NSInteger)NSUTF8StringEncoding) {
            target = item.tag;
            break;
        }
    }
    XCTAssertTrue(target > 0, @"Expected at least two distinct encodings");

    [popup selectItemWithTag:target];
    [controller ok:nil];

    XCTAssertTrue(controller.ok);
    XCTAssertEqualObjects(controller.parameterValue, [@(target) stringValue],
                          @"The saved parameter must reflect the popup selection");
}

@end