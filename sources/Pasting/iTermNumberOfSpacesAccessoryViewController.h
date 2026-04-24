//
//  iTermNumberOfSpacesAccessoryViewController.h
//  iTerm2
//
//  Created by George Nachman on 11/30/14.
//
//

#import <Cocoa/Cocoa.h>

// Controls the "NumberOfSpacesAccessoryView", used in a modal alert shown when
// pasting a string with tabs in it.
@interface iTermNumberOfSpacesAccessoryViewController : NSViewController

// Takes its initial value from user defaults.
@property(nonatomic, readonly) int numberOfSpaces;

// Write number of spaces to user defaults.
- (void)saveToUserDefaults;

@end
