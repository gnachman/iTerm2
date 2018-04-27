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
@property (nonatomic) int pid;
@property (nonatomic, readonly) NSArray<NSString *> *logLines;
@property (nonatomic, readonly) NSArray<NSString *> *callEntries;
@property (nonatomic, weak) iTermWebSocketConnection *websocketConnection;
@property (nonatomic, readonly) BOOL lastLogLineContinues;

- (instancetype)initWithName:(NSString *)name identifier:(NSString *)identifier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)addOutput:(NSString *)output;
- (void)addClientOriginatedRPC:(NSString *)rpc;
- (void)addServerOriginatedRPC:(NSString *)rpc;
- (void)stopRunning;

@end

extern NSString *const iTermScriptHistoryNumberOfEntriesDidChangeNotification;

@interface iTermScriptHistory : NSObject

@property (nonatomic, readonly) NSArray<iTermScriptHistoryEntry *> *entries;
@property (nonatomic, readonly) NSArray<iTermScriptHistoryEntry *> *runningEntries;

+ (instancetype)sharedInstance;
- (void)addHistoryEntry:(iTermScriptHistoryEntry *)entry;
- (iTermScriptHistoryEntry *)entryWithIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
