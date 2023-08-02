//
//  TmuxGateway.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "VT100GridTypes.h"
#import "WindowControllerInterface.h"

typedef NS_OPTIONS(int, kTmuxGatewayCommandOptions) {
    // Command may fail with an error and selector is still run but with nil
    // output.
    kTmuxGatewayCommandShouldTolerateErrors = (1 << 0),

    // Send NSData, not NSString, for output (allowing busted/partial utf-8
    // sequences).
    kTmuxGatewayCommandWantsData = (1 << 1),

    // If this exact command was sent and has been pending for a while, offer to detach.
    kTmuxGatewayCommandOfferToDetachIfLaggyDuplicate = (1 << 2)
};

@class TmuxController;
@class VT100Token;

extern NSString * const kTmuxGatewayErrorDomain;

@interface iTermTmuxSubscriptionHandle: NSObject
@property (nonatomic, readonly) BOOL isValid;
@end

@protocol TmuxGatewayDelegate <NSObject>

- (TmuxController *)tmuxController;
- (BOOL)tmuxUpdateLayoutForWindow:(int)windowId
                           layout:(NSString *)layout
                    visibleLayout:(NSString *)visibleLayout
                           zoomed:(NSNumber *)zoomed
                             only:(BOOL)only;
- (void)tmuxWindowAddedWithId:(int)windowId;
- (void)tmuxWindowClosedWithId:(int)windowId;
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName;
- (void)tmuxHostDisconnected:(NSString *)dcsID;
- (void)tmuxWriteString:(NSString *)string;
- (void)tmuxReadTask:(NSData *)data windowPane:(int)wp latency:(NSNumber *)latency;
- (void)tmuxSessionChanged:(NSString *)sessionName
				 sessionId:(int)sessionId;
- (void)tmuxSessionsChanged;
- (void)tmuxWindowsDidChange;
- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName;
- (VT100GridSize)tmuxClientSize;
- (NSInteger)tmuxNumberOfLinesOfScrollbackHistory;
- (void)tmuxSetSecureLogging:(BOOL)secureLogging;
- (void)tmuxPrintLine:(NSString *)line;
- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow;
- (void)tmuxInitialCommandDidCompleteSuccessfully;
- (void)tmuxInitialCommandDidFailWithError:(NSString *)error;
- (void)tmuxCannotSendCharactersInSupplementaryPlanes:(NSString *)string windowPane:(int)windowPane;
- (void)tmuxDidOpenInitialWindows;
- (void)tmuxDoubleAttachForSessionGUID:(NSString *)sessionGUID;
- (NSString *)tmuxOwningSessionGUID;
- (BOOL)tmuxGatewayShouldForceDetach;
- (void)tmuxGatewayDidTimeOut;
- (void)tmuxActiveWindowPaneDidChangeInWindow:(int)windowID toWindowPane:(int)paneID;
- (void)tmuxSessionWindowDidChangeTo:(int)windowID;
- (void)tmuxWindowPaneDidPause:(int)wp notification:(BOOL)notification;
- (void)tmuxSessionPasteDidChange:(NSString *)pasteBufferName;
@end

typedef NS_ENUM(NSInteger, ControlCommand) {
    CONTROL_COMMAND_OUTPUT,
    CONTROL_COMMAND_LAYOUT_CHANGE,
    CONTROL_COMMAND_WINDOWS_CHANGE,
    CONTROL_COMMAND_NOOP
};

@interface TmuxGateway : NSObject

// Should all protocol-level input be logged to the gateway's session?
@property(nonatomic, assign) BOOL tmuxLogging;
@property(nonatomic, readonly) NSWindowController<iTermWindowController> *window;
@property(nonatomic, weak) id<TmuxGatewayDelegate> delegate;
@property(nonatomic, retain) NSDecimalNumber *minimumServerVersion;
@property(nonatomic, retain) NSDecimalNumber *maximumServerVersion;
@property(nonatomic, assign) BOOL acceptNotifications;
@property(nonatomic, readonly) NSString *dcsID;
@property(nonatomic, readonly) BOOL detachSent;
@property(nonatomic, readonly) BOOL isTmuxUnresponsive;
@property(nonatomic) BOOL pauseModeEnabled;

- (instancetype)initWithDelegate:(id<TmuxGatewayDelegate>)delegate dcsID:(NSString *)dcsID NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)versionAtLeastDecimalNumberWithString:(NSString *)string;

// Returns any unconsumed data if tmux mode is exited.
// The token must be TMUX_xxx.
- (void)executeToken:(VT100Token *)token;

- (void)sendCommand:(NSString *)command
     responseTarget:(id)target
   responseSelector:(SEL)selector;

// flags is one of the kTmuxGateway... constants.
- (void)sendCommand:(NSString *)command
     responseTarget:(id)target
   responseSelector:(SEL)selector
     responseObject:(id)obj
              flags:(int)flags;

- (void)sendCommandList:(NSArray *)commandDicts;
// Set initial to YES when notifications should be accepted after the last
// command gets a response.
- (void)sendCommandList:(NSArray *)commandDicts initial:(BOOL)initial;
- (void)abortWithErrorMessage:(NSString *)message title:(NSString *)title;
- (void)abortWithErrorMessage:(NSString *)message;

// Use this to compose a command list for sendCommandList:.
// flags is one of the kTmuxGateway... constants.
- (NSDictionary *)dictionaryForCommand:(NSString *)command
                        responseTarget:(id)target
                      responseSelector:(SEL)selector
                        responseObject:(id)obj
                                 flags:(int)flags;

- (void)sendKeys:(NSString *)string toWindowPane:(int)windowPane;
- (void)detach;
- (void)forceDetach;
- (void)doubleAttachDetectedForSessionGUID:(NSString *)sessionGuid;
- (BOOL)havePendingCommandEqualTo:(NSString *)command;

- (iTermTmuxSubscriptionHandle *)subscribeToFormat:(NSString *)format
                                            target:(NSString *)target
                                             block:(void (^)(NSString *, NSArray<NSString *> *))block;
- (void)unsubscribe:(iTermTmuxSubscriptionHandle *)handle;
- (BOOL)supportsSubscriptions;

@end
