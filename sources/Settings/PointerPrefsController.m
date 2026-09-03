//
//  PointerPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 George Nachman. All rights reserved.
//

#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "NSPopUpButton+iTerm.h"
#import "NSTextField+iTerm.h"
#import "PointerController.h"
#import "PointerPrefsController.h"
#import "PreferencePanel.h"
#import "iTerm2SharedARC-Swift.h"
#import "iTermApplicationDelegate.h"
#import "iTermFunctionCallTextFieldDelegate.h"
#import "iTermPasteSpecialViewController.h"
#import "iTermUserDefaults.h"

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
NSString *kCopyLinkAddressPointerAction = @"kCopyLinkAddressPointerAction";
NSString *kCopyOrPastePointerAction = @"kCopyOrPastePointerAction";

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
            return ITLocalize(@"PointerPrefsController_Facing_SingleClick", @"single click", @"Text shown in localizedNumClicks:: single click");
        case 2:
            return ITLocalize(@"PointerPrefsController_Facing_DoubleClick", @"double click", @"Text shown in localizedNumClicks:: double click");
        case 3:
            return ITLocalize(@"PointerPrefsController_Facing_TripleClick", @"triple click", @"Text shown in localizedNumClicks:: triple click");
        case 4:
            return ITLocalize(@"PointerPrefsController_Facing_QuadClick", @"quad click", @"Text shown in localizedNumClicks:: quad click");
        default:
            return ITLocalize(@"PointerPrefsController_Facing_Error", @"(error)", @"Text shown in localizedNumClicks:: (error)");  // shouldn't happen
    }
}

