//
//  PointerPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import "PointerPrefsController.h"
#import "PointerController.h"
#import "PreferencePanel.h"
#import "NSPopUpButton+iTerm.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermApplicationDelegate.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermPasteSpecialViewController.h"
#import "ITAddressBookMgr.h"
#import "FutureMethods.h"
#import "NSTextField+iTerm.h"

static NSString *kPointerActionsKey = @"PointerActions";  // Used in NSUserDefaults
static NSString *kActionKey = @"Action";  // Used within values
static NSString *kArgumentKey = @"Argument";  // Used within values
static NSString *kVersionKey = @"Version";
static NSString *kCommandKeyChar = @"c";
static NSString *kOptionKeyChar = @"o";
static NSString *kShiftKeyChar = @"s";
static NSString *kControlKeyChar = @"^";

#define kLeftButton 0
#define kRightButton 1
#define kMiddleButton 2
static int kMaxClicks = 4;

static const int kMinGestureTag = 10;
#define kThreeFingerTapGestureTag 10
#define kThreeFingerSwipeRightGestureTag 11
#define kThreeFingerSwipeLeftGestureTag 12
#define kThreeFingerSwipeUpGestureTag 13
#define kThreeFingerSwipeDownGestureTag 14
#define kForceTouchSingleClickTag 15

static NSString *kButtonSchema = @"Button";  // First field of action key
static NSString *kGestureSchema = @"Gesture";  // First field of action key

NSString *kForceTouchSingleClick = @"ForceTouchSingleClick";  // Single finger force touch
NSString *kThreeFingerClickGesture = @"ThreeFingerClick";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeRight = @"ThreeFingerSwipeRight";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeLeft = @"ThreeFingerSwipeLeft";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeUp = @"ThreeFingerSwipeUp";  // Second field of action key (gesture type)
NSString *kThreeFingerSwipeDown = @"ThreeFingerSwipeDown";  // Second field of action key (gesture type)

NSString *kPasteFromClipboardPointerAction = @"kPasteFromClipboardPointerAction";
NSString *kPasteFromSelectionPointerAction = @"kPasteFromSelectionPointerAction";
NSString *kOpenTargetPointerAction = @"kOpenTargetPointerAction";
NSString *kOpenTargetInBackgroundPointerAction = @"kOpenTargetInBackgroundPointerAction";
NSString *kSmartSelectionPointerAction = @"kSmartSelectionPointerAction";
NSString *kSmartSelectionIgnoringNewlinesPointerAction = @"kSmartSelectionIgnoringNewlinesPointerAction";
NSString *kContextMenuPointerAction = @"kContextMenuPointerAction";
NSString *kNextTabPointerAction = @"kNextTabPointerAction";
NSString *kPrevTabPointerAction = @"kPrevTabPointerAction";
NSString *kNextWindowPointerAction = @"kNextWindowPointerAction";
NSString *kPrevWindowPointerAction = @"kPrevWindowPointerAction";
NSString *kMovePanePointerAction = @"kMovePanePointerAction";
NSString *kSendEscapeSequencePointerAction = @"kSendEscapeSequencePointerAction";
NSString *kSendHexCodePointerAction = @"kSendHexCodePointerAction";
NSString *kSendTextPointerAction = @"kSendTextPointerAction";
NSString *kInvokeScriptFunction = @"kInvokeScriptFunction";
NSString *kSelectPaneLeftPointerAction = @"kSelectPaneLeftPointerAction";
NSString *kSelectPaneRightPointerAction = @"kSelectPaneRightPointerAction";
NSString *kSelectPaneAbovePointerAction = @"kSelectPaneAbovePointerAction";
NSString *kSelectPaneBelowPointerAction = @"kSelectPaneBelowPointerAction";
NSString *kNewWindowWithProfilePointerAction = @"kNewWindowWithProfilePointerAction";
NSString *kNewTabWithProfilePointerAction = @"kNewTabWithProfilePointerAction";
NSString *kNewVerticalSplitWithProfilePointerAction = @"kNewVerticalSplitWithProfilePointerAction";
NSString *kNewHorizontalSplitWithProfilePointerAction = @"kNewHorizontalSplitWithProfilePointerAction";
NSString *kSelectNextPanePointerAction = @"kSelectNextPanePointerAction";
NSString *kSelectPreviousPanePointerAction = @"kSelectPreviousPanePointerAction";
NSString *kExtendSelectionPointerAction = @"kExtendSelectionPointerAction";
NSString *kQuickLookAction = @"kQuickLookAction";
NSString *kIgnoreAction = @"kIgnoreAction";
NSString *kSelectMenuItemPointerAction = @"kSelectMenuItemPointerAction";

typedef enum {
    kNoArg,
    kEscPlusArg,
    kHexCodeArg,
    kTextArg,
    kProfileArg,
    kAdvancedPasteArg,
    kMenuItemArg,
    kScriptFunctionArg
} ArgumentType;

@interface NSString (PointerPrefsController)
- (NSComparisonResult)comparePointerActions:(NSString *)other;
@end

@interface NSDictionary (PointerPrefsController)
- (NSComparisonResult)comparePointerPrefsValue:(NSDictionary *)other;
@end

@interface PointerPrefsController (Private)
+ (NSDictionary *)dictForAction:(NSString *)action;
+ (NSString *)modCharsForMask:(int)modifiers;
+ (int)maskForModChars:(NSString *)modChars;
+ (NSString *)keyForButton:(int)button clicks:(int)clicks modifiers:(int)modifiers;
+ (NSString *)keyForGesture:(NSString *)gestureDescription modifiers:(int)modifiers;
+ (BOOL)keyIsButton:(NSString *)key;
+ (NSArray *)buttonKeyComponents:(NSString *)key;
+ (NSArray *)gestureKeyComponents:(NSString *)key;
+ (int)buttonForKey:(NSString *)key;
+ (int)numClicksForKey:(NSString *)key;
+ (NSString *)localizedNumClicks:(int)n;
+ (NSString *)localizedButtonNameForButtonNumber:(int)n;
+ (NSString *)localizedGestureNameForGestureIdentifier:(NSString *)ident;
+ (NSString *)localizedModifiers:(int)keyMods;
+ (NSDictionary *)localizedActionMap;
+ (NSString *)localizedActionForDict:(NSDictionary *)dict;
+ (NSString *)localizedActionForKey:(NSString *)key;
+ (NSString *)gestureIdentifierForKey:(NSString *)key;
+ (int)modifiersForKey:(NSString *)key;
+ (NSDictionary *)defaultActions;
+ (NSDictionary *)settings;
+ (void)setSettings:(NSDictionary *)newSettings;
+ (NSArray *)sortedKeys;
+ (NSString *)keyForRowIndex:(int)rowIndex;
+ (int)tagForGestureIdentifier:(NSString *)ident;
- (BOOL)okShouldBeEnabled;
- (void)editKey:(NSString *)key;
+ (BOOL)keyIsThreeFingerTap:(NSString *)key;
@end

