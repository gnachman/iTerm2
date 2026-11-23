// In Objective-C so the tests can call private methods of
// ProfilesColorsPreferencesViewController and ProfileModel.

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "NSObject+iTerm.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "iTermColorPresets.h"
#import "iTermProfilePreferences.h"

@interface ProfileModel (ColorPresetPreviewTests)
- (instancetype)initWithName:(NSString *)name;
@end

@interface ProfilesColorsPreferencesViewController (ColorPresetPreviewTests) <NSMenuDelegate>
- (void)popupButtonWillPopUp:(id)sender;
- (void)loadColorPresetWithName:(NSString *)presetName prompt:(BOOL)prompt;
@end

@interface ColorPresetPreviewTests : XCTestCase <iTermProfilePreferencesBaseViewControllerDelegate>
@end

@implementation ColorPresetPreviewTests {
    ProfileModel *_model;
    NSString *_guid;
    ProfilesColorsPreferencesViewController *_controller;
    NSMenu *_menu;
    // Keys passed to willSetObjectWithKey:.
    NSMutableArray<NSString *> *_announcedKeys;
}

- (void)setUp {
    [super setUp];
    // Not backed by user defaults.
    _model = [[ProfileModel alloc] initWithName:@"ColorPresetPreviewTests"];
    _guid = [ProfileModel freshGuid];
    [_model addBookmark:@{ KEY_GUID: _guid }];
    [self loadPreset:@"Solarized Dark" into:0];
    // Without the nib, _mode is nil (selectedTag == 0, i.e. light mode).
    _controller = [[ProfilesColorsPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    _controller.delegate = self;
    _menu = [[NSMenu alloc] initWithTitle:@"Color Presets"];
    _announcedKeys = [NSMutableArray array];
}

// Tests compare whole profiles, so fill in the colors first. Restoring a color the profile lacked
// writes its default.
- (void)loadPreset:(NSString *)name into:(iTermColorPresetMode)destination {
    XCTAssertTrue([_model addColorPresetNamed:name
                                    toProfile:self.profilePreferencesCurrentProfile
                                         from:0
                                           to:destination]);
}

- (void)useSeparateColors {
    [self loadPreset:@"Solarized Dark" into:iTermColorPresetModeLight];
    [_model setObject:@YES
               forKey:KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE
           inBookmark:self.profilePreferencesCurrentProfile];
}

// The same call the preview timer makes.
- (void)previewPreset:(NSString *)name {
    [_controller loadColorPresetWithName:name prompt:NO];
}

- (NSUInteger (^)(void))reloadCounter {
    __block NSUInteger reloads = 0;
    NSThread *thread = NSThread.currentThread;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    id observer = [center addObserverForName:kReloadAllProfiles object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (NSThread.currentThread == thread) {
            reloads++;
        }
    }];
    [self addTeardownBlock:^{ [center removeObserver:observer]; }];
    return ^NSUInteger { return reloads; };
}

- (NSArray<NSString *> *)keysThatDifferBetween:(Profile *)a and:(Profile *)b {
    NSMutableSet<NSString *> *keys = [NSMutableSet setWithArray:a.allKeys];
    [keys addObjectsFromArray:b.allKeys];
    return [keys.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) {
        return ![NSObject object:a[key] isEqualToObject:b[key]];
    }]];
}

- (void)testRemovingHighlightRestoresColorsWithOneReload {
    Profile *original = self.profilePreferencesCurrentProfile;
    [_controller popupButtonWillPopUp:nil];
    [self previewPreset:@"Tango Light"];
    [self previewPreset:@"Tango Dark"];
    NSArray<NSString *> *changedKeys = [self keysThatDifferBetween:original
                                                               and:self.profilePreferencesCurrentProfile];
    // Needs more than one changed key for the reload count to mean anything.
    XCTAssertGreaterThan(changedKeys.count, 1u);

    NSUInteger (^reloads)(void) = [self reloadCounter];
    [_announcedKeys removeAllObjects];
    [_controller menu:_menu willHighlightItem:nil];
    XCTAssertEqual(reloads(), 1u);
    XCTAssertEqualObjects([NSCountedSet setWithArray:_announcedKeys], [NSCountedSet setWithArray:changedKeys]);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);

    // Closing the menu now shouldn't reload again.
    [_controller menuDidClose:_menu];
    XCTAssertEqual(reloads(), 1u);
}

- (void)testCancelingPreviewRestoresTabColorRemovedByPreset {
    [self useSeparateColors];
    NSString *tabColorKey = KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX;
    [_model setObject:[iTermColorPresets presetWithName:@"Tango Dark"][KEY_FOREGROUND_COLOR]
               forKey:tabColorKey
           inBookmark:self.profilePreferencesCurrentProfile];
    Profile *original = self.profilePreferencesCurrentProfile;

    [_controller popupButtonWillPopUp:nil];
    [self previewPreset:@"Tango Light"];
    XCTAssertNil(self.profilePreferencesCurrentProfile[tabColorKey]);
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile[KEY_BACKGROUND_COLOR COLORS_LIGHT_MODE_SUFFIX],
                          [iTermColorPresets presetWithName:@"Tango Light"][KEY_BACKGROUND_COLOR]);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);
}

// No built-in preset has a tab color, so make one that does.
- (void)testCancelingPreviewRemovesTabColorAddedByPreset {
    [self useSeparateColors];
    NSString *tabColorKey = KEY_TAB_COLOR COLORS_LIGHT_MODE_SUFFIX;
    Profile *original = self.profilePreferencesCurrentProfile;
    XCTAssertNil(original[tabColorKey]);

    NSMutableDictionary *preset = [[iTermColorPresets presetWithName:@"Tango Dark"] mutableCopy];
    preset[KEY_TAB_COLOR] = preset[KEY_ANSI_1_COLOR];
    NSString *name = NSUUID.UUID.UUIDString;
    [iTermColorPresets addColorPreset:name withColors:preset];
    [self addTeardownBlock:^{ [iTermColorPresets deletePresetWithName:name]; }];

    [_controller popupButtonWillPopUp:nil];
    [self previewPreset:name];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile[tabColorKey], preset[KEY_TAB_COLOR]);
    [_controller menuDidClose:_menu];
    XCTAssertEqualObjects(self.profilePreferencesCurrentProfile, original);
}

#pragma mark - iTermProfilePreferencesBaseViewControllerDelegate

- (Profile *)profilePreferencesCurrentProfile { return [_model bookmarkWithGuid:_guid]; }
- (ProfileModel *)profilePreferencesCurrentModel { return _model; }
- (BOOL)editingTmuxSession { return NO; }
- (BOOL)profilePreferencesRevealViewController:(iTermProfilePreferencesBaseViewController *)vc { return NO; }
- (void)profilePreferencesViewController:(iTermProfilePreferencesBaseViewController *)vc willSetObjectWithKey:(NSString *)key {
    [_announcedKeys addObject:key];
}
- (void)profilePreferencesContentViewSizeDidChange:(iTermSizeRememberingView *)view {}
- (void)profilePreferencesSessionTypeDidChange {}

@end
