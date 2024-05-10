//
//  iTermAdvancedSettingsModel.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Foundation/Foundation.h>

#if ITERM2_SHARED_ARC
#import "iTerm2SharedARC-Swift.h"
#endif

#import "iTermAdvancedSettingsModel.h"
#import "iTermUserDefaultsObserver.h"
#import "NSApplication+iTerm.h"
#import "NSStringITerm.h"
#import <objc/runtime.h>


NSString *const kAdvancedSettingIdentifier = @"kAdvancedSettingIdentifier";
NSString *const kAdvancedSettingType = @"kAdvancedSettingType";
NSString *const kAdvancedSettingDefaultValue = @"kAdvancedSettingDefaultValue";
NSString *const kAdvancedSettingDescription = @"kAdvancedSettingDescription";
NSString *const kAdvancedSettingSetter = @"kAdvancedSettingSetter";
NSString *const kAdvancedSettingGetter = @"kAdvancedSettingGetter";

NSString *const iTermAdvancedSettingsDidChange = @"iTermAdvancedSettingsDidChange";

static inline BOOL iTermAdvancedSettingsModelTransformBool(id object) {
    return [object boolValue];
}

static inline id iTermAdvancedSettingsModelInverseTransformBool(BOOL value) {
    return @(value);
}

static inline const BOOL *iTermAdvancedSettingsModelTransformOptionalBool(id object) {
    if (object == nil) {
        return nil;
    } else if ([object boolValue]) {
        static BOOL yes = YES;
        return &yes;
    } else {
        static BOOL no = NO;
        return &no;
    }
}

static inline id iTermAdvancedSettingsModelInverseTransformOptionalBool(const BOOL *value) {
    if (value == nil) {
        return nil;
    } else if (*value) {
        return @YES;
    } else {
        return @NO;
    }
}

static inline int iTermAdvancedSettingsModelTransformInt(id object) {
    return [object intValue];
}

