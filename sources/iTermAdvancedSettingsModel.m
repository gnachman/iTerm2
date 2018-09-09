//
//  iTermAdvancedSettingsModel.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Foundation/Foundation.h>

#import "iTermAdvancedSettingsModel.h"
#import "NSApplication+iTerm.h"
#import "NSStringITerm.h"
#import <objc/runtime.h>

static char iTermAdvancedSettingsModelKVOKey;

@interface iTermAdvancedSettingsModelChangeObserver: NSObject
- (void)observeKey:(NSString *)key block:(void (^)(void))block;
@end

@implementation iTermAdvancedSettingsModelChangeObserver {
    NSMutableDictionary<NSString *, void (^)(void)> *_blocks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _blocks = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)observeKey:(NSString *)key block:(void (^)(void))block {
    _blocks[key] = [block copy];
    [[NSUserDefaults standardUserDefaults] addObserver:self
                                            forKeyPath:key
                                               options:NSKeyValueObservingOptionNew
                                               context:(void *)&iTermAdvancedSettingsModelKVOKey];
}

// This is called when user defaults are changed anywhere.
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    if (context == &iTermAdvancedSettingsModelKVOKey) {
        void (^block)(void) = _blocks[keyPath];
        if (block) {
            block();
        }
    }
}
@end


NSString *const kAdvancedSettingIdentifier = @"kAdvancedSettingIdentifier";
NSString *const kAdvancedSettingType = @"kAdvancedSettingType";
NSString *const kAdvancedSettingDefaultValue = @"kAdvancedSettingDefaultValue";
NSString *const kAdvancedSettingDescription = @"kAdvancedSettingDescription";

NSString *const iTermAdvancedSettingsDidChange = @"iTermAdvancedSettingsDidChange";

static inline BOOL iTermAdvancedSettingsModelTransformBool(id object) {
    return [object boolValue];
}

static inline id iTermAdvancedSettingsModelInverseTransformBool(BOOL value) {
    return @(value);
}

static inline BOOL *iTermAdvancedSettingsModelTransformOptionalBool(id object) {
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

static inline id iTermAdvancedSettingsModelInverseTransformOptionalBool(BOOL *value) {
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

static inline int iTermAdvancedSettingsModelTransformNonnegativeInt(id object) {
    int value = [object intValue];
    return MAX(0, value);
}

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
// type: The iTermAdvancedSettingTyep enum value
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
    sAdvancedSetting_##name = [[NSUserDefaults standardUserDefaults] objectForKey:key] ?: inverseTransformation(default); \
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
    [[NSNotificationCenter defaultCenter] postNotificationName:iTermAdvancedSettingsDidChange \
                                                        object:nil]; \
}

#define DEFINE_BOOL(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, BOOL, kiTermAdvancedSettingTypeBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformBool, iTermAdvancedSettingsModelInverseTransformBool)

#define DEFINE_SETTABLE_BOOL(name, capitalizedName, theDefault, theDescription) \
DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, BOOL, kiTermAdvancedSettingTypeBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformBool, iTermAdvancedSettingsModelInverseTransformBool)

#define DEFINE_OPTIONAL_BOOL(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, BOOL *, kiTermAdvancedSettingTypeOptionalBoolean, theDefault, theDescription, iTermAdvancedSettingsModelTransformOptionalBool, iTermAdvancedSettingsModelInverseTransformOptionalBool)

#define DEFINE_INT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, int, kiTermAdvancedSettingTypeInteger, theDefault, theDescription, iTermAdvancedSettingsModelTransformInt, iTermAdvancedSettingsModelInverseTransformInt)

#define DEFINE_NONNEGATIVE_INT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, int, kiTermAdvancedSettingTypeInteger, theDefault, theDescription, iTermAdvancedSettingsModelTransformNonnegativeInt, iTermAdvancedSettingsModelInverseTransformInt)

#define DEFINE_FLOAT(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, double, kiTermAdvancedSettingTypeFloat, theDefault, theDescription, iTermAdvancedSettingsModelTransformFloat, iTermAdvancedSettingsModelInverseTransformFloat)

#define DEFINE_SETTABLE_FLOAT(name, capitalizedName, theDefault, theDescription) \
DEFINE_SETTABLE_BOILERPLATE(name, capitalizedName, double, kiTermAdvancedSettingTypeFloat, theDefault, theDescription, iTermAdvancedSettingsModelTransformFloat, iTermAdvancedSettingsModelInverseTransformFloat)

#define DEFINE_STRING(name, theDefault, theDescription) \
DEFINE_BOILERPLATE(name, NSString *, kiTermAdvancedSettingTypeString, theDefault, theDescription, iTermAdvancedSettingsModelTransformString, iTermAdvancedSettingsModelInverseTransformString)

// Convenience default value for boolean settings that are on for beta users.
#if BETA
#define YES_IF_BETA_ELSE_NO YES
#else
#define YES_IF_BETA_ELSE_NO NO
#endif

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
        if ([name hasPrefix:@"advancedSettingsModelDictionary_"]) {
            NSDictionary *(*impl)(id, SEL) = (NSDictionary *(*)(id, SEL))method_getImplementation(method);
            NSDictionary *dict = impl(self, selector);
            block(dict);
        }
    }];
}

#pragma mark Tabs

#define SECTION_TABS @"Tabs: "

