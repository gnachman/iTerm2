//
//  GeneralPreferencesViewController.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermPreferencesBaseViewController.h"

@interface GeneralPreferencesViewController : iTermPreferencesBaseViewController

// Custom folder stuff
- (IBAction)browseCustomFolder:(id)sender;
- (IBAction)pushToCustomFolder:(id)sender;


@end