+ (NSString *)localizedButtonNameForButtonNumber:(int)n
{
    switch (n) {
        case -1:
            return ITLocalize(@"PointerPrefsController_Facing_UnknownButton", @"Unknown button", @"Text shown in localizedButtonNameForButtonNumber:: Unknown button");
        case kLeftButton:
            return ITLocalize(@"PointerPrefsController_Facing_LeftButton", @"Left button", @"Text shown in localizedButtonNameForButtonNumber:: Left button");
        case kRightButton:
            return ITLocalize(@"PointerPrefsController_Facing_RightButton", @"Right button", @"Text shown in localizedButtonNameForButtonNumber:: Right button");
        case kMiddleButton:
            return ITLocalize(@"PointerPrefsController_Facing_MiddleButton", @"Middle button", @"Text shown in localizedButtonNameForButtonNumber:: Middle button");
        default:
            return [NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_Button_FORMAT", @"Button #%1$d",@"Formatted user-facing text in localizedButtonNameForButtonNumber:(int)n"), n+1];
    }
}

+ (NSDictionary *)gestureNamesDict
{
    NSDictionary *names = @{ kThreeFingerClickGesture: ITLocalize(@"PointerPrefsController_Facing_ThreeFingerTap", @"Three-finger Tap", @"Text shown in gestureNamesDict: Three-finger Tap"),
                             kThreeFingerSwipeRight: ITLocalize(@"PointerPrefsController_Facing_ThreeFingerSwipeRight", @"Three-finger Swipe Right", @"Text shown in gestureNamesDict: Three-finger Swipe Right"),
                             kThreeFingerSwipeLeft: ITLocalize(@"PointerPrefsController_Facing_ThreeFingerSwipeLeft", @"Three-finger Swipe Left", @"Text shown in gestureNamesDict: Three-finger Swipe Left"),
                             kThreeFingerSwipeUp: ITLocalize(@"PointerPrefsController_Facing_ThreeFingerSwipeUp", @"Three-finger Swipe Up", @"Text shown in gestureNamesDict: Three-finger Swipe Up"),
                             kThreeFingerSwipeDown: ITLocalize(@"PointerPrefsController_Facing_ThreeFingerSwipeDown", @"Three-finger Swipe Down", @"Text shown in gestureNamesDict: Three-finger Swipe Down"),
                             kForceTouchSingleClick: ITLocalize(@"PointerPrefsController_Facing_ForceTouchSingleClick", @"Force Touch Single Click", @"Text shown in gestureNamesDict: Force Touch Single Click") };
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
    return [NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_BadName_FORMAT", @"Bad name: %1$@",@"Formatted user-facing text in actionWithLocalizedName:(NSString *)localizedName"), localizedName];
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
            return [NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_BadTag_FORMAT", @"Bad tag %1$d",@"Formatted user-facing text in gestureIdentifierForTag:(int)tag"), tag];
    }
}

+ (NSString *)localizedModifiers:(int)keyMods {
    return [NSString stringForModifiersWithMask:keyMods];
}

+ (NSDictionary *)localizedActionMap
{
    NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                           ITLocalize(@"PointerPrefsController_Facing_Ignore", @"Ignore", @"Text shown in localizedActionMap: Ignore"), kIgnoreAction,
                           ITLocalize(@"PointerPrefsController_Facing_InvokeScriptFunction", @"Invoke Script Function…", @"Text shown in localizedActionMap: Invoke Script Function…"), kInvokeScriptFunction,
                           ITLocalize(@"PointerPrefsController_Facing_PasteFromClipboard", @"Paste from Clipboard…", @"Text shown in localizedActionMap: Paste from Clipboard…"), kPasteFromClipboardPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_PasteFromSelection", @"Paste from Selection…", @"Text shown in localizedActionMap: Paste from Selection…"), kPasteFromSelectionPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_ExtendSelection", @"Extend Selection", @"Text shown in localizedActionMap: Extend Selection"), kExtendSelectionPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_OpenUrlSemanticHistory", @"Open URL/Semantic History", @"Text shown in localizedActionMap: Open URL/Semantic History"), kOpenTargetPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_OpenUrlInBackground", @"Open URL in background", @"Text shown in localizedActionMap: Open URL in background"), kOpenTargetInBackgroundPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SmartSelection", @"Smart Selection", @"Text shown in localizedActionMap: Smart Selection"), kSmartSelectionPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SmartSelectionIgnoringNewlines", @"Smart Selection Ignoring Newlines", @"Text shown in localizedActionMap: Smart Selection Ignoring Newlines"), kSmartSelectionIgnoringNewlinesPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_OpenContextMenu", @"Open Context Menu", @"Text shown in localizedActionMap: Open Context Menu"), kContextMenuPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NextTab", @"Next Tab", @"Text shown in localizedActionMap: Next Tab"), kNextTabPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_PreviousTab", @"Previous Tab", @"Text shown in localizedActionMap: Previous Tab"), kPrevTabPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NextWindow", @"Next Window", @"Text shown in localizedActionMap: Next Window"), kNextWindowPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_PreviousWindow", @"Previous Window", @"Text shown in localizedActionMap: Previous Window"), kPrevWindowPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_MovePane", @"Move Pane", @"Text shown in localizedActionMap: Move Pane"), kMovePanePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SendEscapeSequence", @"Send Escape Sequence…", @"Text shown in localizedActionMap: Send Escape Sequence…"), kSendEscapeSequencePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SendHexCode", @"Send Hex Code…", @"Text shown in localizedActionMap: Send Hex Code…"), kSendHexCodePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SendText", @"Send Text…", @"Text shown in localizedActionMap: Send Text…"), kSendTextPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectPaneLeft", @"Select Pane Left", @"Text shown in localizedActionMap: Select Pane Left"), kSelectPaneLeftPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectPaneRight", @"Select Pane Right", @"Text shown in localizedActionMap: Select Pane Right"), kSelectPaneRightPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectPaneAbove", @"Select Pane Above", @"Text shown in localizedActionMap: Select Pane Above"), kSelectPaneAbovePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectPaneBelow", @"Select Pane Below", @"Text shown in localizedActionMap: Select Pane Below"), kSelectPaneBelowPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NewWindowWithProfile", @"New Window With Profile…", @"Text shown in localizedActionMap: New Window With Profile…"), kNewWindowWithProfilePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NewTabWithProfile", @"New Tab With Profile…", @"Text shown in localizedActionMap: New Tab With Profile…"), kNewWindowWithProfilePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NewTabWithProfile", @"New Tab With Profile…", @"Text shown in localizedActionMap: New Tab With Profile…"), kNewTabWithProfilePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NewVerticalSplitWithProfile", @"New Vertical Split With Profile…", @"Text shown in localizedActionMap: New Vertical Split With Profile…"), kNewVerticalSplitWithProfilePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_NewHorizontalSplitWithProfile", @"New Horizontal Split With Profile…", @"Text shown in localizedActionMap: New Horizontal Split With Profile…"), kNewHorizontalSplitWithProfilePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_QuickLook", @"QuickLook", @"Text shown in localizedActionMap: QuickLook"), kQuickLookAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectMenuItem", @"Select Menu Item", @"Text shown in localizedActionMap: Select Menu Item"), kSelectMenuItemPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_CopyLinkAddress", @"Copy Link Address", @"Text shown in localizedActionMap: Copy Link Address"), kCopyLinkAddressPointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectNextPane", @"Select Next Pane", @"Text shown in localizedActionMap: Select Next Pane"), kSelectNextPanePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_SelectPreviousPane", @"Select Previous Pane", @"Text shown in localizedActionMap: Select Previous Pane"), kSelectPreviousPanePointerAction,
                           ITLocalize(@"PointerPrefsController_Facing_CopyOrPaste", @"Copy or Paste", @"Text shown in localizedActionMap: Copy or Paste"), kCopyOrPastePointerAction,
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
        name = ITLocalize(@"PointerPrefsController_Facing_Unknown", @"(Unknown)", @"Text shown in localizedActionForDict:: (Unknown)");
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
        name = ITLocalize(@"PointerPrefsController_Facing_Unknown", @"(Unknown)", @"Text shown in formattedLocalizedActionForDict:: (Unknown)");
    }
    if (action) {
        switch ([PointerPrefsController argumentTypeForAction:action]) {
            case kNoArg:
                break;
            case kEscPlusArg:
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_Esc_FORMAT", @" Esc + %1$@",@"Formatted user-facing text in formattedLocalizedActionForDict:(NSDictionary *)dict"), argument]];
            case kHexCodeArg:
            case kTextArg:
            case kScriptFunctionArg:
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_FORMAT", @" \"%1$@\"",@"Formatted user-facing text in formattedLocalizedActionForDict:(NSDictionary *)dict"), argument]];
            case kProfileArg: {
                NSString *bookmarkName = [[[ProfileModel sharedInstance] bookmarkWithGuid:argument] objectForKey:KEY_NAME];
                if (!bookmarkName) {
                    bookmarkName = @"?";
                }
                return [name stringByReplacingOccurrencesOfString:@"…"
                                                       withString:[NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_FORMAT", @" \"%1$@\"",@"Formatted user-facing text in formattedLocalizedActionForDict:(NSDictionary *)dict"), bookmarkName]];
            }
            case kAdvancedPasteArg: {
                if (argument.length) {
                    return [NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_FORMAT_2", @"%1$@: %2$@",@"Formatted user-facing text in formattedLocalizedActionForDict:(NSDictionary *)dict"),
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
                return [NSString stringWithFormat:ITLocalize(@"PointerPrefsController_FormattedFacing_SelectMenuItem_FORMAT", @"Select Menu Item “%1$@”",@"Formatted user-facing text in formattedLocalizedActionForDict:(NSDictionary *)dict"), title];
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
    NSDictionary *dict = [[iTermUserDefaults userDefaults] dictionaryForKey:kPointerActionsKey];
    if (!dict) {
        dict = [PointerPrefsController defaultActions];
        [[iTermUserDefaults userDefaults] setObject:dict forKey:kPointerActionsKey];
    }
    return dict;
}

+ (void)setSettings:(NSDictionary *)newSettings
{
    [[iTermUserDefaults userDefaults] setObject:newSettings forKey:kPointerActionsKey];
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
            [editArgumentLabel_ setStringValue:ITLocalize(@"PointerPrefsController_Esc", @"Esc +", @"Label text in updateArgumentFieldsForAction:")];
            [[editArgumentField_ cell] setPlaceholderString:ITLocalize(@"PointerPrefsController_Placeholder_CharactersToSend", @"characters to send",@"Placeholder text in updateArgumentFieldsForAction:(NSString *)actionIdent argument:(NSString *)currentArg")];
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
            [editArgumentLabel_ setStringValue:ITLocalize(@"PointerPrefsController_HexCodes", @"Hex codes:", @"Label text in updateArgumentFieldsForAction:")];
            [[editArgumentField_ cell] setPlaceholderString:ITLocalize(@"PointerPrefsController_Placeholder_Ex0x7f0x20", @"ex: 0x7f 0x20",@"Placeholder text in updateArgumentFieldsForAction:(NSString *)actionIdent argument:(NSString *)currentArg")];
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
            [editArgumentLabel_ setStringValue:ITLocalize(@"PointerPrefsController_Text", @"Text:", @"Label text in updateArgumentFieldsForAction:")];
            [[editArgumentField_ cell] setPlaceholderString:ITLocalize(@"PointerPrefsController_Placeholder_EnterValueToSend", @"Enter value to send",@"Placeholder text in updateArgumentFieldsForAction:(NSString *)actionIdent argument:(NSString *)currentArg")];
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
            [editArgumentLabel_ setStringValue:ITLocalize(@"PointerPrefsController_Text", @"Text:", @"Label text in updateArgumentFieldsForAction:")];
            [[editArgumentField_ cell] setPlaceholderString:ITLocalize(@"PointerPrefsController_Placeholder_EnterFunctionInvocation", @"Enter function invocation",@"Placeholder text in updateArgumentFieldsForAction:(NSString *)actionIdent argument:(NSString *)currentArg")];
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
            [editArgumentLabel_ setStringValue:ITLocalize(@"PointerPrefsController_Profile", @"Profile:", @"Label text in updateArgumentFieldsForAction:")];
            [editArgumentButton_ populateWithProfilesSelectingGuid:currentArg
                                                      profileTypes:ProfileTypeAll];
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
