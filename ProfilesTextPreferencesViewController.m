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
}

- (void)awakeFromNib {
    [self defineControl:_cursorType
                    key:KEY_CURSOR_TYPE
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self setInt:[[sender selectedCell] tag] forKey:KEY_CURSOR_TYPE]; }
                 update:^BOOL{ [_cursorType selectCellWithTag:[self intForKey:KEY_CURSOR_TYPE]]; return YES; }];
    
}

@end
