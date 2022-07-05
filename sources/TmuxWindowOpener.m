//
//  TmuxWindowOpener.m
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import "TmuxWindowOpener.h"
#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermController.h"
#import "iTermPreferences.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "ScreenChar.h"
#import "TmuxHistoryParser.h"
#import "TmuxLayoutParser.h"
#import "TmuxStateParser.h"

NSString * const kTmuxWindowOpenerStatePendingOutput = @"pending_output";

NSString *const kTmuxWindowOpenerWindowOptionStyle = @"WindowStyle";
NSString *const kTmuxWindowOpenerWindowOptionStyleValueFullScreen = @"FullScreen";

@implementation TmuxWindowOpener {
    int windowIndex_;
    NSString *name_;
    NSSize size_;
    NSString *layout_;
    int maxHistory_;
    TmuxGateway *gateway_;
    NSMutableDictionary *parseTree_;
    int pendingRequests_;
    __weak TmuxController *controller_;
    NSMutableDictionary *histories_;
    NSMutableDictionary *altHistories_;
    NSMutableDictionary *states_;
    PTYTab *tabToUpdate_;
    id target_;
    SEL selector_;
    BOOL ambiguousIsDoubleWidth_;
}

@synthesize windowIndex = windowIndex_;
@synthesize name = name_;
@synthesize size = size_;
@synthesize layout = layout_;
@synthesize maxHistory = maxHistory_;
@synthesize gateway = gateway_;
@synthesize parseTree = parseTree_;
@synthesize controller = controller_;
@synthesize target = target_;
@synthesize selector = selector_;
@synthesize ambiguousIsDoubleWidth = ambiguousIsDoubleWidth_;

+ (TmuxWindowOpener *)windowOpener {
    return [[TmuxWindowOpener alloc] init];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        histories_ = [[NSMutableDictionary alloc] init];
        altHistories_ = [[NSMutableDictionary alloc] init];
        states_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)openWindows:(BOOL)initial {
    DLog(@"openWindows initial=%d", (int)initial);
    if (!self.layout) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Can't open window: missing layout"]];
        return NO;
    }
    self.parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    if (!self.parseTree) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
        return NO;
    }
    NSMutableArray *cmdList = [NSMutableArray array];
    DLog(@"Parse this tree: %@", self.parseTree);
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:self.parseTree
                                                 callingSelector:@selector(appendRequestsForNode:toArray:)
                                                        onTarget:self
                                                      withObject:cmdList];
    if (self.zoomed.boolValue) {
        // Unzoom the window because there's no way to tell which window pane is zoomed in tmux 2.1.
        // I submitted a patch to tmux (commit 531869bd92f0daff3cc3c3cc0ab273846f411dc8) to correct
        // this. Once a fixed version of tmux is ubiquitous, I can improve this by respecting the
        // tmux server's initial setting of the zoomed flag. This is a race condition because
        // another client could change the window's zoom status at the same time, causing a mess.
        [cmdList addObject:[self dictToToggleZoomForWindow]];
    }
    DLog(@"Depth-first search of parse tree gives command list %@", cmdList);
    [gateway_ sendCommandList:cmdList initial:initial];
    return YES;
}

- (void)unpauseWindowPanes:(NSArray<NSNumber *> *)windowPanes {
    if (!windowPanes.count) {
        return;
    }
    _unpausingWindowPanes = [windowPanes copy];
    NSMutableArray<NSDictionary *> *commands = [NSMutableArray array];
    for (NSNumber *wp in windowPanes) {
        [self appendRequestsForWindowPane:wp toArray:commands];
    }
    [gateway_ sendCommandList:commands];
}

