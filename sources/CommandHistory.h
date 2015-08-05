//
//  CommandHistory.h
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import <Foundation/Foundation.h>
#import "CommandUse.h"

extern NSString *const kCommandHistoryDidChangeNotificationName;

@class VT100RemoteHost;
@class VT100ScreenMark;

// This is an informal protocol that the first responder may adopt.
@protocol ShellIntegrationInstaller <NSObject>

- (void)installShellIntegration:(id)sender;

@end

@interface CommandHistory : NSObject

+ (instancetype)sharedInstance;

+ (void)showInformationalMessage;

- (BOOL)commandHistoryHasEverBeenUsed;

- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark;

- (NSArray *)commandHistoryEntriesWithPrefix:(NSString *)partialCommand
                                      onHost:(VT100RemoteHost *)host;

// Returns an array of CommandUse
- (NSArray *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                onHost:(VT100RemoteHost *)host;

- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host;

- (void)eraseHistory;

- (CommandUse *)commandUseWithMarkGuid:(NSString *)markGuid onHost:(VT100RemoteHost *)host;

- (NSMutableArray *)commandUsesForHost:(VT100RemoteHost *)host;

#pragma mark - Testing

- (void)eraseHistoryForHost:(VT100RemoteHost *)host;

@end
