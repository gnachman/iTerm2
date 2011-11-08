//
//  PointerPrefsController.h
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PointerPrefsController : NSObject {
    IBOutlet NSTableView *tableView_;
    IBOutlet NSTableColumn *buttonColumn_;
    IBOutlet NSTableColumn *actionColumn_;

    IBOutlet NSPanel *panel_;
    IBOutlet NSTextField *editButtonLabel_;
    IBOutlet NSPopUpButton *editButton_;
    IBOutlet NSTextField *editModifiersLabel_;
    IBOutlet NSButton *editModifiersCommand_;
    IBOutlet NSButton *editModifiersOption_;
    IBOutlet NSButton *editModifiersShift_;
    IBOutlet NSButton *editModifiersControl_;
    IBOutlet NSTextField *editActionLabel_;
    IBOutlet NSPopUpButton *editAction_;
    IBOutlet NSTextField *editClickTypeLabel_;
    IBOutlet NSPopUpButton *editClickType_;
    
    NSString *origKey_;
    BOOL hasSelection_;
}

@property (nonatomic, assign) BOOL hasSelection;

- (IBAction)buttonOrGestureChanged:(id)sender;
- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;

@end