DEFINE_BOOL(useUnevenTabs, NO, SECTION_TABS @"Uneven tab widths allowed.");
DEFINE_INT(minTabWidth, 75, SECTION_TABS @"Minimum tab width when using uneven tab widths.");
DEFINE_INT(minCompactTabWidth, 60, SECTION_TABS @"Minimum tab width when using uneven tab widths for compact tabs.");
DEFINE_INT(optimumTabWidth, 175, SECTION_TABS @"Preferred tab width when tabs are equally sized.");
DEFINE_BOOL(addNewTabAtEndOfTabs, YES, SECTION_TABS @"Add new tabs at the end of the tab bar, not next to current tab.");
DEFINE_BOOL(navigatePanesInReadingOrder, YES, SECTION_TABS @"Next Pane and Previous Pane commands use reading order, not the time of last use.");
DEFINE_BOOL(eliminateCloseButtons, NO, SECTION_TABS @"Eliminate close buttons from tabs, even on mouse-over.");
DEFINE_FLOAT(tabAutoShowHoldTime, 1.0, SECTION_TABS @"How long in seconds to show tabs in fullscreen.\nThe tab bar appears briefly in fullscreen when the number of tabs changes or you switch tabs. This setting gives the time in seconds for it to remain visible.");
DEFINE_FLOAT(tabFlashAnimationDuration, 0.25, SECTION_TABS @"Animation duration for fade in/out animation of tabs in full screen, in seconds.")
DEFINE_BOOL(allowDragOfTabIntoNewWindow, YES, SECTION_TABS @"Allow a tab to be dragged and dropped outside any existing tab bar to create a new window.");
DEFINE_INT(minimumTabDragDistance, 10, SECTION_TABS @"How far must the mouse move before a tab drag is initiated?\nYou must restart iTerm2 after changing this setting for it to take effect.");
DEFINE_BOOL(tabTitlesUseSmartTruncation, YES, SECTION_TABS @"Use “smart truncation” for tab titles.\nIf a tab‘s title is too long to fit, ellipsize the start of the title if more tabs have unique suffixes than prefixes in a given window.");
DEFINE_BOOL(middleClickClosesTab, YES, SECTION_TABS @"Should middle-click on a tab in the tab bar close the tab?");
DEFINE_FLOAT(coloredSelectedTabOutlineStrength, 0.5, SECTION_TABS @"How prominent should the outline around the selected tab be drawn when there are colored tabs in a window?\nTakes a value in 0 to 3, where 0 means no outline and 3 means a very prominent outline.");
DEFINE_FLOAT(minimalTabStyleBackgroundColorDifference, 0, SECTION_TABS @"In minimal tab style, how different should the background color of the selected tab be from the others?\nTakes a value in 0 to 1, where 0 is no difference and 1 very different.");
DEFINE_FLOAT(minimalTabStyleOutlineStrength, 0.3, SECTION_TABS @"In minimal tab style, how prominent should the tab outline be?\nTakes a value in 0 to 1, where 0 is invisible and 1 is very prominent");
DEFINE_FLOAT(coloredUnselectedTabTextProminence, 0.1, SECTION_TABS @"How prominent should the text in a non-selected tab be when there are colored tabs in a window?\nTakes a value in 0 to 0.5, the distance from middle gray.");

#pragma mark Mouse

#define SECTION_MOUSE @"Mouse: "
DEFINE_STRING(alternateMouseScrollStringForUp, @"",
              SECTION_MOUSE @"Scroll wheel up sends the specified text when in alternate screen mode.\n"
              @"The value should use Vim syntax, such as \\e for escape.");
DEFINE_STRING(alternateMouseScrollStringForDown, @"",
              SECTION_MOUSE @"Scroll wheel down sends the specified text when in alternate screen mode.\n"
              @"The value should use Vim syntax, such as \\e for escape.");
DEFINE_BOOL(alternateMouseScroll, NO, SECTION_MOUSE @"Scroll wheel sends arrow keys when in alternate screen mode.");
DEFINE_BOOL(pinchToChangeFontSizeDisabled, NO, SECTION_MOUSE @"Disable changing font size in response to a pinch gesture.");
DEFINE_BOOL(useSystemCursorWhenPossible, NO, SECTION_MOUSE @"Use system cursor icons when possible.");
DEFINE_BOOL(alwaysAcceptFirstMouse, NO, SECTION_MOUSE @"Always accept first mouse event on terminal windows.\nThis means clicks will work the same when iTerm2 is active as when it’s inactive.");
DEFINE_BOOL(doubleReportScrollWheel, NO, SECTION_MOUSE @"Double-report scroll wheel events to work around tmux scrolling bug.");
DEFINE_BOOL(stealKeyFocus, NO, SECTION_MOUSE @"When Focus Follows Mouse is enabled, steal key focus even when inactive.");
DEFINE_BOOL(aggressiveFocusFollowsMouse, NO, SECTION_MOUSE @"When Focus Follows Mouse is enabled, activate the window under the cursor when iTerm2 becomes active?");
DEFINE_BOOL(cmdClickWhenInactiveInvokesSemanticHistory, NO, SECTION_MOUSE @"⌘-click in an active pane while iTerm2 isn't the active app invokes Semantic History.\nBy default, iTerm2 respects the OS standard that ⌘-click in an app that doesn't have keyboard focus behaves like a non-⌘ click that does not raise the window.");
DEFINE_BOOL(enableUnderlineSemanticHistoryOnCmdHover, YES, SECTION_MOUSE @"Underline Semantic History-selectable items under the cursor while holding ⌘?");
DEFINE_BOOL(sensitiveScrollWheel, NO, SECTION_MOUSE @"Scroll on any scroll wheel movement, no matter how small?");

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

#pragma mark Terminal

#define SECTION_TERMINAL @"Terminal: "

