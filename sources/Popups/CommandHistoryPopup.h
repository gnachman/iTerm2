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

@protocol VT100RemoteHostReading;

@interface CommandHistoryPopupEntry : PopupEntry
@property(nonatomic, copy) NSString *command;
@property(nonatomic, retain) NSDate *date;
@end

@interface CommandHistoryPopupWindowController : iTermPopupWindowController

@property (nonatomic) BOOL forwardKeyDown;

- (instancetype)initForAutoComplete:(BOOL)autocomplete;
- (instancetype)init NS_UNAVAILABLE;

// Returns uses if expand is NO or entries if it is YES.
- (NSArray *)commandsForHost:(id<VT100RemoteHostReading>)host
              partialCommand:(NSString *)partialCommand
                      expand:(BOOL)expand;


- (void)loadCommands:(NSArray *)commands
      partialCommand:(NSString *)partialCommand
 sortChronologically:(BOOL)sortChronologically;

@end
