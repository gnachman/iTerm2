//
//  PointerPreferencesEnabledStateTests.m
//  ModernTests
//
//  “…even to views like Search or Composer” only applies with Focus follows mouse on, so it must
//  be disabled whenever that setting is off. Its enabled-state rule was attached after the control
//  was defined, so the first update ran without it and the checkbox stayed enabled until Focus
//  follows mouse was toggled (QA finding F-417).
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
}

- (void)setUp {
    [super setUp];
    // Read the stored values, not iTermPreferences, which fills in defaults, so tearDown can
    // remove a key that was unset.
    _savedFocusFollowsMouse = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyFocusFollowsMouse];
    _savedIncludingSubviews = [[iTermUserDefaults userDefaults] objectForKey:kPreferenceKeyFocusFollowsMouseIncludingSubviews];
}

- (void)tearDown {
    [iTermPreferences setObject:_savedFocusFollowsMouse forKey:kPreferenceKeyFocusFollowsMouse];
    [iTermPreferences setObject:_savedIncludingSubviews forKey:kPreferenceKeyFocusFollowsMouseIncludingSubviews];
    [super tearDown];
}

// Builds the controller with stand-in checkboxes for its outlets and runs awakeFromNib, as
// loading the Settings window does. Returns the “including subviews” checkbox.
- (NSButton *)includingSubviewsCheckboxAfterAwakening {
    PointerPreferencesViewController *vc = [[PointerPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    NSArray<NSString *> *outlets = @[ @"_cmdSelection",
                                      @"_controlLeftClickActsLikeRightClick",
                                      @"_rightClickActsLikeRightClick",
                                      @"_optionClickMovesCursor",
                                      @"_threeFingerEmulatesMiddle",
                                      @"_focusFollowsMouse",
                                      @"_focusFollowsMouseIncludingSubviews",
                                      @"_focusOnRightOrMiddleClick",
                                      @"_reportHorizontalScrollEvents" ];
    for (NSString *outlet in outlets) {
        NSButton *button = [NSButton checkboxWithTitle:outlet target:nil action:nil];
        [vc setValue:button forKey:outlet];
    }
    [vc awakeFromNib];
    return [vc valueForKey:@"_focusFollowsMouseIncludingSubviews"];
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

@end
