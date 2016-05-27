//
//  TmuxGateway.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>
#import "WindowControllerInterface.h"

// Constant values for flags:
// Command may fail with an error and selector is still run but with nil
// output.
extern const int kTmuxGatewayCommandShouldTolerateErrors;
// Send NSData, not NSString, for output (allowing busted/partial utf-8
// sequences).
extern const int kTmuxGatewayCommandWantsData;

@class TmuxController;
@class VT100Token;

extern NSString * const kTmuxGatewayErrorDomain;

@protocol TmuxGatewayDelegate <NSObject>

- (TmuxController *)tmuxController;
- (void)tmuxUpdateLayoutForWindow:(int)windowId
                           layout:(NSString *)layout
                           zoomed:(NSNumber *)zoomed;
- (void)tmuxWindowAddedWithId:(int)windowId;
- (void)tmuxWindowClosedWithId:(int)windowId;
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName;
- (void)tmuxHostDisconnected;
- (void)tmuxWriteString:(NSString *)string;
- (void)tmuxReadTask:(NSData *)data;
- (void)tmuxSessionChanged:(NSString *)sessionName
				 sessionId:(int)sessionId;
- (void)tmuxSessionsChanged;
- (void)tmuxWindowsDidChange;
- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName;
- (NSSize)tmuxBookmarkSize;  // rows, cols
- (NSInteger)tmuxNumHistoryLinesInBookmark;
- (void)tmuxSetSecureLogging:(BOOL)secureLogging;
- (void)tmuxPrintLine:(NSString *)line;
- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow;
- (void)tmuxInitialCommandDidCompleteSuccessfully;
- (void)tmuxInitialCommandDidFailWithError:(NSString *)error;

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
@property(nonatomic, readonly) id<TmuxGatewayDelegate> delegate;

- (instancetype)initWithDelegate:(id<TmuxGatewayDelegate>)delegate;

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

@end
