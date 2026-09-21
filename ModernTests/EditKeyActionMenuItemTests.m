//
//  EditKeyActionMenuItemTests.m
//  ModernTests
//
//  End-to-end check that opening the key binding editor on a Select Menu Item
//  binding, changing only the keystroke, and clicking OK preserves the menu
//  item. The editor reads the menu item back out of its popup on OK, so a
//  popup that fails to report a programmatically restored selection silently
//  erases the binding's parameter.
//

#import <XCTest/XCTest.h>

#import "iTermEditKeyActionWindowController.h"
#import "iTermKeystroke.h"

// ok: is an IBAction wired up in the xib, so it isn't in the public header.
@interface iTermEditKeyActionWindowController (Testing)
- (IBAction)ok:(id)sender;
@end

@interface EditKeyActionMenuItemTests : XCTestCase
@end

@implementation EditKeyActionMenuItemTests

// Finds a menu item in the app's main menu so the test only runs against a
// menu that really contains the item it binds to.
- (NSMenuItem *)menuItemWithIdentifier:(NSString *)identifier inMenu:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.identifier isEqualToString:identifier]) {
            return item;
        }
        if (item.hasSubmenu) {
            NSMenuItem *found = [self menuItemWithIdentifier:identifier inMenu:item.submenu];
            if (found) {
                return found;
            }
        }
    }
    return nil;
}

- (void)testChangingOnlyTheKeystrokePreservesTheMenuItem {
    NSMenuItem *menuItem = [self menuItemWithIdentifier:@"Edit Tab Title" inMenu:NSApp.mainMenu];
    XCTAssertNotNil(menuItem, @"Test host's main menu lacks Edit Tab Title");

    NSString *parameter = [NSString stringWithFormat:@"%@\n%@", menuItem.title, menuItem.identifier];
    iTermEditKeyActionWindowController *controller =
        [[iTermEditKeyActionWindowController alloc] initWithContext:iTermVariablesSuggestionContextSession
                                                              mode:iTermEditKeyActionWindowControllerModeKeyboardShortcut
                                                       profileType:ProfileTypeTerminal];
    [controller setAction:KEY_ACTION_SELECT_MENU_ITEM
                parameter:parameter
                applyMode:iTermActionApplyModeCurrentSession];
    controller.currentKeystroke = [iTermKeystroke withCharacter:'t'
                                                  modifierFlags:NSEventModifierFlagControl];
    // Loads the window, which populates the menu item popup from the parameter.
    (void)controller.window;

    // The user changes only the keystroke and clicks OK.
    controller.currentKeystroke = [iTermKeystroke withCharacter:'y'
                                                  modifierFlags:NSEventModifierFlagControl];
    [controller ok:nil];

    XCTAssertTrue(controller.ok);
    XCTAssertEqual(controller.action, KEY_ACTION_SELECT_MENU_ITEM);
    XCTAssertEqualObjects(controller.parameterValue, parameter);
}

@end
