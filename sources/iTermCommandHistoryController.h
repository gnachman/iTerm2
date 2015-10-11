//
//  iTermCommandHistoryController.h
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import <Foundation/Foundation.h>

#import "iTermCommandHistoryCommandUseMO+Addtions.h"

extern NSString *const kCommandHistoryDidChangeNotificationName;

@class VT100RemoteHost;
@class VT100ScreenMark;

// This is an informal protocol that the first responder may adopt.
@protocol ShellIntegrationInstaller <NSObject>

- (void)installShellIntegration:(id)sender;

@end

@interface iTermCommandHistoryController : NSObject

+ (instancetype)sharedInstance;

+ (void)showInformationalMessage;

- (BOOL)commandHistoryHasEverBeenUsed;

- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark;

- (void)setStatusOfCommandAtMark:(VT100ScreenMark *)mark
                          onHost:(VT100RemoteHost *)remoteHost
                              to:(int)status;

- (NSArray<iTermCommandHistoryEntryMO *> *)commandHistoryEntriesWithPrefix:(NSString *)partialCommand
                                                                    onHost:(VT100RemoteHost *)host;

- (NSArray<iTermCommandHistoryCommandUseMO *> *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                onHost:(VT100RemoteHost *)host;

- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host;

- (void)eraseHistory;

- (iTermCommandHistoryCommandUseMO *)commandUseWithMarkGuid:(NSString *)markGuid
                                                     onHost:(VT100RemoteHost *)host;

- (NSArray<iTermCommandHistoryCommandUseMO *> *)commandUsesForHost:(VT100RemoteHost *)host;

#pragma mark - Testing

- (void)eraseHistoryForHost:(VT100RemoteHost *)host;
- (NSString *)pathForFileNamed:(NSString *)name;
- (NSTimeInterval)now;
- (BOOL)saveToDisk;
- (NSString *)databaseFilenamePrefix;
- (BOOL)finishInitialization;
- (instancetype)initPartially;

@end
