//
//  PointerPreferencesEnabledStateTests.m
//  ModernTests
//
//  “…even to views like Search or Composer” only applies with Focus follows mouse on, so it must
//  be disabled whenever that setting is off. Its enabled-state rule was attached after the control
//  was defined, so the first update ran without it and the checkbox stayed enabled until Focus
//  follows mouse was toggled (QA finding F-417).
//
//  The Quick Look hover settings only matter when hovering is on, so they are disabled when the
//  hover mode is Off, and the close delay field is disabled while “Never” is checked.
//

#import <XCTest/XCTest.h>

#import "iTermPreferences.h"
#import "iTermUserDefaults.h"
#import "PointerPreferencesViewController.h"

@interface PointerPreferencesEnabledStateTests : XCTestCase
@end

@implementation PointerPreferencesEnabledStateTests {
    id _savedFocusFollowsMouse;
    id _savedIncludingSubviews;
    id _savedHoverMode;
    id _savedAutoCloseDelay;
    id _savedUsesBrowserEngine;
}

- (void)setUp {
    [super setUp];
    // Read the stored values, not iTermPreferences, which fills in defaults, so tearDown can
    // remove a key that was unset.
    _savedFocusFollowsMouse = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyFocusFollowsMouse];
    _savedIncludingSubviews = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyFocusFollowsMouseIncludingSubviews];
    _savedHoverMode = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyQuickLookHoverMode];
    _savedAutoCloseDelay = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];
    _savedUsesBrowserEngine = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyQuickLookUsesBrowserEngine];
}

- (void)tearDown {
    [iTermPreferences setObject:_savedFocusFollowsMouse forKey:kPreferenceKeyFocusFollowsMouse];
    [iTermPreferences setObject:_savedIncludingSubviews forKey:kPreferenceKeyFocusFollowsMouseIncludingSubviews];
    [iTermPreferences setObject:_savedHoverMode forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setObject:_savedAutoCloseDelay forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];
    [iTermPreferences setObject:_savedUsesBrowserEngine forKey:kPreferenceKeyQuickLookUsesBrowserEngine];
    [super tearDown];
}

