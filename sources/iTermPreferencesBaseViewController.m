//
//  iTermPreferencesBaseViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "iTermPreferences.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"
#import "PreferencePanel.h"

#import <ColorPicker/ColorPicker.h>

static NSString *const kPreferenceDidChangeFromOtherPanel = @"kPreferenceDidChangeFromOtherPanel";

// key for userInfo dictionary of kPreferenceDidChangeFromOtherPanel notification having
// key of changed preference.
static NSString *const kKey = @"key";

@implementation iTermPreferencesBaseViewController {
    // Maps NSControl* -> PreferenceInfo*.
    NSMapTable *_keyMap;
    // Set of all defined keys (KEY_XXX).
    NSMutableSet *_keys;
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _keyMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                            valueOptions:NSPointerFunctionsStrongMemory
                                                capacity:16];
        _keys = [[NSMutableSet alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(preferenceDidChangeFromOtherPanel:)
                                                     name:kPreferenceDidChangeFromOtherPanel
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_keyMap release];
    [_keys release];
    [super dealloc];
}

- (PreferenceInfo *)infoForKey:(NSString *)key {
    for (NSControl *control in _keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        if ([info.key isEqualToString:key]) {
            return info;
        }
    }
    return nil;
}

#pragma mark - Methods to override

- (BOOL)boolForKey:(NSString *)key {
    return [iTermPreferences boolForKey:key];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [iTermPreferences setBool:value forKey:key];
}

- (int)intForKey:(NSString *)key {
    return [iTermPreferences intForKey:key];
}

- (void)setInt:(int)value forKey:(NSString *)key {
    [iTermPreferences setInt:value forKey:key];
}

- (double)floatForKey:(NSString *)key {
    return [iTermPreferences floatForKey:key];
}

- (void)setFloat:(double)value forKey:(NSString *)key {
    [iTermPreferences setFloat:value forKey:key];
}

- (NSString *)stringForKey:(NSString *)key {
    return [iTermPreferences stringForKey:key];
}

- (void)setString:(NSString *)value forKey:(NSString *)key {
    [iTermPreferences setString:value forKey:key];
}

- (NSObject *)objectForKey:(NSString *)key {
    return [iTermPreferences objectForKey:key];
}

- (void)setObject:(NSObject *)object forKey:(NSString *)key {
    [iTermPreferences setObject:object forKey:key];
}

- (BOOL)keyHasDefaultValue:(NSString *)key {
    return [iTermPreferences keyHasDefaultValue:key];
}

- (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type {
    return [iTermPreferences defaultValueForKey:key isCompatibleWithType:type];
}

- (BOOL)shouldUpdateOtherPanels {
    return YES;
}

#pragma mark - APIs

- (IBAction)settingChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);

    if (info.willChange) {
        info.willChange();
    }
    
    if (info.customSettingChangedHandler) {
        info.customSettingChangedHandler(sender);
    } else {
        switch (info.type) {
            case kPreferenceInfoTypeCheckbox:
                [self setBool:([sender state] == NSOnState) forKey:info.key];
                break;

            case kPreferenceInfoTypeIntegerTextField:
                [self applyIntegerConstraints:info];
                [self setInt:[sender separatorTolerantIntValue] forKey:info.key];
                break;
                
            case kPreferenceInfoTypeStringTextField:
                [self setString:[sender stringValue] forKey:info.key];
                break;
                
            case kPreferenceInfoTypeTokenField:
                [self setObject:[sender objectValue] forKey:info.key];
                break;

            case kPreferenceInfoTypeMatrix:
                assert(false);  // Must use a custom setting changed handler
            
            case kPreferenceInfoTypePopup:
                [self setInt:[sender selectedTag] forKey:info.key];
                break;
                
            case kPreferenceInfoTypeSlider:
                [self setFloat:[sender doubleValue] forKey:info.key];
                break;

            case kPreferenceInfoTypeColorWell:
                [self setObject:[[sender color] dictionaryValue] forKey:info.key];
                break;

            default:
                assert(false);
        }
        if (info.onChange) {
            info.onChange();
        }
    }
    if (info.observer) {
        info.observer();
    }
    if ([self shouldUpdateOtherPanels]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kPreferenceDidChangeFromOtherPanel
                                                            object:self
                                                          userInfo:@{ kKey: info.key }];
    }
    
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type {
    return [self defineControl:control
                           key:key
                          type:type
                settingChanged:NULL
                        update:NULL];
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)())update {
    assert(![_keyMap objectForKey:key]);
    assert(key);
    assert(control);
    assert([self keyHasDefaultValue:key]);
    if (!settingChanged || !update) {
        assert([self defaultValueForKey:key isCompatibleWithType:type]);
        assert(type != kPreferenceInfoTypeMatrix);  // Matrix type requires both.
    }
    
    PreferenceInfo *info = [PreferenceInfo infoForPreferenceWithKey:key
                                                               type:type
                                                            control:control];
    info.customSettingChangedHandler = settingChanged;
    info.onUpdate = update;
    [_keyMap setObject:info forKey:control];
    [_keys addObject:key];
    [self updateValueForInfo:info];
    
    return info;
}