@implementation PointerPrefsController {
    IBOutlet NSTableView *tableView_;
    IBOutlet NSTableColumn *buttonColumn_;
    IBOutlet NSTableColumn *actionColumn_;

    IBOutlet NSPanel *panel_;
    IBOutlet NSTextField *editButtonLabel_;
    IBOutlet NSPopUpButton *editButton_;
    IBOutlet NSTextField *editModifiersLabel_;
    IBOutlet NSButton *editModifiersCommand_;
    IBOutlet NSButton *editModifiersOption_;
    IBOutlet NSButton *editModifiersShift_;
    IBOutlet NSButton *editModifiersControl_;
    IBOutlet NSTextField *editActionLabel_;
    IBOutlet NSPopUpButton *editAction_;
    IBOutlet NSTextField *editClickTypeLabel_;
    IBOutlet NSPopUpButton *editClickType_;
    IBOutlet NSTextField *editArgumentLabel_;
    IBOutlet NSPopUpButton *editArgumentButton_;
    IBOutlet NSTextField *editArgumentField_;

    IBOutlet NSButton *ok_;
    IBOutlet NSButton *remove_;
    iTermPasteSpecialViewController *_pasteSpecialViewController;
    IBOutlet NSView *_pasteSpecialViewContainer;

    IBOutlet iTermMenuItemPopupView *_menuItemPopupView;

    iTermFunctionCallTextFieldDelegate *_invocationDelegate;

    NSRect _initialFrame;
    NSRect _initialPasteContainerFrame;

    NSString *origKey_;
    int version_;
}

- (void)dealloc {
    tableView_.delegate = nil;
    tableView_.dataSource = nil;
}

+ (NSDictionary *)dictForAction:(NSString *)action {
    return [NSDictionary dictionaryWithObject:action forKey:kActionKey];
}

+ (NSString *)modCharsForMask:(int)modifiers
{
    NSMutableString *modStr = [NSMutableString string];
    if (modifiers & NSEventModifierFlagCommand) {
        [modStr appendString:kCommandKeyChar];
    }
    if (modifiers & NSEventModifierFlagOption) {
        [modStr appendString:kOptionKeyChar];
    }
    if (modifiers & NSEventModifierFlagShift) {
        [modStr appendString:kShiftKeyChar];
    }
    if (modifiers & NSEventModifierFlagControl) {
        [modStr appendString:kControlKeyChar];
    }
    return modStr;
}

