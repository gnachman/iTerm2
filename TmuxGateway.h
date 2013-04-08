//
//  TmuxGateway.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>

// Constant values for flags:
// Command may fail with an error and selector is still run but with nil
// output.
extern const int kTmuxGatewayCommandShouldTolerateErrors;
// Send NSData, not NSString, for output (allowing busted/partial utf-8
// sequences).
extern const int kTmuxGatewayCommandWantsData;
// Bug in tmux 1.8. %end guard not printed, so watch for %error in command
// output.
extern const int kTmuxGatewayCommandHasEndGuardBug;

@class TmuxController;

extern NSString * const kTmuxGatewayErrorDomain;

@protocol TmuxGatewayDelegate

- (TmuxController *)tmuxController;
- (void)tmuxUpdateLayoutForWindow:(int)windowId
                           layout:(NSString *)layout;
- (void)tmuxWindowAddedWithId:(int)windowId;
- (void)tmuxWindowClosedWithId:(int)windowId;
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName;
- (void)tmuxHostDisconnected;
- (void)tmuxWriteData:(NSData *)data;
- (void)tmuxReadTask:(NSData *)data;
- (void)tmuxSessionChanged:(NSString *)sessionName
				 sessionId:(int)sessionId;
- (void)tmuxSessionsChanged;
- (void)tmuxWindowsDidChange;
- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName;
- (NSSize)tmuxBookmarkSize;  // rows, cols
- (int)tmuxNumHistoryLinesInBookmark;
- (void)tmuxSetSecureLogging:(BOOL)secureLogging;

@end

typedef enum {
    CONTROL_COMMAND_OUTPUT,
    CONTROL_COMMAND_LAYOUT_CHANGE,
    CONTROL_COMMAND_WINDOWS_CHANGE,
    CONTROL_COMMAND_NOOP
} ControlCommand;

typedef enum {
    CONTROL_STATE_READY,
    CONTROL_STATE_DETACHED,
} ControlState;

@interface TmuxGateway : NSObject {
    NSObject<TmuxGatewayDelegate> *delegate_;  // weak
    ControlState state_;
    NSMutableData *stream_;

    // Data from parsing an incoming command
    ControlCommand command_;

    NSMutableArray *commandQueue_;  // NSMutableDictionary objects
    NSMutableString *currentCommandResponse_;
    NSMutableDictionary *currentCommand_;  // Set between %begin and %end
    NSMutableData *currentCommandData_;

    BOOL detachSent_;
    BOOL acceptNotifications_;  // Initially NO. When YES, respond to notifications.
}

- (id)initWithDelegate:(NSObject<TmuxGatewayDelegate> *)delegate;

// Returns any unconsumed data if tmux mode is exited.
- (NSData *)readTask:(NSData *)data;
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
- (void)abortWithErrorMessage:(NSString *)message;

// Use this to compose a command list for sendCommandList:.
// flags is one of the kTmuxGateway... constants.
- (NSDictionary *)dictionaryForCommand:(NSString *)command
                        responseTarget:(id)target
                      responseSelector:(SEL)selector
                        responseObject:(id)obj
                                 flags:(int)flags;

- (void)sendKeys:(NSData *)data toWindowPane:(int)windowPane;
- (void)detach;
- (NSObject<TmuxGatewayDelegate> *)delegate;

@end