DEFINE_BOOL(traditionalVisualBell, NO, SECTION_TERMINAL @"Visual bell flashes the whole screen, not just a bell icon.");
DEFINE_FLOAT(timeBetweenBlinks, 0.5, SECTION_TERMINAL @"Cursor blink speed (seconds).");
DEFINE_BOOL(doNotSetCtype, NO, SECTION_TERMINAL @"Never set the CTYPE environment variable.");
// For these, 1 is more aggressive and 0 turns the feature off:
DEFINE_FLOAT(smartCursorColorBgThreshold, 0.5, SECTION_TERMINAL @"Threshold for Smart Cursor Color for background color (0 to 1).\n0 means the cursor’s background color will always be the cell’s text color, while 1 means it will always be black or white.");
DEFINE_FLOAT(smartCursorColorFgThreshold, 0.75, SECTION_TERMINAL @"Threshold for Smart Cursor Color for text color (0 to 1).\n0 means the cursor’s text color will always be the cell’s background color, while 1 means it will always be black or white.");
DEFINE_STRING(findUrlsRegex,
              @"https?://([a-z0-9A-Z]+(:[a-zA-Z0-9]+)?@)?[a-z0-9A-Z\\-]+(\\.[a-z0-9A-Z\\-]+)*"
              @"((:[0-9]+)?)(/[a-zA-Z0-9;:/\\.\\-_+%~?&amp;@=#\\(\\)]*)?",
              SECTION_TERMINAL @"Regular expression for “Find URLs” command.");
DEFINE_FLOAT(echoProbeDuration, 0.5, SECTION_TERMINAL @"Amount of time to wait while testing if echo is on (seconds).\nThis is used by the password manager to ensure you're at a password prompt.");
DEFINE_BOOL(disablePasswordManagerAnimations, NO, SECTION_TERMINAL @"Disable animations for showing/hiding password manager.");
DEFINE_BOOL(optionIsMetaForSpecialChars, YES, SECTION_TERMINAL @"When you press an arrow key or other function key that transmits the modifiers, should ⌥ be translated to Meta?\nIf this is set to No then it will be translated to Alt.");
DEFINE_BOOL(noSyncSilenceAnnoyingBellAutomatically, NO, SECTION_TERMINAL @"Automatically silence bell when it rings too much.");
DEFINE_BOOL(restoreWindowContents, YES, SECTION_TERMINAL @"Restore window contents at startup.\nThis requires “System Prefs>General>Close windows when quitting an app” to be off.");
DEFINE_INT(numberOfLinesForAccessibility, 1000, SECTION_TERMINAL @"Maximum number of lines of history to expose to Accessibility.\nAccessibility APIs can make iTerm2 slow. In order to limit the effect, you can restrict the number of lines in each session that are visible to accessibility. The last lines of each session will be made accessible.");
DEFINE_INT(triggerRadius, 3, SECTION_TERMINAL @"Number of screen lines to match against trigger regular expressions.\nTrigger regular expressions are matched against the last logical line of text when a newline is received. A search is performed to find the start of the line. Since very long lines would cause performance problems, the search (and consequently the regular expression match, highlighting, and so on) is limited to this many screen lines.");
DEFINE_BOOL(requireCmdForDraggingText, NO, SECTION_TERMINAL @"To drag images or selected text, you must hold ⌘. This prevents accidental drags.");
DEFINE_BOOL(focusReportingEnabled, YES, SECTION_TERMINAL @"Apps may turn on Focus Reporting.\nFocus reporting causes iTerm2 to send an escape sequence when a session gains or loses focus. It can cause problems when an ssh session dies unexpectedly because it gets left on, so some users prefer to disable it.");
DEFINE_BOOL(useColorfgbgFallback, YES, SECTION_TERMINAL @"Use fallback for COLORFGBG if no exact match found?\nThe COLORFGBG variable indicates the ANSI colors that match the foreground and background colors. If no colors match and this setting is enabled, then the variable will be set to 15;0 to indicate a dark background or 0;15 to indicate a light background.");
DEFINE_BOOL(zeroWidthSpaceAdvancesCursor, YES, SECTION_TERMINAL @"Zero-Width Space (U+200B) advances cursor?\nWhile a zero-width space should not advance the cursor per the Unicode spec, both Terminal.app and Konsole do this, and Weechat depends on it. You must restart iTerm2 after changing this setting.");
DEFINE_BOOL(fullHeightCursor, NO, SECTION_TERMINAL @"Cursor occupies line spacing area.\nIf lines have more than 100% vertical spacing and this setting is enabled the bottom of the cursor will be aligned to the bottom of the spacing area.");
DEFINE_FLOAT(underlineCursorOffset, 0, SECTION_TERMINAL @"Vertical offset for underline cursor.\nPositive values move it up, negative values move it down.");
DEFINE_BOOL(preventEscapeSequenceFromClearingHistory, NO, SECTION_TERMINAL @"Prevent CSI 3 J from clearing scrollback history?\nThis is also known as the terminfo E3 capability.");
DEFINE_FLOAT(verticalBarCursorWidth, 1, SECTION_TERMINAL @"Width of vertical bar cursor.");
DEFINE_BOOL(acceptOSC7, YES, SECTION_TERMINAL @"Accept OSC 7 to set username, hostname, and path.");
DEFINE_BOOL(detectPasswordInput, YES, SECTION_TERMINAL @"Show key at cursor at password prompt?");
DEFINE_BOOL(tabsWrapAround, NO, SECTION_TERMINAL @"Tabs wrap around to the next line.\nThis is useful for preserving tabs for later copying to the pasteboard. It breaks backward compatibility and may cause layout problems with programs that don’t expect this behavior.");
DEFINE_STRING(sshSchemePath, @"ssh", SECTION_TERMINAL @"Command to run when handling an ssh:// URL.");

