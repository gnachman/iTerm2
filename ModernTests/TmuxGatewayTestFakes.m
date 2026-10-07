//
//  TmuxGatewayTestFakes.m
//  ModernTests
//

#import "TmuxGatewayTestFakes.h"

#import "VT100Token.h"

@implementation TmuxRecordingGateway

- (void)abortWithErrorMessage:(NSString *)message title:(NSString *)title {
    self.abortMessage = message ?: @"(nil)";
}

- (void)feedLine:(NSString *)line {
    VT100Token *token = [[VT100Token alloc] init];
    token.type = TMUX_LINE;
    token.string = line;
    token.savedData = [line dataUsingEncoding:NSUTF8StringEncoding];
    [self executeToken:token];
}

- (void)feedLines:(NSArray<NSString *> *)lines {
    for (NSString *line in lines) {
        [self feedLine:line];
    }
}

@end

@implementation TmuxFakeGatewayDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _writtenStrings = [NSMutableArray array];
    }
    return self;
}

- (TmuxController *)tmuxController { return nil; }
- (BOOL)tmuxUpdateLayoutForWindow:(int)windowId layout:(NSString *)layout visibleLayout:(NSString *)visibleLayout zoomed:(NSNumber *)zoomed only:(BOOL)only {
    self.sawLayoutChange = YES;
    self.layout = layout;
    self.visibleLayout = visibleLayout;
    self.zoomed = zoomed;
    return NO;
}
- (void)tmuxWindowAddedWithId:(int)windowId {}
- (void)tmuxWindowClosedWithId:(int)windowId {}
- (void)tmuxWindowRenamedWithId:(int)windowId to:(NSString *)newName {}
- (void)tmuxHostDisconnected:(NSString *)dcsID {}
- (void)tmuxWriteString:(NSString *)string { [_writtenStrings addObject:string]; }
- (void)tmuxReadTask:(NSData *)data windowPane:(int)wp latency:(NSNumber *)latency {}
- (void)tmuxSessionChanged:(NSString *)sessionName sessionId:(int)sessionId {}
- (void)tmuxSessionsChanged {}
- (void)tmuxWindowsDidChange {}
- (void)tmuxSession:(int)sessionId renamed:(NSString *)newName {}
- (VT100GridSize)tmuxClientSize { return VT100GridSizeMake(80, 25); }
- (NSInteger)tmuxNumberOfLinesOfScrollbackHistory { return 1000; }
- (void)tmuxSetSecureLogging:(BOOL)secureLogging {}
- (void)tmuxPrintLine:(NSString *)line {}
- (NSWindowController<iTermWindowController> *)tmuxGatewayWindow { return nil; }
- (void)tmuxInitialCommandDidCompleteSuccessfully {}
- (void)tmuxInitialCommandDidFailWithError:(NSString *)error {}
- (void)tmuxCannotSendCharactersInSupplementaryPlanes:(NSString *)string windowPane:(int)windowPane {}
- (void)tmuxDidOpenInitialWindows {}
- (void)tmuxDoubleAttachForSessionGUID:(NSString *)sessionGUID {}
- (NSString *)tmuxOwningSessionGUID { return @"guid"; }
- (NSString *)tmuxGatewayOriginIdentifier { return nil; }
- (NSDictionary<NSString *, NSString *> *)tmuxGatewayIT2ClientRecord { return nil; }
- (BOOL)tmuxGatewayShouldForceDetach { return NO; }
- (void)tmuxGatewayDidTimeOutDuringInitialization:(BOOL)duringInitialization {}
- (void)tmuxActiveWindowPaneDidChangeInWindow:(int)windowID toWindowPane:(int)paneID {}
- (void)tmuxSessionWindowDidChangeTo:(int)windowID {}
- (void)tmuxWindowPaneDidPause:(int)wp notification:(BOOL)notification {}
- (void)tmuxSessionPasteDidChange:(NSString *)pasteBufferName {}
- (void)tmuxClientSessionChanged:(NSString *)clientName {}
- (void)tmuxClientDetached:(NSString *)clientName {}
- (void)tmuxServerMayOmitEndGuardBeforeExit:(BOOL)mayOmit {}

@end
