//
//  iTermBroadcastInputHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/4/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const iTermBroadcastDomainsDidChangeNotification;

typedef NS_ENUM(NSInteger, BroadcastMode) {
    BROADCAST_OFF,
    BROADCAST_TO_ALL_PANES,
    BROADCAST_TO_ALL_TABS,
    BROADCAST_CUSTOM
};

@class iTermBroadcastInputHelper;
@class NSWindow;

@protocol iTermBroadcastInputHelperDelegate<NSObject>

- (NSArray<NSString *> *)broadcastInputHelperSessionsInCurrentTab:(iTermBroadcastInputHelper *)helper
                                                    includeExited:(BOOL)includeExited;
- (NSArray<NSString *> *)broadcastInputHelperSessionsInAllTabs:(iTermBroadcastInputHelper *)helper
                                                 includeExited:(BOOL)includeExited;
- (NSString *)broadcastInputHelperCurrentSession:(iTermBroadcastInputHelper *)helper;
- (void)broadcastInputHelperDidUpdate:(iTermBroadcastInputHelper *)helper;
- (BOOL)broadcastInputHelperCurrentTabIsBroadcasting:(iTermBroadcastInputHelper *)helper;
- (void)broadcastInputHelperSetNoTabBroadcasting:(iTermBroadcastInputHelper *)helper;
- (void)broadcastInputHelper:(iTermBroadcastInputHelper *)helper setCurrentTabBroadcasting:(BOOL)broadcasting;
- (NSWindow *)broadcastInputHelperWindowForWarnings:(iTermBroadcastInputHelper *)helper;
@end

@interface iTermBroadcastInputHelper : NSObject

@property (nonatomic, weak) id<iTermBroadcastInputHelperDelegate> delegate;

// How input should be broadcast (or not).
@property (nonatomic) BroadcastMode broadcastMode;
@property (nonatomic, copy) NSSet<NSString *> *broadcastSessionIDs;

- (void)toggleSession:(NSString *)sessionID;

@end

NS_ASSUME_NONNULL_END
