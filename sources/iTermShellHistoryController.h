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

@protocol VT100RemoteHostReading;
@protocol VT100ScreenMarkReading;

// This is an informal protocol that the first responder may adopt.
@protocol ShellIntegrationInstaller <NSObject>

- (void)installShellIntegration:(id)sender;

@end

@interface iTermShellHistoryController : NSObject

+ (instancetype)sharedInstance;

// Advertises shell integration in a modal alert.
+ (void)showInformationalMessageInWindow:(NSWindow *)window;

// Switch between in-memory and on-disk backing store based on global preference.
- (void)backingStoreTypeDidChange;

// Erase data and vacuum database.
- (void)eraseCommandHistory:(BOOL)commandHistory directories:(BOOL)directories;

#pragma mark - Command History

#pragma mark Mutation

// Record the use of a command.
- (void)addCommand:(NSString *)command
            onHost:(id<VT100RemoteHostReading>)host
       inDirectory:(NSString *)directory
          withMark:(id<VT100ScreenMarkReading>)mark;

// Change the status code of a command after it finishes running.
- (void)setStatusOfCommandAtMark:(id<VT100ScreenMarkReading>)mark
                          onHost:(id<VT100RemoteHostReading>)remoteHost
                              to:(int)status;

#pragma mark Lookup

// Has a command ever been saved to history? Suggests user already knows about shell integration.
- (BOOL)commandHistoryHasEverBeenUsed;

// Returns unique commands that have a given prefix. Sorted by frecency.
- (NSArray<iTermCommandHistoryEntryMO *> *)commandHistoryEntriesWithPrefix:(NSString *)partialCommand
                                                                    onHost:(id<VT100RemoteHostReading>)host;

// Just like commandHistoryEntriesWithPrefix:onHost, but returns command uses rather than entries.
// Only the most recent use is returned.
- (NSArray<iTermCommandHistoryCommandUseMO *> *)autocompleteSuggestionsWithPartialCommand:(NSString *)partialCommand
                                                                                   onHost:(id<VT100RemoteHostReading>)host;

// Is there any command history for this host?
- (BOOL)haveCommandsForHost:(id<VT100RemoteHostReading>)host;

// Returns a command use for a given mark.
- (iTermCommandHistoryCommandUseMO *)commandUseWithMarkGuid:(NSString *)markGuid
                                                     onHost:(id<VT100RemoteHostReading>)host;

// Returns all command uses on a given host.
- (NSArray<iTermCommandHistoryCommandUseMO *> *)commandUsesForHost:(id<VT100RemoteHostReading>)host;

#pragma mark - Recent Directories

#pragma mark Mutation

// Record that a directory was entered. Set isChange to YES if the directory has just changed, or
// NO if it's a repeat of the last path on this host.
- (iTermRecentDirectoryMO *)recordUseOfPath:(NSString *)path
                                     onHost:(id<VT100RemoteHostReading>)host
                                   isChange:(BOOL)isChange;

// Change the "starred" setting of a directory.
- (void)setDirectory:(iTermRecentDirectoryMO *)directory starred:(BOOL)starred;

#pragma mark Lookup

// Indicate which components in entry's path may be safely abbreviated because they aren't needed
// to disambiguate.
- (NSIndexSet *)abbreviationSafeIndexesInRecentDirectory:(iTermRecentDirectoryMO *)entry;

// Find directories on a given host sorted by frecency.
- (NSArray *)directoriesSortedByScoreOnHost:(id<VT100RemoteHostReading>)host;

// Are there any directories known for this host?
- (BOOL)haveDirectoriesForHost:(id<VT100RemoteHostReading>)host;

#pragma mark - Testing

- (void)eraseCommandHistoryForHost:(id<VT100RemoteHostReading>)host;
- (void)eraseDirectoriesForHost:(id<VT100RemoteHostReading>)host;
- (NSString *)pathForFileNamed:(NSString *)name;
- (NSTimeInterval)now;
- (NSString *)databaseFilenamePrefix;
- (BOOL)finishInitialization;
- (instancetype)initPartially;

@end
