//
//  ProfilesTerminalPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/17/14.
//
//

#import "ProfilesTerminalPreferencesViewController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"

@implementation ProfilesTerminalPreferencesViewController {
    IBOutlet NSTextField *_numScrollbackLines;
    IBOutlet NSButton *_unlimitedScrollback;
    IBOutlet NSButton *_scrollbackWithStatusBar;
    IBOutlet NSButton *_scrollbackInAlternateScreen;
    IBOutlet NSPopUpButton *_characterEncoding;
    IBOutlet NSComboBox *_terminalType;
    IBOutlet NSButton *_xtermMouseReporting;
}

- (void)awakeFromNib {
    PreferenceInfo *info;
    info = [self defineControl:_numScrollbackLines
                           key:KEY_SCROLLBACK_LINES
                          type:kPreferenceInfoTypeIntegerTextField];
    info.range = NSMakeRange(0, 10 * 1000 * 1000);
    
    info = [self defineControl:_unlimitedScrollback
                           key:KEY_UNLIMITED_SCROLLBACK
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^() {
        BOOL unlimited = [self boolForKey:KEY_UNLIMITED_SCROLLBACK];
        _numScrollbackLines.enabled = !unlimited;
        if (unlimited) {
            _numScrollbackLines.stringValue = @"";
        } else {
            _numScrollbackLines.intValue = [self intForKey:KEY_SCROLLBACK_LINES];
        }
    };

    [self defineControl:_scrollbackWithStatusBar
                    key:KEY_SCROLLBACK_WITH_STATUS_BAR
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_scrollbackInAlternateScreen
                    key:KEY_SCROLLBACK_IN_ALTERNATE_SCREEN
                   type:kPreferenceInfoTypeCheckbox];
    
    [self populateEncodings];
    [self defineControl:_characterEncoding
                    key:KEY_CHARACTER_ENCODING
                   type:kPreferenceInfoTypePopup];
    
    // It's a combobox, but we can safely treat it as a string text field.
    [self defineControl:_terminalType
                    key:KEY_TERMINAL_TYPE
                   type:kPreferenceInfoTypeStringTextField];
    
    [self defineControl:_xtermMouseReporting
                    key:KEY_XTERM_MOUSE_REPORTING
                   type:kPreferenceInfoTypeCheckbox];
}

#pragma mark - Character Encoding

- (void)populateEncodings {
    [_characterEncoding removeAllItems];
    for (NSNumber *anEncoding in [self sortedEncodings]) {
        NSString *theTitle = [NSString localizedNameOfStringEncoding:[anEncoding unsignedIntValue]];
        [_characterEncoding addItemWithTitle:theTitle];
        [[_characterEncoding lastItem] setTag:[anEncoding unsignedIntValue]];
    }
}

// Comparator for sorting encodings
static NSInteger CompareEncodingByLocalizedName(id a, id b, void *unused) {
    NSString *localizedA = [NSString localizedNameOfStringEncoding:[a unsignedIntValue]];
    NSString *localizedB = [NSString localizedNameOfStringEncoding:[b unsignedIntValue]];
    return [localizedA caseInsensitiveCompare:localizedB];
}

- (NSArray *)sortedEncodings {
    NSStringEncoding const *encodingPtr;
    NSMutableArray *encodings = [NSMutableArray array];
    
    for (encodingPtr = [NSString availableStringEncodings]; *encodingPtr; ++encodingPtr) {
        [encodings addObject:@(*encodingPtr)];
    }
    [encodings sortUsingFunction:CompareEncodingByLocalizedName context:NULL];

    return encodings;
}



@end
