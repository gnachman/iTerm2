//
//  PointerPrefsController.m
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "PointerPrefsController.h"
#import "PointerController.h"
#import "PreferencePanel.h"

static NSString *kPointerActionsKey = @"PointerActions";  // Used in NSUserDefaults
static NSString *kActionKey = @"Action";  // Used within values
static NSString *kCommandKeyChar = @"c";
static NSString *kOptionKeyChar = @"o";
static NSString *kShiftKeyChar = @"s";
static NSString *kControlKeyChar = @"^";
#define kLeftButton 0
#define kRightButton 1
#define kMiddleButton 2
static int kMaxClicks = 4;

static NSString *kButtonSchema = @"Button";  // First field of action key
static NSString *kGestureSchema = @"Gesture";  // First field of action key

static NSString *kThreeFingerClickGesture = @"ThreeFingerClick";  // Second field of action key (gesture type)
static NSString *kThreeFingerSwipeRight = @"ThreeFingerSwipeRight";  // Second field of action key (gesture type)
static NSString *kThreeFingerSwipeLeft = @"ThreeFingerSwipeLeft";  // Second field of action key (gesture type)

@interface NSString (PointerPrefsController)
- (NSComparisonResult)comparePointerActions:(NSString *)other;
@end

@implementation PointerPrefsController

@synthesize hasSelection = hasSelection_;

+ (NSDictionary *)dictForAction:(NSString *)action
{
    return [NSDictionary dictionaryWithObject:action forKey:kActionKey];
}

+ (NSString *)modCharsForMask:(int)modifiers
{
    NSMutableString *modStr = [NSMutableString string];
    if (modifiers & NSCommandKeyMask) {
        [modStr appendString:kCommandKeyChar];
    }
    if (modifiers & NSAlternateKeyMask) {
        [modStr appendString:kOptionKeyChar];
    }
    if (modifiers & NSShiftKeyMask) {
        [modStr appendString:kShiftKeyChar];
    }
    if (modifiers & NSControlKeyMask) {
        [modStr appendString:kControlKeyChar];
    }
    return modStr;
}

+ (int)maskForModChars:(NSString *)modChars
{
    int mask = 0;
    if ([modChars rangeOfString:kCommandKeyChar].location != NSNotFound) {
        mask |= NSCommandKeyMask;
    }
    if ([modChars rangeOfString:kOptionKeyChar].location != NSNotFound) {
        mask |= NSAlternateKeyMask;
    }
    if ([modChars rangeOfString:kShiftKeyChar].location != NSNotFound) {
        mask |= NSShiftKeyMask;
    }
    if ([modChars rangeOfString:kControlKeyChar].location != NSNotFound) {
        mask |= NSControlKeyMask;
    }
    return mask;
}

+ (NSString *)keyForButton:(int)button clicks:(int)clicks modifiers:(int)modifiers
{
    NSString *modStr = [PointerPrefsController modCharsForMask:modifiers];
    return [NSString stringWithFormat:@"%@,%d,%d,%@", kButtonSchema, button, clicks, modStr];
}

+ (NSString *)keyForGesture:(NSString *)gestureDescription modifiers:(int)modifiers
{
    return [NSString stringWithFormat:@"%@,%@,%@",
                kGestureSchema,
                gestureDescription,
                [PointerPrefsController modCharsForMask:modifiers]];
}

+ (BOOL)keyIsButton:(NSString *)key
{
    return [key hasPrefix:kButtonSchema];
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
        case 0:
            return @"drag";
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

+ (NSString *)localizedGestureNameForGestureIdentifier:(NSString *)ident
{
    NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"3-finger click", kThreeFingerClickGesture,
                           @"3-finger swipe right", kThreeFingerSwipeRight,
                           @"3-finger swipe left", kThreeFingerSwipeLeft,
                           nil];
    NSString *name = [names objectForKey:ident];
    if (name) {
        return name;
    } else {
        // Shouldn't happen
        return ident;
    }
}