- (BOOL)updateLayoutInTab:(PTYTab *)tab {
    DLog(@"updateLayoutInTab:%@ layout=%@", tab, self.layout);
    if (!self.layout) {
        DLog(@"Bad layout");
        return NO;
    }
    if (!self.controller) {
        DLog(@"No controller");
        return NO;
    }
    if (!self.gateway) {
        DLog(@"No gateway");
        return NO;
    }

    TmuxLayoutParser *parser = [TmuxLayoutParser sharedInstance];
    self.parseTree = [parser parsedLayoutFromString:self.layout];
    if (!self.parseTree) {
        DLog(@"Failed to create parse tree for %@", self.layout);
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
        return NO;
    }
    NSSet *oldPanes = [NSSet setWithArray:[tab windowPanes]];
    NSMutableArray *cmdList = [NSMutableArray array];
    for (NSNumber *addedPane in [parser windowPanesInParseTree:self.parseTree]) {
        if (![oldPanes containsObject:addedPane]) {
            [self appendRequestsForWindowPane:addedPane
                                      toArray:cmdList];
        }
    }
    if (cmdList.count) {
        tabToUpdate_ = tab;
        [gateway_ sendCommandList:cmdList];
        DLog(@"Sending command list before setting layout: %@", cmdList);
        return NO;
    }
    [tab setTmuxLayout:self.parseTree
        tmuxController:controller_
                zoomed:_zoomed];
    return YES;
}

#pragma mark - Private

// This is called for each window pane via a DFS. It sends all commands needed
// to open a window.
- (id)appendRequestsForNode:(NSMutableDictionary *)node
                    toArray:(NSMutableArray *)cmdList {
    NSNumber *wp = [node objectForKey:kLayoutDictWindowPaneKey];
    DLog(@"Append requests for node: %@", node);
    [self appendRequestsForWindowPane:wp toArray:cmdList];
    return nil;  // returning nil means keep going with the DFS
}

- (void)appendRequestsForWindowPane:(NSNumber *)wp
                            toArray:(NSMutableArray *)cmdList {
    [cmdList addObject:[self dictForRequestHistoryForWindowPane:wp alt:NO]];
    [cmdList addObject:[self dictForRequestHistoryForWindowPane:wp alt:YES]];
    [cmdList addObject:[self dictForDumpStateForWindowPane:wp]];
    [cmdList addObject:[self dictForGetPendingOutputForWindowPane:wp]];
    if (gateway_.pauseModeEnabled) {
        [cmdList addObject:[self dictToUnpauseWindowPane:wp]];
    }
    if (self.minimumServerVersion != nil &&
        [self.minimumServerVersion compare:[NSDecimalNumber decimalNumberWithString:@"3.1"]] != NSOrderedAscending) {
        [cmdList addObject:[self dictForGetUserVars:wp]];
    }
}

- (NSDictionary *)dictToUnpauseWindowPane:(NSNumber *)wp {
    // If tmux is too old to support pause mode, this does nothing.
    // If the pane isn't paused, this does nothing.
    // If we are unpausing the pane at the user's behest, this is obviously important.
    // The tricky case: if we got unpaused before accepting notifications, this unpauses the pane.
    NSString *command = [NSString stringWithFormat:@"refresh-client -A '%%%@:continue'", wp];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(requestDidComplete)
                           responseObject:nil
                                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSDictionary *)dictToToggleZoomForWindow {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"resize-pane -Z -t @%d", self.windowIndex];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(requestDidComplete)
                           responseObject:nil
                                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSDictionary *)dictForGetPendingOutputForWindowPane:(NSNumber *)wp {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);

    NSString *command = [NSString stringWithFormat:@"capture-pane -p -P -C -t \"%%%d\"", [wp intValue]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(getPendingOutputResponse:pane:)
                           responseObject:wp
                                    flags:kTmuxGatewayCommandWantsData | kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSDictionary *)dictForGetUserVars:(NSNumber *)wp {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"show-options -v -p -t %%%d @uservars",
                         [wp intValue]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(getUserVarsResponse:pane:)
                           responseObject:wp
                                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSDictionary *)dictForDumpStateForWindowPane:(NSNumber *)wp {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"list-panes -t \"%%%d\" -F \"%@\"", [wp intValue],
                         [TmuxStateParser format]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpStateResponse:pane:)
                           responseObject:wp
                                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (NSDictionary *)dictForRequestHistoryForWindowPane:(NSNumber *)wp
                                                 alt:(BOOL)alternate {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *maybeN = @"";
    if (self.minimumServerVersion && [self.minimumServerVersion compare:[NSDecimalNumber decimalNumberWithString:@"3.1"]] != NSOrderedAscending) {
        maybeN = @"N";
    }
    NSString *command = [NSString stringWithFormat:@"capture-pane -peqJ%@ %@-t \"%%%d\" -S -%d",
                         maybeN,
                         (alternate ? @"-a " : @""), [wp intValue], self.maxHistory];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpHistoryResponse:paneAndAlternate:)
                           responseObject:[NSArray arrayWithObjects:
                                           wp,
                                           [NSNumber numberWithBool:alternate],
                                           nil]
                                    flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (void)didReceiveError {
    _errorCount += 1;
    if (pendingRequests_ - _errorCount == 0) {
        [self finishErroneously];
    }
}