#pragma mark Hotkey

#define SECTION_HOTKEY @"Hotkey: "
DEFINE_FLOAT(hotkeyTermAnimationDuration, 0.25, SECTION_HOTKEY @"Duration in seconds of the hotkey window animation.\nWarning: reducing this value may cause problems if you have multiple displays.");
DEFINE_BOOL(dockIconTogglesWindow, NO, SECTION_HOTKEY @"If the only window is a hotkey window, then clicking the dock icon shows or hides it.");
DEFINE_BOOL(hotkeyWindowFloatsAboveOtherWindows, NO, SECTION_HOTKEY @"The hotkey window floats above other windows even when another application is active.\nYou must disable “Prefs > Keys > Hotkey window hides when focus is lost” for this setting to be effective.");
DEFINE_FLOAT(hotKeyDoubleTapMaxDelay, 0.3, SECTION_HOTKEY @"The maximum amount of time allowed between presses of a modifier key when performing a modifier double-tap.");
DEFINE_FLOAT(hotKeyDoubleTapMinDelay, 0.01, SECTION_HOTKEY @"The minimum amount of time required between presses of a modifier key when performing a modifier double-tap.");

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
DEFINE_BOOL(useOpenDirectory, YES, SECTION_GENERAL @"Use Open Directory to determine the user shell");
DEFINE_BOOL(disablePotentiallyInsecureEscapeSequences, NO, SECTION_GENERAL @"Disable potentially insecure escape sequences.\nSome features of iTerm2 expand the surface area for security issues. Consider turning this on when viewing untrusted content. The following custom escape sequences will be disabled: RemoteHost, StealFocus, CurrentDir, SetProfile, CopyToClipboard, EndCopy, File, SetBackgroundImageFile. The following DEC sequences are disabled: DECRQCRA. The following xterm extensions are disabled: Window Title Reporting, Icon Title Reporting. This will break displaying inline images, file download, some shell integration features, and other features.");
DEFINE_BOOL(performDictionaryLookupOnQuickLook, YES, SECTION_GENERAL @"Perform dictionary lookups on force press.\nIf this is NO, force press will still preview the Semantic History action; only dictionary lookups can be disabled.");
DEFINE_BOOL(jiggleTTYSizeOnClearBuffer, NO, SECTION_GENERAL @"Redraw the screen after the Clear Buffer menu item is selected.\nWhen enabled, the TTY size is briefly changed after clearing the buffer to cause the shell or current app to redraw.");
DEFINE_BOOL(indicateBellsInDockBadgeLabel, YES, SECTION_GENERAL @"Indicate the number of bells rung while the app is inactive in the dock icon’s badge label");
DEFINE_STRING(downloadsDirectory, @"", SECTION_GENERAL @"Downloads folder.\nIf set, downloaded files go to this location instead of the user’s $HOME/Downloads folder.");
DEFINE_FLOAT(pointSizeOfTimeStamp, 10, SECTION_GENERAL @"Point size for timestamps");
DEFINE_NONNEGATIVE_INT(terminalMargin, 5, SECTION_GENERAL @"Width of left and right margins in terminal panes\nHow much space to leave between the left and right edges of the terminal.\nYou must restart iTerm2 after modifying this property. Saved window arrangements should be re-created.");
DEFINE_INT(terminalVMargin, 2, SECTION_GENERAL @"Height of top and bottom margins in terminal panes\nHow much space to leave between the top and bottom edges of the terminal.\nYou must restart iTerm2 after modifying this property. Saved window arrangements should be re-created.");
DEFINE_STRING(viewManPageCommand, @"man %@ || sleep 3", SECTION_GENERAL @"Command to view man pages.\nUsed when you press the man page button on the touch bar. %@ is replaced with the command. End the command with & to avoid opening an iTerm2 window (e.g., if you're launching an external viewer).");
DEFINE_BOOL(hideStuckTooltips, YES, SECTION_GENERAL @"Hide stuck tooltips.\nWhen you hide iTerm2 using a hotkey while a tooltip is fading out it gets stuck because of an OS bug. Work around it with a nasty hack by enabling this feature.")
DEFINE_BOOL(openFileOverridesSendText, YES, SECTION_GENERAL @"Should opening a script with iTerm2 disable the default profile's “Send Text at Start” setting?\nIf you use “open iTerm2 file.command” or drag a script onto iTerm2's icon and this setting is enabled then the script will be executed in lieu of the profile's “Send Text at Start” setting. If this setting is off then both will be executed.");
DEFINE_BOOL(statusBarIcon, YES, SECTION_GENERAL @"Add status bar icon when excluded from dock?\nWhen you turn on “Exclude from Dock and ⌘-Tab Application Switcher” a status bar icon is added to the menu bar so you can switch the setting back off. Disable this to remove the status bar icon. Doing so makes it very hard to get to Preferences. You must restart iTerm2 after changing this setting.");
DEFINE_BOOL(wrapFocus, YES, SECTION_GENERAL @"Should split pane navigation by direction wrap around?");
DEFINE_BOOL(openUntitledFile, YES, SECTION_GENERAL @"Open a new window when you click the dock icon and no windows are already open?");
DEFINE_BOOL(openNewWindowAtStartup, YES, SECTION_GENERAL @"Open a window at startup?\nThis is useful if you wish to use the system window restoration settings but not create a new window if none would be restored.");
DEFINE_FLOAT(timeToWaitForEmojiPanel, 1, SECTION_GENERAL @"How long to wait for the emoji panel to open in seconds?\nFloating hotkey windows adjust their level when the emoji panel is open. If it’s really slow you might need to increase this value to prevent it from appearing beneath a floating hotkey window.");
DEFINE_FLOAT(timeoutForStringEvaluation, 10, SECTION_GENERAL @"Timeout (seconds) for evaluating RPCs.\nThis applies to invoking functions registered by scripts when using the Swift syntax for inline expressions.");
DEFINE_STRING(pathToFTP, @"ftp", SECTION_GENERAL @"Path to ftp for opening ftp: URLs.\nYou may want to set this to /usr/local/bin/ftp to use the Homebrew install.");
DEFINE_STRING(pathToTelnet, @"telnet", SECTION_GENERAL @"Path to telnet for opening telnet: URLs.\nYou may want to set this to /usr/local/bin/telnet to use the Homebrew install.");
DEFINE_STRING(fallbackLCCType, @"", SECTION_GENERAL @"Value to set LC_CTYPE to if the machine‘s combination of country and language are not supported.\nIf unset, the encoding (e.g., UTF-8) will be used.");
DEFINE_BOOL(useVirtualKeyCodesForDetectingDigits, NO, SECTION_GENERAL @"On keyboards that require a modifier to press a digit, do not require that modifier for switching between windows, tabs, and panes by number.\nFor example, AZERTY requires you to hold down Shift to enter a number. To switch tabs with ⌘+Number on an AZERTY keyboard, you must enable this setting. Then, for example, ⌘-& switches to tab 1. When this setting is enabled, some user-defined shortcuts may become unavailable because the tab/window/pane switching behavior takes precedence.");
DEFINE_BOOL(hotkeyWindowsExcludedFromCycling, YES, SECTION_GENERAL @"Hotkey windows are excluded from Cycle Through Windows.");