+ (int)maskForModChars:(NSString *)modChars
{
    int mask = 0;
    if ([modChars rangeOfString:kCommandKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagCommand;
    }
    if ([modChars rangeOfString:kOptionKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagOption;
    }
    if ([modChars rangeOfString:kShiftKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagShift;
    }
    if ([modChars rangeOfString:kControlKeyChar].location != NSNotFound) {
        mask |= NSEventModifierFlagControl;
    }
    return mask;
}

+ (NSString *)keyForButton:(int)button clicks:(int)clicks modifiers:(int)modifiers
{
    NSString *modStr = [PointerPrefsController modCharsForMask:modifiers];
    return [NSString stringWithFormat:@"%@,%d,%d,%@,", kButtonSchema, button, clicks, modStr];
}

+ (NSString *)keyForGesture:(NSString *)gestureDescription modifiers:(int)modifiers
{
    return [NSString stringWithFormat:@"%@,%@,%@,",
                kGestureSchema,
                gestureDescription,
                [PointerPrefsController modCharsForMask:modifiers]];
}

+ (BOOL)keyIsButton:(NSString *)key
{
    return [key hasPrefix:kButtonSchema];
}

+ (BOOL)keyIsThreeFingerTap:(NSString *)key
{
    if (![key hasPrefix:kGestureSchema]) {
        return NO;
    }
    NSArray *components = [PointerPrefsController gestureKeyComponents:key];
    NSString *gesture = [components objectAtIndex:1];
    return [gesture isEqualToString:kThreeFingerClickGesture];
}

+ (NSArray *)buttonKeyComponents:(NSString *)key
{
    // Parse string like "Button,1,2,cso,freeform text"
    // Field 1: "Button"
    // Field 2: Button number (0-maxint)
    // Field 3: Number of clicks (0-4)
    // Field 4: Modifiers mask, including c, o, s, and ^ optionally (cmd, opt, shift, ctrl).
    // Field 5: Arbitrary textual parameter [may be empty]
    NSArray *a = [key componentsSeparatedByString:@","];
    if (a.count == 5 && [[a objectAtIndex:0] isEqualToString:kButtonSchema]) {
        return a;
    } else {
        return nil;
    }
}

+ (NSArray *)gestureKeyComponents:(NSString *)key
{
    // Parse string like "Gesture,Three Finger Click,cso,free form text"
    // Field 1: "Gesture"
    // Field 2: Gesture identifier string
    // Field 3: Modifiers mask, including c, o, s, and ^ optionally (cmd, opt, shift, ctrl).
    // Field 4: Arbitrary textual parameter [may be empty]
    NSArray *a = [key componentsSeparatedByString:@","];
    if (a.count == 4 && [[a objectAtIndex:0] isEqualToString:kGestureSchema]) {
        return a;
    } else {
        return nil;
    }
}

+ (int)buttonForKey:(NSString *)key
{
    NSArray *parts = [PointerPrefsController buttonKeyComponents:key];
    if (parts) {
        return [[parts objectAtIndex:1] intValue];
    } else {
        return -1;
    }
}

+ (int)numClicksForKey:(NSString *)key
{
    NSArray *parts = [PointerPrefsController buttonKeyComponents:key];
    if (parts) {
        return [[parts objectAtIndex:2] intValue];
    } else {
        return -1;
    }
}

+ (NSString *)localizedNumClicks:(int)n
{
    switch (n) {
        case 1:
            return @"single click";
        case 2:
            return @"double click";
        case 3:
            return @"triple click";
        case 4:
            return @"quad click";
        default:
            return @"(error)";  // shouldn't happen
    }
}

+ (NSString *)localizedButtonNameForButtonNumber:(int)n
{
    switch (n) {
        case -1:
            return @"Unknown button";
        case kLeftButton:
            return @"Left button";
        case kRightButton:
            return @"Right button";
        case kMiddleButton:
            return @"Middle button";
        default:
            return [NSString stringWithFormat:@"Button #%d", n+1];
    }
}

+ (NSDictionary *)gestureNamesDict
{
    NSDictionary *names = @{ kThreeFingerClickGesture: @"Three-finger Tap",
                             kThreeFingerSwipeRight: @"Three-finger Swipe Right",
                             kThreeFingerSwipeLeft: @"Three-finger Swipe Left",
                             kThreeFingerSwipeUp: @"Three-finger Swipe Up",
                             kThreeFingerSwipeDown: @"Three-finger Swipe Down",
                             kForceTouchSingleClick: @"Force Touch Single Click" };
    return names;
}

+ (NSString *)localizedGestureNameForGestureIdentifier:(NSString *)ident
{
    NSDictionary *names = [PointerPrefsController gestureNamesDict];
    NSString *name = [names objectForKey:ident];
    if (name) {
        return name;
    } else {
        // Shouldn't happen
        return ident;
    }
}

+ (int)tagForGestureIdentifier:(NSString *)ident
{
    NSArray *keys = @[ kThreeFingerClickGesture,
                       kThreeFingerSwipeRight,
                       kThreeFingerSwipeLeft,
                       kThreeFingerSwipeUp,
                       kThreeFingerSwipeDown,
                       kForceTouchSingleClick ];

    NSUInteger i = [keys indexOfObject:ident];
    if (i == NSNotFound) {
        return -1;
    }
    return i + kMinGestureTag;
}

+ (NSString *)actionWithLocalizedName:(NSString *)localizedName
{
    NSDictionary *actionMap = [PointerPrefsController localizedActionMap];
    for (NSString *action in actionMap) {
        NSString *curName = [actionMap objectForKey:action];
        if ([curName isEqualToString:localizedName]) {
            return action;
        }
    }
    return [NSString stringWithFormat:@"Bad name: %@", localizedName];
}

+ (NSString *)gestureIdentifierForTag:(int)tag
{
    switch (tag) {
        case kThreeFingerTapGestureTag:
            return kThreeFingerClickGesture;
        case kThreeFingerSwipeRightGestureTag:
            return kThreeFingerSwipeRight;
        case kThreeFingerSwipeLeftGestureTag:
            return kThreeFingerSwipeLeft;
        case kThreeFingerSwipeUpGestureTag:
            return kThreeFingerSwipeUp;
        case kThreeFingerSwipeDownGestureTag:
            return kThreeFingerSwipeDown;
        case kForceTouchSingleClickTag:
            return kForceTouchSingleClick;
        default:
            return [NSString stringWithFormat:@"Bad tag %d", tag];
    }
}

+ (NSString *)localizedModifiers:(int)keyMods {
    return [NSString stringForModifiersWithMask:keyMods];
}

+ (NSDictionary *)localizedActionMap
{
    NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"Ignore", kIgnoreAction,
                           @"Invoke Script Function…", kInvokeScriptFunction,
                           @"Paste from Clipboard…", kPasteFromClipboardPointerAction,
                           @"Paste from Selection…", kPasteFromSelectionPointerAction,
                           @"Extend Selection", kExtendSelectionPointerAction,
                           @"Open URL/Semantic History", kOpenTargetPointerAction,
                           @"Open URL in background", kOpenTargetInBackgroundPointerAction,
                           @"Smart Selection", kSmartSelectionPointerAction,
                           @"Smart Selection Ignoring Newlines", kSmartSelectionIgnoringNewlinesPointerAction,
                           @"Open Context Menu", kContextMenuPointerAction,
                           @"Next Tab", kNextTabPointerAction,
                           @"Previous Tab", kPrevTabPointerAction,
                           @"Next Window", kNextWindowPointerAction,
                           @"Previous Window", kPrevWindowPointerAction,
                           @"Move Pane", kMovePanePointerAction,
                           @"Send Escape Sequence…", kSendEscapeSequencePointerAction,
                           @"Send Hex Code…", kSendHexCodePointerAction,
                           @"Send Text…", kSendTextPointerAction,
                           @"Select Pane Left", kSelectPaneLeftPointerAction,
                           @"Select Pane Right", kSelectPaneRightPointerAction,
                           @"Select Pane Above", kSelectPaneAbovePointerAction,
                           @"Select Pane Below", kSelectPaneBelowPointerAction,
                           @"New Window With Profile…", kNewWindowWithProfilePointerAction,
                           @"New Tab With Profile…", kNewWindowWithProfilePointerAction,
                           @"New Tab With Profile…", kNewTabWithProfilePointerAction,
                           @"New Vertical Split With Profile…", kNewVerticalSplitWithProfilePointerAction,
                           @"New Horizontal Split With Profile…", kNewHorizontalSplitWithProfilePointerAction,
                           @"QuickLook", kQuickLookAction,
                           @"Select Menu Item", kSelectMenuItemPointerAction,
                           @"Select Next Pane", kSelectNextPanePointerAction,
                           @"Select Previous Pane", kSelectPreviousPanePointerAction,
                           nil];
    return names;
}

+ (ArgumentType)argumentTypeForAction:(NSString *)action
{
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                          @(kEscPlusArg), kSendEscapeSequencePointerAction,
                          @(kHexCodeArg), kSendHexCodePointerAction,
                          @(kTextArg), kSendTextPointerAction,
                          @(kScriptFunctionArg), kInvokeScriptFunction,
                          @(kProfileArg), kNewWindowWithProfilePointerAction,
                          @(kProfileArg), kNewTabWithProfilePointerAction,
                          @(kProfileArg), kNewVerticalSplitWithProfilePointerAction,
                          @(kProfileArg), kNewHorizontalSplitWithProfilePointerAction,
                          @(kAdvancedPasteArg), kPasteFromClipboardPointerAction,
                          @(kAdvancedPasteArg), kPasteFromSelectionPointerAction,
                          @(kMenuItemArg), kSelectMenuItemPointerAction,
                          nil];
    NSNumber *n = [args objectForKey:action];
    if (n) {
        return (ArgumentType) [n intValue];
    } else {
        return (ArgumentType) kNoArg;
    }
}

+ (NSString *)localizedActionForDict:(NSDictionary *)dict
{
    NSDictionary *names = [PointerPrefsController localizedActionMap];
    NSString *action = [dict objectForKey:kActionKey];
    NSString *name = nil;
    if (action) {
        name = [names objectForKey:action];
    }
    if (!name) {
        name = @"(Unknown)";
    }
    return name;
}

+ (NSString *)formattedLocalizedActionForDict:(NSDictionary *)dict {
    NSDictionary *names = [PointerPrefsController localizedActionMap];
    NSString *action = [dict objectForKey:kActionKey];
    NSString *argument = [dict objectForKey:kArgumentKey];
    NSString *name = nil;
    if (action) {
        name = [names objectForKey:action];
    }
    if (!name) {
        name = @"(Unknown)";
    }
    if (action) {
        switch ([PointerPrefsController argumentTypeForAction:action]) {
            case kNoArg:
                break;
            case kEscPlusArg:
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:@" Esc + %@", argument]];
            case kHexCodeArg:
            case kTextArg:
            case kScriptFunctionArg:
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:@" \"%@\"", argument]];
            case kProfileArg: {
                NSString *bookmarkName = [[[ProfileModel sharedInstance] bookmarkWithGuid:argument] objectForKey:KEY_NAME];
                if (!bookmarkName) {
                    bookmarkName = @"?";
                }
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:@" \"%@\"", bookmarkName]];
            }
            case kAdvancedPasteArg: {
                if (argument.length) {
                    return [NSString stringWithFormat:@"%@: %@",
                            [name stringByReplacingOccurrencesOfString:@"…" withString:@""],
                            [iTermPasteSpecialViewController descriptionForCodedSettings:argument]];
                }
                break;
            }
            case kMenuItemArg: {
                NSArray *parts = [argument componentsSeparatedByString:@"\n"];
                NSString *title = parts.firstObject;
                if (!title.length) {
                    break;
                }
                return [NSString stringWithFormat:@"Select Menu Item “%@”", title];
            }
        }
    }

    return name;
}