- (void)finishErroneously {
    if (self.target) {
        [self.target it_performNonObjectReturningSelector:self.selector
                                               withObject:self];
    }
    if (self.completion) {
        self.completion(windowIndex_);
    }
}

// Command response handler for dump-history
// info is an array: [window pane number, isAlternate flag]
- (void)dumpHistoryResponse:(NSString *)response
           paneAndAlternate:(NSArray *)info {
    if (!response) {
        [self didReceiveError];
        return;
    }

    NSNumber *wp = [info objectAtIndex:0];
    NSNumber *alt = [info objectAtIndex:1];
    // Lie and say it's the alternate screen because tmux doesn't support variation selector 16 yet.
    NSArray *history = [[TmuxHistoryParser sharedInstance] parseDumpHistoryResponse:response
                                                             ambiguousIsDoubleWidth:ambiguousIsDoubleWidth_
                                                                     unicodeVersion:self.unicodeVersion
                                                                    alternateScreen:YES];
    if (history) {
        if ([alt boolValue]) {
            [altHistories_ setObject:history forKey:wp];
        } else {
            [histories_ setObject:history forKey:wp];
        }
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Error: malformed history line from tmux.";
            alert.informativeText = @"See Console.app for details";
            [alert runModal];
        });
    }
    [self requestDidComplete];
}

- (NSArray<NSData *> *)historyLinesForWindowPane:(int)wp alternateScreen:(BOOL)altScreen {
    NSDictionary *dict = altScreen ? altHistories_ : histories_;
    return dict[@(wp)];
}

static BOOL IsOctalDigit(char c) {
    return c >= '0' && c <= '7';
}

static int OctalValue(const char *bytes) {
    int value = 0;
    for (int i = 0; i < 3; i++) {
        if (!IsOctalDigit(bytes[i])) {
            return -1;
        }
        value *= 8;
        value += bytes[i] - '0';
    }
    return value;
}

- (void)getPendingOutputResponse:(NSData *)response pane:(NSNumber *)wp {
    if (!response) {
        [self didReceiveError];
        return;
    }

    const char *bytes = response.bytes;
    NSMutableData *pending = [NSMutableData data];
    for (int i = 0; i < response.length; i++) {
        char c = bytes[i];

        // TODO: Fix tmux and update this code.
        if (c == '\\' &&
            response.length >= i + 4) {
            // tmux has a bug where control characters get escaped but backslashes do not.
            // Only accept octal values that are control codes to minimize the chance of problems.
            int octalValue = OctalValue(bytes + i + 1);
            if (octalValue >= 0 && octalValue < ' ') {
                i += 3;
                c = octalValue;
            }
        }
        [pending appendBytes:&c length:1];
    }

    NSMutableDictionary *state = [[states_ objectForKey:wp] mutableCopy];
    [state setObject:pending forKey:kTmuxWindowOpenerStatePendingOutput];
    [states_ setObject:state forKey:wp];
    [self requestDidComplete];
}

- (NSDictionary *)stateForWindowPane:(int)wp {
    return states_[@(wp)];
}

- (void)getUserVarsResponse:(NSString *)response pane:(NSNumber *)wp {
    if (!response) {
        [self didReceiveError];
        return;
    }

    if (wp) {
        [self.controller setEncodedUserVars:response forPane:wp.intValue];
    }
    [self requestDidComplete];
}

