//
//  CommandHistoryPopup.h
//  iTerm
//
//  Created by George Nachman on 1/14/14.
//
//

#import <Foundation/Foundation.h>
#import "Popup.h"
#import "PopupEntry.h"

@class VT100RemoteHost;

@interface CommandHistoryPopupEntry : PopupEntry
@property(nonatomic, copy) NSString *command;
@property(nonatomic, retain) NSDate *date;
@end

@interface CommandHistoryPopupWindowController : Popup

- (void)loadCommandsForHost:(VT100RemoteHost *)host
             partialCommand:(NSString *)partialCommand;

@end
