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
    TmuxController *controller_;  // weak
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
    return [[[TmuxWindowOpener alloc] init] autorelease];
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

- (void)dealloc {
    [name_ release];
    [layout_ release];
    [gateway_ release];
    [parseTree_ release];
    [target_ release];
    [histories_ release];
    [altHistories_ release];
    [states_ release];
    [tabToUpdate_ release];
    [_windowOptions release];
    [_zoomed release];
    [super dealloc];
}

- (void)openWindows:(BOOL)initial {
    DLog(@"openWindows initial=%d", (int)initial);
    if (!self.layout) {
        DLog(@"Bad layout");
        return;
    }
    self.parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    if (!self.parseTree) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
        return;
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
}

- (void)updateLayoutInTab:(PTYTab *)tab {
    if (!self.layout) {
        DLog(@"Bad layout");
        return;
    }
    if (!self.controller) {
        DLog(@"No controller");
        return;
    }
    if (!self.gateway) {
        DLog(@"No gateway");
        return;
    }

    TmuxLayoutParser *parser = [TmuxLayoutParser sharedInstance];
    self.parseTree = [parser parsedLayoutFromString:self.layout];
    if (!self.parseTree) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
        return;
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
        tabToUpdate_ = [tab retain];
        [gateway_ sendCommandList:cmdList];
    } else {
        [tab setTmuxLayout:self.parseTree
            tmuxController:controller_
                    zoomed:_zoomed];
        if ([tab layoutIsTooLarge]) {
            // The tab's root splitter is larger than the window's tabview.
            // If there are no outstanding window resizes then setTmuxLayout:tmuxController:
            // has called fitWindowToTabs:, and it's still too big, so shrink
            // the layout.
            for (TmuxController *controller in [[tab realParentWindow] uniqueTmuxControllers]) {
                if ([controller hasOutstandingWindowResize]) {
                    return;
                }
            }
            [controller_ fitLayoutToWindows];
        }
    }
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
}

- (NSDictionary *)dictToToggleZoomForWindow {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"resize-pane -Z -t @%d", self.windowIndex];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(requestDidComplete)
                           responseObject:nil
                                    flags:0];
}

- (NSDictionary *)dictForGetPendingOutputForWindowPane:(NSNumber *)wp {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"capture-pane -p -P -C -t %%%d", [wp intValue]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(getPendingOutputResponse:pane:)
                           responseObject:wp
                                    flags:kTmuxGatewayCommandWantsData];
}

- (NSDictionary *)dictForDumpStateForWindowPane:(NSNumber *)wp {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"list-panes -t %%%d -F \"%@\"", [wp intValue],
                         [TmuxStateParser format]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpStateResponse:pane:)
                           responseObject:wp
                                    flags:0];
}

 - (NSDictionary *)dictForRequestHistoryForWindowPane:(NSNumber *)wp
                        alt:(BOOL)alternate {
    ++pendingRequests_;
    DLog(@"Increment pending requests to %d", pendingRequests_);
    NSString *command = [NSString stringWithFormat:@"capture-pane -peqJ %@-t %%%d -S -%d",
                         (alternate ? @"-a " : @""), [wp intValue], self.maxHistory];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpHistoryResponse:paneAndAlternate:)
                           responseObject:[NSArray arrayWithObjects:
                                           wp,
                                           [NSNumber numberWithBool:alternate],
                                           nil]
                                    flags:0];
}

// Command response handler for dump-history
// info is an array: [window pane number, isAlternate flag]
- (void)dumpHistoryResponse:(NSString *)response
           paneAndAlternate:(NSArray *)info {
    NSNumber *wp = [info objectAtIndex:0];
    NSNumber *alt = [info objectAtIndex:1];
    NSArray *history = [[TmuxHistoryParser sharedInstance] parseDumpHistoryResponse:response
                                                             ambiguousIsDoubleWidth:ambiguousIsDoubleWidth_];
    if (history) {
        if ([alt boolValue]) {
            [altHistories_ setObject:history forKey:wp];
        } else {
            [histories_ setObject:history forKey:wp];
        }
    } else {
        [[NSAlert alertWithMessageText:@"Error: malformed history line from tmux."
                         defaultButton:@"OK"
                       alternateButton:@""
                           otherButton:@""
             informativeTextWithFormat:@"See Console.app for details"] runModal];
    }
    [self requestDidComplete];
}