static inline id iTermAdvancedSettingsModelInverseTransformInt(int value) {
    return @(value);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
static inline int iTermAdvancedSettingsModelTransformNonnegativeInt(id object) {
    int value = [object intValue];
    return MAX(0, value);
}
#pragma clang diagnostic pop

static inline double iTermAdvancedSettingsModelTransformFloat(id object) {
    return [object doubleValue];
}

static inline id iTermAdvancedSettingsModelInverseTransformFloat(double value) {
    return @(value);
}

static inline NSString *iTermAdvancedSettingsModelTransformString(id object) {
    return object;
}

static inline id iTermAdvancedSettingsModelInverseTransformString(NSString *value) {
    return value;
}

// name: A token uniquely identifying the property. It is the same as the name of the method to fetch its value.
// podtype: The data type. For example, BOOL or NSString *
// type: The iTermAdvancedSettingType enum value
// default: The default value, such as YES or @"foo". Nonnil.
// transformation: Name of a function (as a token) that converts podtype to id
// inverseTransformation: Name of a function (as a token) that converts id to podtype
#define DEFINE_BOILERPLATE(name, podtype, type, default, description, transformation, inverseTransformation) \
static id sAdvancedSetting_##name; \
+ (NSDictionary *)advancedSettingsModelDictionary_##name { \
    return @{ kAdvancedSettingIdentifier: [@#name stringByCapitalizingFirstLetter], \
              kAdvancedSettingType: @(type), \
              kAdvancedSettingDefaultValue: inverseTransformation(default) ?: [NSNull null], \
              kAdvancedSettingDescription: description }; \
} \
+ (NSString *)name##UserDefaultsKey { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return theIdentifier; \
} \
+ (NSString *)load_##name { \
    NSString *key = [self name##UserDefaultsKey]; \
    id valueFromUserDefaults = [[NSUserDefaults standardUserDefaults] objectForKey:key]; \
    sAdvancedSetting_##name = valueFromUserDefaults ?: inverseTransformation(default); \
    return key; \
} \
+ (podtype)name { \
    return transformation(sAdvancedSetting_##name); \
}

// See DEFINE_BOILERPLATE.
// capitalizedName: Same as name but with the first letter capitalized so it looks nice in +setFoo:.
#define DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, podtype, type, default, description, transformation, inverseTransformation) \
DEFINE_BOILERPLATE(name, podtype, type, default, description, transformation, inverseTransformation) \
+ (void)set##capitalizedName :(podtype)newValue { \
    sAdvancedSetting_##name = inverseTransformation(newValue); \
    [[NSUserDefaults standardUserDefaults] setObject:sAdvancedSetting_##name forKey:@#capitalizedName]; \
}

#if ITERM2_SHARED_ARC

#define DEFINE_SECURE_BOILERPLATE(name, capitalizedName, podtype, type, description, transformation, inverseTransformation) \
static podtype sAdvancedSetting_##name; \
+ (NSDictionary *)advancedSettingsModelDictionary_##name { \
    podtype defaultValue = iTermSecureUserDefaults.instance.defaultValue_##name; \
    return @{ kAdvancedSettingIdentifier: [@#name stringByCapitalizingFirstLetter], \
              kAdvancedSettingType: @(type), \
              kAdvancedSettingDefaultValue: inverseTransformation(defaultValue) ?: [NSNull null], \
              kAdvancedSettingDescription: description, \
              kAdvancedSettingSetter: [NSString stringWithFormat:@"setFromObject_%s:", #capitalizedName], \
              kAdvancedSettingGetter: [NSString stringWithFormat:@"object_%s", #name], \
            }; \
} \
+ (NSString *)name##UserDefaultsKey { \
    NSString *theIdentifier = [@#name stringByCapitalizingFirstLetter]; \
    return theIdentifier; \
} \
+ (NSString *)load_##name { \
    NSString *key = [self name##UserDefaultsKey]; \
    podtype valueFromUserDefaults = [[iTermSecureUserDefaults instance] name]; \
    sAdvancedSetting_##name = valueFromUserDefaults; \
    return key; \
} \
+ (podtype)name { \
    return sAdvancedSetting_##name; \
} \
+ (id)object_##name { \
    return inverseTransformation(sAdvancedSetting_##name); \
} \
+ (void)set##capitalizedName :(podtype)newValue { \
    [[iTermSecureUserDefaults instance] set##capitalizedName :newValue]; \
    [self load_##name]; \
} \
+ (id)setFromObject_##capitalizedName :(id)newValue { \
    [[iTermSecureUserDefaults instance] set##capitalizedName :transformation(newValue)]; \
    [self load_##name]; \
    return inverseTransformation(sAdvancedSetting_##name); \
}


#define DEFINE_SECURE_BOOL(name, capitalizedName, theDescription) \
DEFINE_SECURE_BOILERPLATE(name, capitalizedName, BOOL, kiTermAdvancedSettingTypeBoolean, theDescription, iTermAdvancedSettingsModelTransformBool, iTermAdvancedSettingsModelInverseTransformBool)
// NOTE: To add more secure types, you'll need to modify iTermAdvancedSettingsViewController.m to
// call the appropriate getter & setter and, afterwards, update the UI with the return value of the setter
// since setting can fail.
#endif  // ITERM2_SHARED_ARC

#define DEFINE_BOOL(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, BOOL, kiTermAdvancedSettingTypeBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformBool, iTermAdvancedSettingsModelInverseTransformBool)

#define DEFINE_SETTABLE_BOOL(name, capitalizedName, theDefault, theDescription) \
DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, BOOL, kiTermAdvancedSettingTypeBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformBool, iTermAdvancedSettingsModelInverseTransformBool)

#define DEFINE_OPTIONAL_BOOL(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, const BOOL *, kiTermAdvancedSettingTypeOptionalBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformOptionalBool, iTermAdvancedSettingsModelInverseTransformOptionalBool)

#define DEFINE_SETTABLE_OPTIONAL_BOOL(name, capitalizedName, theDefault, theDescription) \
DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, const BOOL *, kiTermAdvancedSettingTypeOptionalBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformOptionalBool, iTermAdvancedSettingsModelInverseTransformOptionalBool)

#define DEFINE_INT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, int, kiTermAdvancedSettingTypeInteger, theDefault, theDescription, iTermAdvancedSettingsModelTransformInt, iTermAdvancedSettingsModelInverseTransformInt)

#define DEFINE_NONNEGATIVE_INT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, int, kiTermAdvancedSettingTypeInteger, theDefault, theDescription, iTermAdvancedSettingsModelTransformNonnegativeInt, iTermAdvancedSettingsModelInverseTransformInt)

#define DEFINE_OPTIONAL_INT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, int *, kiTermAdvancedSettingTypeOptionalInteger, theDefault, theDescription, iTermAdvancedSettingsModelTransformOptionalInt, iTermAdvancedSettingsModelInverseTransformOptionalInt)

#define DEFINE_FLOAT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, double, kiTermAdvancedSettingTypeFloat, theDefault, theDescription, iTermAdvancedSettingsModelTransformFloat, iTermAdvancedSettingsModelInverseTransformFloat)

#define DEFINE_SETTABLE_FLOAT(name, capitalizedName, theDefault, theDescription) \
DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, double, kiTermAdvancedSettingTypeFloat, theDefault, theDescription, iTermAdvancedSettingsModelTransformFloat, iTermAdvancedSettingsModelInverseTransformFloat)

#define DEFINE_STRING(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, NSString *, kiTermAdvancedSettingTypeString, theDefault, theDescription, iTermAdvancedSettingsModelTransformString, iTermAdvancedSettingsModelInverseTransformString)

#define DEFINE_SETTABLE_STRING(name, capitalizedName, theDefault, theDescription) \
DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, NSString *, kiTermAdvancedSettingTypeString, theDefault, theDescription, iTermAdvancedSettingsModelTransformString, iTermAdvancedSettingsModelInverseTransformString)

#pragma mark -

#define DEFINE_DEPRECATED_STRING(name, theDefault, theDescription) DEFINE_STRING(name, theDefault, theDescription); + (BOOL)deprecated_##name { return YES; }
// Convenience default value for boolean settings that are on for beta users.
#if BETA
#define YES_IF_BETA_ELSE_NO YES
#else
#define YES_IF_BETA_ELSE_NO NO
#endif

#pragma mark - Custom Defaults

BOOL UseSystemCursorWhenPossibleDefault(void) {
    if (@available(macOS 10.15, *)) {
        return YES;
    }
    return NO;
}

#pragma mark - iTermAdvancedSettingsModel

@implementation iTermAdvancedSettingsModel

+ (void)enumerateMethods:(void (^)(Method method, SEL selector))block {
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(object_getClass([iTermAdvancedSettingsModel class]), &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        SEL selector = method_getName(method);
        block(method, selector);
    }
    free(methods);
}

+ (void)enumerateDictionaries:(void (^)(NSDictionary *))block {
    [self enumerateMethods:^(Method method, SEL selector) {
        NSString *name = NSStringFromSelector(selector);
        NSString *prefix = @"advancedSettingsModelDictionary_";
        if ([name hasPrefix:prefix] && ![self settingIsDeprecated:[name stringByRemovingPrefix:prefix]]) {
            NSDictionary *(*impl)(id, SEL) = (NSDictionary *(*)(id, SEL))method_getImplementation(method);
            NSDictionary *dict = impl(self, selector);
            block(dict);
        }
    }];
}

+ (BOOL)settingIsDeprecated:(NSString *)name {
    NSString *string = [@"deprecated_" stringByAppendingString:name];
    SEL selector = NSSelectorFromString(string);
    return [self respondsToSelector:selector];
}
#pragma mark Tabs

#define SECTION_TABS @"Tabs: "

DEFINE_BOOL(openProfilesInNewWindow, NO, SECTION_TABS @"Choosing a profile from the “Profiles” menu opens a new window.\nYou must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(useUnevenTabs, NO, SECTION_TABS @"Uneven tab widths allowed.");
DEFINE_INT(minTabWidth, 75, SECTION_TABS @"Minimum tab width when using uneven tab widths.");
DEFINE_INT(minCompactTabWidth, 60, SECTION_TABS @"Minimum tab width when using uneven tab widths for compact tabs.");
DEFINE_INT(optimumTabWidth, 175, SECTION_TABS @"Preferred tab width when tabs are equally sized.");
DEFINE_BOOL(addNewTabAtEndOfTabs, YES, SECTION_TABS @"Add new tabs at the end of the tab bar, not next to current tab.");
DEFINE_BOOL(navigatePanesInReadingOrder, YES, SECTION_TABS @"Next Pane and Previous Pane commands use reading order, not the time of last use.");
DEFINE_FLOAT(tabAutoShowHoldTime, 1.0, SECTION_TABS @"How long in seconds to show tabs in fullscreen.\nThe tab bar appears briefly in fullscreen when the number of tabs changes or you switch tabs. This setting gives the time in seconds for it to remain visible.");
DEFINE_FLOAT(tabFlashAnimationDuration, 0.25, SECTION_TABS @"Animation duration for fade in/out animation of tabs in full screen, in seconds.")
DEFINE_BOOL(allowDragOfTabIntoNewWindow, YES, SECTION_TABS @"Allow a tab to be dragged and dropped outside any existing tab bar to create a new window.");
DEFINE_INT(minimumTabDragDistance, 10, SECTION_TABS @"How far must the mouse move before a tab drag is initiated?\nYou must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(tabTitlesUseSmartTruncation, YES, SECTION_TABS @"Use “smart truncation” for tab titles.\nIf a tab‘s title is too long to fit, ellipsize the start of the title if more tabs have unique suffixes than prefixes in a given window.");
DEFINE_BOOL(middleClickClosesTab, YES, SECTION_TABS @"Should middle-click on a tab in the tab bar close the tab?");
DEFINE_FLOAT(coloredSelectedTabOutlineStrength, 0.5, SECTION_TABS @"How prominent should the outline around the selected tab be drawn when there are colored tabs in a window?\nTakes a value in 0 to 3, where 0 means no outline and 3 means a very prominent outline.");
DEFINE_FLOAT(minimalEdgeDragSize, 12, SECTION_TABS @"In the Minimal theme, you can move the window by dragging starting in a region on the edge near the window border. This gives the size of that region.");
DEFINE_FLOAT(compactEdgeDragSize, 10, SECTION_TABS @"In the Compact theme, you can move the window by dragging starting in a region on the edge near the window border. This gives the size of that region.");
DEFINE_FLOAT(minimalTabStyleBackgroundColorDifference, 0.05, SECTION_TABS @"In the Minimal theme, how different should the background color of the selected tab be from the others?\nTakes a value in 0 to 1, where 0 is no difference and 1 very different.");
DEFINE_FLOAT(minimalTabStyleOutlineStrength, 0.2, SECTION_TABS @"In the Minimal theme, how prominent should the tab outline be?\nTakes a value in 0 to 1, where 0 is invisible and 1 is very prominent");
DEFINE_FLOAT(minimalSplitPaneDividerProminence, 0.15, SECTION_TABS @"In the Minimal theme, how prominent should split pane dividers be?\nTakes a value in 0 to 1, where 0 is invisible and 1 is very prominent");
DEFINE_FLOAT(coloredUnselectedTabTextProminence, 0.5, SECTION_TABS @"How prominent should the text in a non-selected tab be when there are colored tabs in a window?\nTakes a value in 0 to 1, the alpha value.");
DEFINE_FLOAT(minimalTextLegibilityAdjustment, 1.0, SECTION_TABS @"How much should contrast be increased for text in tabs in the Minimal theme?\nChoose a value larger than 1 to increase contrast. Values between 0 and 1 have less contrast than the default.");
DEFINE_BOOL(minimalTabStyleTreatLeftInsetAsPartOfFirstTab, NO, SECTION_TABS @"In the Minimal theme, should the area left of the tab bar be treated as part of the first tab?");
DEFINE_FLOAT(compactMinimalTabBarHeight, 38, SECTION_TABS @"Tab bar height (points) for the Minimal theme.\nThe default is 38. Use 22 to match the compact theme's height.");
DEFINE_SETTABLE_FLOAT(defaultTabBarHeight, DefaultTabBarHeight, 24, SECTION_TABS @"Default tab bar height")
DEFINE_BOOL(doubleClickTabToEdit, YES, SECTION_TABS @"Should double-clicking a tab open a window to edit its title?");
DEFINE_FLOAT(minimumTabLabelWidth, 35, SECTION_TABS @"Minimum width for tab labels.\nThe activity/bell icon will be hidden when the space for the label drops below this size (in points)");
DEFINE_BOOL(disregardDockSettingToOpenTabsInsteadOfWindows, YES, SECTION_TABS @"Ignore System Settings > Dock > Prefer tabs when opening documents?\nWhen set to No, asking to open a window will open a tab instead when system settings is configured to prefer tabs over windows. When set to Yes, asking to open a window may open a tab instead.");
DEFINE_BOOL(convertTabDragToWindowDragForSolitaryTabInCompactOrMinimalTheme, YES, SECTION_TABS @"In the Minimal and Compact themes when there is a single tab and the tab bar is visible, should dragging the tab bar move the window?\nThis also affects windows without titlebars in any theme.");
DEFINE_BOOL(highVisibility, YES, SECTION_TABS @"High Contrast modes maximize visibility.\nWhen enabled, the dark high-contrast theme emphasizes visibility over beauty.");
DEFINE_BOOL(drawBottomLineForHorizontalTabBar, YES, SECTION_TABS @"Draw bottom line for horizontal tabbar in Regular, Dark and Light theme?");
DEFINE_BOOL(disableTabBarTooltips, NO, SECTION_TABS @"Disable tab bar tooltips?");
DEFINE_BOOL(useCustomTabBarFontSize, NO, SECTION_TABS @"Use custom font size for tab labels?\nSee also advanced setting “Custom tab label font size”.");
DEFINE_FLOAT(customTabBarFontSize, 11.0, SECTION_TABS @"Custom tab label font size\nFor this to take effect, turn on “Use custom font size for tab labels?”.");
DEFINE_FLOAT(minimalSelectedTabUnderlineProminence, 1, SECTION_TABS @"Prominence of selected tab underline indicator in the Minimal theme when there is at least one colored tab.");
DEFINE_BOOL(allowInteractiveSwipeBetweenTabs, YES, SECTION_TABS @"Allow two-finger interactive swipe between tabs?\nThe system preference Trackpad > More Gestures > Swipe between pages controls this globally. When “swipe with two fingers” is enabled, you can change this setting to “No” to prevent swiping between tabs in iTerm2.");
DEFINE_BOOL(selectsTabsOnMouseDown, YES, SECTION_TABS @"Select tabs on mouse-down?\nChanging this setting will not affect existing windows.");
DEFINE_FLOAT(minimalDeslectedColoredTabAlpha, 0.5, SECTION_TABS @"Alpha value for tab color for non-selected colored tabs in the Minimal theme.\nMust be between 0 and 1.");
DEFINE_STRING(tabColorMenuOptions, @"#fb6b62 #f6ac47 #f0dc4f #b5d749 #5fa3f8 #c18ed9 #787878", SECTION_TABS @"Colors for tab color menu item.\nSpace delimited strings like #rrggbb or #rgb in sRGB color space. If the P3 color space is available, you can use strings like: color(p3 1 0.5 0.25)");
DEFINE_BOOL(removeAddTabButton, NO, SECTION_TABS @"Remove the “new tab” button from horizontal tab bars?");
DEFINE_FLOAT(lightModeInactiveTabDarkness, 0.07, SECTION_TABS @"Darkness (in [0…1]) for non-selected tabs in non-Minimal theme in light mode.");
DEFINE_FLOAT(darkModeInactiveTabDarkness, 0.5, SECTION_TABS @"Darkness (in [0…1]) for non-selected tabs in non-Minimal theme in dark mode.");
DEFINE_BOOL(saveProfilesToRecentDocuments, NO, SECTION_TABS @"Add items to Recents (in the dock icon's menu) to reopen recently used profiles as tabs?")
DEFINE_BOOL(placeTabsInTitlebarAccessoryInFullScreen, YES, SECTION_TABS @"Place the tabbar in the window's titlebar in full screen mode (macOS 13+ only)?\nThis can be disabled to work around a bug in macOS where tabs may not be visible in full screen.");
DEFINE_BOOL(defaultIconsUsingLetters, YES, SECTION_TABS @"Use the running command's first letter as the tab's default icon if there isn't a built in one.\nThis takes effect when tabs are configured to use built-in icons.");

#pragma mark Mouse

#define SECTION_MOUSE @"Mouse: "
DEFINE_STRING(alternateMouseScrollStringForUp, @"",
              SECTION_MOUSE @"Scroll wheel up sends the specified text when in alternate screen mode.\n"
              @"The value should use Vim syntax, such as \\e for escape.");
DEFINE_STRING(alternateMouseScrollStringForDown, @"",
              SECTION_MOUSE @"Scroll wheel down sends the specified text when in alternate screen mode.\n"
              @"The value should use Vim syntax, such as \\e for escape.");
DEFINE_SETTABLE_BOOL(alternateMouseScroll, AlternateMouseScroll, NO, SECTION_MOUSE @"Scroll wheel sends arrow keys when in alternate screen mode.");
DEFINE_BOOL(pinchToChangeFontSizeDisabled, NO, SECTION_MOUSE @"Disable changing font size in response to a pinch gesture.");
DEFINE_BOOL(useSystemCursorWhenPossible, UseSystemCursorWhenPossibleDefault(), SECTION_MOUSE @"Use system cursor icons when possible.");
DEFINE_BOOL(alwaysAcceptFirstMouse, YES, SECTION_MOUSE @"Always accept first mouse event on terminal windows.\nThis means clicks will work the same when iTerm2 is active as when it’s inactive.");
DEFINE_BOOL(doubleReportScrollWheel, NO, SECTION_MOUSE @"Double-report scroll wheel events to work around tmux scrolling bug.");
DEFINE_BOOL(stealKeyFocus, NO, SECTION_MOUSE @"When Focus Follows Mouse is enabled, steal key focus even when inactive.");
DEFINE_BOOL(aggressiveFocusFollowsMouse, NO, SECTION_MOUSE @"When Focus Follows Mouse is enabled, activate the window under the cursor when iTerm2 becomes active?");
DEFINE_BOOL(cmdClickWhenInactiveInvokesSemanticHistory, NO, SECTION_MOUSE @"⌘-click in an active pane while iTerm2 isn't the active app invokes Semantic History.\nBy default, iTerm2 respects the OS standard that ⌘-click in an app that doesn't have keyboard focus behaves like a non-⌘ click that does not raise the window.");
DEFINE_BOOL(enableUnderlineSemanticHistoryOnCmdHover, YES, SECTION_MOUSE @"Underline Semantic History-selectable items under the cursor while holding ⌘?");
DEFINE_BOOL(enableCmdClickPromptForShowCommandInfo, YES, SECTION_MOUSE @"⌘-click in the prompt shows the Command Info window");
DEFINE_BOOL(sensitiveScrollWheel, NO, SECTION_MOUSE @"Scroll on any scroll wheel movement, no matter how small?");
DEFINE_FLOAT(scrollWheelAcceleration, 1, SECTION_MOUSE @"Speed up scroll gestures by this factor.");

// This defines the fraction of a character's width on its right side that is used to
// select the NEXT character.
//        |   A rightward drag beginning left of the bar selects G.
//        <-> [iTermAdvancedSettingsModel fractionOfCharacterSelectingNextNeighbor] * charWidth
//  <-------> Character width
//   .-----.  .      :
//  ;         :      :
//  :         :      :
//  :    ---- :------:
//  '       : :      :
//   `-----'  :      :
DEFINE_FLOAT(fractionOfCharacterSelectingNextNeighbor, 0.35, SECTION_MOUSE @"Fraction of character’s width on its right side that can be used to select the character to its right.");
DEFINE_BOOL(naturalScrollingAffectsHorizontalMouseReporting, NO, SECTION_MOUSE @"Horizontal scrolling is reversed when “Natural scrolling” is enabled in system prefs");
DEFINE_FLOAT(horizontalScrollingSensitivity, 0.1, SECTION_MOUSE @"Sensitivity of mouse wheel for horizontal scrolling.\nUse 0 to disable. Value should be between 0 and 1. Changes to this setting only affect new sessions.");

#pragma mark Terminal

#define SECTION_TERMINAL @"Terminal: "

DEFINE_BOOL(bounceOnInactiveBell, NO, SECTION_TERMINAL @"Bounce dock icon when the bell rings while another app is active?");
DEFINE_BOOL(traditionalVisualBell, NO, SECTION_TERMINAL @"Visual bell flashes the whole screen, not just a bell icon.");
DEFINE_FLOAT(indicatorFlashInitialAlpha, 0.5, SECTION_TERMINAL @"Initial alpha value when flashing the visual bell or search wraparound indicator");
DEFINE_FLOAT(timeBetweenBlinks, 0.5, SECTION_TERMINAL @"Cursor blink speed (seconds).");
DEFINE_BOOL(doNotSetCtype, NO, SECTION_TERMINAL @"Never set the CTYPE environment variable.");
// For these, 1 is more aggressive and 0 turns the feature off:
DEFINE_FLOAT(smartCursorColorBgThreshold, 0.5, SECTION_TERMINAL @"Threshold for Smart Cursor Color for background color (0 to 1).\n0 means the cursor’s background color will always be the cell’s text color, while 1 means it will always be black or white.");
DEFINE_FLOAT(smartCursorColorFgThreshold, 0.75, SECTION_TERMINAL @"Threshold for Smart Cursor Color for text color (0 to 1).\n0 means the cursor’s text color will always be the cell’s background color, while 1 means it will always be black or white.");
DEFINE_STRING(findUrlsRegex,
              @"https?://([a-z0-9A-Z]+(:[a-zA-Z0-9]+)?@)?[a-z0-9A-Z\\-]+(\\.[a-z0-9A-Z\\-]+)*"
              @"((:[0-9]+)?)(/[a-zA-Z0-9;:/\\.\\-_+%~?&amp;@=#\\(\\)]*)?",
              SECTION_TERMINAL @"Regular expression for “Find URLs” command.");
DEFINE_SETTABLE_FLOAT(echoProbeDuration, EchoProbeDuration, 0.5, SECTION_TERMINAL @"Amount of time to wait while testing if echo is on (seconds).\nThis is used by the password manager to ensure you're at a password prompt. Set to 0 to disable echo probe.");
DEFINE_BOOL(disablePasswordManagerAnimations, NO, SECTION_TERMINAL @"Disable animations for showing/hiding password manager.");
DEFINE_BOOL(optionIsMetaForSpecialChars, YES, SECTION_TERMINAL @"When you press an arrow key or other function key that transmits the modifiers, should ⌥ be translated to Meta?\nIf this is set to No then it will be translated to Alt.");
DEFINE_BOOL(noSyncSilenceAnnoyingBellAutomatically, NO, SECTION_TERMINAL @"Automatically silence bell when it rings too much.");
DEFINE_SETTABLE_STRING(noSyncVariablesToReport, NoSyncVariablesToReport, @"", SECTION_TERMINAL @"Variables to report via control sequence\nThis is a comma-delimited list of variables that can be reported with the OSC 1337 ReportVariable=name control sequence. Each variable name must be prefixed with “allow:” or “deny:”.");
DEFINE_BOOL(restoreWindowContents, YES, SECTION_TERMINAL @"Restore window contents at startup.\nThis requires “System Settings > Desktop & Dock > Close windows when quitting an app” to be off.");
DEFINE_INT(numberOfLinesForAccessibility, 1000, SECTION_TERMINAL @"Maximum number of lines of history to expose to Accessibility.\nAccessibility APIs can make iTerm2 slow. In order to limit the effect, you can restrict the number of lines in each session that are visible to accessibility. The last lines of each session will be made accessible.");
DEFINE_INT(triggerRadius, 3, SECTION_TERMINAL @"Number of screen lines to match against trigger regular expressions.\nTrigger regular expressions are matched against the last logical line of text when a newline is received. A search is performed to find the start of the line. Since very long lines would cause performance problems, the search (and consequently the regular expression match, highlighting, and so on) is limited to this many screen lines.");
DEFINE_BOOL(allowIdempotentTriggers, NO, SECTION_TERMINAL @"Evaluate idempotent triggers periodically in interactive apps, even when triggers in interactive apps are disabled.");
DEFINE_FLOAT(idempotentTriggerModeRateLimit, 0.25, SECTION_TERMINAL @"When evaluating idempotent triggers in interactive apps, wait this long (in seconds) between updates.\nThis limits the performance impact of trigger evaluation.");
DEFINE_BOOL(requireCmdForDraggingText, NO, SECTION_TERMINAL @"To drag images or selected text, you must hold ⌘. This prevents accidental drags.");
DEFINE_BOOL(focusReportingEnabled, YES, SECTION_TERMINAL @"Apps may turn on Focus Reporting.\nFocus reporting causes iTerm2 to send an escape sequence when a session gains or loses focus. It can cause problems when an ssh session dies unexpectedly because it gets left on, so some users prefer to disable it.");
DEFINE_BOOL(useColorfgbgFallback, YES, SECTION_TERMINAL @"Use fallback for COLORFGBG if no exact match found?\nThe COLORFGBG variable indicates the ANSI colors that match the foreground and background colors. If no colors match and this setting is enabled, then the variable will be set to 15;0 to indicate a dark background or 0;15 to indicate a light background.");
DEFINE_BOOL(zeroWidthSpaceAdvancesCursor, YES, SECTION_TERMINAL @"Zero-Width Space (U+200B) advances cursor?\nWhile a zero-width space should not advance the cursor per the Unicode spec, both Terminal.app and Konsole do this, and Weechat depends on it. You must restart iTerm2 after changing this setting.");
DEFINE_BOOL(fullHeightCursor, NO, SECTION_TERMINAL @"Cursor occupies line spacing area.\nIf lines have more than 100% vertical spacing and this setting is enabled the bottom of the cursor will be aligned to the bottom of the spacing area.");
DEFINE_FLOAT(underlineCursorOffset, 0, SECTION_TERMINAL @"Vertical offset for underline cursor.\nPositive values move it up, negative values move it down.");
DEFINE_SETTABLE_OPTIONAL_BOOL(preventEscapeSequenceFromClearingHistory, PreventEscapeSequenceFromClearingHistory, nil, SECTION_TERMINAL @"Prevent CSI 3 J from clearing scrollback history?\nThis is also known as the terminfo E3 capability.");
DEFINE_SETTABLE_OPTIONAL_BOOL(preventEscapeSequenceFromChangingProfile, PreventEscapeSequenceFromChangingProfile, nil, SECTION_TERMINAL @"Prevent control sequences from changing the current profile?");
DEFINE_SETTABLE_BOOL(warnAboutSecureKeyboardInputWithOpenCommand, WarnAboutSecureKeyboardInputWithOpenCommand, YES, SECTION_TERMINAL @"Warn if the `open` command appears to fail when secure keyboard input is enabled?")
DEFINE_INT(maxHistoryLinesToRestore, 20000, SECTION_TERMINAL @"Maximum number of lines of history to restore.\nWhen the app is relaunched, only the last N lines of history are restored to avoid making launch too slow. If you reduce this number, existing sessions won't be affected until their history is cleared.");

DEFINE_FLOAT(verticalBarCursorWidth, 1, SECTION_TERMINAL @"Width of vertical bar cursor.");
DEFINE_BOOL(acceptOSC7, YES, SECTION_TERMINAL @"Accept OSC 7 to set username, hostname, and path.");
DEFINE_BOOL(detectPasswordInput, YES, SECTION_TERMINAL @"Show key at cursor at password prompt?");
DEFINE_BOOL(tabsWrapAround, NO, SECTION_TERMINAL @"Tabs wrap around to the next line.\nThis is useful for preserving tabs for later copying to the pasteboard. It breaks backward compatibility and may cause layout problems with programs that don’t expect this behavior.");
DEFINE_STRING(sshSchemePath, @"ssh", SECTION_TERMINAL @"Command to run when handling an ssh:// URL.");
DEFINE_INT(defaultTabStopWidth, 8, SECTION_TERMINAL @"Default tab stop width for new sessions.\nNote: this will break drawing in emacs and other apps.");
DEFINE_BOOL(convertItalicsToReverseVideoForTmux, YES, SECTION_TERMINAL @"Convert italics to reverse video in tmux integration?");
DEFINE_FLOAT(bellRateLimit, 0.1, SECTION_TERMINAL @"Minimum time between beeping or flashing screen on bell, in seconds.\nIf the time interval between bells is less than this amount of time, it will be ignored.");
DEFINE_BOOL(translateScreenToXterm, YES, SECTION_TERMINAL @"Support TERM=screen\nMost notably, this fixes italics replacing inverse text.");
DEFINE_BOOL(shouldSetTerminfoDirs, YES, SECTION_TERMINAL @"Set $TERMINFO_DIRS to add modern terminal features to xterm-like $TERMs?\niTerm2 ships with extended terminfo capabilities for common TERMs (xterm, xterm-new, and xterm-256color). For example, it enables undercurl. New sessions get created with a TERMINFO_DIRS that make the customized TERMINFOs take precedence over the system defaults.");

// See the discussion in -[VT100Output reportSecondaryDeviceAttribute]
DEFINE_INT(xtermVersion, 2500, SECTION_TERMINAL @"xterm version for secondary device attributes (SDA).\nIncreasing this number enables more features in apps but may break things. Use 95 to recover pre-3.4.10 behavior.");
DEFINE_BOOL(p3, YES, SECTION_TERMINAL @"Use P3 as default color space? If No, sRGB will be used.");
DEFINE_STRING(fileDropCoprocess, @"", SECTION_TERMINAL @"When files are dropped into a terminal window, execute a silent coprocess.\nThis is an interpolated string. Use \\(filenames) to reference the shell-quoted, space-delimited full paths to the dropped files. If this preference is empty, the filenames get pasted instead.")
DEFINE_INT(maxURLLength, 2097152, SECTION_TERMINAL @"Maximum length for OSC 8 URLs");
DEFINE_BOOL(defaultWideMode, NO, SECTION_TERMINAL @"When rendering natively, use wide mode by default?");

#if ITERM2_SHARED_ARC

DEFINE_SECURE_BOOL(enableSecureKeyboardEntryAutomatically, EnableSecureKeyboardEntryAutomatically, SECTION_TERMINAL @"Automatically enable secure keyboard entry at password prompts?");
#endif  // ITERM2_SHARED_ARC


#pragma mark Hotkey

#define SECTION_HOTKEY @"Hotkey: "
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, SECTION_HOTKEY @"Duration in seconds of the hotkey window animation.\nWarning: reducing this value may cause problems if you have multiple displays.");
DEFINE_BOOL(dockIconTogglesWindow, NO, SECTION_HOTKEY @"If the only window is a hotkey window, then clicking the dock icon shows or hides it.");
DEFINE_BOOL(hotkeyWindowFloatsAboveOtherWindows, NO, SECTION_HOTKEY @"The hotkey window floats above other windows even when another application is active.\nYou must disable “Prefs > Keys > Hotkey window hides when focus is lost” for this setting to be effective.");
DEFINE_FLOAT(hotKeyDoubleTapMaxDelay, 0.3, SECTION_HOTKEY @"The maximum amount of time allowed between presses of a modifier key when performing a modifier double-tap.");
DEFINE_FLOAT(hotKeyDoubleTapMinDelay, 0.01, SECTION_HOTKEY @"The minimum amount of time required between presses of a modifier key when performing a modifier double-tap.");
DEFINE_BOOL(showPinnedIndicator, NO, SECTION_HOTKEY @"Show indicator for pinned hotkey windows.");

#pragma mark General

#define SECTION_GENERAL @"General: "

DEFINE_STRING(searchCommand, @"https://google.com/search?q=%@", SECTION_GENERAL @"Template for URL of search engine.\niTerm2 replaces the string “%@” with the text to search for. Query parameter percent escaping is used.");
DEFINE_INT(autocompleteMaxOptions, 20, SECTION_GENERAL @"Number of autocomplete options to present.\nA value less than 100 is recommended.");
DEFINE_FLOAT(minRunningTime, 10, SECTION_GENERAL @"Grace period for automatic quitting after the last window is closed.\nIf iTerm2 is configured to quit automatically when the last window is closed, this setting gives a grace period (in seconds) after startup where that feature is disabled. Set to 0 to have no grace period.");
DEFINE_FLOAT(updateScreenParamsDelay, 1, SECTION_GENERAL @"Delay after changing number of screens/resolution until refresh (seconds).\nThis works around OS bugs where it takes some time after a screen change before it is safe to resize windows.");
DEFINE_BOOL(disableAppNap, NO, SECTION_GENERAL @"Disable App Nap.\nChange effective after restarting iTerm2.");
DEFINE_FLOAT(idleTimeSeconds, 2, SECTION_GENERAL @"Time in seconds before a session is considered idle.\nUsed for updating icons and activity indicator in tabs.");
DEFINE_FLOAT(findDelaySeconds, 1, SECTION_GENERAL @"Time to wait before performing Find action on 1- or 2- character queries.");
DEFINE_INT(maximumBytesToProvideToServices, 100000, SECTION_GENERAL @"Maximum number of bytes of selection to provide to Services.\nA large value here can cause performance issues when you have a big selection.");
DEFINE_INT(maximumBytesToProvideToPythonAPI, 100, SECTION_GENERAL @"Maximum number of bytes of selection to provide to Python API.\nA large value here can cause performance issues when you have a big selection.");
DEFINE_BOOL(useOpenDirectory, YES, SECTION_GENERAL @"Use Open Directory to determine the user shell");
DEFINE_SETTABLE_BOOL(disableDECRQCRA, NoSyncDisableDECRQCRA, YES, SECTION_GENERAL @"Disable DECRQCRA?\nThis control sequence allows an app running in the terminal to read its contents.");
DEFINE_BOOL(disablePotentiallyInsecureEscapeSequences, NO, SECTION_GENERAL @"Disable potentially insecure escape sequences.\nSome features of iTerm2 expand the surface area for security issues. Consider turning this on when viewing untrusted content. The following custom escape sequences will be disabled: RemoteHost, StealFocus, CurrentDir, SetProfile, CopyToClipboard, EndCopy, File, SetBackgroundImageFile, OSC 6’s proxy icon-changing feature. The following DEC sequences are disabled: DECRQCRA. The following xterm extensions are disabled: Window Title Reporting, Icon Title Reporting. This will break displaying inline images, file download, some shell integration features, and other features.");
DEFINE_BOOL(performDictionaryLookupOnQuickLook, YES, SECTION_GENERAL @"Perform dictionary lookups on force press.\nIf this is NO, force press will still preview the Semantic History action; only dictionary lookups can be disabled.");
DEFINE_STRING(webUserAgent, @"Mozilla/5.0 (Macintosh; Intel Mac OS X 14_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15", SECTION_GENERAL @"User agent for web views. Leave empty to use system default.");

DEFINE_BOOL(jiggleTTYSizeOnClearBuffer, NO, SECTION_GENERAL @"Redraw the screen after the Clear Buffer menu item is selected.\nWhen enabled, the TTY size is briefly changed after clearing the buffer to cause the shell or current app to redraw.");
DEFINE_BOOL(saveScrollBufferWhenClearing, YES, SECTION_GENERAL @"Save scroll buffer when clearing screen.\nWhen enabled, saves the current screen into scroll back buffer instead of clearing it.");
DEFINE_BOOL(indicateBellsInDockBadgeLabel, YES, SECTION_GENERAL @"Indicate the number of bells rung while the app is inactive in the dock icon’s badge label");
DEFINE_STRING(downloadsDirectory, @"", SECTION_GENERAL @"Downloads folder.\nIf set, downloaded files go to this location instead of the user’s $HOME/Downloads folder.");
DEFINE_BOOL(noSyncSuppressDownloadConfirmation, NO, SECTION_GENERAL @"Suppress confirmation of terminal-initiated downloads?");
DEFINE_BOOL(showTimestampsByDefault, NO, SECTION_GENERAL @"Show timestamps by default?");
DEFINE_STRING(viewManPageCommand, @"man %@ || sleep 3", SECTION_GENERAL @"Command to view man pages.\nUsed when you press the man page button on the touch bar. %@ is replaced with the command. End the command with & to avoid opening an iTerm2 window (e.g., if you're launching an external viewer).");
DEFINE_BOOL(hideStuckTooltips, YES, SECTION_GENERAL @"Hide stuck tooltips.\nWhen you hide iTerm2 using a hotkey while a tooltip is fading out it gets stuck because of an OS bug. Work around it with a nasty hack by enabling this feature.")
DEFINE_BOOL(openFileOverridesSendText, YES, SECTION_GENERAL @"Should opening a script with iTerm2 disable the default profile's “Send Text at Start” setting?\nIf you use “open iTerm2 file.command” or drag a script onto iTerm2's icon and this setting is enabled then the script will be executed in lieu of the profile's “Send Text at Start” setting. If this setting is off then both will be executed.");
DEFINE_BOOL(statusBarIcon, YES, SECTION_GENERAL @"Add status bar icon when excluded from dock?\nWhen you turn on “Exclude from Dock and ⌘-Tab Application Switcher” a status bar icon is added to the menu bar so you can switch the setting back off. Disable this to remove the status bar icon. Doing so makes it very hard to get to Settings. You must restart iTerm2 after changing this setting.");
DEFINE_FLOAT(statusBarHeight, 21, SECTION_GENERAL @"Height of the status bar in points.\nThis will also affect the height of per-pane title bars becuase the status bar may be embedded in it. You must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(wrapFocus, YES, SECTION_GENERAL @"Should split pane navigation by direction wrap around?");
DEFINE_BOOL(openUntitledFile, YES, SECTION_GENERAL @"Open a new window when you click the dock icon and no windows are already open, and also on app launch when no other windows are open?");
DEFINE_BOOL(openNewWindowAtStartup, YES, SECTION_GENERAL @"Open a window at startup?\nThis is useful if you wish to use the system window restoration settings but not create a new window if none would be restored.");
DEFINE_FLOAT(timeToWaitForEmojiPanel, 1, SECTION_GENERAL @"How long to wait for the emoji panel to open in seconds?\nFloating hotkey windows adjust their level when the emoji panel is open. If it’s really slow you might need to increase this value to prevent it from appearing beneath a floating hotkey window.");
DEFINE_FLOAT(timeoutForStringEvaluation, 10, SECTION_GENERAL @"Timeout (seconds) for evaluating RPCs.\nThis applies to invoking functions registered by scripts when using the Swift syntax for inline expressions.");
DEFINE_STRING(pathToFTP, @"ftp", SECTION_GENERAL @"Path to ftp for opening ftp: URLs.\nYou may want to set this to /usr/local/bin/ftp to use the Homebrew install.");
DEFINE_STRING(pathToTelnet, @"telnet", SECTION_GENERAL @"Path to telnet for opening telnet: URLs.\nYou may want to set this to /usr/local/bin/telnet to use the Homebrew install.");
DEFINE_STRING(fallbackLCCType, @"", SECTION_GENERAL @"Value to set LC_CTYPE to if the machine‘s combination of country and language are not supported.\nIf unset, the encoding (e.g., UTF-8) will be used.");
// See issue 6994
DEFINE_BOOL(useVirtualKeyCodesForDetectingDigits, NO, SECTION_GENERAL @"Treat the top row of keys like number keys on an English keyboard for the purposes of switching panes, tabs, and windows with modifier+number.\nFor example, AZERTY requires you to hold down Shift to enter a number. To switch tabs with ⌘+Number on an AZERTY keyboard, you must enable this setting. Then, for example, ⌘-& switches to tab 1. When this setting is enabled, some user-defined shortcuts may become unavailable because the tab/window/pane switching behavior takes precedence.");
DEFINE_BOOL(hotkeyWindowsExcludedFromCycling, NO, SECTION_GENERAL @"Hotkey windows are excluded from Cycle Through Windows.");
DEFINE_BOOL(swapFindNextPrevious, YES, SECTION_GENERAL @"Swap Find Next and Find Previous.\nIf enabled, Find Next will search up and Find Previous will search down (iTerm2's traditional behavior, which is a departure from macOS's standard). When disabled, search behaves like a normal macOS app.");
DEFINE_BOOL(pinEditSession, NO, SECTION_GENERAL @"Pin Edit Session window to the session it originally edited.\nIf not set, it will affect the most recently active session.");
DEFINE_BOOL(remapModifiersWithoutEventTap, NO, SECTION_GENERAL @"Disable remapping modifiers for system shortcuts.\nThis prevents asking for accessibility permission. It breaks remapping system shortcuts like cmd-tab.");
DEFINE_BOOL(alertsIndicateShortcuts, NO, SECTION_GENERAL @"Buttons in modal alerts indicate keyboard shortcuts.\nDo you miss Windows 95? I do.");
DEFINE_BOOL(showHintsInSplitPaneMenuItems, NO, SECTION_GENERAL @"Show hints in split pane menu items to indicate horizontal vs vertical semantics.\nYou must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(useOldStyleDropDownViews, NO, SECTION_GENERAL @"Use old-style find and paste progress indicator views.\nThis change will only affect new windows.");
DEFINE_BOOL(synchronizeQueryWithFindPasteboard, YES, SECTION_GENERAL @"Synchronize search queries across windows and applications.\nNormally, when you enter a search query in a Find field all find fields in all applications get updated to hold the same value. This is utter nonsense, and can be disabled by setting this preference to No.");
DEFINE_STRING(dynamicProfilesPath, @"", SECTION_GENERAL @"Path to folder with dynamic profiles.\nWhen empty, ~/Library/Application Support/iTerm2/DynamicProfiles will be used. You must restart iTerm2 after modifying this setting.");
DEFINE_FLOAT(dynamicProfilesNotificationLatency, 0.1, SECTION_GENERAL @"Delay between detecting a change to dynamic profiles and acting on it.\nIf a lot of changes happen to the DynamicProfiles folder a longer delay will help coalesce filesystem events to reduce CPU usage.");
DEFINE_STRING(gitSearchPath, @"", SECTION_GENERAL @"$PATH used when running git for the status bar component.\nChange this to use a custom install of git. You must restart iTerm2 for a change here to take effect.");
DEFINE_FLOAT(gitTimeout, 4, SECTION_GENERAL @"Timeout in seconds when running git for the status bar component.");
DEFINE_BOOL(workAroundBigSurBug, NO, SECTION_GENERAL @"Work around Big Sur bug where a white line flashes at the top of the screen in full screen mode.");
DEFINE_STRING(preferredBaseDir, @"", SECTION_GENERAL @"Folder for config files. There must not be a space in the path.\nIf empty, then ~/.config/iterm2 will be the default location.");
DEFINE_INT(maximumNumberOfTriggerCommands, 16, SECTION_GENERAL @"Maximum number of trigger-launched commands that can run at once.\nIf too many “Run Command…” triggers fire their commands will be queued. You must restart iTerm2 for changes to this setting to take effect.");
DEFINE_INT(smartSelectionRadius, 2, SECTION_GENERAL @"Maximum number of lines before and after the click location to include in smart selection.");
DEFINE_FLOAT(alertTriggerRateLimit, 1, SECTION_GENERAL @"Rate limit for Alert triggers.\nIf the same trigger fires with less than this time interval (in seconds) between firings, it will be suppressed.")
DEFINE_FLOAT(userNotificationTriggerRateLimit, 0, SECTION_GENERAL @"Rate limit for Notification triggers.\nIf the same trigger fires with less than this time interval (in seconds) between firings, it will be suppressed.")
DEFINE_FLOAT(notificationOcclusionThreshold, 0.4, SECTION_GENERAL @"Foreground tabs will post user notifications if their window is partially hidden (for example, it is partially offscreen). This value, in 0 to 1, gives the fraction that must be occluded for a notification be posted.");
DEFINE_BOOL(silentUserNotifications, NO, SECTION_GENERAL @"System notifications should be silent.");

DEFINE_FLOAT(commandHistoryUsePower, 3, SECTION_GENERAL @"When sorting command history for auto command completion: how much should number of uses of a command contribute to its score? A higher score moves the command closer to the top of the list.\nUse 0 to ignore number of uses.");
DEFINE_FLOAT(commandHistoryAgePower, 1, SECTION_GENERAL @"When sorting command history for auto command completion: how much should the time-since-last-use of a command contribute to its score? A higher score moves the command closer to the top of the list.\nUse 0 to ignore time since last use.");
DEFINE_BOOL(performSQLiteIntegrityCheck, YES, SECTION_GENERAL @"Perform restorable state integrity checks?");
DEFINE_STRING(lastpassGroups, @"", SECTION_GENERAL @"Comma-separated list of LastPass groups for the password manager to look in for passwords.");
DEFINE_STRING(onePasswordAccount, @"", SECTION_GENERAL @"1Password account name.\nThis is used if you’ve enabled the 1Password integration in the password manager. Use `op account list` to get the list of accounts. This can be an account shorthand, sign-in address, account ID, or user ID.");
DEFINE_BOOL(excludeUtunFromNetworkUtilization, YES, SECTION_GENERAL @"Exclude utun interfaces from network utilization?\nThis is useful if you use a VPN and only want to see the traffic that goes over Wi-Fi or Ethernet.");
DEFINE_FLOAT(noSyncDownloadPrefsTimeout, 5.0, SECTION_GENERAL @"Timeout for downloading settings");

#pragma mark - Drawing

#define SECTION_DRAWING @"Drawing: "

DEFINE_BOOL(zippyTextDrawing, YES, SECTION_DRAWING @"Use zippy text drawing algorithm?\nThis draws non-ASCII text more quickly but with lower fidelity. This setting is ignored if ligatures are enabled in Prefs > Profiles > Text.");
DEFINE_BOOL(lowFiCombiningMarks, NO, SECTION_DRAWING @"Prefer speed to accuracy for characters with combining marks?");
DEFINE_BOOL(useAdaptiveFrameRate, YES, SECTION_DRAWING @"Use adaptive framerate.\nWhen throughput is low, the screen will update at 60 frames per second. When throughput is higher, it will drop to a configurable rate (15 fps by default).");
DEFINE_BOOL(disableAdaptiveFrameRateInInteractiveApps, YES, SECTION_DRAWING @"Disable adaptive framerate in interactive apps.\nTurn off adaptive frame rate while in alternate screen mode for more consistent refresh rate. This works even if alternate screen mode is disabled.");
DEFINE_FLOAT(slowFrameRate, 15.0, SECTION_DRAWING @"When adaptive framerate is enabled, refresh at this rate during high throughput conditions (FPS).\n Does not apply to Metal renderer.");
DEFINE_FLOAT(metalSlowFrameRate, 30.0, SECTION_DRAWING @"When adaptive framerate is enabled and using the Metal renderer, refresh at this rate during high throughput conditions (FPS).");
DEFINE_FLOAT(activeUpdateCadence, 60.0, SECTION_DRAWING @"Maximum frame rate (FPS) when adaptive framerate is disabled.\nNote: this is doubled on ARM Macs for displays that support at least 120hz. Modifications to this setting will not affect existing sessions.");
DEFINE_INT(adaptiveFrameRateThroughputThreshold, 10000, SECTION_DRAWING @"Throughput threshold for adaptive frame rate.\nIf more than this many bytes per second are received, use the lower frame rate of 30 fps.");
DEFINE_FLOAT(maximumFrameRate, 60.0, SECTION_DRAWING @"Frame rate (FPS) when adaptive framerate is enabled and throughput is low but not 0.");
DEFINE_BOOL(dwcLineCache, YES, SECTION_DRAWING @"Enable cache of double-width character locations?\nThis should improve performance. It is always on in nightly builds. You must restart iTerm2 for this setting to take effect.");
DEFINE_BOOL(useGCDUpdateTimer, YES, SECTION_DRAWING @"Use GCD-based update timer instead of NSTimer.\nThis should cause more regular screen updates. Restart iTerm2 after changing this setting.");
DEFINE_BOOL(drawOutlineAroundCursor, NO, SECTION_DRAWING @"Draw outline around underline and vertical bar cursors using background color.");
DEFINE_BOOL(disableCustomBoxDrawing, NO, SECTION_DRAWING @"Use your typeface’s box-drawing characters instead of iTerm2’s custom drawing code.\nYou must restart iTerm2 after changing this setting.");
DEFINE_INT(minimumWeightDifferenceForBoldFont, 4, SECTION_DRAWING @"Minimum weight difference between regular and bold font.\nThis affects selection of the bold version of a font. Font weights go from 0 to 9. If no font can be found that has a high enough weight then the regular font will be double-struck with a small offset.");
DEFINE_FLOAT(underlineCursorHeight, 2, SECTION_DRAWING @"Thickness of underline cursor.");
DEFINE_BOOL(preferSpeedToFullLigatureSupport, YES, SECTION_DRAWING @"Improves drawing performance at the expense of disallowing alphanumeric characters to belong to ligatures.");
DEFINE_BOOL(forceAntialiasingOnRetina, NO, SECTION_DRAWING @"Force text to be anti-aliased on Retina displays.\nEnable this to use non-AA text on non-retina displays, which sometimes looks better.");
DEFINE_BOOL(makeSomePowerlineSymbolsWide, YES, SECTION_DRAWING @"Draw certain Powerline symbols double-width?\nThis matches how most “nerd” fonts render them, but your favorite one might not do this. An example code point that is affected is U+E0B8.");

#if ENABLE_LOW_POWER_GPU_DETECTION
DEFINE_BOOL(useLowPowerGPUWhenUnplugged, NO, SECTION_DRAWING @"Metal renderer uses integrated GPU when not connected to power?\nFor this to be effective you must disable “Disable Metal renderer when not connected to power”.");
#endif

DEFINE_BOOL(underlineHyperlinks, YES, SECTION_DRAWING @"Underline OSC 8 hyperlinks");
DEFINE_BOOL(solidUnderlines, NO, SECTION_DRAWING @"Use solid underlines?\nWhen disabled, underlines break near text that would intersect them.");
DEFINE_BOOL(showMetalFPSmeter, NO, SECTION_DRAWING @"Show FPS meter\nRequires Metal renderer");
DEFINE_BOOL(hdrCursor, NO, SECTION_DRAWING @"HDR cursor\nExperimental. Half-baked. Probably don't use this.");
DEFINE_FLOAT(metalRedrawPeriod, 0.5, SECTION_DRAWING @"GPU renderer redraws at least this often, in seconds.\nThis is to work around a problem where the GPU renderer encounters a lot of latency when drawing for the first time after a short period of inactivity. Set this to a big number to render it ineffectual.");
DEFINE_BOOL(animateGraphStatusBarComponents, YES, SECTION_DRAWING @"Animate graph-based status bar components?\nTurn this off to reduce CPU/GPU usage in WindowServer.");
DEFINE_BOOL(disableTopRightIndicators, NO, SECTION_DRAWING @"Disable indicator icons that appear in the top right of a session?\nThis includes the following indicators: maximized pane, broadcast input, coprocess running, alert on next mark, output suppression, zoom, copy mode, and debug logging.");
DEFINE_STRING(nativeRenderingCSSLight, @"", SECTION_DRAWING @"Path to CSS file to customize native drawing (for light background colors).");
DEFINE_STRING(nativeRenderingCSSDark, @"", SECTION_DRAWING @"Path to CSS file to customize native drawing (for dark background colors).");
DEFINE_BOOL(supportPowerlineExtendedSymbols, YES, SECTION_DRAWING @"Include extended symbols when drawing Powerline natively.");

#pragma mark - Semantic History

#define SECTION_SEMANTIC_HISTORY @"Semantic History: "

DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, SECTION_SEMANTIC_HISTORY @"Ignore hard newlines for the purposes of locating URLs and file names for Semantic History.\nIf a hard newline occurs at the end of a line then ⌘-click will not see it all unless this setting is turned on. This is useful for some interactive applications. Turning this on will remove newlines from the \\3 and \\4 substitutions.");
// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'(（)）|[]", SECTION_SEMANTIC_HISTORY @"Non-alphanumeric characters considered part of a URL or file name for Semantic History.\nLetters and numbers are always considered part of the URL. These non-alphanumeric characters are used in addition for the purposes of figuring out where a URL begins and ends. You must restart iTerm2 for changes to this setting to take effect.");
DEFINE_STRING(URLCharacterSetExclusions, @"¬", SECTION_SEMANTIC_HISTORY @"Characters never considered part of a URL.\nThe characters in this string may never occur in a URL; when one is seen that delineates the beginning or end of a URL.");
DEFINE_INT(maxSemanticHistoryPrefixOrSuffix, 2000, SECTION_SEMANTIC_HISTORY @"Maximum number of bytes of text before and after click location to take into account.\nThis also limits the size of the \\3 and \\4 substitutions.");
DEFINE_STRING(pathsToIgnore, @"", SECTION_SEMANTIC_HISTORY @"Paths to ignore for Semantic History.\nSeparate paths with a comma. Any file under one of these paths will not be openable with Semantic History. It is wise to add network file systems to this list, since they can be very slow.");
DEFINE_BOOL(showYellowMarkForJobStoppedBySignal, YES, SECTION_SEMANTIC_HISTORY @"Use a yellow for a Shell Integration prompt mark when the job is stopped by a signal.");
DEFINE_BOOL(conservativeURLGuessing, NO, SECTION_SEMANTIC_HISTORY @"URLs must contain a scheme?\nEnable this to reduce the number of false positives that semantic history thinks are a URL");
DEFINE_BOOL(requireSlashInURLGuess, YES, SECTION_SEMANTIC_HISTORY @"Only consider a two+ part domain-name to be a URL if it also contains a slash.\nThis setting is used when guessing if a string is a URL for semantic history. When enabled, `example.com` would not be considered a URL but `example.com/` would be.")
DEFINE_STRING(trailingPunctuationMarks, @"!?…)].\"';:,", SECTION_SEMANTIC_HISTORY @"Characters to ignore at the end of a URL");
DEFINE_STRING(defaultURLScheme, @"https", SECTION_SEMANTIC_HISTORY @"Default URL scheme.\nThis is applied to hostnames that are not a single word.");
DEFINE_BOOL(restrictSemanticHistoryPrefixAndSuffixToLogicalWindow, YES, SECTION_SEMANTIC_HISTORY @"Respect soft boundaries for computing the prefix and suffix text passed to semantic history commands?\nDue to a long-standing bug this did not used to be respected. Soft boundaries were always respected for deciding what text was clicked on, but the prefix and suffix did not. If you have a semantic history command that depends on the bug, you can switch this off to get the pre-3.1.2 behavior.");
DEFINE_BOOL(enableSemanticHistoryOnNetworkMounts, NO, SECTION_SEMANTIC_HISTORY @"Enable semantic history for network-mounted filesystems?\nOnly enable this if you know your network-mounted filesystems are really fast and reliable. A slow filesystem may cause the entire iTerm2 app to hang.");
DEFINE_BOOL(prioritizeSmartSelectionActions, NO, SECTION_SEMANTIC_HISTORY @"Check smart selection actions before existing files on cmd-click?");

#pragma mark - Debugging

#define SECTION_DEBUGGING @"Debugging: "

DEFINE_BOOL(startDebugLoggingAutomatically, NO, SECTION_DEBUGGING @"Start debug logging automatically when iTerm2 is launched.");
DEFINE_BOOL(appendToExistingDebugLog, NO, SECTION_DEBUGGING @"Append to existing debug log rather than replacing it.");
DEFINE_BOOL(logDrawingPerformance, NO, SECTION_DEBUGGING @"Log stats about text drawing performance to console.\nUsed for performance testing.");
DEFINE_BOOL(logRestorableStateSize, NO, SECTION_DEBUGGING @"Log restorable state size info to /tmp/statesize.*.txt.");
DEFINE_BOOL(showBlockBoundaries, NO, SECTION_DEBUGGING @"Show line buffer block boundaries (issue 6207)");

#pragma mark - Session

#define SECTION_SESSION @"Session: "

DEFINE_BOOL(runJobsInServers, YES, SECTION_SESSION @"Enable session restoration.\nSession restoration runs jobs in separate processes. They will survive crashes, force quits, and upgrades.\nYou must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(bootstrapDaemon, YES, SECTION_SESSION @"Allow sessions to survive logging out and back in.\nThis breaks the “auth sufficient pam_tid.so” hack some people use to allow sudo to authenticate with Touch ID.");

DEFINE_BOOL(killJobsInServersOnQuit, YES, SECTION_SESSION @"User-initiated Quit (⌘Q) of iTerm2 will kill all running jobs.\nApplies only when session restoration is on.");
DEFINE_SETTABLE_BOOL(suppressRestartAnnouncement, SuppressRestartAnnouncement, NO, SECTION_SESSION @"Suppress the Restart Session offer.\nWhen a session terminates, it will offer to restart itself. Turn this on to suppress the offer permanently.");
DEFINE_BOOL(showSessionRestoredBanner, YES, SECTION_SESSION @"When restoring a session without restoring a running job, draw a banner saying “Session Contents Restored” below the restored contents.");
DEFINE_DEPRECATED_STRING(autoLogFormat,
                         @"\\(creationTimeString).\\(profileName).\\(termid).\\(iterm2.pid).\\(autoLogId).log",
                         SECTION_SESSION @"Format for automatic session log filenames.\nSee the Badges documentation for supported substitutions.");
DEFINE_BOOL(autologAppends, YES, SECTION_SESSION @"Automatic session logging appends to existing files.\nWhen set to No, the file will be overwritten instead.");
DEFINE_BOOL(focusNewSplitPaneWithFocusFollowsMouse, YES, SECTION_SESSION @"When focus follows mouse is enabled, should new split panes automatically be focused?");
DEFINE_BOOL(NoSyncSuppressRestartSessionConfirmationAlert, NO, SECTION_SESSION @"Suppress restart session confirmation alert.\nDon't ask for a confirmation when manually restarting a session.");
DEFINE_BOOL(showAutomaticProfileSwitchingBanner, YES, SECTION_SESSION @"Show a “Switched to profile” message when Automatic Profile Switching activates.");
DEFINE_BOOL(autoLockSessionNameOnEdit, YES, SECTION_SESSION @"Auto-lock session name after editing it.");
DEFINE_FLOAT(timeoutForDaemonAttachment, 10, SECTION_SESSION @"How long to wait when trying to attach to an iTerm daemon at startup when restoring windows (in seconds)?");
DEFINE_BOOL(logTimestampsWithPlainText, YES, SECTION_SESSION @"When logging plain text, include timestamps for each line?");
DEFINE_STRING(composerClearSequence, @"0x15 0x0b", SECTION_SESSION @"Hex codes to send to clear the command line when entering the composer.\n0x15 is ^U, 0x0b is ^K.");
DEFINE_BOOL(alwaysUseStatusBarComposer, NO, SECTION_SESSION @"Temporarily add a composer to the status bar instead of opening the large composer view when a status bar is present.");

#pragma mark - Windows

#define SECTION_WINDOWS @"Windows: "

DEFINE_BOOL(openFileInNewWindows, NO, SECTION_WINDOWS @"Open files in new windows, not new tabs.\nThis affects shell scripts opened from Finder, for example.");
DEFINE_BOOL(rememberWindowPositions, YES, SECTION_WINDOWS @"Remember window locations even after the windows are closed.\nWhen a new window is opened, one of the recorded locations is used.");
DEFINE_BOOL(disableWindowSizeSnap, NO, SECTION_WINDOWS @"Terminal windows resize smoothly.\nDisables snapping to character grid. Holding Control will temporarily disable snap-to-grid.");
DEFINE_BOOL(profilesWindowJoinsActiveSpace, NO, SECTION_WINDOWS @"If the Profiles window is open, it always moves to join the active Space.\nYou must restart iTerm2 for a change in this setting to take effect.");
DEFINE_BOOL(darkThemeHasBlackTitlebar, YES, SECTION_WINDOWS @"Dark themes give terminal windows black title bars by default.");
DEFINE_BOOL(fontChangeAffectsBroadcastingSessions, NO, SECTION_WINDOWS @"Should growing or shrinking the font in a session that's broadcasting input affect all session that broadcast input?\nThis only applies to changing the font size with Make Text Bigger, Make Text Normal Size, and Make Text Smaller");
DEFINE_BOOL(serializeOpeningMultipleFullScreenWindows, YES, SECTION_WINDOWS @"When opening multiple fullscreen windows, enter fullscreen one window at a time.");
DEFINE_BOOL(trackingRunloopForLiveResize, YES, SECTION_WINDOWS @"Use a tracking runloop for live resizing.\nThis allows the terminal to redraw during a resizing drag.");
DEFINE_FLOAT(invalidateShadowTimesPerSecond, 15, SECTION_WINDOWS @"How many times per second to update the shadow of transparent windows to prevent ghosting.\nThis works around a macOS Mojave bug that leaves a ghost of past window contents behind in transparent windows. It hurts performance to do it frequently, especially in large windows. Set to 0 to disable.");
DEFINE_BOOL(disableWindowShadowWhenTransparencyOnMojave, YES, SECTION_WINDOWS @"Disable the window shadow on Mojave when the window has a transparent session to improve performance.");
DEFINE_BOOL(disableWindowShadowWhenTransparencyPreMojave, YES, SECTION_WINDOWS @"Disable the window shadow on High Sierra and earlier when the window has a transparent session to prevent text shadows.");
DEFINE_BOOL(restoreWindowsWithinScreens, YES, SECTION_WINDOWS @"When restoring a window arrangement, ensure windows are entirely within the bounds of the current displays.")
DEFINE_FLOAT(extraSpaceBeforeCompactTopTabBar, 0, SECTION_WINDOWS @"Amount of extra space (in points) between stoplight buttons and inline tab bar.\nThis only takes effect for the Compact and Minimal themes when the tab bar is visible and located at the top of the window.");
DEFINE_BOOL(workAroundMultiDisplayOSBug, YES, SECTION_WINDOWS @"Work around a macOS bug where the OS moves windows to the first display for no good reason.");
DEFINE_BOOL(disableDocumentedEditedIndicator, NO, SECTION_WINDOWS @"Disable documented edited indicator (black dot in close button)");
DEFINE_BOOL(showWindowTitleWhenTabBarInvisible, YES, SECTION_WINDOWS @"Show window title when the tab bar is not visible?\nWhen disabled, the tab's title will be shown where the window title would normally go.");
DEFINE_BOOL(squareWindowCorners, NO, SECTION_WINDOWS @"Windows have square corners.\nThis is only for users who have already hacked macOS to remove rounded corners. You must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(useShortcutAccessoryViewController, YES, SECTION_WINDOWS @"Show window number in titlebar accessory?");
DEFINE_BOOL(includeShortcutInWindowsMenu, YES, SECTION_WINDOWS @"Include keyboard shortcut for windows in Window menu?");
DEFINE_FLOAT(toolbeltFontSize, 0, SECTION_WINDOWS @"Toolbelt font size in points.\nSet to 0 to use the system default. Changing this setting does not affect existing windows.");
DEFINE_STRING(toolbeltFont, @"Menlo", SECTION_WINDOWS @"Toolbelt font family name");
DEFINE_FLOAT(fakeNotchHeight, 0, SECTION_WINDOWS @"Simulated notch height");
DEFINE_STRING(splitPaneColor, @"", SECTION_WINDOWS @"Custom color for split pane dividers. Leave empty to use default color.\nThis should be an HTML-style color, like #aabbcc.");
DEFINE_BOOL(bordersOnlyInLightMode, YES, SECTION_WINDOWS @"Opaque windows have a border only in light mode.\nThis setting modifies “Show border around windows”. Borders in opaque windows in dark mode are ugly and the OS draws one that is pretty serviceable. Enable this if you have trouble seeing them.")
DEFINE_BOOL(allowLiveResize, YES, SECTION_WINDOWS @"Allow window resizing by dragging edges and corners?");

#pragma mark tmux

#define SECTION_TMUX @"Tmux Integration: "

DEFINE_BOOL(noSyncNewWindowOrTabFromTmuxOpensTmux, NO, SECTION_TMUX @"Suppress alert asking what kind of tab/window to open in tmux integration. Affects both windows and tabs.\nThis setting predates having separate settings for windows vs tabs. If it is off, then the two new settings will take effect.");
DEFINE_BOOL(noSyncNewWindowFromTmuxOpensTmux, NO, SECTION_TMUX @"Suppress alert asking what kind of window to open in tmux integration.\nNOTE: This only takes effect if the now-deprecated “Suppress alert asking what kind of tab/window to open in tmux integration” setting is off.");
DEFINE_BOOL(noSyncNewTabFromTmuxOpensTmux, NO, SECTION_TMUX @"Suppress alert asking what kind of tab to open in tmux integration.\nNOTE: This only takes effect if the now-deprecated “Suppress alert asking what kind of tab/window to open in tmux integration” setting is off.");
DEFINE_BOOL(tolerateUnrecognizedTmuxCommands, NO, SECTION_TMUX @"Tolerate unrecognized commands from server.\nIf enabled, an unknown command from tmux (such as output from ssh or wall) will end the session. Turning this off helps detect dead ssh sessions.");
DEFINE_BOOL(useBlackFillerColorForTmuxInFullScreen, NO, SECTION_TMUX @"Use black for filler area in tmux windows in full screen.");
DEFINE_SETTABLE_OPTIONAL_BOOL(tmuxWindowsShouldCloseAfterDetach, TmuxWindowsShouldCloseAfterDetach, nil, SECTION_TMUX @"Close tmux windows after detaching?\nThis only takes effect when “Prefs > Profiles > Session > After a session ends” is set to “No Action”.");
DEFINE_BOOL(disableTmuxWindowPositionRestoration, NO, SECTION_TMUX @"Disable window position restoration in tmux integration.");
DEFINE_BOOL(disableTmuxWindowResizing, YES, SECTION_TMUX @"Don't automatically resize tmux windows");
DEFINE_BOOL(anonymousTmuxWindowsOpenInCurrentWindow, YES, SECTION_TMUX @"Should new tmux windows not created by iTerm2 open in the current window?\nIf set to No, they will open in new windows.");
DEFINE_BOOL(pollForTmuxForegroundJob, NO, SECTION_TMUX @"Poll for foreground job name in tmux integration with tmux < 3.2?\nThis enables tab icons but can cause a lot of background traffic. This has no effect in tmux 3.2 and later, where polling is unnecessary.");
DEFINE_STRING(tmuxTitlePrefix, @"↣ ", SECTION_TMUX @"Insert this string at the start of tab and window titles to indicate tmux integration.");
DEFINE_BOOL(tmuxIncludeClientNameInWindowTitle, YES, SECTION_TMUX @"When using tmux integration, should the tmux client name (typically the name of the attaching session or the host name) appear in brackets in the window title?");

#define SECTION_SSH @"SSH Integration: "

DEFINE_BOOL(enableSSHFileProvider, NO, SECTION_SSH @"Enable cloud filesystem for SSH integration.\nThis feature is still in development and doesn't work well.");

#pragma mark Warnings

#define SECTION_WARNINGS @"Warnings: "

DEFINE_BOOL(neverWarnAboutMeta, NO, SECTION_WARNINGS @"Suppress a warning when ⌥ Key Acts as Meta is enabled in Prefs>Profiles>Keys.");
DEFINE_BOOL(neverWarnAboutSpaces, NO, SECTION_WARNINGS @"Suppress a warning about how to configure Spaces when setting a window's Space.");
DEFINE_BOOL(neverWarnAboutOverrides, NO, SECTION_WARNINGS @"Suppress a warning about a change to a Profile key setting that overrides a global setting.");
DEFINE_BOOL(neverWarnAboutPossibleOverrides, NO, SECTION_WARNINGS @"Suppress a warning about a change to a global key that's overridden by a Profile.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForUrl, NO, SECTION_WARNINGS @"Suppress changed-setting warning when prefs are loaded from a URL.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForFile, NO, SECTION_WARNINGS @"Suppress changed-setting warning when prefs are loaded from a custom folder.");
DEFINE_BOOL(noSyncSuppressAnnyoingBellOffer, NO, SECTION_WARNINGS @"Suppress offer to silence bell when it rings too much.");

DEFINE_BOOL(suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline, NO, SECTION_WARNINGS @"Suppress warning about multi-line paste when pasting a single line ending with a newline.\nThis suppresses all multi-line paste warnings when a single line is being pasted.");
DEFINE_BOOL(suppressMultilinePasteWarningWhenNotAtShellPrompt, NO, SECTION_WARNINGS @"Suppress warning about multi-line paste when not at prompt.\nRequires Shell Integration to be installed.");
DEFINE_BOOL(noSyncSuppressBroadcastInputWarning, NO, SECTION_WARNINGS @"Suppress warning about broadcasting input.");
DEFINE_BOOL(noSyncSuppressCaptureOutputRequiresShellIntegrationWarning, NO,
            SECTION_WARNINGS @"Suppress warning “Shell Integration is required for Capture Output.”");
DEFINE_BOOL(noSyncSuppressCaptureOutputToolNotVisibleWarning, NO,
            SECTION_WARNINGS @"Suppress warning that the Captured Output tool is not visible.");
DEFINE_BOOL(closingTmuxWindowKillsTmuxWindows, NO, SECTION_WARNINGS @"Suppress kill/hide dialog when closing a tmux window.");
DEFINE_BOOL(closingTmuxTabKillsTmuxWindows, NO, SECTION_WARNINGS @"Suppress kill/hide dialog when closing a tmux tab.");
DEFINE_BOOL(aboutToPasteTabsWithCancel, NO, SECTION_WARNINGS @"Suppress warning when pasting tabs with offer to convert them to spaces or perform advanced paste.");
DEFINE_FLOAT(shortLivedSessionDuration, 3, SECTION_WARNINGS @"Warn about short-lived sessions that live less than this many seconds.");

DEFINE_SETTABLE_BOOL(noSyncDoNotWarnBeforeMultilinePaste, NoSyncDoNotWarnBeforeMultilinePaste, NO, SECTION_WARNINGS @"Suppress warning about multi-line pastes (or a single line ending in a newline).\nThis applies whether you are at the shell prompt or not, provided two or more lines are being pasted.");
DEFINE_SETTABLE_BOOL(noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt, NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt, NO, SECTION_WARNINGS @"Suppress warning about pasting a single line ending in a newline when at the shell prompt.\nThis requires Shell Integration to be installed.");

DEFINE_BOOL(noSyncReplaceProfileWarning, NO, SECTION_WARNINGS @"Suppress warning about copying a session's settings over a Profile");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffFocusReportingOnHostChange, nil, SECTION_WARNINGS @"Always turn off focus reporting when host changes?");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffMouseReportingOnHostChange, nil, SECTION_WARNINGS @"Always turn off mouse reporting when host changes?");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffBracketedPasteOnHostChange, nil, SECTION_WARNINGS @"Always turn off paste bracketing when host changes?");
DEFINE_SETTABLE_BOOL(noSyncSuppressClipboardAccessDeniedWarning, NoSyncSuppressClipboardAccessDeniedWarning, NO, SECTION_WARNINGS @"Suppress the notification that the terminal attempted to access the clipboard but it was denied?");
DEFINE_SETTABLE_BOOL(noSyncSuppressMissingProfileInArrangementWarning, NoSyncSuppressMissingProfileInArrangementWarning, NO, SECTION_WARNINGS @"Suppress the notification that a restored session’s profile no longer exists?");
DEFINE_SETTABLE_BOOL(noSyncSuppressBadPWDInArrangementWarning,
                     NoSyncSuppressBadPWDInArrangementWarning, NO, SECTION_WARNINGS @"Suppress the notification that a saved arrangement has a bad initial working directory.");
DEFINE_SETTABLE_BOOL(noSyncNeverAskAboutMouseReportingFrustration, NoSyncNeverAskAboutMouseReportingFrustration, NO, SECTION_WARNINGS @"Suppress the notification asking if you want to disable mouse reporting that is shown after a drag followed by Cmd-C when mouse reporting is on?");
DEFINE_SETTABLE_BOOL(noSyncDontWarnAboutTmuxPause, NoSyncDontWarnAboutTmuxPause, NO, SECTION_WARNINGS @"Suppress announcement that tmux will pause a session.");
DEFINE_OPTIONAL_BOOL(noSyncClearAllBroadcast, nil, SECTION_WARNINGS @"Send Clear Session to all broadcasted-to sessions?");
DEFINE_BOOL(noSyncSuppressSendSignal, NO, SECTION_WARNINGS @"Suppress warning about sending a signal to terminate a job.\nThis is used in the process tree, which you can find the toolbelt or by clicking the Jobs status bar component.");
DEFINE_BOOL(noSyncConfirmRemoveAnnotation, NO, SECTION_WARNINGS @"Suppress confirmation to remove annotation?");
DEFINE_SETTABLE_BOOL(noSyncDisableOpenURL, NoSyncDisableOpenURL, NO, SECTION_WARNINGS @"Disable control sequence to open URLs?");

#pragma mark Pasteboard

#define SECTION_PASTEBOARD @"Pasteboard: "

DEFINE_BOOL(trimWhitespaceOnCopy, YES, SECTION_PASTEBOARD @"Trim whitespace when copying to pasteboard.");
DEFINE_INT(quickPasteBytesPerCall, 667, SECTION_PASTEBOARD @"Number of bytes to paste in each chunk when pasting normally.");
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01530456, SECTION_PASTEBOARD @"Delay in seconds between chunks when pasting normally.")
DEFINE_INT(slowPasteBytesPerCall, 16, SECTION_PASTEBOARD @"Number of bytes to paste in each chunk when pasting slowly.");
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, SECTION_PASTEBOARD @"Delay in seconds between chunks when pasting slowly");
DEFINE_BOOL(copyWithStylesByDefault, NO, SECTION_PASTEBOARD @"Copy to pasteboard on selection includes color and font style.");
DEFINE_BOOL(copyBackgroundColor, YES, SECTION_PASTEBOARD @"Exclude the default background color when text is copied with color and font style?\nWhen off, the default background color will be left unset. Non-default background colors will remain.");
DEFINE_INT(pasteHistoryMaxOptions, 20, SECTION_PASTEBOARD @"Number of entries to save in Paste History.\n");
DEFINE_BOOL(disallowCopyEmptyString, NO, SECTION_PASTEBOARD @"Disallow copying empty string to pasteboard.\nIf enabled, selecting an empty string (or all whitespace if trimming is enabled) will not erase the contents of the pasteboard.");
DEFINE_BOOL(typingClearsSelection, YES, SECTION_PASTEBOARD @"Pressing a key will remove the selection.");
DEFINE_BOOL(pastingClearsSelection, YES, SECTION_PASTEBOARD @"Pasting text will remove the selection.");
DEFINE_SETTABLE_BOOL(promptForPasteWhenNotAtPrompt, PromptForPasteWhenNotAtPrompt, NO, SECTION_PASTEBOARD @"Warn before pasting when not at shell prompt?");
DEFINE_BOOL(excludeBackgroundColorsFromCopiedStyle, NO, SECTION_PASTEBOARD @"Exclude all background colors when text is copied with color and font style?\nThis includes both the default background color and non-default background colors.");
DEFINE_BOOL(includePasteHistoryInAdvancedPaste, YES, SECTION_PASTEBOARD @"Include paste history in the advanced paste menu.");
DEFINE_INT(alwaysWarnBeforePastingOverSize, -1, SECTION_PASTEBOARD @"When pasting more than this many characters, require confirmation.\nSet to -1 to disable warning.\nCharacters are counted in UTF-16.");
DEFINE_BOOL(saveToPasteHistoryWhenSecureInputEnabled, NO, SECTION_PASTEBOARD @"Save to paste history when secure keyboard input is enabled?");

#pragma mark - Tip of the day

#define SECTION_TOTD @"Tip of the Day: "

DEFINE_BOOL(noSyncTipsDisabled, NO, SECTION_TOTD @"Disable the Tip of the Day?");
DEFINE_SETTABLE_FLOAT(timeBetweenTips, TimeBetweenTips, 24 * 60 * 60, SECTION_TOTD @"Time between tips (in seconds)");

#pragma mark - Badge

#define SECTION_BADGE @"Badge: "

DEFINE_STRING(badgeFont, @"Helvetica", SECTION_BADGE @"Font to use for the badge.");
DEFINE_BOOL(badgeFontIsBold, YES, SECTION_BADGE @"Should the badge render in bold type?");
DEFINE_FLOAT(badgeMaxWidthFraction, 0.5, SECTION_BADGE @"Maximum width of the badge\nAs a fraction of the width of the terminal, between 0 and 1.0. This is the default value if a profile does not have a setting.");
DEFINE_FLOAT(badgeMaxHeightFraction, 0.2, SECTION_BADGE @"Maximum height of the badge\nAs a fraction of the height of the terminal, between 0 and 1.0. This is the default value if a profile does not have a setting.");
DEFINE_INT(badgeRightMargin, 10, SECTION_BADGE @"Default value for right margin for the badge\nHow much space to leave between the right edge of the badge and the right edge of the terminal. Can be overridden by a profile setting. This is the default value if a profile does not have a setting.");
DEFINE_INT(badgeTopMargin, 10, SECTION_BADGE @"Default value for the top margin for the badge\nHow much space to leave between the top edge of the badge and the top edge of the terminal. Can be overridden by a profile setting. This is the default value if a profile does not have a setting.");

#pragma mark - Experimental Features

#define SECTION_EXPERIMENTAL @"Experimental Features: "

// Experimental features I'm afraid to turn on right now, but want to in the future:
DEFINE_BOOL(killSessionsOnLogout, NO, SECTION_EXPERIMENTAL @"Kill sessions on logout.\nA possible fix for issue 4147.");
DEFINE_BOOL(useExperimentalFontMetrics, NO, SECTION_EXPERIMENTAL @"Use a more theoretically correct technique to measure line height.\nYou must restart iTerm2 or adjust a session's font size for this change to take effect.");
DEFINE_BOOL(fastForegroundJobUpdates, YES, SECTION_EXPERIMENTAL @"Enable low-latency updates of the current foreground job");

// Experiments currently under test
DEFINE_BOOL(tmuxVariableWindowSizesSupported, YES, SECTION_EXPERIMENTAL @"Allow variable window sizes in tmux integration.\nRequres tmux version 2.9 or later.");
DEFINE_BOOL(aggressiveBaseCharacterDetection, YES, SECTION_EXPERIMENTAL @"Detect base unicode characters with lookup table.\nApple's algorithm for segmenting composed characters makes bad choices, such as for Tamil. Enable this to reduce text overlapping.");
DEFINE_BOOL(escapeWithQuotes, NO, SECTION_EXPERIMENTAL @"Escape file names with single quotes instead of backslashes.\nThis is intended for users of xonsh, which does not accept backslash escaping.");
DEFINE_STRING(fontsForGenerousRounding, @"consolas", SECTION_EXPERIMENTAL @"List of fonts to use alternate rounding algorithm for line height calculation.\nThis fixes consolas and emulates Terminal.app’s behavior on macOS 10.15. This is a comma-delimited list of font family substrings.");

// Experimental features that are mostly dead:
// This causes problems like issue 6052, where repeats cause the IME to swallow subsequent keypresses.
DEFINE_BOOL(experimentalKeyHandling, NO, SECTION_EXPERIMENTAL @"Improved support for input method editors like AquaSKK.");
// This is just a bad idea because of the latency it adds. It was also maybe related to crashes, but I never did figure it out.
DEFINE_BOOL(disableMetalWhenIdle, NO, SECTION_EXPERIMENTAL @"Disable metal renderer when idle to save CPU utilization?\nRequires Metal renderer");
// This never proved itself.
DEFINE_BOOL(metalDeferCurrentDrawable, NO, SECTION_EXPERIMENTAL @"Defer invoking currentDrawable.\nThis may improve overall performance at the cost of a lower frame rate.");
DEFINE_BOOL(dismemberScrollView, NO, SECTION_EXPERIMENTAL @"Dismember scroll view for better GPU performance?\nThis enables a dangerous hack that might improve drawing performance on macOS 10.14 only.");

// Experimental features that have graduated:
DEFINE_BOOL(supportREPCode, YES, SECTION_EXPERIMENTAL @"Enable support for REP (Repeat previous character) escape sequence?");
DEFINE_BOOL(proportionalScrollWheelReporting, YES, SECTION_EXPERIMENTAL @"Report multiple mouse scroll events when scrolling quickly?");
DEFINE_BOOL(useModernScrollWheelAccumulator, YES, SECTION_EXPERIMENTAL @"Use modern scroll wheel accumulator.\nThis should support wheel mice better and feel more natural.");
DEFINE_BOOL(resetSGROnPrompt, YES, SECTION_EXPERIMENTAL @"Reset colors at shell prompt?\nUses shell integration to detect a shell prompt and, if enabled, resets colors to their defaults.");
DEFINE_BOOL(retinaInlineImages, YES, SECTION_EXPERIMENTAL @"Show inline images at Retina resolution.");
DEFINE_BOOL(throttleMetalConcurrentFrames, YES, SECTION_EXPERIMENTAL @"Reduce number of frames in flight when GPU can't produce drawables quickly.");
DEFINE_BOOL(sshURLsSupportPath, YES, SECTION_EXPERIMENTAL @"SSH URLs respect the path.\nThey run the command: ssh -t \"cd $$PATH$$; exec \\$SHELL -l\"");
DEFINE_BOOL(useDivorcedProfileToSplit, YES, SECTION_EXPERIMENTAL @"When splitting a pane, use the profile with local modifications, not the backing profile.");
DEFINE_BOOL(synergyModifierRemappingEnabled, YES, SECTION_EXPERIMENTAL @"Support modifier remapping for keystrokes originated by Synergy.");
DEFINE_BOOL(shouldSetLCTerminal, YES, SECTION_EXPERIMENTAL @"Set LC_TERMINAL=iTerm2.\nopenssh and mosh pass this to hosts you connect to. It communicates the current terminal emulator. This is useful for enabling terminal emulator-specific features.");
DEFINE_BOOL(clearBellIconAggressively, YES, SECTION_EXPERIMENTAL @"Clear bell icon when a session becomes active.\nWhen off, you must type in the session to clear the bell icon.");
DEFINE_BOOL(workAroundNumericKeypadBug, YES, SECTION_EXPERIMENTAL @"Treat the equals sign on the numeric keypad as a key on the numeric keypad.\nFor mysterious reasons, macOS does not treat this key as belonging to the numeric keypad. Enable this setting to work around the bug.");
DEFINE_BOOL(enableCharacterAccentMenu, NO, SECTION_EXPERIMENTAL @"Enable character accent menu.\nThis disables the ordinary key repeat behavior for press-and-hold. You must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(accelerateUploads, YES, SECTION_EXPERIMENTAL @"Make uploads with it2ul really fast.");
DEFINE_BOOL(multiserver, YES, SECTION_EXPERIMENTAL @"Enable multi-server daemon.\nA new implementation of session restoration that combines daemon processes.");
DEFINE_BOOL(useRestorableStateController, YES, SECTION_EXPERIMENTAL @"Enable restorable state controller?\nThis makes window restoration more reliable.");
DEFINE_BOOL(fixMouseWheel, YES, SECTION_EXPERIMENTAL @"Mouse wheel always scrolls when scroll bars are visible");
DEFINE_BOOL(oscColorReport16Bits, YES, SECTION_EXPERIMENTAL @"Report 16-bit color values to OSC 4 and 10 through 19.\nWorks around a bug in older vim where they could not properly parse 8-bit values.");
DEFINE_BOOL(showLocationsInScrollbar, YES, SECTION_EXPERIMENTAL @"Show search result and prompt locations in scroll bar.\nChanging this setting will not affect existing sessions until you restart.");
DEFINE_BOOL(showMarksInScrollbar, YES, SECTION_EXPERIMENTAL @"Show prompt locations in scroll bar?\nChanging this setting will not affect existing sessions until you restart. You must also enable “Show search result and prompt locations in scroll bar” for this to take effect.");
DEFINE_BOOL(allowTabbarInTitlebarAccessoryBigSur, NO, SECTION_EXPERIMENTAL @"Make the tab bar a titlebar accessory view in Big Sur?");
DEFINE_BOOL(storeStateInSqlite, YES, SECTION_EXPERIMENTAL @"Store window restoration state in SQLite");
DEFINE_BOOL(useNewContentFormat, YES, SECTION_EXPERIMENTAL @"Save unlimited amount of window contents.\nThis is going to be slow unless you enable SQLite-based window restoration too.");
DEFINE_BOOL(vs16Supported, NO, SECTION_EXPERIMENTAL @"Support variation selector 16 making emoji fullwidth in all modes?");
DEFINE_BOOL(vs16SupportedInPrimaryScreen, YES, SECTION_EXPERIMENTAL @"Support variation selector 16 making emoji fullwidth outside of alternate screen mode?");
DEFINE_BOOL(fastTrackpad, YES, SECTION_EXPERIMENTAL @"Trackpad scrolls fast?\nSet to No for legacy scrolling speed.");
DEFINE_BOOL(supportDecsetMetaSendsEscape, YES_IF_BETA_ELSE_NO, SECTION_EXPERIMENTAL @"Support DECSET 1036?\nThis allows apps in the terminal to control whether the option key sends esc+ or acts like a regular option key.");
DEFINE_BOOL(concurrentMutation, NO, SECTION_EXPERIMENTAL @"Mutate session state in a separate thread.");
DEFINE_BOOL(fastTriggerRegexes, YES, SECTION_EXPERIMENTAL @"Fast regular expression evaluation for triggers.\nThis is experimental because it could potentially change how regular expressions are interpreted.");
DEFINE_BOOL(postFakeFlagsChangedEvents, NO, SECTION_EXPERIMENTAL @"Post fake flags-changed events when remapping modifiers with an event tap.\nThis is an attempt to work around incompatibilities with AltTab in issue 10220.");
DEFINE_BOOL(fullWidthFlags, YES, SECTION_EXPERIMENTAL @"Flag emoji render full-width");
DEFINE_INT(aiResponseMaxTokens, 1000, SECTION_EXPERIMENTAL @"Maximum tokens for OpenAI to use in its response");
DEFINE_BOOL(addUtilitiesToPATH, YES, SECTION_EXPERIMENTAL @"Add path to iTerm2 utilities to $PATH for new sessions?");
DEFINE_STRING(aitermURL, @"https://api.openai.com/v1/completions", SECTION_EXPERIMENTAL @"URL for AI API.\nA ChatGPT API endpoint should be here. Note that this URL is only used if the model name does not begin with `gpt-` because those models used an older API.");
DEFINE_BOOL(autoSearch, NO, SECTION_EXPERIMENTAL @"Automatically search for selected text after making a selection?");
DEFINE_BOOL(smartLoggingWithAutoComposer, NO, SECTION_EXPERIMENTAL @"Enable more compact logging when using auto composer?\nThis will avoid logging raw data in your prompt and your interactions with it. Instead, the prompt is logged once in plain text and the command is logged when sent.");
DEFINE_BOOL(disclaimChildren, NO, SECTION_EXPERIMENTAL @"Disclaim ownership of children.\nBy enabling this, when launching a Cocoa app from a terminal window TCC should attribute ownership to the app, not iTerm2, for permissions. In order for changes to this setting to take effect, you must kill iTermServer.");
DEFINE_BOOL(restoreKeyModeAutomaticallyOnHostChange, YES, SECTION_EXPERIMENTAL @"Automatically restore keyboard mode when an ssh session ends?");
DEFINE_BOOL(useSSHIntegrationForURLOpening, NO, SECTION_EXPERIMENTAL @"Use SSH integration when opening an ssh: URL");

#pragma mark - Scripting
#define SECTION_SCRIPTING @"Scripting: "

DEFINE_STRING(pythonRuntimeDownloadURL, @"https://iterm2.com/downloads/pyenv/manifest.json", SECTION_SCRIPTING @"URL to check for new versions of the Python scripting runtime.");
DEFINE_STRING(pythonRuntimeBetaDownloadURL, @"https://iterm2.com/downloads/pyenv/betamanifest.json", SECTION_SCRIPTING @"URL to check for new Beta versions of the Python scripting runtime.");
DEFINE_BOOL(laxNilPolicyInInterpolatedStrings, YES, SECTION_SCRIPTING @"Should references to undefined variables in interpolated strings be converted to empty string?\nWhen enabled, an expression in an interpolated string that references an undefined variable will be treated as an empty string. For example, “\\(bogus)”. References to undefined variables as arguments to function calls, such as “\\(f(bogus))”, are still errors.");
DEFINE_SETTABLE_BOOL(setCookie, SetCookie, NO, SECTION_SCRIPTING @"Set ITERM2_COOKIE environment variable, allowing Python scripts to be launched without confirmation?\nThis will only affect sessions created after changing this setting.");

+ (void)initialize {
    if (self == [iTermAdvancedSettingsModel self]) {
        static iTermUserDefaultsObserver *observer;
        observer = [[iTermUserDefaultsObserver alloc] init];
        [self enumerateMethods:^(Method method, SEL selector) {
            NSString *name = NSStringFromSelector(selector);
            if ([name hasPrefix:@"load_"]) {
                NSString *(*impl)(id, SEL) = (NSString *(*)(id, SEL))method_getImplementation(method);
                NSString *identifier = impl(self, selector);

                [observer observeKey:identifier block:^{
                    impl(self, selector);
                    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAdvancedSettingsDidChange object:nil];
                }];
            }
        }];
        [self updateSettingsForUnitTestsIfNeeded];
    }
}

+ (void)updateSettingsForUnitTestsIfNeeded {
    if ([NSApp isRunningUnitTests]) {
        sAdvancedSetting_runJobsInServers = @NO;
    }
}

+ (void)loadAdvancedSettingsFromUserDefaults {
    [self enumerateMethods:^(Method method, SEL selector) {
        NSString *name = NSStringFromSelector(selector);
        if ([name hasPrefix:@"load_"]) {
            NSString *(*impl)(id, SEL) = (NSString *(*)(id, SEL))method_getImplementation(method);
            impl(self, selector);
        }
    }];
    [self updateSettingsForUnitTestsIfNeeded];
}

@end
