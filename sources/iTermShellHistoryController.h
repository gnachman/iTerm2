//
//  iTermShellHistoryController.h
//  iTerm
//
//  Created by George Nachman on 1/6/14.
//
//

#import <Foundation/Foundation.h>

#import "iTermCommandHistoryCommandUseMO+Additions.h"
#import "iTermRecentDirectoryMO.h"

extern NSString *const kCommandHistoryDidChangeNotificationName;
extern NSString *const kDirectoriesDidChangeNotificationName;

@class VT100RemoteHost;
@class VT100ScreenMark;

// This is an informal protocol that the first responder may adopt.
@protocol ShellIntegrationInstaller <NSObject>

- (void)installShellIntegration:(id)sender;

@end

@interface iTermShellHistoryController : NSObject

+ (instancetype)sharedInstance;

// Advertises shell integration in a modal alert.
+ (void)showInformationalMessage;

// Switch between in-memory and on-disk backing store based on global preference.
- (void)backingStoreTypeDidChange;

// Erase data and vacuum database.
- (void)eraseCommandHistory:(BOOL)commandHistory directories:(BOOL)directories;

#pragma mark - Command History

#pragma mark Mutation

// Record the use of a command.
- (void)addCommand:(NSString *)command
            onHost:(VT100RemoteHost *)host
       inDirectory:(NSString *)directory
          withMark:(VT100ScreenMark *)mark;

// Change the status code of a command after it finishes running.
- (void)setStatusOfCommandAtMark:(VT100ScreenMark *)mark
                          onHost:(VT100RemoteHost *)remoteHost
                              to:(int)status;

#pragma mark Lookup

// Has a command ever been saved to history? Suggests user already knows about shell integration.
- (BOOL)commandHistoryHasEverBeenUsed;

// Returns unique commands that have a given prefix. Sorted by frecency.
- (NSArray<iTermCommandHistoryEntryMO *> *)commandHistoryEntriesWithPrefix:(NSString *)partialCommand
                                                                    onHost:(VT100RemoteHost *)host;

// Just like commandHistoryEntriesWithPrefix:onHost, but returns command uses rather than entries.
// Only the most recent use is returned.
- (NSArray<iTermCommandHistoryCommandUseMO *> *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                                                   onHost:(VT100RemoteHost *)host;

// Is there any command history for this host?
- (BOOL)haveCommandsForHost:(VT100RemoteHost *)host;

// Returns a command use for a given mark.
- (iTermCommandHistoryCommandUseMO *)commandUseWithMarkGuid:(NSString *)markGuid
                                                     onHost:(VT100RemoteHost *)host;

// Returns all command uses on a given host.
- (NSArray<iTermCommandHistoryCommandUseMO *> *)commandUsesForHost:(VT100RemoteHost *)host;

#pragma mark - Recent Directories

#pragma mark Mutation

// Record that a directory was entered. Set isChange to YES if the directory has just changed, or
// NO if it's a repeat of the last path on this host.
- (iTermRecentDirectoryMO *)recordUseOfPath:(NSString *)path
                                     onHost:(VT100RemoteHost *)host
                                   isChange:(BOOL)isChange;

// Change the "starred" setting of a directory.
- (void)setDirectory:(iTermRecentDirectoryMO *)directory starred:(BOOL)starred;

#pragma mark Lookup

// Indicate which components in entry's path may be safely abbreviated because they aren't needed
// to disambiguate.
- (NSIndexSet *)abbreviationSafeIndexesInRecentDirectory:(iTermRecentDirectoryMO *)entry;

// Find directories on a given host sorted by frecency.
- (NSArray *)directoriesSortedByScoreOnHost:(VT100RemoteHost *)host;

// Are there any directories known for this host?
- (BOOL)haveDirectoriesForHost:(VT100RemoteHost *)host;

#pragma mark - Testing

- (void)eraseCommandHistoryForHost:(VT100RemoteHost *)host;
- (void)eraseDirectoriesForHost:(VT100RemoteHost *)host;
- (NSString *)pathForFileNamed:(NSString *)name;
- (NSTimeInterval)now;
- (NSString *)databaseFilenamePrefix;
- (BOOL)finishInitialization;
- (instancetype)initPartially;

@end
