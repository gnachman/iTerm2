//
//  TriggerController.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>

@class TriggerController;

@protocol TriggerDelegate
- (void)triggerChanged:(TriggerController *)controller;
@end

@interface TriggerController : NSWindowController {
  NSString *guid_;
  BOOL hasSelection_;
  IBOutlet NSObject<TriggerDelegate> *delegate_;  // weak
  IBOutlet NSTableView *tableView_;
  IBOutlet NSTableColumn *regexColumn_;
  IBOutlet NSTableColumn *actionColumn_;
  IBOutlet NSTableColumn *parametersColumn_;
}

@property (nonatomic, copy) NSString *guid;
@property (nonatomic, assign) BOOL hasSelection;
@property (nonatomic, assign) NSObject<TriggerDelegate> *delegate;

- (NSArray *)triggers;

- (IBAction)addTrigger:(id)sender;
- (IBAction)removeTrigger:(id)sender;
- (IBAction)help:(id)sender;

@end
