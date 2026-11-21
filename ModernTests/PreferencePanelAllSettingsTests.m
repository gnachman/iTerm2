//
//  PreferencePanelAllSettingsTests.m
//  ModernTests
//
//  -[PreferencePanel allSettings] is declared nonnull. Before the settings
//  window's nib loads, _tabView is nil, so the fold over its tab view items
//  messaged nil and returned nil (the nullability sanitizer reported it at
//  PreferencePanel.m). Swift callers such as SettingPopupView and
//  ProfileBoolSettingCatalog already saw an empty array there, because the
//  bridge turns a nil NSArray into []. This test is in Objective-C because
//  only Objective-C can observe the nil.
//

#import <XCTest/XCTest.h>

#import "PreferencePanel.h"
#import "ProfileModel.h"

@interface PreferencePanelAllSettingsTests : XCTestCase
@end

@implementation PreferencePanelAllSettingsTests

- (void)testAllSettingsBeforeTheWindowLoadsIsAnEmptyArray {
    // A fresh panel, not the shared one: another test may already have loaded
    // the shared panel's window.
    PreferencePanel *panel = [[PreferencePanel alloc] initWithProfileModel:[ProfileModel sharedInstance]
                                                    editCurrentSessionMode:NO];
    XCTAssertFalse(panel.isWindowLoaded, @"Precondition: the nib has not loaded");

    NSArray<iTermSetting *> *settings = [panel allSettings];

    XCTAssertNotNil(settings);
    XCTAssertEqual(settings.count, 0u);
    XCTAssertFalse(panel.isWindowLoaded, @"allSettings must not load the window");
}

@end