#pragma mark - Drawing

#define SECTION_DRAWING @"Drawing: "

DEFINE_BOOL(zippyTextDrawing, YES, SECTION_DRAWING @"Use zippy text drawing algorithm?\nThis draws non-ASCII text more quickly but with lower fidelity. This setting is ignored if ligatures are enabled in Prefs > Profiles > Text.");
DEFINE_BOOL(lowFiCombiningMarks, NO, SECTION_DRAWING @"Prefer speed to accuracy for characters with combining marks?");
DEFINE_BOOL(useAdaptiveFrameRate, YES, SECTION_DRAWING @"Use adaptive framerate.\nWhen throughput is low, the screen will update at 60 frames per second. When throughput is higher, it will drop to a configurable rate (15 fps by default).");
DEFINE_BOOL(disableAdaptiveFrameRateInInteractiveApps, YES, SECTION_DRAWING @"Disable adaptive framerate in interactive apps.\nTurn off adaptive frame rate while in alternate screen mode for more consistent refresh rate. This works even if alternate screen mode is disabled.");
DEFINE_FLOAT(slowFrameRate, 15.0, SECTION_DRAWING @"When adaptive framerate is enabled, refresh at this rate during high throughput conditions (FPS).\n Does not apply to Metal renderer.");
DEFINE_FLOAT(metalSlowFrameRate, 30.0, SECTION_DRAWING @"When adaptive framerate is enabled and using the Metal renderer, refresh at this rate during high throughput conditions (FPS).");
DEFINE_FLOAT(activeUpdateCadence, 60.0, SECTION_DRAWING @"Maximum frame rate (FPS) when adaptive framerate is disabled.\nModifications to this setting will not affect existing sessions.");
DEFINE_INT(adaptiveFrameRateThroughputThreshold, 10000, SECTION_DRAWING @"Throughput threshold for adaptive frame rate.\nIf more than this many bytes per second are received, use the lower frame rate of 30 fps.");
DEFINE_BOOL(dwcLineCache, YES, SECTION_DRAWING @"Enable cache of double-width character locations?\nThis should improve performance. It is always on in nightly builds. You must restart iTerm2 for this setting to take effect.");
DEFINE_BOOL(useGCDUpdateTimer, YES, SECTION_DRAWING @"Use GCD-based update timer instead of NSTimer.\nThis should cause more regular screen updates. Restart iTerm2 after changing this setting.");
DEFINE_BOOL(drawOutlineAroundCursor, NO, SECTION_DRAWING @"Draw outline around underline and vertical bar cursors using background color.");
DEFINE_BOOL(disableCustomBoxDrawing, NO, SECTION_DRAWING @"Use your typeface’s box-drawing characters instead of iTerm2’s custom drawing code.\nYou must restart iTerm2 after changing this setting.");
DEFINE_INT(minimumWeightDifferenceForBoldFont, 4, SECTION_DRAWING @"Minimum weight difference between regular and bold font.\nThis affects selection of the bold version of a font. Font weights go from 0 to 9. If no font can be found that has a high enough weight then the regular font will be double-struck with a small offset.");
DEFINE_FLOAT(underlineCursorHeight, 2, SECTION_DRAWING @"Thickness of underline cursor.");

#if ENABLE_LOW_POWER_GPU_DETECTION
DEFINE_BOOL(useLowPowerGPUWhenUnplugged, NO, SECTION_DRAWING @"Metal renderer uses integrated GPU when not connected to power?\nFor this to be effective you must disable “Disable Metal renderer when not connected to power”.");
#endif

#pragma mark - Semantic History

#define SECTION_SEMANTIC_HISTORY @"Semantic History: "

