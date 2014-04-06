//
//  GeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Cocoa/Cocoa.h>

@interface GeneralPreferencesViewController : NSViewController

- (IBAction)settingChanged:(id)sender;

// Enable or disable controls as needed.
- (void)updateEnabledState;

// Custom folder stuff
- (IBAction)browseCustomFolder:(id)sender;
- (IBAction)pushToCustomFolder:(id)sender;


@end
