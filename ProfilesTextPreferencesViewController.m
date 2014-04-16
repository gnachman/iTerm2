//
//  ProfilesTextPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "ProfilesTextPreferencesViewController.h"
#import "ITAddressBookMgr.h"

@implementation ProfilesTextPreferencesViewController {
    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
    IBOutlet NSMatrix *_cursorType;
    IBOutlet NSButton *_blinkingCursor;
    IBOutlet NSButton *_useBoldFont;
    IBOutlet NSButton *_useBrightBold;  // Bold text in bright colors
    IBOutlet NSButton *_blinkAllowed;
    IBOutlet NSButton *_useItalicFont;
    IBOutlet NSButton *_ambiguousIsDoubleWidth;
}

- (void)awakeFromNib {
    [self defineControl:_cursorType
                    key:KEY_CURSOR_TYPE
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self setInt:[[sender selectedCell] tag] forKey:KEY_CURSOR_TYPE]; }
                 update:^BOOL{ [_cursorType selectCellWithTag:[self intForKey:KEY_CURSOR_TYPE]]; return YES; }];
    
    [self defineControl:_blinkingCursor
                    key:KEY_BLINKING_CURSOR
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_useBoldFont
                    key:KEY_USE_BOLD_FONT
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_useBrightBold
                    key:KEY_USE_BRIGHT_BOLD
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_blinkAllowed
                    key:KEY_BLINK_ALLOWED
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_useItalicFont
                    key:KEY_USE_ITALIC_FONT
                   type:kPreferenceInfoTypeCheckbox];
    
    [self defineControl:_ambiguousIsDoubleWidth
                    key:KEY_AMBIGUOUS_DOUBLE_WIDTH
                   type:kPreferenceInfoTypeCheckbox];
}

@end
