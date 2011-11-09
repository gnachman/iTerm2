//
//  PointerPrefsController.h
//  iTerm
//
//  Created by George Nachman on 11/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

extern NSString *kPasteFromClipboardPointerAction;
extern NSString *kPasteFromSelectionPointerAction;
extern NSString *kOpenTargetPointerAction;
extern NSString *kOpenTargetInBackgroundPointerAction;
extern NSString *kSmartSelectionPointerAction;
extern NSString *kContextMenuPointerAction;
extern NSString *kNextTabPointerAction;
extern NSString *kPrevTabPointerAction;
extern NSString *kNextWindowPointerAction;
extern NSString *kPrevWindowPointerAction;
extern NSString *kMovePanePointerAction;

extern NSString *kThreeFingerClickGesture;
extern NSString *kThreeFingerSwipeRight;
extern NSString *kThreeFingerSwipeLeft;
extern NSString *kThreeFingerSwipeUp;
extern NSString *kThreeFingerSwipeDown;

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
    IBOutlet NSButton *ok_;
    IBOutlet NSButton *remove_;

    NSString *origKey_;
    BOOL hasSelection_;
}

@property (nonatomic, assign) BOOL hasSelection;

+ (NSString *)actionWithButton:(int)buttonNumber
                     numClicks:(int)numClicks
                     modifiers:(int)modMask;

+ (NSString *)actionForTapWithTouches:(int)numTouches
                            modifiers:(int)modMask;

+ (NSString *)actionForGesture:(NSString *)gesture
                     modifiers:(int)modMask;

- (IBAction)buttonOrGestureChanged:(id)sender;
- (IBAction)ok:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)add:(id)sender;
- (IBAction)remove:(id)sender;
- (IBAction)actionChanged:(id)sender;
- (IBAction)clicksChanged:(id)sender;

@end