+ (NSString *)localizedActionForKey:(NSString *)key
{
    NSDictionary *dict = [[PointerPrefsController settings] objectForKey:key];
    return [PointerPrefsController localizedActionForDict:dict];
}

+ (NSString *)gestureIdentifierForKey:(NSString *)key
{
    NSArray *parts = [PointerPrefsController gestureKeyComponents:key];
    if (parts) {
        return [parts objectAtIndex:1];
    } else {
        return nil;
    }
}

+ (int)modifiersForKey:(NSString *)key
{
    NSArray *parts;
    int i;
    if ([PointerPrefsController keyIsButton:key]) {
        parts = [PointerPrefsController buttonKeyComponents:key];
        i = 3;
    } else {
        parts = [PointerPrefsController gestureKeyComponents:key];
        i = 2;
    }
    if (parts) {
        return [PointerPrefsController maskForModChars:[parts objectAtIndex:i]];
    } else {
        return 0;
    }
}

+ (NSDictionary *)defaultSettings
{
    NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"DefaultPointerActions"
                                                                           ofType:@"plist"];
    return [NSDictionary dictionaryWithContentsOfFile:plistFile];
}

+ (NSDictionary *)defaultActions
{
    static NSDictionary *defaultDict;
    if (!defaultDict) {
        NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[PointerPrefsController defaultSettings]];
        if ([iTermPreferences boolForKey:kPreferenceKeyThreeFingerEmulatesMiddle]) {
            // Find all actions that use middle button and add corresponding three-finger gesture.
            NSMutableDictionary *tempCopy = [temp mutableCopy];
            for (NSString *key in temp) {
                if ([PointerPrefsController keyIsButton:key] &&
                    [PointerPrefsController buttonForKey:key] == kMiddleButton) {
                    NSDictionary *middleAction = [temp objectForKey:key];
                    NSString *gestureKey = [PointerPrefsController keyForGesture:kThreeFingerClickGesture
                                                                       modifiers:[PointerPrefsController modifiersForKey:key]];
                    [tempCopy setObject:middleAction forKey:gestureKey];
                }
            }
            temp = tempCopy;
            int modMasks[] = { NSEventModifierFlagCommand, NSEventModifierFlagOption, NSEventModifierFlagControl, NSEventModifierFlagShift };
            int numModCombos = 1 << (sizeof(modMasks) / sizeof(int));
            for (int numClicks = 0; numClicks <= kMaxClicks; numClicks++) {
                // i is a bitmask over the modMasks array indices.
                for (int i = 0; i < numModCombos; i++) {
                    int modifiers = 0;
                    // Set modifiers to the OR of the NS...KeyMask values given the bits in i.
                    for (int j = 0; j < sizeof(modMasks)/sizeof(int); j++) {
                        if (i & (1 << j)) {
                            // The j'th bit is set in i, so OR in the j'th modifier mask.
                            modifiers |= modMasks[j];
                        }
                    }
                    NSString *key = [PointerPrefsController keyForButton:kMiddleButton
                                                                  clicks:numClicks
                                                               modifiers:modifiers];
                    NSDictionary *middleAction = [temp objectForKey:key];
                    if (middleAction) {
                        [temp setObject:middleAction forKey:key];
                    }
                }
            }
        }
        defaultDict = temp;
    }
    return defaultDict;
}

+ (NSDictionary *)settings
{
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kPointerActionsKey];
    if (!dict) {
        dict = [PointerPrefsController defaultActions];
        [[NSUserDefaults standardUserDefaults] setObject:dict forKey:kPointerActionsKey];
    }
    return dict;
}

