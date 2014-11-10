//
//  NSPopUpButton+iTerm.h
//  iTerm
//
//  Created by George Nachman on 4/7/14.
//
//

#import <Cocoa/Cocoa.h>

@interface NSPopUpButton (iTerm)

// Add profile names and select the indicated one.
- (void)populateWithProfilesSelectingGuid:(NSString *)selectedGuid;

// Add color presets and selected the indicated one.
- (void)loadColorPresetsSelecting:(NSString *)presetName;

@end
