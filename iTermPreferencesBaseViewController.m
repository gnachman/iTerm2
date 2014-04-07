//
//  iTermPreferencesBaseViewController.m
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import "iTermPreferencesBaseViewController.h"
#import "iTermPreferences.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"

@interface iTermPreferencesBaseViewController ()

@end

@implementation iTermPreferencesBaseViewController {
    // Maps NSControl* -> PreferenceInfo*.
    NSMapTable *_keyMap;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        _keyMap = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory
                                            valueOptions:NSPointerFunctionsStrongMemory
                                                capacity:16];
    }
    return self;
}

- (void)dealloc {
    [_keyMap release];
    [super dealloc];
}

#pragma mark - APIs

- (IBAction)settingChanged:(id)sender {
    PreferenceInfo *info = [self infoForControl:sender];
    assert(info);

    if (info.customSettingChangedHandler) {
        info.customSettingChangedHandler(sender);
        return;
    }

    switch (info.type) {
        case kPreferenceInfoTypeCheckbox:
            [iTermPreferences setBool:([sender state] == NSOnState) forKey:info.key];
            break;

        case kPreferenceInfoTypeIntegerTextField:
            [self applyIntegerConstraints:info];
            [iTermPreferences setInt:[sender intValue] forKey:info.key];
            break;
            
        case kPreferenceInfoTypeStringTextField:
            [iTermPreferences setString:[sender stringValue] forKey:info.key];
            break;
            
        case kPreferenceInfoTypePopup:
            [iTermPreferences setInt:[sender selectedTag] forKey:info.key];
            break;
            
        case kPreferenceInfoTypeSlider:
            [iTermPreferences setFloat:[sender doubleValue] forKey:info.key];
            break;

        default:
            assert(false);
    }
    if (info.onChange) {
        info.onChange();
    }
}

- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type {
    assert(![_keyMap objectForKey:key]);
    assert(key);
    assert(control);
    assert([iTermPreferences keyHasDefaultValue:key]);
    
    PreferenceInfo *info = [PreferenceInfo infoForPreferenceWithKey:key
                                                               type:type
                                                            control:control];
    [_keyMap setObject:info forKey:control];
    [self updateValueForInfo:info];
    
    return info;
}

- (void)updateValueForInfo:(PreferenceInfo *)info {
    switch (info.type) {
        case kPreferenceInfoTypeCheckbox: {
            assert([info.control isKindOfClass:[NSButton class]]);
            NSButton *button = (NSButton *)info.control;
            button.state = [iTermPreferences boolForKey:info.key] ? NSOnState : NSOffState;
            break;
        }
            
        case kPreferenceInfoTypeIntegerTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.intValue = [iTermPreferences intForKey:info.key];
            break;
        }
            
        case kPreferenceInfoTypeStringTextField: {
            assert([info.control isKindOfClass:[NSTextField class]]);
            NSTextField *field = (NSTextField *)info.control;
            field.stringValue = [iTermPreferences stringForKey:info.key];
            break;
        }
            
        case kPreferenceInfoTypePopup: {
            assert([info.control isKindOfClass:[NSPopUpButton class]]);
            NSPopUpButton *popup = (NSPopUpButton *)info.control;
            [popup selectItemWithTag:[iTermPreferences intForKey:info.key]];
            break;
        }
            
        case kPreferenceInfoTypeSlider: {
            assert([info.control isKindOfClass:[NSSlider class]]);
            NSSlider *slider = (NSSlider *)info.control;
            slider.doubleValue = [iTermPreferences floatForKey:info.key];
            break;
        }

        default:
            assert(false);
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
    if (iv != [textField intValue] || (lastChar < '0' || lastChar > '9')) {
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

@end