+ (NSString *)localizedModifers:(int)keyMods
{
    NSMutableString *theKeyString = [NSMutableString string];
    if (keyMods & NSControlKeyMask) {
        [theKeyString appendString: @"^"];
    }
    if (keyMods & NSAlternateKeyMask) {
        [theKeyString appendString: @"⌥"];
    }
    if (keyMods & NSShiftKeyMask) {
        [theKeyString appendString: @"⇧"];
    }
    if (keyMods & NSCommandKeyMask) {
        [theKeyString appendString: @"⌘"];
    }
    return theKeyString;
}

+ (NSDictionary *)localizedActionMap
{
    NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:
                           @"Paste from Clipboard", kPasteFromClipboardPointerAction,
                           @"Paste from Selection", kPasteFromSelectionPointerAction,
                           @"Open URL/Semantic History", kOpenTargetPointerAction,
                           @"Smart Selection", kSmartSelectionPointerAction,
                           @"Context Menu", kContextMenuPointerAction,
                           @"Select Word", kSelectWordPointerAction,
                           @"Select Line", kSelectLinePointerAction,
                           @"Select Rectangle", kBlockSelectPointerAction,
                           @"Extend Selection", kExtendSelectionPointerAction,
                           @"Extend Selection by Words", kExtendSelectionByWordPointerAction,
                           @"Extend Selection by Lines", kExtendSelectionByLinePointerAction,
                           @"Extend Selection by Smart Selection", kExtendSelectionBySmartSelectionPointerAction,
                           @"Next Tab", kNextTabPointerAction,
                           @"Previous Tab", kPrevTabPointerAction,
                           @"Drag Pane", kDragPanePointerAction,
                           @"Report Mouse Action Only", kNoActionPointerAction,
                           nil];
    return names;
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
    NSArray *parts = [PointerPrefsController buttonKeyComponents:key];
    if (parts) {
        return [PointerPrefsController maskForModChars:[parts objectAtIndex:3]];
    } else {
        return 0;
    }
}

