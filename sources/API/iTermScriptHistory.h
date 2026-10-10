//
//  iTermScriptHistory.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/19/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermScriptHistoryEntryDidChangeNotification;
extern NSString *const iTermScriptHistoryEntryDelta;  // User info key giving next log/call
extern NSString *const iTermScriptHistoryEntryFieldKey;  // User info key giving what changed
extern NSString *const iTermScriptHistoryEntryFieldLogsValue;  // Logs changed
extern NSString *const iTermScriptHistoryEntryFieldRPCValue;  // RPC changed

@class iTermWebSocketConnection;

@interface iTermScriptHistoryEntry : NSObject

@property (nonatomic, readonly) NSDate *startDate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, copy) NSArray<NSNumber *> *pids;
@property (nonatomic, readonly) pid_t onlyPid;  // Returns the pid if there's only one, otherwise 0
@property (nonatomic, readonly) NSArray<NSString *> *logLines;
@property (nonatomic, readonly) NSArray<NSString *> *callEntries;
@property (nonatomic, weak) iTermWebSocketConnection *websocketConnection;
@property (nonatomic, readonly) BOOL lastLogLineContinues;
@property (nonatomic, nullable, readonly) void (^relaunch)(void);
@property (nonatomic) BOOL terminatedByUser;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, readonly, nullable) NSString *fullPath;  // This can be passed to launchScriptWithAbsolutePath:
// Whether an API shutdown would kill this entry's process. See -trackProcess:.
@property (nonatomic, readonly) BOOL observesAPIShutdown;
// Stopped, with no launched process still alive. Only finished entries are
// removed from the history, by the cap on finished entries or by Clear
// Terminated.
@property (nonatomic, readonly) BOOL isFinished;

+ (instancetype)globalEntry;
+ (instancetype)apsEntry;
+ (instancetype)dynamicProfilesEntry;
+ (instancetype)browserEntry:(NSString *)identifier;
+ (instancetype)smartSelectionAnctionsEntry;
- (instancetype)initWithName:(NSString *)name
                    fullPath:(nullable NSString *)fullPath
                  identifier:(NSString *)identifier
                    relaunch:(void (^ _Nullable)(void))relaunch NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addOutput:(NSString *)output completion:(void (^)(void))completion;
- (void)addClientOriginatedRPC:(NSString *)rpc;
- (void)addServerOriginatedRPC:(NSString *)rpc;
- (void)stopRunning;
// Connections can reuse a key after closing (it2 over SSH shares one key per
// session; a client may reconnect with its old key), so a stopped entry can
// come back to life.
- (void)resumeRunning;
// Track the API connections using this entry's key. The entry stops when the
// last one closes, and resumes if one opens while it's stopped. pids describes
// the connecting process.
- (void)connectionDidOpenWithPIDs:(nullable NSArray<NSNumber *> *)pids;
- (void)connectionDidClose;
// For a process iTerm2 launched. Its entry stays responsible for killing the
// process when the API shuts down, even after its connections close, until
// -processDidExit, which also stops the entry.
- (void)trackProcess:(pid_t)pid;
- (void)processDidExit;
- (void)kill;

@end

extern NSString *const iTermScriptHistoryNumberOfEntriesDidChangeNotification;

@interface iTermScriptHistory : NSObject

@property (nonatomic, readonly) NSArray<iTermScriptHistoryEntry *> *entries;
@property (nonatomic, readonly) NSArray<iTermScriptHistoryEntry *> *runningEntries;

+ (instancetype)sharedInstance;
- (void)addHistoryEntry:(iTermScriptHistoryEntry *)entry;
- (void)removeHistoryEntry:(iTermScriptHistoryEntry *)entry;
// Removes every finished entry. Persistent pseudo-entries (the app, APS,
// dynamic profiles, browser loggers) are always running and survive.
- (void)removeTerminatedEntries;
- (iTermScriptHistoryEntry *)entryWithIdentifier:(NSString *)identifier;
- (iTermScriptHistoryEntry *)runningEntryWithPath:(NSString *)path;
- (iTermScriptHistoryEntry *)runningEntryWithFullPath:(NSString *)fullPath;
- (void)addAPSLoggingEntryIfNeeded;
- (void)addDynamicProfilesLoggingEntryIfNeeded;
- (void)addBrowserLoggingEntryIfNeeded:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