- (void)dumpStateResponse:(NSString *)response pane:(NSNumber *)wp {
    if (!response) {
        [self didReceiveError];
        return;
    }

    NSDictionary *state = [[TmuxStateParser sharedInstance] parsedStateFromString:response
                                                                        forPaneId:[wp intValue]];
    [states_ setObject:state forKey:wp];
    [self requestDidComplete];
}

- (void)didResizePane:(NSString *)response {
    if (!response) {
        [self didReceiveError];
        return;
    }
    [self requestDidComplete];
}

- (void)requestDidComplete {
    --pendingRequests_;
    if (_errorCount) {
        if (pendingRequests_ - _errorCount == 0) {
            [self finishErroneously];
            return;
        }
    }
    DLog(@"requestDidComplete. Pending requests is now %d", pendingRequests_);
    if (pendingRequests_ != 0) {
        return;
    }
    if (_unpausingWindowPanes) {
        [self.target it_performNonObjectReturningSelector:self.selector
                                               withObject:self];
        return;
    }
    NSWindowController<iTermWindowController> *term = nil;
    BOOL isNewWindow = NO;
    if (!tabToUpdate_) {
        DLog(@"Have no tab to update.");
        if (![self.profile[KEY_PREVENT_TAB] boolValue]) {
            term = [self.controller windowWithAffinityForWindowId:self.windowIndex];
            DLog(@"Term with affinity is %@", term);
        }
    } else {
        term = [tabToUpdate_ realParentWindow];
        DLog(@"Using window of tabToUpdate: %@", term);
    }
    const BOOL useOriginalWindow = [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn] == kOpenTmuxWindowsAsNativeTabsInExistingWindow;
    NSInteger initialTabs = term.tabs.count;
    if (!term) {
        if (self.initial && useOriginalWindow) {
            term = [gateway_ window];
            initialTabs = term.tabs.count;
            DLog(@"Use original window %@", term);
        }
        if (!term &&
            !self.initial &&
            self.anonymous &&
            [iTermAdvancedSettingsModel anonymousTmuxWindowsOpenInCurrentWindow]) {
            PseudoTerminal *candidate = [[iTermController sharedInstance] currentTerminal];
            if ([[candidate uniqueTmuxControllers] count] == 0 ||
                [[candidate uniqueTmuxControllers] containsObject:controller_]) {
                term = candidate;
                initialTabs = term.tabs.count;
                DLog(@"Use current window %@", term);
            }
        }
        if (!term) {
            DLog(@"Creating a new term with guid %@", self.windowGUID);
            term = [[iTermController sharedInstance] openTmuxIntegrationWindowUsingProfile:self.profile
                                                                          perWindowSetting:self.perWindowSettings[self.windowGUID]];
            if (self.newWindowBlock) {
                self.newWindowBlock(term.terminalGuid);
            }
            isNewWindow = YES;
            DLog(@"Opened a new window %@", term);
        }
    }
    NSMutableDictionary *parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    if (!parseTree) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
        return;
    }
    DLog(@"Parse tree: %@", parseTree);
    [self decorateParseTree:parseTree];
    DLog(@"Decorated parse tree: %@", parseTree);
    NSValue *windowPos = nil;
    NSString *widStr = [@(windowIndex_) stringValue];
    if (tabToUpdate_) {
        DLog(@"Updating existing tab");
        [tabToUpdate_ setTmuxLayout:parseTree
                     tmuxController:controller_
                             zoomed:@NO];
        [tabToUpdate_ setPerTabSettings:_perTabSettings[widStr]];
        if ([tabToUpdate_ updatedTmuxLayoutRequiresAdjustment]) {
            DLog(@"layout requires adjustment! fit the layout to windows");
            [controller_ fitLayoutToWindows];
        }
    } else {
        if (![self.controller window:windowIndex_]) {
            DLog(@"Calling loadTmuxLayout");
            // Safety valve: don't open an existing tmux window.
            [term loadTmuxLayout:parseTree
                          window:windowIndex_
                  tmuxController:controller_
                            name:name_];

            // Check if we know the position for the window
            NSArray *panes = [[TmuxLayoutParser sharedInstance] windowPanesInParseTree:parseTree];
            windowPos = [self.controller positionForWindowWithPanes:panes windowID:windowIndex_];

            // This is to handle the case where we couldn't create a window as
            // large as we were asked to (for instance, if the gateway is full-
            // screen).
            DLog(@"Calling windowDidResize: in case the window was smaller than we'd hoped");
            [controller_ windowDidResize:term];

            // Check the window flags
            NSString *windowId = [NSString stringWithFormat:@"%d", windowIndex_];
            NSDictionary *flags = _windowOptions[windowId];
            NSString *style = flags[kTmuxWindowOpenerWindowOptionStyle];
            BOOL wantFullScreen = [style isEqual:kTmuxWindowOpenerWindowOptionStyleValueFullScreen];
            BOOL isFullScreen = [term anyFullScreen];
            if (wantFullScreen && !isFullScreen) {
                if (windowPos) {
                    [[term window] setFrameOrigin:[windowPos pointValue]];
                    windowPos = nil;
                }
                if ([iTermAdvancedSettingsModel serializeOpeningMultipleFullScreenWindows]) {
                    [[iTermController sharedInstance] makeTerminalWindowFullScreen:term];
                } else {
                    [term toggleFullScreenMode:nil];
                }
            }
        } else {
            DLog(@"Not calling loadTmuxLayout");
        }
        [[self.controller window:windowIndex_] setPerTabSettings:_perTabSettings[widStr]];
    }
    if (self.target) {
        [self.target it_performNonObjectReturningSelector:self.selector
                                               withObject:self];
    }
    DLog(@"useOriginalWindow=%@ initialTabs=%@ initial=%@ windowPos=%@",
         @(useOriginalWindow), @(initialTabs), @(self.initial), windowPos);
    if (windowPos) {
        if (!useOriginalWindow || initialTabs < 2 || !self.initial) {
            // Do this after calling the completion selector because it may affect the window's
            // frame (e.g., when burying a session and that causes the number of tabs to change).
            [[term window] setFrameOrigin:[windowPos pointValue]];
        }
    }
    if (isNewWindow) {
        [[iTermController sharedInstance] didFinishCreatingTmuxWindow:(PseudoTerminal *)term];
    }
    if (self.completion) {
        self.completion(windowIndex_);
    }
}