DEFINE_BOOL(ignoreHardNewlinesInURLs, NO, SECTION_SEMANTIC_HISTORY @"Ignore hard newlines for the purposes of locating URLs and file names for Semantic History.\nIf a hard newline occurs at the end of a line then ⌘-click will not see it all unless this setting is turned on. This is useful for some interactive applications. Turning this on will remove newlines from the \\3 and \\4 substitutions.");
// Note: square brackets are included for ipv6 addresses like http://[2600:3c03::f03c:91ff:fe96:6a7a]/
DEFINE_STRING(URLCharacterSet, @".?\\/:;%=&_-,+~#@!*'(（)）|[]", SECTION_SEMANTIC_HISTORY @"Non-alphanumeric characters considered part of a URL for Semantic History.\nLetters and numbers are always considered part of the URL. These non-alphanumeric characters are used in addition for the purposes of figuring out where a URL begins and ends.");
DEFINE_INT(maxSemanticHistoryPrefixOrSuffix, 2000, SECTION_SEMANTIC_HISTORY @"Maximum number of bytes of text before and after click location to take into account.\nThis also limits the size of the \\3 and \\4 substitutions.");
DEFINE_STRING(pathsToIgnore, @"", SECTION_SEMANTIC_HISTORY @"Paths to ignore for Semantic History.\nSeparate paths with a comma. Any file under one of these paths will not be openable with Semantic History. It is wise to add network file systems to this list, since they can be very slow.");
DEFINE_BOOL(showYellowMarkForJobStoppedBySignal, YES, SECTION_SEMANTIC_HISTORY @"Use a yellow for a Shell Integration prompt mark when the job is stopped by a signal.");
DEFINE_BOOL(conservativeURLGuessing, NO, SECTION_SEMANTIC_HISTORY @"URLs must contain a scheme?\nEnable this to reduce the number of false positives that semantic history things are a URL");
DEFINE_STRING(trailingPunctuationMarks, @"!?…)].\"';:,", SECTION_SEMANTIC_HISTORY @"Characters to ignore at the end of a URL");

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
DEFINE_BOOL(killJobsInServersOnQuit, YES, SECTION_SESSION @"User-initiated Quit (⌘Q) of iTerm2 will kill all running jobs.\nApplies only when session restoration is on.");
DEFINE_SETTABLE_BOOL(suppressRestartAnnouncement, SuppressRestartAnnouncement, NO, SECTION_SESSION @"Suppress the Restart Session offer.\nWhen a session terminates, it will offer to restart itself. Turn this on to suppress the offer permanently.");
DEFINE_BOOL(showSessionRestoredBanner, YES, SECTION_SESSION @"When restoring a session without restoring a running job, draw a banner saying “Session Contents Restored” below the restored contents.");
DEFINE_STRING(autoLogFormat,
              @"\\(session.creationTimeString).\\(session.name).\\(session.termid).\\(iterm2.pid).\\(session.autoLogId).log",
              SECTION_SESSION @"Format for automatic session log filenames.\nSee the Badges documentation for supported substitutions.");
DEFINE_BOOL(focusNewSplitPaneWithFocusFollowsMouse, YES, SECTION_SESSION @"When focus follows mouse is enabled, should new split panes automatically be focused?");
DEFINE_BOOL(NoSyncSuppressRestartSessionConfirmationAlert, NO, SECTION_SESSION @"Suppress restart session confirmation alert.\nDon't ask for a confirmation when manually restarting a session.");

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

#pragma mark tmux

#define SECTION_TMUX @"Tmux Integration: "

DEFINE_BOOL(noSyncNewWindowOrTabFromTmuxOpensTmux, NO, SECTION_TMUX @"Suppress alert asking what kind of tab/window to open in tmux integration.");
DEFINE_BOOL(tmuxUsesDedicatedProfile, YES, SECTION_TMUX @"Tmux always uses the “tmux” profile.\nIf disabled, tmux sessions use the profile of the session you ran tmux -CC in.");
DEFINE_BOOL(tolerateUnrecognizedTmuxCommands, NO, SECTION_TMUX @"Tolerate unrecognized commands from server.\nIf enabled, an unknown command from tmux (such as output from ssh or wall) will end the session. Turning this off helps detect dead ssh sessions.");

#pragma mark Warnings

#define SECTION_WARNINGS @"Warnings: "