+ (void)setSettings:(NSDictionary *)newSettings
{
    [[NSUserDefaults standardUserDefaults] setObject:newSettings forKey:kPointerActionsKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPointerPrefsChangedNotification
                                                        object:nil];
}

+ (NSArray *)sortedKeys
{
//    NSArray *keys = [[PointerPrefsController settings] keysSortedByValueUsingSelector:@selector(comparePointerPrefsValue:)];
    NSArray *keys = [[[PointerPrefsController settings] allKeys] sortedArrayUsingSelector:@selector(comparePointerActions:)];
    return keys;
}

- (void)awakeFromNib
{
    [tableView_ setDoubleAction:@selector(tableViewRowDoubleClicked:)];
    [tableView_ setTarget:self];
    NSArray *actions = [[[PointerPrefsController localizedActionMap] allValues] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [editAction_ addItemsWithTitles:actions];
}

+ (NSString *)keyForRowIndex:(int)rowIndex
{
    NSArray *sortedKeys = [PointerPrefsController sortedKeys];
    NSString *key = [sortedKeys objectAtIndex:rowIndex];
    return key;
}

+ (NSString *)argumentWithButton:(int)buttonNumber
                       numClicks:(int)numClicks
                       modifiers:(int)modMask {
    NSString *key = [PointerPrefsController keyForButton:buttonNumber
                                                  clicks:numClicks
                                               modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [setting objectForKey:kArgumentKey];
}

+ (BOOL)useCompatibilityEscapingWithButton:(int)buttonNumber
                                 numClicks:(int)numClicks
                                 modifiers:(int)modMask {
    NSString *key = [PointerPrefsController keyForButton:buttonNumber
                                                  clicks:numClicks
                                               modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

+ (NSString *)actionWithButton:(int)buttonNumber
                     numClicks:(int)numClicks
                     modifiers:(int)modMask
{
    NSString *key = [PointerPrefsController keyForButton:buttonNumber
                                                  clicks:numClicks
                                               modifiers:modMask];
    DLog(@"Look up key %@", key);
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    NSString *action = [setting objectForKey:kActionKey];
    return action;
}

+ (NSString *)actionForTapWithTouches:(int)numTouches
                            modifiers:(int)modMask
{
    NSString *gesture = @"";
    if (numTouches == 3) {
        gesture = kThreeFingerClickGesture;
    } else {
        return nil;
    }
    return [PointerPrefsController actionForGesture:gesture modifiers:modMask];
}

+ (NSString *)argumentForTapWithTouches:(int)numTouches
                              modifiers:(int)modMask
{
    NSString *gesture = @"";
    if (numTouches == 3) {
        gesture = kThreeFingerClickGesture;
    } else {
        return nil;
    }
    return [PointerPrefsController argumentForGesture:gesture modifiers:modMask];
}

+ (BOOL)useCompatibilityEscapingForTapWithTouches:(int)numTouches
                                        modifiers:(int)modMask {
    NSString *gesture = @"";
    if (numTouches == 3) {
        gesture = kThreeFingerClickGesture;
    } else {
        return NO;
    }
    return [PointerPrefsController useCompatibilityEscapingForGesture:gesture modifiers:modMask];
}

+ (NSString *)actionForGesture:(NSString *)gesture
                     modifiers:(int)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    DLog(@"Look up action for gesture %@", key);
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [setting objectForKey:kActionKey];
}

+ (BOOL)useCompatibilityEscapingForGesture:(NSString *)gesture
                                 modifiers:(int)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    DLog(@"Look up use compatibility escaping for gesture %@", key);
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

+ (NSString *)argumentForGesture:(NSString *)gesture
                       modifiers:(int)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [setting objectForKey:kArgumentKey];
}

+ (BOOL)compatibilityEscapingForGesture:(NSString *)gesture
                              modifiers:(NSEventModifierFlags)modMask {
    NSString *key;
    key = [PointerPrefsController keyForGesture:gesture
                                      modifiers:modMask];
    NSDictionary *settings = [PointerPrefsController settings];
    NSDictionary *setting = [settings objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

+ (BOOL)haveThreeFingerTapEvents
{
    for (NSString *key in [PointerPrefsController sortedKeys]) {
        if ([PointerPrefsController keyIsThreeFingerTap:key]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[PointerPrefsController settings] count];
}

+ (NSString *)localizedButton:(int)buttonNumber numClicks:(int)clicks modifiers:(int)modFlags
{
    NSString *button = [PointerPrefsController localizedButtonNameForButtonNumber:buttonNumber];
    NSString *numClicks = [PointerPrefsController localizedNumClicks:clicks];
    NSString *modifiers = [PointerPrefsController localizedModifiers:modFlags];
    if ([modifiers length]) {
        modifiers = [modifiers stringByAppendingString:@" + "];
    }
    return [NSString stringWithFormat:@"%@%@ %@", modifiers, button, numClicks];
}

+ (NSString *)localizedButtonKey:(NSString *)key
{
    return [PointerPrefsController localizedButton:[PointerPrefsController buttonForKey:key]
                                         numClicks:[PointerPrefsController numClicksForKey:key]
                                         modifiers:[PointerPrefsController modifiersForKey:key]];
}

- (void)setModifierButtons:(int)modMask
{
    [editModifiersCommand_ setState:(modMask & NSEventModifierFlagCommand) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersOption_ setState:(modMask & NSEventModifierFlagOption) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersShift_ setState:(modMask & NSEventModifierFlagShift) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersControl_ setState:(modMask & NSEventModifierFlagControl) ? NSControlStateValueOn : NSControlStateValueOff];
}

- (void)setButtonNumber:(int)buttonNumber clickCount:(int)clickCount modifiers:(int)modMask
{
    DLog(@"PointerPrefsController setButtonNumber:%d clickCount:%d modifiers:0x%x",
         buttonNumber, clickCount, modMask);
    if (buttonNumber >= 1 && clickCount > 0 && clickCount < 5) {
        [editButton_ selectItemWithTag:buttonNumber];
        [editClickType_ selectItemWithTag:clickCount];
        [self setModifierButtons:modMask];
        [self buttonOrGestureChanged:nil];
    }
}

- (void)setGesture:(NSString *)gesture modifiers:(int)modMask
{
    [editButton_ selectItemWithTag:[PointerPrefsController tagForGestureIdentifier:gesture]];
    [self setModifierButtons:modMask];
    [self buttonOrGestureChanged:nil];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
    row:(NSInteger)rowIndex {
    NSString *key = [PointerPrefsController keyForRowIndex:rowIndex];
    NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];
    BOOL isButton = [PointerPrefsController keyIsButton:key];

    if (aTableColumn == buttonColumn_) {
        if (isButton) {
            return [PointerPrefsController localizedButtonKey:key];
        } else {
            NSString *modifiers = [PointerPrefsController localizedModifiers:[PointerPrefsController modifiersForKey:key]];
            if ([modifiers length]) {
                modifiers = [modifiers stringByAppendingString:@" + "];
            }
            NSString *gesture = [PointerPrefsController localizedGestureNameForGestureIdentifier:[PointerPrefsController gestureIdentifierForKey:key]];
            return [NSString stringWithFormat:@"%@%@", modifiers, gesture];
        }
    } else {
        // Action
        return [PointerPrefsController formattedLocalizedActionForDict:action];
    }
}

- (BOOL)okShouldBeEnabled
{
    if (![editButton_ selectedItem]) {
        return NO;
    }
    if (![editAction_ selectedItem]) {
        return NO;
    }
    if ([editButton_ selectedTag] >= kMinGestureTag) {
        // Gesture
        return YES;
    } else {
        // Button
        return [editClickType_ selectedItem] != nil;
    }
}

+ (NSString *)actionForKey:(NSString *)key {
    NSDictionary *setting = [[PointerPrefsController settings] objectForKey:key];
    return [setting objectForKey:kActionKey];
}

+ (NSString *)argumentForKey:(NSString *)key {
    NSDictionary *setting = [[PointerPrefsController settings] objectForKey:key];
    return [setting objectForKey:kArgumentKey];
}

+ (BOOL)useCompatibilityEscapingForKey:(NSString *)key {
    NSDictionary *setting = [[PointerPrefsController settings] objectForKey:key];
    return [[setting objectForKey:kVersionKey] intValue] == 0;
}

- (void)updateArgumentFieldsForAction:(NSString *)actionIdent argument:(NSString *)currentArg
{
    if (NSEqualRects(NSZeroRect, _initialFrame)) {
        _initialFrame = _pasteSpecialViewContainer.window.frame;
        _initialPasteContainerFrame = _pasteSpecialViewContainer.frame;
    }
    ArgumentType argType = kNoArg;
    if (actionIdent) {
        argType = [PointerPrefsController argumentTypeForAction:actionIdent];
    }
    switch (argType) {
        case kNoArg:
            [editArgumentLabel_ setHidden:YES];
            [editArgumentField_ setHidden:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            _pasteSpecialViewContainer.hidden = YES;
            break;

        case kEscPlusArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:@"Esc +"];
            [[editArgumentField_ cell] setPlaceholderString:@"characters to send"];
            [editArgumentField_ setStringValue:currentArg];
            [editArgumentField_ setRefusesFirstResponder:NO];
            [editArgumentField_ setSelectable:YES];
            _pasteSpecialViewContainer.hidden = YES;
            editArgumentField_.delegate = nil;
            break;

        case kHexCodeArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:@"Hex codes:"];
            [[editArgumentField_ cell] setPlaceholderString:@"ex: 0x7f 0x20"];
            [editArgumentField_ setStringValue:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            editArgumentField_.delegate = nil;
            break;

        case kTextArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:@"Text:"];
            [[editArgumentField_ cell] setPlaceholderString:@"Enter value to send"];
            [editArgumentField_ setStringValue:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            editArgumentField_.delegate = nil;
            break;

        case kScriptFunctionArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:NO];
            [editArgumentField_ setEnabled:YES];
            [editArgumentButton_ setHidden:YES];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:@"Text:"];
            [[editArgumentField_ cell] setPlaceholderString:@"Enter function invocation"];
            [editArgumentField_ setStringValue:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            _invocationDelegate = [[iTermFunctionCallTextFieldDelegate alloc] initWithPathSource:[iTermVariableHistory pathSourceForContext:iTermVariablesSuggestionContextSession]
                                                                                     passthrough:nil
                                                                                   functionsOnly:YES];
            editArgumentField_.delegate = _invocationDelegate;
            break;

        case kProfileArg:
            [editArgumentLabel_ setHidden:NO];
            [editArgumentField_ setHidden:YES];
            [editArgumentButton_ setHidden:NO];
            _menuItemPopupView.hidden = YES;
            [editArgumentLabel_ setStringValue:@"Profile:"];
            [editArgumentButton_ populateWithProfilesSelectingGuid:currentArg];
            _pasteSpecialViewContainer.hidden = YES;
            break;

        case kAdvancedPasteArg:
            editArgumentLabel_.hidden = YES;
            editArgumentField_.hidden = YES;
            editArgumentButton_.hidden = YES;
            _pasteSpecialViewContainer.hidden = NO;
            _menuItemPopupView.hidden = YES;
            [self configurePasteSpecialWithArgument:currentArg];
            break;

        case kMenuItemArg: {
            editArgumentLabel_.hidden = YES;
            editArgumentField_.hidden = YES;
            editArgumentButton_.hidden = YES;
            _pasteSpecialViewContainer.hidden = YES;
            _menuItemPopupView.hidden = NO;
            [_menuItemPopupView reloadData];
            NSArray<NSString *> *parts = [currentArg componentsSeparatedByString:@"\n"];
            if (parts.count > 0) {
                (void)[_menuItemPopupView selectItemWithIdentifier:parts.firstObject];
            }
            break;
        }

    }
    [self updateWindowFrame];
}

- (void)loadKeyIntoEditPane:(NSString *)key
{
    int modMask;
    if (key) {
        modMask = [PointerPrefsController modifiersForKey:key];
    } else {
        modMask = 0;
    }
    NSString *localizedAction = @"";
    if (key) {
        localizedAction = [PointerPrefsController localizedActionForKey:key];
    }
    NSString *actionIdent = [PointerPrefsController actionForKey:key];
    NSString *currentArg = [PointerPrefsController argumentForKey:key];
    [self updateArgumentFieldsForAction:actionIdent argument:currentArg];

    [editModifiersCommand_ setState:(modMask & NSEventModifierFlagCommand) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersOption_ setState:(modMask & NSEventModifierFlagOption) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersShift_ setState:(modMask & NSEventModifierFlagShift) ? NSControlStateValueOn : NSControlStateValueOff];
    [editModifiersControl_ setState:(modMask & NSEventModifierFlagControl) ? NSControlStateValueOn : NSControlStateValueOff];
    [editAction_ selectItemWithTitle:localizedAction];
    BOOL isButton = !key || [PointerPrefsController keyIsButton:key];
    if (isButton) {
        int button = key ? [PointerPrefsController buttonForKey:key] : 2;
        int numClicks = key ? [PointerPrefsController numClicksForKey:key] : 1;

        [editButton_ selectItemWithTag:button];
        [editClickType_ selectItemWithTag:numClicks];
    } else {
        NSString *gestureIdent = [PointerPrefsController gestureIdentifierForKey:key];
        [editButton_ selectItemWithTag:[PointerPrefsController tagForGestureIdentifier:gestureIdent]];
        [editClickType_ selectItem:nil];
    }
    origKey_ = key;
    if (key) {
        version_ = [PointerPrefsController useCompatibilityEscapingForKey:key] ? 0 : 1;
    } else {
        version_ = 1;
    }
    [self buttonOrGestureChanged:nil];
    [ok_ setEnabled:[self okShouldBeEnabled]];
}

- (IBAction)buttonOrGestureChanged:(id)sender
{
    if ([editButton_ selectedTag] >= kMinGestureTag) {
        editClickTypeLabel_.labelEnabled = NO;
        [editClickType_ setEnabled:NO];
    } else {
        editClickTypeLabel_.labelEnabled = YES;
        [editClickType_ setEnabled:YES];
    }
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
    int rowIndex = [tableView_ selectedRow];

    if (self.hasSelection) {
        NSString *key = [PointerPrefsController keyForRowIndex:rowIndex];
        NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];

        [editButton_ selectItemWithTag:[PointerPrefsController buttonForKey:key]];
        [editAction_ selectItemWithTitle:[PointerPrefsController localizedActionForDict:action]];

        int modflags = [PointerPrefsController modifiersForKey:key];
        [editModifiersCommand_ setState:(modflags & NSEventModifierFlagCommand) ? NSControlStateValueOn : NSControlStateValueOff];
        [editModifiersOption_ setState:(modflags & NSEventModifierFlagOption) ? NSControlStateValueOn : NSControlStateValueOff];
        [editModifiersShift_ setState:(modflags & NSEventModifierFlagShift) ? NSControlStateValueOn : NSControlStateValueOff];
        [editModifiersControl_ setState:(modflags & NSEventModifierFlagControl) ? NSControlStateValueOn : NSControlStateValueOff];
    }
    editButtonLabel_.labelEnabled = self.hasSelection;
    editModifiersLabel_.labelEnabled = self.hasSelection;
    editActionLabel_.labelEnabled = self.hasSelection;
}

- (void)tableViewRowDoubleClicked:(id)sender
{
    if ([tableView_ selectedRow] >= 0) {
        NSString *key = [PointerPrefsController keyForRowIndex:[tableView_ selectedRow]];
        [self editKey:key];
    }
}

- (void)editKey:(NSString *)key {
    [self loadKeyIntoEditPane:key];
    __weak __typeof(self) weakSelf = self;
    [[[PreferencePanel sharedInstance] window] beginSheet:panel_
                                        completionHandler:^(NSModalResponse returnCode) {
                                            __strong __typeof(weakSelf) strongSelf = self;
                                            if (strongSelf) {
                                                [strongSelf->panel_ close];
                                            }
                                        }];
}

- (IBAction)ok:(id)sender {
    NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[PointerPrefsController settings]];
    if (origKey_) {
        [temp removeObjectForKey:origKey_];
    }
    NSString *theAction = [PointerPrefsController actionWithLocalizedName:[[editAction_ selectedItem] title]];
    NSMutableDictionary *newValue = [NSMutableDictionary dictionaryWithObject:theAction
                                                                       forKey:kActionKey];
    newValue[kVersionKey] = @(version_);
    if (![editArgumentField_ isHidden]) {
        [newValue setObject:[editArgumentField_ stringValue]
                     forKey:kArgumentKey];
    } else if (![editArgumentButton_ isHidden]) {
        if ([PointerPrefsController argumentTypeForAction:theAction] == kProfileArg) {
            NSString *profileName = [[editArgumentButton_ selectedItem] title];
            NSString *guid = [[[ProfileModel sharedInstance] bookmarkWithName:profileName] objectForKey:KEY_GUID];
            if (guid) {
                [newValue setObject:guid forKey:kArgumentKey];
            } else {
                [newValue setObject:@"" forKey:kArgumentKey];
            }
        } else {
            [newValue setObject:[[editArgumentButton_ selectedItem] title]
                         forKey:kArgumentKey];
        }
    } else if (!_pasteSpecialViewContainer.isHidden) {
        if ([PointerPrefsController argumentTypeForAction:theAction] == kAdvancedPasteArg) {
            [newValue setObject:[_pasteSpecialViewController stringEncodedSettings] ?: @""
                         forKey:kArgumentKey];
        }
    } else if (!_menuItemPopupView.isHidden) {
        newValue[kArgumentKey] = [NSString stringWithFormat:@"%@\n%@", _menuItemPopupView.selectedIdentifier, _menuItemPopupView.selectedTitle];
    }
    NSString *newKey;
    int modMask = 0;
    if ([editModifiersCommand_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagCommand;
    }
    if ([editModifiersOption_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagOption;
    }
    if ([editModifiersShift_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagShift;
    }
    if ([editModifiersControl_ state] == NSControlStateValueOn) {
        modMask |= NSEventModifierFlagControl;
    }
    if ([editButton_ selectedTag] >= kMinGestureTag) {
        // Gesture
        newKey = [PointerPrefsController keyForGesture:[PointerPrefsController gestureIdentifierForTag:[editButton_ selectedTag]]
                                             modifiers:modMask];
    } else {
        // Button
        newKey = [PointerPrefsController keyForButton:[editButton_ selectedTag]
                                               clicks:[editClickType_ selectedTag]
                                            modifiers:modMask];
    }
    [temp setObject:newValue forKey:newKey];
    [PointerPrefsController setSettings:temp];
    [tableView_ reloadData];
    [[[PreferencePanel sharedInstance] window] endSheet:panel_];
}

- (IBAction)cancel:(id)sender {
    [[[PreferencePanel sharedInstance] window] endSheet:panel_];
}

- (IBAction)add:(id)sender
{
    [self editKey:nil];
}

- (IBAction)remove:(id)sender
{
    if ([tableView_ selectedRow] >= 0) {
        NSString *key = [PointerPrefsController keyForRowIndex:[tableView_ selectedRow]];
        NSMutableDictionary *temp = [NSMutableDictionary dictionaryWithDictionary:[PointerPrefsController settings]];
        if (key) {
            [temp removeObjectForKey:key];
            [PointerPrefsController setSettings:temp];
        }
        [tableView_ reloadData];
    }
}

- (IBAction)actionChanged:(id)sender
{
    [ok_ setEnabled:[self okShouldBeEnabled]];
    NSString *actionIdent = [PointerPrefsController actionWithLocalizedName:[[editAction_ selectedItem] title]];
    [self updateArgumentFieldsForAction:actionIdent
                               argument:@""];
}

- (IBAction)clicksChanged:(id)sender
{
    [ok_ setEnabled:[self okShouldBeEnabled]];
}

- (IBAction)loadDefaults:(id)sender
{
    [PointerPrefsController setSettings:[PointerPrefsController defaultSettings]];
    [tableView_ reloadData];
}

- (void)configurePasteSpecialWithArgument:(NSString *)parameterValue {
    _pasteSpecialViewController = [[iTermPasteSpecialViewController alloc] init];
    [_pasteSpecialViewController view];

    // Set a few defaults; otherwise everything is reasonable.
    _pasteSpecialViewController.numberOfSpacesPerTab = [iTermPreferences intForKey:kPreferenceKeyPasteSpecialSpacesPerTab];
    _pasteSpecialViewController.shouldRemoveNewlines = NO;
    _pasteSpecialViewController.shouldBase64Encode = NO;
    _pasteSpecialViewController.shouldWaitForPrompt = NO;
    _pasteSpecialViewController.shouldEscapeShellCharsWithBackslash = NO;
    if (parameterValue.length > 0) {
        [_pasteSpecialViewController loadSettingsFromString:parameterValue];
    }
    _pasteSpecialViewController.view.frame = _pasteSpecialViewController.view.bounds;
    NSRect theFrame = _pasteSpecialViewContainer.frame;
    CGFloat originalHeight = theFrame.size.height;
    theFrame.size = _pasteSpecialViewController.view.bounds.size;
    theFrame.origin.y -= (theFrame.size.height - originalHeight);
    _pasteSpecialViewContainer.frame = theFrame;
    [_pasteSpecialViewContainer addSubview:_pasteSpecialViewController.view];
}

- (void)updateWindowFrame {
    NSRect frame;
    if (_pasteSpecialViewContainer.isHidden) {
        frame = _initialFrame;
    } else {
        frame = _initialFrame;
        NSSize desiredSize = _pasteSpecialViewController.view.frame.size;
        frame.size.width += desiredSize.width - _initialPasteContainerFrame.size.width;
        frame.size.height += desiredSize.height - _initialPasteContainerFrame.size.height;
    }
    [_pasteSpecialViewContainer.window setFrame:frame display:YES animate:YES];
}

@end

@implementation NSString (PointerPrefsController)

- (NSComparisonResult)comparePointerActions:(NSString *)other
{
    BOOL selfIsButton = [PointerPrefsController keyIsButton:self];
    BOOL otherIsButton = [PointerPrefsController keyIsButton:other];
    if (selfIsButton != otherIsButton) {
        // Compare dissimilar types
        if (selfIsButton) {
            return NSOrderedDescending;
        } else {
            return NSOrderedAscending;
        }
    }
    if (selfIsButton) {
        // Compare buttons
        NSArray *selfParts = [PointerPrefsController buttonKeyComponents:self];
        NSArray *otherParts = [PointerPrefsController buttonKeyComponents:other];
        if (!selfParts && !otherParts) {
            return NSOrderedSame;
        } else if (!selfParts && !otherParts) {
            return NSOrderedAscending;
        } else if (selfParts && !otherParts) {
            return NSOrderedDescending;
        }
        NSComparisonResult result;
        result = [[NSNumber numberWithInt:[[selfParts objectAtIndex:1] intValue]] compare:[NSNumber numberWithInt:[[otherParts objectAtIndex:1] intValue]]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[NSNumber numberWithInt:[[selfParts objectAtIndex:2] intValue]] compare:[NSNumber numberWithInt:[[otherParts objectAtIndex:2] intValue]]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:3] compare:[otherParts objectAtIndex:3]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:4] compare:[otherParts objectAtIndex:4]];
        return result;
    } else {
        // Compare gestures
        NSArray *selfParts = [PointerPrefsController gestureKeyComponents:self];
        NSArray *otherParts = [PointerPrefsController gestureKeyComponents:self];
        NSComparisonResult result;
        NSString *selfIdent = [PointerPrefsController localizedGestureNameForGestureIdentifier:[selfParts objectAtIndex:1]];
        NSString *otherIdent = [PointerPrefsController localizedGestureNameForGestureIdentifier:[otherParts objectAtIndex:1]];
        result = [selfIdent localizedCaseInsensitiveCompare:otherIdent];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[NSNumber numberWithInt:[[selfParts objectAtIndex:2] intValue]] compare:[NSNumber numberWithInt:[[otherParts objectAtIndex:2] intValue]]];
        if (result != NSOrderedSame) {
            return result;
        }
        result = [[selfParts objectAtIndex:3] compare:[otherParts objectAtIndex:3]];
        return result;
    }
}

@end

@implementation NSDictionary (PointerPrefsController)

- (NSComparisonResult)comparePointerPrefsValue:(NSDictionary *)other
{
    NSString *selfAction = [PointerPrefsController localizedActionForDict:self];
    NSString *otherAction = [PointerPrefsController localizedActionForDict:other];
    return [selfAction localizedCaseInsensitiveCompare:otherAction];
}

@end