+ (NSDictionary *)defaultActions
{
    static NSDictionary *defaultDict;
    if (!defaultDict) {
        NSString* plistFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"DefaultPointerActions"
                                                                               ofType:@"plist"];
        NSMutableDictionary *temp = [NSDictionary dictionaryWithContentsOfFile:plistFile];
        // Migrate old global prefs into the dict.
        if (![[PreferencePanel sharedInstance] legacyPasteFromClipboard]) {
            NSDictionary *middleButtonPastesFromSelection = [PointerPrefsController dictForAction:kPasteFromSelectionPointerAction];
            [temp setObject:middleButtonPastesFromSelection
                     forKey:[PointerPrefsController keyForButton:kMiddleButton
                                                          clicks:1
                                                       modifiers:0]];
        }
        if (![[PreferencePanel sharedInstance] legacyCmdSelection]) {
            [temp removeObjectForKey:[PointerPrefsController keyForButton:kLeftButton
                                                                   clicks:1
                                                                modifiers:NSCommandKeyMask]];
        }
        if ([[PreferencePanel sharedInstance] legacyPassOnControlLeftClick]) {
            NSDictionary *noAction = [PointerPrefsController dictForAction:kNoActionPointerAction];
            [temp setObject:noAction
                     forKey:[PointerPrefsController keyForButton:kLeftButton
                                                          clicks:1
                                                       modifiers:NSControlKeyMask]];
        }
        if ([[PreferencePanel sharedInstance] legacyThreeFingerEmulatesMiddle]) {
            // Find all actions that use middle button and add corresponding three-finger gesture.
            for (NSString *key in temp) {
                if ([PointerPrefsController keyIsButton:key] &&
                    [PointerPrefsController buttonForKey:key] == kMiddleButton) {
                    NSDictionary *middleAction = [temp objectForKey:key];
                    NSString *gestureKey = [PointerPrefsController keyForGesture:kThreeFingerClickGesture
                                                                       modifiers:[PointerPrefsController modifiersForKey:key]];
                    [temp setObject:middleAction forKey:gestureKey];
                }
            }
            int modMasks[] = { NSCommandKeyMask, NSAlternateKeyMask, NSControlKeyMask, NSShiftKeyMask };
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

+ (NSArray *)sortedKeys
{
    NSArray *keys = [[PointerPrefsController settings] allKeys];
    return [keys sortedArrayUsingSelector:@selector(comparePointerActions:)];
}

#pragma mark NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [[PointerPrefsController settings] count];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
    row:(NSInteger)rowIndex {
    NSArray *sortedKeys = [PointerPrefsController sortedKeys];
    NSString *key = [sortedKeys objectAtIndex:rowIndex];
    NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];
    BOOL isButton = [PointerPrefsController keyIsButton:key];
    
    if (aTableColumn == buttonColumn_) {
        if (isButton) {
            NSString *button = [PointerPrefsController localizedButtonNameForButtonNumber:[PointerPrefsController buttonForKey:key]];
            NSString *numClicks = [PointerPrefsController localizedNumClicks:[PointerPrefsController numClicksForKey:key]];
            NSString *modifiers = [PointerPrefsController localizedModifers:[PointerPrefsController modifiersForKey:key]];
            if ([modifiers length]) {
                modifiers = [modifiers stringByAppendingString:@" + "];
            }
            return [NSString stringWithFormat:@"%@%@ %@", modifiers, button, numClicks];
        } else {
            return [PointerPrefsController localizedGestureNameForGestureIdentifier:[PointerPrefsController gestureIdentifierForKey:key]];
        }
    } else {
        // Action
        return [PointerPrefsController localizedActionForDict:action];
    }
}

+ (void)addKeyBasedOnKey:(NSString *)origKey modifiedByButtonOrGestureObject:(id)bogobj withAction:(NSDictionary *)actionDict
{
    
}

+ (void)addKeyBasedOnKey:(NSString *)origKey modifiedByModifiersObject:(id)modobj withAction:(NSDictionary *)actionDict
{
    
}

+ (void)setActionNumber:(int)n forKey:(NSString *)key
{
    
}

+ (void)removeKey:(NSString *)key
{
    
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    NSArray *sortedKeys = [PointerPrefsController sortedKeys];
    NSString *key = [sortedKeys objectAtIndex:rowIndex];
    NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];
    
    if (aTableColumn == buttonColumn_) {
        [action retain];
        [PointerPrefsController removeKey:key];
        [PointerPrefsController addKeyBasedOnKey:key modifiedByButtonOrGestureObject:anObject withAction:action];
        [action release];
    } else {
        [PointerPrefsController setActionNumber:[anObject intValue] forKey:key];
    }
}

#pragma mark NSTableViewDelegate

- (BOOL)tableView:(NSTableView *)aTableView
    shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
    return NO;
}

#if 0
- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
    row:(NSInteger)rowIndex
{
    NSArray *sortedKeys = [PointerPrefsController sortedKeys];
    NSString *key = [sortedKeys objectAtIndex:rowIndex];
    NSDictionary *action = [[PointerPrefsController settings] objectForKey:key];

    if (tableColumn == buttonColumn_) {
        NSButtonCell *cell = [[[NSButtonCell alloc] initTextCell:[self tableView:tableView_
                                                                      objectValueForTableColumn:tableColumn
                                                                             row:rowIndex]] autorelease];
        [cell setAction:@selector(buttonOrGestureClicked:)];
        [cell setTarget:self];
        [cell setBordered:NO];
        
        return cell;
    } else if (tableColumn == actionColumn_) {
        NSDictionary *names = [PointerPrefsController localizedActionMap];
        NSArray *localNames = [[names allValues] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
        NSPopUpButtonCell *cell =
            [[[NSPopUpButtonCell alloc] initTextCell:[localNames objectAtIndex:0] pullsDown:NO] autorelease];
        for (NSString *title in localNames) {
            [cell addItemWithTitle:title];
        }
        
        [cell setBordered:NO];
        
        return cell;
    }
    return nil;
}

- (void)buttonOrGestureClicked:(id)sender
{
    NSLog(@"YOU CLICKED IT");
}
#endif
- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    self.hasSelection = [tableView_ numberOfSelectedRows] > 0;
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

