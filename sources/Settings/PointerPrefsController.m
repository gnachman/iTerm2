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
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.SingleClick", nil, [NSBundle mainBundle], @"single click", @"Name for a single mouse click");
        case 2:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.DoubleClick", nil, [NSBundle mainBundle], @"double click", @"Name for a double mouse click");
        case 3:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.TripleClick", nil, [NSBundle mainBundle], @"triple click", @"Name for a triple mouse click");
        case 4:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.QuadClick", nil, [NSBundle mainBundle], @"quad click", @"Name for a quadruple mouse click");
        default:
            // Localization unneeded
            return @"(error)";  // shouldn't happen
    }
}

+ (NSString *)localizedButtonNameForButtonNumber:(int)n
{
    switch (n) {
        case -1:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.UnknownButton", nil, [NSBundle mainBundle], @"Unknown button", @"Name for an unrecognized mouse button");
        case kLeftButton:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.LeftButton", nil, [NSBundle mainBundle], @"Left button", @"Name for the left mouse button");
        case kRightButton:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.RightButton", nil, [NSBundle mainBundle], @"Right button", @"Name for the right mouse button");
        case kMiddleButton:
            return NSLocalizedStringWithDefaultValue(@"PointerPrefs.MiddleButton", nil, [NSBundle mainBundle], @"Middle button", @"Name for the middle mouse button");
        default:
            return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"PointerPrefs.ButtonNumber", nil, [NSBundle mainBundle], @"Button #%d", @"Name for a numbered mouse button; %d is the button number"), n+1];
    }
}

