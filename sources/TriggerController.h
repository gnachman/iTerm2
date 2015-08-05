//
//  TriggerController.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"

@class TriggerController;

@protocol TriggerDelegate
- (void)triggerChanged:(TriggerController *)controller newValue:(NSArray *)value;
@end

@interface TriggerController : NSWindowController <NSWindowDelegate> 

@property (nonatomic, copy) NSString *guid;
@property (nonatomic, assign) BOOL hasSelection;
@property (nonatomic, assign) IBOutlet NSObject<TriggerDelegate> *delegate;
@property (nonatomic, readonly) NSTableView *tableView;

- (void)windowWillOpen;

@end
