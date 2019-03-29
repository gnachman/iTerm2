//
//  iTermAdvancedSettingsController.h
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermSearchableViewController.h"

extern BOOL gIntrospecting;

@interface iTermAdvancedSettingsViewController : NSViewController <iTermSearchableViewController, NSTableViewDataSource, NSTableViewDelegate>

@end