DEFINE_BOOL(neverWarnAboutMeta, NO, SECTION_WARNINGS @"Suppress a warning when ⌥ Key Acts as Meta is enabled in Prefs>Profiles>Keys.");
DEFINE_BOOL(neverWarnAboutSpaces, NO, SECTION_WARNINGS @"Suppress a warning about how to configure Spaces when setting a window's Space.");
DEFINE_BOOL(neverWarnAboutOverrides, NO, SECTION_WARNINGS @"Suppress a warning about a change to a Profile key setting that overrides a global setting.");
DEFINE_BOOL(neverWarnAboutPossibleOverrides, NO, SECTION_WARNINGS @"Suppress a warning about a change to a global key that's overridden by a Profile.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForUrl, NO, SECTION_WARNINGS @"Suppress changed-setting warning when prefs are loaded from a URL.");
DEFINE_BOOL(noSyncNeverRemindPrefsChangesLostForFile, NO, SECTION_WARNINGS @"Suppress changed-setting warning when prefs are loaded from a custom folder.");
DEFINE_BOOL(noSyncSuppressAnnyoingBellOffer, NO, SECTION_WARNINGS @"Suppress offer to silence bell when it rings too much.");

DEFINE_BOOL(suppressMultilinePasteWarningWhenPastingOneLineWithTerminalNewline, NO, SECTION_WARNINGS @"Suppress warning about multi-line paste when pasting a single line ending with a newline.\nThis supresses all multi-line paste warnings when a single line is being pasted.");
DEFINE_BOOL(suppressMultilinePasteWarningWhenNotAtShellPrompt, NO, SECTION_WARNINGS @"Suppress warning about multi-line paste when not at prompt.\nRequires Shell Integration to be installed.");
DEFINE_BOOL(noSyncSuppressBroadcastInputWarning, NO, SECTION_WARNINGS @"Suppress warning about broadcasting input.");
DEFINE_BOOL(noSyncSuppressCaptureOutputRequiresShellIntegrationWarning, NO,
            SECTION_WARNINGS @"Suppress warning “Shell Integration is required for Capture Output.”");
DEFINE_BOOL(noSyncSuppressCaptureOutputToolNotVisibleWarning, NO,
            SECTION_WARNINGS @"Suppress warning that the Captured Output tool is not visible.");
DEFINE_BOOL(closingTmuxWindowKillsTmuxWindows, NO, SECTION_WARNINGS @"Suppress kill/hide dialog when closing a tmux window.");
DEFINE_BOOL(closingTmuxTabKillsTmuxWindows, NO, SECTION_WARNINGS @"Suppress kill/hide dialog when closing a tmux tab.");
DEFINE_BOOL(aboutToPasteTabsWithCancel, NO, SECTION_WARNINGS @"Suppress warning about pasting tabs with offer to convert them to spaces.");
DEFINE_FLOAT(shortLivedSessionDuration, 3, SECTION_WARNINGS @"Warn about short-lived sessions that live less than this many seconds.");

DEFINE_SETTABLE_BOOL(noSyncDoNotWarnBeforeMultilinePaste, NoSyncDoNotWarnBeforeMultilinePaste, NO, SECTION_WARNINGS @"Suppress warning about multi-line pastes (or a single line ending in a newline).\nThis applies whether you are at the shell prompt or not, provided two or more lines are being pasted.");
DEFINE_SETTABLE_BOOL(noSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt, NoSyncDoNotWarnBeforePastingOneLineEndingInNewlineAtShellPrompt, NO, SECTION_WARNINGS @"Suppress warning about pasting a single line ending in a newline when at the shell prompt.\nThis requires Shell Integration to be installed.");

DEFINE_BOOL(noSyncReplaceProfileWarning, NO, SECTION_WARNINGS @"Suppress warning about copying a session's settings over a Profile");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffFocusReportingOnHostChange, nil, SECTION_WARNINGS @"Always turn off focus reporting when host changes?");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffMouseReportingOnHostChange, nil, SECTION_WARNINGS @"Always turn off mouse reporting when host changes?");
DEFINE_OPTIONAL_BOOL(noSyncTurnOffBracketedPasteOnHostChange, nil, SECTION_WARNINGS @"Always turn off paste bracketing when host changes?");
DEFINE_SETTABLE_BOOL(noSyncSuppressClipboardAccessDeniedWarning, NoSyncSuppressClipboardAccessDeniedWarning, NO, SECTION_WARNINGS @"Suppress the notification that the terminal attempted to access the clipboard but it was denied?");
DEFINE_SETTABLE_BOOL(noSyncSuppressMissingProfileInArrangementWarning, NoSyncSuppressMissingProfileInArrangementWarning, NO, SECTION_WARNINGS @"Suppress the notification that a restored session’s profile no longer exists?");

#pragma mark Pasteboard

#define SECTION_PASTEBOARD @"Pasteboard: "

DEFINE_BOOL(trimWhitespaceOnCopy, YES, SECTION_PASTEBOARD @"Trim whitespace when copying to pasteboard.");
DEFINE_INT(quickPasteBytesPerCall, 667, SECTION_PASTEBOARD @"Number of bytes to paste in each chunk when pasting normally.");
DEFINE_FLOAT(quickPasteDelayBetweenCalls, 0.01530456, SECTION_PASTEBOARD @"Delay in seconds between chunks when pasting normally.")
DEFINE_INT(slowPasteBytesPerCall, 16, SECTION_PASTEBOARD @"Number of bytes to paste in each chunk when pasting slowly.");
DEFINE_FLOAT(slowPasteDelayBetweenCalls, 0.125, SECTION_PASTEBOARD @"Delay in seconds between chunks when pasting slowly");
DEFINE_BOOL(copyWithStylesByDefault, NO, SECTION_PASTEBOARD @"Copy to pasteboard on selection includes color and font style.");
DEFINE_INT(pasteHistoryMaxOptions, 20, SECTION_PASTEBOARD @"Number of entries to save in Paste History.\n.");
DEFINE_BOOL(disallowCopyEmptyString, NO, SECTION_PASTEBOARD @"Disallow copying empty string to pasteboard.\nIf enabled, selecting an empty string (or all whitespace if trimming is enabled) will not erase the contents of the pasteboard.");
DEFINE_BOOL(typingClearsSelection, YES, SECTION_PASTEBOARD @"Pressing a key will remove the selection.");
DEFINE_SETTABLE_BOOL(promptForPasteWhenNotAtPrompt, PromptForPasteWhenNotAtPrompt, NO, SECTION_PASTEBOARD @"Warn before pasting when not at shell prompt?");
DEFINE_BOOL(excludeBackgroundColorsFromCopiedStyle, NO, SECTION_PASTEBOARD @"Exclude background colors when text is copied with color and font style?");
DEFINE_BOOL(includePasteHistoryInAdvancedPaste, YES, SECTION_PASTEBOARD @"Include paste history in the advanced paste menu.");

#pragma mark - Tip of the day

#define SECTION_TOTD @"Tip of the Day: "

DEFINE_BOOL(noSyncTipsDisabled, NO, SECTION_TOTD @"Disable the Tip of the Day?");
DEFINE_SETTABLE_FLOAT(timeBetweenTips, TimeBetweenTips, 24 * 60 * 60, SECTION_TOTD @"Time between tips (in seconds)");