+ (NSDictionary *)gestureNamesDict
{
    NSDictionary *names = @{ kThreeFingerClickGesture: NSLocalizedStringWithDefaultValue(@"PointerPrefs.GestureThreeFingerTap", nil, [NSBundle mainBundle], @"Three-finger Tap", @"Gesture name"),
                             kThreeFingerSwipeRight: NSLocalizedStringWithDefaultValue(@"PointerPrefs.GestureThreeFingerSwipeRight", nil, [NSBundle mainBundle], @"Three-finger Swipe Right", @"Gesture name"),
                             kThreeFingerSwipeLeft: NSLocalizedStringWithDefaultValue(@"PointerPrefs.GestureThreeFingerSwipeLeft", nil, [NSBundle mainBundle], @"Three-finger Swipe Left", @"Gesture name"),
                             kThreeFingerSwipeUp: NSLocalizedStringWithDefaultValue(@"PointerPrefs.GestureThreeFingerSwipeUp", nil, [NSBundle mainBundle], @"Three-finger Swipe Up", @"Gesture name"),
                             kThreeFingerSwipeDown: NSLocalizedStringWithDefaultValue(@"PointerPrefs.GestureThreeFingerSwipeDown", nil, [NSBundle mainBundle], @"Three-finger Swipe Down", @"Gesture name"),
                             kForceTouchSingleClick: NSLocalizedStringWithDefaultValue(@"PointerPrefs.GestureForceTouchSingleClick", nil, [NSBundle mainBundle], @"Force Touch Single Click", @"Gesture name") };
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
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionIgnore", nil, [NSBundle mainBundle], @"Ignore", @"Pointer action name"), kIgnoreAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionInvokeScriptFunction", nil, [NSBundle mainBundle], @"Invoke Script Function…", @"Pointer action name"), kInvokeScriptFunction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionPasteFromClipboard", nil, [NSBundle mainBundle], @"Paste from Clipboard…", @"Pointer action name"), kPasteFromClipboardPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionPasteFromSelection", nil, [NSBundle mainBundle], @"Paste from Selection…", @"Pointer action name"), kPasteFromSelectionPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionExtendSelection", nil, [NSBundle mainBundle], @"Extend Selection", @"Pointer action name"), kExtendSelectionPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionOpenURLSemanticHistory", nil, [NSBundle mainBundle], @"Open URL/Semantic History", @"Pointer action name"), kOpenTargetPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionOpenURLInBackground", nil, [NSBundle mainBundle], @"Open URL in background", @"Pointer action name"), kOpenTargetInBackgroundPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSmartSelection", nil, [NSBundle mainBundle], @"Smart Selection", @"Pointer action name"), kSmartSelectionPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSmartSelectionIgnoringNewlines", nil, [NSBundle mainBundle], @"Smart Selection Ignoring Newlines", @"Pointer action name"), kSmartSelectionIgnoringNewlinesPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionOpenContextMenu", nil, [NSBundle mainBundle], @"Open Context Menu", @"Pointer action name"), kContextMenuPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNextTab", nil, [NSBundle mainBundle], @"Next Tab", @"Pointer action name"), kNextTabPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionPreviousTab", nil, [NSBundle mainBundle], @"Previous Tab", @"Pointer action name"), kPrevTabPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNextWindow", nil, [NSBundle mainBundle], @"Next Window", @"Pointer action name"), kNextWindowPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionPreviousWindow", nil, [NSBundle mainBundle], @"Previous Window", @"Pointer action name"), kPrevWindowPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionMovePane", nil, [NSBundle mainBundle], @"Move Pane", @"Pointer action name"), kMovePanePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSendEscapeSequence", nil, [NSBundle mainBundle], @"Send Escape Sequence…", @"Pointer action name"), kSendEscapeSequencePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSendHexCode", nil, [NSBundle mainBundle], @"Send Hex Code…", @"Pointer action name"), kSendHexCodePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSendText", nil, [NSBundle mainBundle], @"Send Text…", @"Pointer action name"), kSendTextPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectPaneLeft", nil, [NSBundle mainBundle], @"Select Pane Left", @"Pointer action name"), kSelectPaneLeftPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectPaneRight", nil, [NSBundle mainBundle], @"Select Pane Right", @"Pointer action name"), kSelectPaneRightPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectPaneAbove", nil, [NSBundle mainBundle], @"Select Pane Above", @"Pointer action name"), kSelectPaneAbovePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectPaneBelow", nil, [NSBundle mainBundle], @"Select Pane Below", @"Pointer action name"), kSelectPaneBelowPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNewWindowWithProfile", nil, [NSBundle mainBundle], @"New Window With Profile…", @"Pointer action name"), kNewWindowWithProfilePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNewTabWithProfile", nil, [NSBundle mainBundle], @"New Tab With Profile…", @"Pointer action name"), kNewWindowWithProfilePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNewTabWithProfile", nil, [NSBundle mainBundle], @"New Tab With Profile…", @"Pointer action name"), kNewTabWithProfilePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNewVerticalSplitWithProfile", nil, [NSBundle mainBundle], @"New Vertical Split With Profile…", @"Pointer action name"), kNewVerticalSplitWithProfilePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionNewHorizontalSplitWithProfile", nil, [NSBundle mainBundle], @"New Horizontal Split With Profile…", @"Pointer action name"), kNewHorizontalSplitWithProfilePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionQuickLook", nil, [NSBundle mainBundle], @"QuickLook", @"Pointer action name"), kQuickLookAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectMenuItem", nil, [NSBundle mainBundle], @"Select Menu Item", @"Pointer action name"), kSelectMenuItemPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionCopyLinkAddress", nil, [NSBundle mainBundle], @"Copy Link Address", @"Pointer action name"), kCopyLinkAddressPointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectNextPane", nil, [NSBundle mainBundle], @"Select Next Pane", @"Pointer action name"), kSelectNextPanePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionSelectPreviousPane", nil, [NSBundle mainBundle], @"Select Previous Pane", @"Pointer action name"), kSelectPreviousPanePointerAction,
                           NSLocalizedStringWithDefaultValue(@"PointerPrefs.ActionCopyOrPaste", nil, [NSBundle mainBundle], @"Copy or Paste", @"Pointer action name"), kCopyOrPastePointerAction,
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
        name = NSLocalizedStringWithDefaultValue(@"PointerPrefs.UnknownAction", nil, [NSBundle mainBundle], @"(Unknown)", @"Displayed when a pointer action is not recognized");
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
        name = NSLocalizedStringWithDefaultValue(@"PointerPrefs.UnknownAction", nil, [NSBundle mainBundle], @"(Unknown)", @"Displayed when a pointer action is not recognized");
    }
    // Actions that take an argument are displayed with a trailing ellipsis (e.g. "Send Text…").
    // When formatting a configured action we drop that ellipsis and append the argument. Strip a
    // trailing ellipsis explicitly rather than replacing an embedded "…": a localized name may
    // place the ellipsis differently or omit it, and an embedded-replace would then silently drop
    // the argument.
    NSString *base = name;
    if ([base hasSuffix:@"…"]) {
        base = [base substringToIndex:base.length - 1];
    }
    if (action) {
        switch ([PointerPrefsController argumentTypeForAction:action]) {
            case kNoArg:
                break;
            case kEscPlusArg:
                return [base stringByAppendingFormat:NSLocalizedStringWithDefaultValue(@"PointerPrefs.EscPlusArgumentSuffix", nil, [NSBundle mainBundle], @" Esc + %@", @"Suffix appended to a pointer action showing the Esc-plus argument; %@ is the argument"), argument];
            case kHexCodeArg:
            case kTextArg:
            case kScriptFunctionArg:
                return [base stringByAppendingFormat:@" \"%@\"", argument];
            case kProfileArg: {
                NSString *bookmarkName = [[[ProfileModel sharedInstance] bookmarkWithGuid:argument] objectForKey:KEY_NAME];
                if (!bookmarkName) {
                    // Localization unneeded
                    bookmarkName = @"?";
                }
                return [base stringByAppendingFormat:@" \"%@\"", bookmarkName];
            }
            case kAdvancedPasteArg: {
                if (argument.length) {
                    return [NSString stringWithFormat:@"%@: %@",
                            base,
                            [iTermPasteSpecialViewController descriptionForCodedSettings:argument]];
                }
                break;
            }
            case kMenuItemArg: {
                // The argument is "identifier\ntitle"; show the human title (the last
                // component), not the identifier, which may be a synthetic "_NS:<n>".
                NSArray *parts = [argument componentsSeparatedByString:@"\n"];
                NSString *title = parts.lastObject;
                if (!title.length) {
                    break;
                }
                return [NSString stringWithFormat:NSLocalizedStringWithDefaultValue(@"PointerPrefs.SelectMenuItemNamed", nil, [NSBundle mainBundle], @"Select Menu Item “%@”", @"Formatted pointer action showing which menu item is selected; %@ is the menu item title"), title];
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
            [editArgumentLabel_ setStringValue:NSLocalizedStringWithDefaultValue(@"PointerPrefs.EscPlusLabel", nil, [NSBundle mainBundle], @"Esc +", @"Label for the Esc-plus argument field when editing a pointer action")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedStringWithDefaultValue(@"PointerPrefs.CharactersToSendPlaceholder", nil, [NSBundle mainBundle], @"characters to send", @"Placeholder for the Esc-plus characters argument field")];
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
            [editArgumentLabel_ setStringValue:NSLocalizedStringWithDefaultValue(@"PointerPrefs.HexCodesLabel", nil, [NSBundle mainBundle], @"Hex codes:", @"Label for the hex codes argument field when editing a pointer action")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedStringWithDefaultValue(@"PointerPrefs.HexCodesPlaceholder", nil, [NSBundle mainBundle], @"ex: 0x7f 0x20", @"Placeholder example for the hex codes argument field")];
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
            [editArgumentLabel_ setStringValue:NSLocalizedStringWithDefaultValue(@"PointerPrefs.TextLabel", nil, [NSBundle mainBundle], @"Text:", @"Label for the text argument field when editing a pointer action")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedStringWithDefaultValue(@"PointerPrefs.TextToSendPlaceholder", nil, [NSBundle mainBundle], @"Enter value to send", @"Placeholder for the text-to-send argument field")];
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
            [editArgumentLabel_ setStringValue:NSLocalizedStringWithDefaultValue(@"PointerPrefs.TextLabel", nil, [NSBundle mainBundle], @"Text:", @"Label for the text argument field when editing a pointer action")];
            [[editArgumentField_ cell] setPlaceholderString:NSLocalizedStringWithDefaultValue(@"PointerPrefs.FunctionInvocationPlaceholder", nil, [NSBundle mainBundle], @"Enter function invocation", @"Placeholder for the script function invocation argument field")];
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
            [editArgumentLabel_ setStringValue:NSLocalizedStringWithDefaultValue(@"PointerPrefs.ProfileLabel", nil, [NSBundle mainBundle], @"Profile:", @"Label for the profile argument field when editing a pointer action")];
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
            NSString *storedIdentifier = parts.count > 0 ? parts.firstObject : nil;
            NSString *storedTitle = parts.count > 1 ? parts[1] : nil;
            (void)[_menuItemPopupView selectItemWithIdentifier:storedIdentifier title:storedTitle];
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
        NSString *originalArg = origKey_ ? [PointerPrefsController argumentForKey:origKey_] : nil;
        newValue[kArgumentKey] = [iTermMenuItemBinding storedParameterForIdentifier:_menuItemPopupView.selectedIdentifier
                                                                              title:_menuItemPopupView.selectedTitle
                                                                       hasSelection:_menuItemPopupView.hasSelection
                                                                           original:originalArg
                                                                    identifierFirst:YES];
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