// Builds the controller with stand-in controls for its outlets and runs awakeFromNib, as loading
// the Settings window does.
- (PointerPreferencesViewController *)awakenedController {
    PointerPreferencesViewController *vc = [[PointerPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    NSArray<NSString *> *checkboxes = @[ @"_cmdSelection",
                                         @"_controlLeftClickActsLikeRightClick",
                                         @"_rightClickActsLikeRightClick",
                                         @"_optionClickMovesCursor",
                                         @"_threeFingerEmulatesMiddle",
                                         @"_focusFollowsMouse",
                                         @"_focusFollowsMouseIncludingSubviews",
                                         @"_focusOnRightOrMiddleClick",
                                         @"_reportHorizontalScrollEvents",
                                         @"_quickLookUsesBrowserEngine",
                                         @"_quickLookHoverNeverClose" ];
    for (NSString *outlet in checkboxes) {
        NSButton *button = [NSButton checkboxWithTitle:outlet target:nil action:nil];
        [vc setValue:button forKey:outlet];
    }
    NSArray<NSString *> *textFields = @[ @"_quickLookHoverDelay",
                                         @"_quickLookHoverAutoCloseDelay",
                                         @"_quickLookHoverDomainAllowlist" ];
    for (NSString *outlet in textFields) {
        [vc setValue:[NSTextField textFieldWithString:@""] forKey:outlet];
    }
    [vc setValue:[NSTextField labelWithString:@""] forKey:@"_quickLookPluginNote"];

    NSPopUpButton *mode = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSArray<NSString *> *titles = @[ @"Off", @"Hover", @"⌘ + Hover" ];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        [mode addItemWithTitle:titles[i]];
        mode.lastItem.tag = i;
    }
    [vc setValue:mode forKey:@"_quickLookHoverMode"];

    [vc awakeFromNib];
    return vc;
}

// Returns the “including subviews” checkbox.
- (NSButton *)includingSubviewsCheckboxAfterAwakening {
    return [[self awakenedController] valueForKey:@"_focusFollowsMouseIncludingSubviews"];
}

- (NSArray<NSControl *> *)hoverControlsOf:(PointerPreferencesViewController *)vc {
    return @[ [vc valueForKey:@"_quickLookHoverDelay"],
              [vc valueForKey:@"_quickLookHoverAutoCloseDelay"],
              [vc valueForKey:@"_quickLookHoverNeverClose"],
              [vc valueForKey:@"_quickLookHoverDomainAllowlist"] ];
}

- (void)testIncludingSubviewsStartsDisabledWhenFocusFollowsMouseIsOff {
    [iTermPreferences setBool:NO forKey:kPreferenceKeyFocusFollowsMouse];
    [iTermPreferences setBool:YES forKey:kPreferenceKeyFocusFollowsMouseIncludingSubviews];

    XCTAssertFalse([self includingSubviewsCheckboxAfterAwakening].enabled);
}

- (void)testIncludingSubviewsStartsEnabledWhenFocusFollowsMouseIsOn {
    [iTermPreferences setBool:YES forKey:kPreferenceKeyFocusFollowsMouse];
    [iTermPreferences setBool:YES forKey:kPreferenceKeyFocusFollowsMouseIncludingSubviews];

    XCTAssertTrue([self includingSubviewsCheckboxAfterAwakening].enabled);
}

- (void)testQuickLookHoverFieldsDisabledWhenOff {
    [iTermPreferences setInt:0 forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setDouble:1.5 forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];

    PointerPreferencesViewController *vc = [self awakenedController];
    for (NSControl *control in [self hoverControlsOf:vc]) {
        XCTAssertFalse(control.enabled, @"%@ should be disabled when hover mode is Off", control);
    }
}

- (void)testQuickLookHoverFieldsEnabledInHoverMode {
    [iTermPreferences setInt:1 forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setDouble:1.5 forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];

    PointerPreferencesViewController *vc = [self awakenedController];
    for (NSControl *control in [self hoverControlsOf:vc]) {
        XCTAssertTrue(control.enabled, @"%@ should be enabled when hover mode is Hover", control);
    }
    NSButton *never = [vc valueForKey:@"_quickLookHoverNeverClose"];
    XCTAssertEqual(never.state, NSControlStateValueOff);
}

- (void)testAutoCloseFieldDisabledWhenNeverIsChecked {
    [iTermPreferences setInt:1 forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setDouble:0 forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];

    PointerPreferencesViewController *vc = [self awakenedController];
    NSButton *never = [vc valueForKey:@"_quickLookHoverNeverClose"];
    NSTextField *autoClose = [vc valueForKey:@"_quickLookHoverAutoCloseDelay"];
    XCTAssertEqual(never.state, NSControlStateValueOn);
    XCTAssertTrue(never.enabled);
    XCTAssertFalse(autoClose.enabled);
}

- (void)testNeverStoresZeroAndUncheckingRestoresDefault {
    [iTermPreferences setInt:1 forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setDouble:4 forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];

    PointerPreferencesViewController *vc = [self awakenedController];
    NSButton *never = [vc valueForKey:@"_quickLookHoverNeverClose"];
    NSTextField *autoClose = [vc valueForKey:@"_quickLookHoverAutoCloseDelay"];

    never.state = NSControlStateValueOn;
    [vc quickLookHoverNeverCloseChanged:never];
    XCTAssertEqual([iTermPreferences doubleForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay], 0);
    XCTAssertFalse(autoClose.enabled);

    never.state = NSControlStateValueOff;
    [vc quickLookHoverNeverCloseChanged:never];
    XCTAssertEqual([iTermPreferences doubleForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay], 1.5);
    XCTAssertEqualObjects(autoClose.stringValue,
                          [PointerPreferencesViewController quickLookStringFromSeconds:1.5 locale:[NSLocale currentLocale]]);
    XCTAssertTrue(autoClose.enabled);
}

// In comma-decimal locales “0,75” used to parse as 0, which also checked “Never”.
- (void)testSecondsParseWithTheLocaleDecimalSeparator {
    NSLocale *german = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    NSLocale *american = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    XCTAssertEqualObjects([PointerPreferencesViewController quickLookSecondsFromString:@"0,75" locale:german], @0.75);
    XCTAssertEqualObjects([PointerPreferencesViewController quickLookSecondsFromString:@"0.75" locale:german], @0.75,
                          @"a period is accepted in every locale");
    XCTAssertEqualObjects([PointerPreferencesViewController quickLookSecondsFromString:@" 2 " locale:german], @2);
    XCTAssertEqualObjects([PointerPreferencesViewController quickLookSecondsFromString:@"1.5" locale:american], @1.5);
    XCTAssertNil([PointerPreferencesViewController quickLookSecondsFromString:@"" locale:german]);
    XCTAssertNil([PointerPreferencesViewController quickLookSecondsFromString:@"abc" locale:american]);

    XCTAssertEqualObjects([PointerPreferencesViewController quickLookStringFromSeconds:0.75 locale:german], @"0,75");
    XCTAssertEqualObjects([PointerPreferencesViewController quickLookStringFromSeconds:1.5 locale:american], @"1.5");
    XCTAssertEqualObjects([PointerPreferencesViewController quickLookStringFromSeconds:2 locale:american], @"2");
}

- (void)testTypingSecondsStoresTheParsedValue {
    [iTermPreferences setInt:1 forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setDouble:1.5 forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];

    PointerPreferencesViewController *vc = [self awakenedController];
    NSTextField *autoClose = [vc valueForKey:@"_quickLookHoverAutoCloseDelay"];
    autoClose.stringValue = [PointerPreferencesViewController quickLookStringFromSeconds:0.25 locale:[NSLocale currentLocale]];
    [vc settingChanged:autoClose];
    XCTAssertEqual([iTermPreferences doubleForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay], 0.25);

    autoClose.stringValue = @"";
    [vc settingChanged:autoClose];
    XCTAssertEqual([iTermPreferences doubleForKey:kPreferenceKeyQuickLookHoverAutoCloseDelay], 0.25,
                   @"an empty field mid-edit does not store 0");
}

- (void)testPluginNoteHiddenWhileBrowserEngineIsOff {
    [iTermPreferences setBool:NO forKey:kPreferenceKeyQuickLookUsesBrowserEngine];

    PointerPreferencesViewController *vc = [self awakenedController];
    NSTextField *note = [vc valueForKey:@"_quickLookPluginNote"];
    XCTAssertTrue(note.hidden);
}

- (void)testChangingHoverModeUpdatesEnabledState {
    [iTermPreferences setInt:0 forKey:kPreferenceKeyQuickLookHoverMode];
    [iTermPreferences setDouble:1.5 forKey:kPreferenceKeyQuickLookHoverAutoCloseDelay];

    PointerPreferencesViewController *vc = [self awakenedController];
    NSPopUpButton *mode = [vc valueForKey:@"_quickLookHoverMode"];
    [mode selectItemWithTag:2];
    [vc settingChanged:mode];

    XCTAssertEqual([iTermPreferences intForKey:kPreferenceKeyQuickLookHoverMode], 2);
    for (NSControl *control in [self hoverControlsOf:vc]) {
        XCTAssertTrue(control.enabled, @"%@ should be enabled after choosing ⌘ + Hover", control);
    }
}

@end
