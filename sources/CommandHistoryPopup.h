//
//  CommandHistoryPopup.h
//  iTerm
//
//  Created by George Nachman on 1/14/14.
//
//

#import <Foundation/Foundation.h>
#import "iTermPopupWindowController.h"
#import "PopupEntry.h"

@class VT100RemoteHost;

@interface CommandHistoryPopupEntry : PopupEntry
@property(nonatomic, copy) NSString *command;
@property(nonatomic, retain) NSDate *date;
@end

@interface CommandHistoryPopupWindowController : iTermPopupWindowController

// Returns uses if expand is NO or entries if it is YES.
- (NSArray *)commandsForHost:(VT100RemoteHost *)host
              partialCommand:(NSString *)partialCommand
                      expand:(BOOL)expand;


- (void)loadCommands:(NSArray *)commands partialCommand:(NSString *)partialCommand;

@end
