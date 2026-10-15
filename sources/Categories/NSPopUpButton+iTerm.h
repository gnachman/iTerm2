//
//  NSPopUpButton+iTerm.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"

@interface NSPopUpButton (iTerm)

// Add profile names and select the indicated one.
- (void)populateWithProfilesSelectingGuid:(NSString *)selectedGuid
                             profileTypes:(ProfileType)profileTypes;

// Add color presets and selected the indicated one.
- (void)loadColorPresetsSelecting:(NSString *)presetName;

// Add snippets.
- (void)populateWithSnippetsSelectingActionKey:(id)actionKey;
- (void)it_addItemWithTitle:(NSString *)title tag:(NSUInteger)tag;

// Selects the item whose represented object equals `object`. If there is none, selects the one for
// `fallback`, and if that is missing too, shows no selection. A nil or NSNull `object` changes
// nothing.
- (void)it_selectItemWithRepresentedObject:(id)object fallback:(id)fallback;

@end