- (void)updateValueForInfo:(PreferenceInfo *)info {
    if (info.onUpdate) {
        if (info.onUpdate()) {
            return;
        }
    }
    switch (info.type) {
        case kPreferenceInfoTypeCheckbox: {
            assert([info.control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)info.control;
            button.state = [self boolForKey:info.key] ? NSOnState : NSOffState;
            break;
        }
            
        case kPreferenceInfoTypeIntegerTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.intValue = [self intForKey:info.key];
            break;
        }
            
        case kPreferenceInfoTypeStringTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.stringValue = [self stringForKey:info.key] ?: @"";
            break;
        }

        case kPreferenceInfoTypeTokenField: {
            assert([info.control isKindOfClass:[NSTokenField class]]);
            NSTokenField *field = (NSTokenField *)info.control;
            NSObject *object = [self objectForKey:info.key];;
            assert(!object || [object conformsToProtocol:@protocol(NSCopying)]);
            field.objectValue = (id<NSCopying>)object;
            break;
        }

        case kPreferenceInfoTypePopup: {
            assert([info.control isKindOfClass:[NSPopUpButton class]]);
            NSPopUpButton *popup = (NSPopUpButton *)info.control;
            [popup selectItemWithTag:[self intForKey:info.key]];
            break;
        }
            
        case kPreferenceInfoTypeSlider: {
            assert([info.control isKindOfClass:[NSSlider class]]);
            NSSlider *slider = (NSSlider *)info.control;
            slider.doubleValue = [self floatForKey:info.key];
            break;
        }

        case kPreferenceInfoTypeMatrix:
            assert(false);  // Must use onChange() only.

        case kPreferenceInfoTypeColorWell: {
            assert([info.control isKindOfClass:[CPKColorWell class]]);
            CPKColorWell *colorWell = (CPKColorWell *)info.control;
            NSDictionary *dict = (NSDictionary *)[self objectForKey:info.key];
            if (dict) {
                assert([dict isKindOfClass:[NSDictionary class]]);
                [colorWell setColor:[dict colorValue]];
            }
            break;
        }
            
        default:
            assert(false);
    }
    if (info.observer) {
        info.observer();
    }
}

- (void)updateEnabledState {
    for (NSControl *control in _keyMap) {
        PreferenceInfo *info = [self infoForControl:control];
        [self updateEnabledStateForInfo:info];
    }
}

- (void)updateEnabledStateForInfo:(PreferenceInfo *)info {
    if (info.shouldBeEnabled) {
        [info.control setEnabled:info.shouldBeEnabled()];
    }
}

- (PreferenceInfo *)infoForControl:(NSControl *)control {
    PreferenceInfo *info = [_keyMap objectForKey:control];
    assert(info);
    return info;
}

- (void)postRefreshNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:kRefreshTerminalNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (NSArray *)keysForBulkCopy {
    return [_keys allObjects];
}

#pragma mark - Constraints

// Pick out the digits from s and clamp it to a range.
- (int)intForString:(NSString *)s inRange:(NSRange)range
{
    NSString *i = [s stringWithOnlyDigits];
    
    int val = 0;
    if ([i length]) {
        val = [i intValue];
    }
    val = MAX(val, range.location);
    val = MIN(val, range.location + range.length - 1);
    return val;
}

- (void)applyIntegerConstraints:(PreferenceInfo *)info {
    // NSNumberFormatter seems to have lost its mind on Lion. See a description of the problem here:
    // http://stackoverflow.com/questions/7976951/nsnumberformatter-erasing-value-when-it-violates-constraints
    assert([info.control isKindOfClass:[NSTextField class]]);
    NSTextField *textField = (NSTextField *)info.control;
    int iv = [self intForString:[textField stringValue] inRange:info.range];
    unichar lastChar = '0';
    int numChars = [[textField stringValue] length];
    if (numChars) {
        lastChar = [[textField stringValue] characterAtIndex:numChars - 1];
    }
    if (iv != [textField separatorTolerantIntValue] || (lastChar < '0' || lastChar > '9')) {
        // If the int values don't match up or there are terminal non-number
        // chars, then update the value.
        [textField setIntValue:iv];
    }
}

#pragma mark - NSControl Delegate Informal Protocol

// This is a notification signature but it gets called because we're the delegate of text fields.
- (void)controlTextDidChange:(NSNotification *)aNotification {
    id control = [aNotification object];
    PreferenceInfo *info = [_keyMap objectForKey:control];
    if (info) {
        [self settingChanged:control];
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    id control = [aNotification object];
    PreferenceInfo *info = [_keyMap objectForKey:control];
    if (info.controlTextDidEndEditing) {
        info.controlTextDidEndEditing(aNotification);
    }
}

#pragma mark - Notifications

- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification {
    NSString *key = notification.userInfo[kKey];
    if (![_keys containsObject:key]) {
        return;
    }
    PreferenceInfo *info = [self infoForKey:key];
    assert(info);
    [self updateValueForInfo:info];
}

@end