- (void)getPendingOutputResponse:(NSData *)response pane:(NSNumber *)wp {
    const char *bytes = response.bytes;
    NSMutableData *pending = [NSMutableData data];
    for (int i = 0; i < response.length; i++) {
        char c = bytes[i];
        if (c == '\\') {
            if (i + 3 >= response.length) {
                DLog(@"Bogus pending output (truncated): %@", response);
                return;
            }
            i++;
            int value = 0;
            for (int j = 0; j < 3; j++, i++) {
                c = bytes[i];
                if (c < '0' || c > '7') {
                    DLog(@"Bogus pending output (non-octal): %@", response);
                    return;
                }
                value *= 8;
                value += (c - '0');
            }
            i--;
            c = value;
        }
        [pending appendBytes:&c length:1];
    }

    NSMutableDictionary *state = [[[states_ objectForKey:wp] mutableCopy] autorelease];
    [state setObject:pending forKey:kTmuxWindowOpenerStatePendingOutput];
    [states_ setObject:state forKey:wp];
    [self requestDidComplete];
}

- (void)dumpStateResponse:(NSString *)response pane:(NSNumber *)wp {
    NSDictionary *state = [[TmuxStateParser sharedInstance] parsedStateFromString:response
                                                                        forPaneId:[wp intValue]];
    [states_ setObject:state forKey:wp];
    [self requestDidComplete];
}

- (void)requestDidComplete {
    --pendingRequests_;
    DLog(@"requestDidComplete. Pending requests is now %d", pendingRequests_);
    if (pendingRequests_ == 0) {
        NSWindowController<iTermWindowController> *term = nil;
        if (!tabToUpdate_) {
            DLog(@"Have no tab to update.");
            if (![[[PTYTab tmuxBookmark] objectForKey:KEY_PREVENT_TAB] boolValue]) {
                term = [self.controller windowWithAffinityForWindowId:self.windowIndex];
                DLog(@"Term with affinity is %@", term);
            }
        } else {
            term = [tabToUpdate_ realParentWindow];
            DLog(@"Using window of tabToUpdate: %@", term);
        }
        if (!term) {
            BOOL useOriginalWindow =
                [iTermPreferences intForKey:kPreferenceKeyOpenTmuxWindowsIn] == kOpenTmuxWindowsAsNativeTabsInExistingWindow;
            if (useOriginalWindow) {
                term = [gateway_ window];
                DLog(@"Use original window %@", term);
            }
            if (!term) {
                term = [[iTermController sharedInstance] openTmuxIntegrationWindowUsingProfile:[PTYTab tmuxBookmark]];
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
        if (tabToUpdate_) {
            DLog(@"Updating existing tab");
            [tabToUpdate_ setTmuxLayout:parseTree
                         tmuxController:controller_
                                 zoomed:NO];
            if ([tabToUpdate_ layoutIsTooLarge]) {
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
                NSValue *windowPos = [self.controller positionForWindowWithPanes:panes];
                if (windowPos) {
                    [[term window] setFrameOrigin:[windowPos pointValue]];
                }

                // This is to handle the case where we couldn't create a window as
                // large as we were asked to (for instance, if the gateway is full-
                // screen).
                [controller_ windowDidResize:term];

                // Check the window flags
                NSString *windowId = [NSString stringWithFormat:@"%d", windowIndex_];
                NSDictionary *flags = _windowOptions[windowId];
                NSString *style = flags[kTmuxWindowOpenerWindowOptionStyle];
                BOOL wantFullScreen = [style isEqual:kTmuxWindowOpenerWindowOptionStyleValueFullScreen];
                BOOL isFullScreen = [term anyFullScreen];
                if (wantFullScreen && !isFullScreen) {
                    if ([iTermAdvancedSettingsModel serializeOpeningMultipleFullScreenWindows]) {
                        [[iTermController sharedInstance] makeTerminalWindowFullScreen:term];
                    } else {
                        [term toggleFullScreenMode:nil];
                    }
                }
            } else {
                DLog(@"Not calling loadTmuxLayout");
            }
        }
        if (self.target) {
            [self.target performSelector:self.selector
                              withObject:[NSNumber numberWithInt:windowIndex_]];
        }
    }
}

// Add info from command responses to leaf nodes of parse tree.
- (void)decorateParseTree:(NSMutableDictionary *)parseTree {
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:parseTree
                                                 callingSelector:@selector(decorateWindowPane:)
                                                        onTarget:self
                                                      withObject:nil];
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

    return nil;
}

@end
