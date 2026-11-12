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
#import "NSStringITerm.h"

// ok: is an IBAction wired up in the xib, so it isn't in the public header.
@interface iTermEditKeyActionWindowController (Testing)
- (IBAction)ok:(id)sender;
- (void)loadParameter:(NSString *)parameterValue
               action:(KEY_ACTION)action
            applyMode:(iTermActionApplyMode)applyMode
            secondary:(BOOL)secondary;
- (void)searchableComboView:(id)view didSelectItem:(id)item;
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

// A binding can name an encoding this Mac lacks (imported or synced from
// elsewhere). Saving it without touching the popup must keep that value
// rather than writing -1 or swapping in some other encoding.
- (void)testUnavailableEncodingIsPreservedWhenSaving {
    NSString *parameter = @"987654321";
    XCTAssertFalse([NSString it_isAvailableStringEncoding:parameter.integerValue]);
    iTermEditKeyActionWindowController *controller = [self encodingControllerWithParameter:parameter];
    NSPopUpButton *popup = [controller valueForKey:@"encodingPopup"];
    XCTAssertNotNil(popup.selectedItem, @"Something must be selected for an unavailable encoding");

    [controller ok:nil];

    XCTAssertTrue(controller.ok);
    XCTAssertEqualObjects(controller.parameterValue, parameter);
}

// Loading a different binding into the same editor must drop the placeholder
// for an unavailable encoding.
- (void)testUnavailablePlaceholderIsRemovedWhenReloaded {
    iTermEditKeyActionWindowController *controller = [self encodingControllerWithParameter:@"987654321"];
    NSPopUpButton *popup = [controller valueForKey:@"encodingPopup"];
    const NSInteger countWithPlaceholder = popup.numberOfItems;

    [controller setAction:KEY_ACTION_SET_CHARACTER_ENCODING
                parameter:[@(NSUTF8StringEncoding) stringValue]
                applyMode:iTermActionApplyModeCurrentSession];
    [controller loadParameter:controller.parameterValue
                       action:controller.action
                    applyMode:iTermActionApplyModeCurrentSession
                    secondary:NO];

    XCTAssertEqual(popup.numberOfItems, countWithPlaceholder - 1);
    XCTAssertEqual(popup.selectedTag, (NSInteger)NSUTF8StringEncoding);
}

- (void)testDisplayNameForUnavailableEncodingIsNotBlank {
    for (NSString *parameter in @[ @"", @"987654321" ]) {
        iTermKeyBindingAction *action =
            [iTermKeyBindingAction withAction:KEY_ACTION_SET_CHARACTER_ENCODING
                                    parameter:parameter
                                     escaping:iTermSendTextEscapingNone
                                    applyMode:iTermActionApplyModeCurrentSession];
        NSString *name = action.displayName;
        XCTAssertGreaterThan(name.length, 0);
        XCTAssertFalse([name containsString:@"“”"],
                       @"Display name should not show an empty encoding name: %@", name);
    }
}

// Changing a sequence row's action to Set Character Encoding must start it at
// UTF-8, not inherit the popup state left by the previously selected row, which
// here is the unavailable-encoding placeholder.
- (void)testNewSequenceRowDoesNotInheritPreviousRowsEncoding {
    iTermKeyBindingAction *first =
        [iTermKeyBindingAction withAction:KEY_ACTION_SET_CHARACTER_ENCODING
                                parameter:@"987654321"
                                 escaping:iTermSendTextEscapingNone
                                applyMode:iTermActionApplyModeCurrentSession];
    iTermKeyBindingAction *second =
        [iTermKeyBindingAction withAction:KEY_ACTION_TEXT
                                parameter:@"hello"
                                 escaping:iTermSendTextEscapingNone
                                applyMode:iTermActionApplyModeCurrentSession];
    NSString *sequence = [NSString parameterForKeyBindingActionSequence:@[ first, second ]];

    iTermEditKeyActionWindowController *controller =
        [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession
                                                              mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut
                                                       profileType:ProfileTypeTerminal];
    [controller setAction:KEY_ACTION_SEQUENCE
                parameter:sequence
                applyMode:iTermActionApplyModeCurrentSession];
    (void)controller.window;

    id sequenceController = [controller valueForKey:@"sequenceTableViewController"];
    NSTableView *tableView = [sequenceController valueForKey:@"tableView"];
    XCTAssertEqual(tableView.numberOfRows, 2);

    // Selecting row 0 loads the placeholder into the popup.
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    NSPopUpButton *popup = [controller valueForKey:@"encodingPopup"];
    XCTAssertEqualObjects(popup.selectedItem.representedObject, @"987654321");

    // Row 1 is Send Text, so the popup is hidden and keeps its selection.
    [tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];

    // Change row 1's action to Set Character Encoding.
    NSPopUpButton *secondaryComboView = [controller valueForKey:@"secondaryComboView"];
    XCTAssertTrue([secondaryComboView selectItemWithTag:KEY_ACTION_SET_CHARACTER_ENCODING]);
    [controller searchableComboView:secondaryComboView didSelectItem:nil];

    NSArray<iTermKeyBindingAction *> *actions = [sequenceController valueForKey:@"actions"];
    XCTAssertEqual(actions[1].keyAction, KEY_ACTION_SET_CHARACTER_ENCODING);
    XCTAssertEqualObjects(actions[1].parameter, [@(NSUTF8StringEncoding) stringValue]);
    // Row 0 is untouched.
    XCTAssertEqualObjects(actions[0].parameter, @"987654321");
}

@end