// Add info from command responses to leaf nodes of parse tree.
- (void)decorateParseTree:(NSMutableDictionary *)parseTree {
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:parseTree
                                                 callingSelector:@selector(decorateWindowPane:)
                                                        onTarget:self
                                                      withObject:nil];
    if (self.manuallyOpened) {
        parseTree[kLayoutDictTabOpenedManually] = @YES;
    }
    if (self.tabIndex) {
        parseTree[kLayoutDictTabIndex] = self.tabIndex;
    }
    if (self.allInitialWindowsAdded) {
        parseTree[kLayoutDictAllInitialWindowsAdded] = @YES;
    }
}

// Callback for DFS of parse tree from decorateParseTree:
- (id)decorateWindowPane:(NSMutableDictionary *)parseTree {
    NSNumber *n = [parseTree objectForKey:kLayoutDictWindowPaneKey];
    if (!n) {
        return nil;
    }
    NSArray *history = [histories_ objectForKey:n];
    if (history) {
        [parseTree setObject:history forKey:kLayoutDictHistoryKey];
    }

    history = [altHistories_ objectForKey:n];
    if (history) {
        [parseTree setObject:history forKey:kLayoutDictAltHistoryKey];
    }

    NSDictionary *state = [states_ objectForKey:n];
    if (state) {
        [parseTree setObject:state forKey:kLayoutDictStateKey];
    }

    NSDictionary *hotkey = [controller_ hotkeyForWindowPane:n.intValue];
    if (hotkey) {
        parseTree[kLayoutDictHotkeyKey] = hotkey;
    }

    if (self.tabColors[n]) {
        parseTree[kLayoutDictTabColorKey] = self.tabColors[n];
    }
    parseTree[kLayoutDictFocusReportingKey] = @(self.focusReporting);
    return nil;
}

@end