#pragma mark - Badge

#define SECTION_BADGE @"Badge: "

DEFINE_STRING(badgeFont, @"Helvetica", SECTION_BADGE @"Font to use for the badge.");
DEFINE_BOOL(badgeFontIsBold, YES, SECTION_BADGE @"Should the badge render in bold type?");
DEFINE_FLOAT(badgeMaxWidthFraction, 0.5, SECTION_BADGE @"Maximum width of the badge\nAs a fraction of the width of the terminal, between 0 and 1.0.");
DEFINE_FLOAT(badgeMaxHeightFraction, 0.2, SECTION_BADGE @"Maximum height of the badge\nAs a fraction of the height of the terminal, between 0 and 1.0.");
DEFINE_INT(badgeRightMargin, 10, SECTION_BADGE @"Right Margin for the badge\nHow much space to leave between the right edge of the badge and the right edge of the terminal.");
DEFINE_INT(badgeTopMargin, 10, SECTION_BADGE @"Top Margin for the badge\nHow much space to leave between the top edge of the badge and the top edge of the terminal.");

#pragma mark - Experimental Features

#define SECTION_EXPERIMENTAL @"Experimental Features: "

DEFINE_BOOL(enableAPIServer, NO, SECTION_EXPERIMENTAL @"Enable websocket API server.\nYou must restart iTerm2 for this change to take effect.");
DEFINE_BOOL(killSessionsOnLogout, NO, SECTION_EXPERIMENTAL @"Kill sessions on logout.\nA possible fix for issue 4147.");

// This causes problems like issue 6052, where repeats cause the IME to swallow subsequent keypresses.
DEFINE_BOOL(experimentalKeyHandling, NO, SECTION_EXPERIMENTAL @"Improved support for input method editors like AquaSKK.");

DEFINE_BOOL(useExperimentalFontMetrics, NO, SECTION_EXPERIMENTAL @"Use a more theoretically correct technique to measure line height.\nYou must restart iTerm2 or adjust a session's font size for this change to take effect.");
DEFINE_BOOL(supportREPCode, YES, SECTION_EXPERIMENTAL @"Enable support for REP (Repeat previous character) escape sequence?");

DEFINE_BOOL(showMetalFPSmeter, NO, SECTION_EXPERIMENTAL @"Show FPS meter\nRequires Metal renderer");

// TODO: Turn this back on by default in a few days. Let's see if it is responsible for the spike in nightly build crasehs starting with the 3-12-2018 build.
// The number of crashes fell off a cliff starting with the 3/18 build (usually 0, never more than 2/day, while it had been at 47 on the 3/15 build). I'm switching the default back to YES for the 4/18 build to see if the number climbs.
DEFINE_BOOL(disableMetalWhenIdle, NO, SECTION_EXPERIMENTAL @"Disable metal renderer when idle to save CPU utilization?\nRequires Metal renderer");

DEFINE_BOOL(proportionalScrollWheelReporting, YES, SECTION_EXPERIMENTAL @"Report multiple mouse scroll events when scrolling quickly?");
DEFINE_BOOL(useModernScrollWheelAccumulator, NO, SECTION_EXPERIMENTAL @"Use modern scroll wheel accumulator.\nThis should support wheel mice better and feel more natural.");
DEFINE_BOOL(resetSGROnPrompt, YES, SECTION_EXPERIMENTAL @"Reset colors at shell prompt?\nUses shell integration to detect a shell prompt and, if enabled, resets colors to their defaults.");
DEFINE_BOOL(retinaInlineImages, YES, SECTION_EXPERIMENTAL @"Show inline images at Retina resolution.");
DEFINE_BOOL(throttleMetalConcurrentFrames, YES, SECTION_EXPERIMENTAL @"Reduce number of frames in flight when GPU can't produce drawables quickly.");
DEFINE_BOOL(evaluateSwiftyStrings, NO, SECTION_EXPERIMENTAL @"Evaluate certain strings with inline expressions using a Swift-like syntax?\nThis applies to session names and will eventually apply in other places.");
DEFINE_BOOL(metalDeferCurrentDrawable, NO, SECTION_EXPERIMENTAL @"Defer invoking currentDrawable.\nThis may improve overall performance at the cost of a lower frame rate.");
DEFINE_BOOL(sshURLsSupportPath, YES_IF_BETA_ELSE_NO, SECTION_EXPERIMENTAL @"SSH URLs respect the path.\nThey run the command: ssh -t \"cd $$PATH$$; exec \\$SHELL -l\"");

#pragma mark - Scripting
#define SECTION_SCRIPTING @"Scripting: "

DEFINE_STRING(pythonRuntimeDownloadURL, @"https://iterm2.com/downloads/pyenv/manifest.json", SECTION_SCRIPTING @"URL to check for new versions of the Python scripting runtime.");

+ (void)initialize {
    if (self == [iTermAdvancedSettingsModel self]) {
        static iTermAdvancedSettingsModelChangeObserver *observer;
        observer = [[iTermAdvancedSettingsModelChangeObserver alloc] init];
        [self enumerateMethods:^(Method method, SEL selector) {
            NSString *name = NSStringFromSelector(selector);
            if ([name hasPrefix:@"load_"]) {
                NSString *(*impl)(id, SEL) = (NSString *(*)(id, SEL))method_getImplementation(method);
                NSString *identifier = impl(self, selector);

                [observer observeKey:identifier block:^{
                    impl(self, selector);
                }];
            }
        }];
        if ([NSApp isRunningUnitTests]) {
            sAdvancedSetting_runJobsInServers = @NO;
        }
    }
}


@end
