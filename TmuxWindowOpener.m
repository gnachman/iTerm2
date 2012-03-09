//
//  TmuxWindowOpener.m
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import "TmuxWindowOpener.h"
#import "iTermController.h"
#import "TmuxLayoutParser.h"
#import "ScreenChar.h"
#import "PseudoTerminal.h"
#import "TmuxHistoryParser.h"
#import "TmuxStateParser.h"
#import "PTYTab.h"

@interface TmuxWindowOpener (Private)

- (id)appendRequestsForNode:(NSMutableDictionary *)node
                    toArray:(NSMutableArray *)cmdList;
- (void)decorateParseTree:(NSMutableDictionary *)parseTree;
- (id)decorateWindowPane:(NSMutableDictionary *)parseTree;
- (void)requestDidComplete;
- (void)dumpHistoryResponse:(NSString *)response
           paneAndAlternate:(NSArray *)info;
- (NSDictionary *)dictForStartControlCommand;
- (NSDictionary *)dictForDumpStateForWindowPane:(NSNumber *)wp;
- (NSDictionary *)dictForRequestHistoryForWindowPane:(NSNumber *)wp
                                                 alt:(BOOL)alternate;
- (void)appendRequestsForWindowPane:(NSNumber *)wp
                            toArray:(NSMutableArray *)cmdList;

@end

@implementation TmuxWindowOpener

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

+ (TmuxWindowOpener *)windowOpener
{
    return [[[TmuxWindowOpener alloc] init] autorelease];
}

- (id)init
{
    self = [super init];
    if (self) {
        histories_ = [[NSMutableDictionary alloc] init];
        altHistories_ = [[NSMutableDictionary alloc] init];
        states_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [name_ release];
    [layout_ release];
    [gateway_ release];
    [parseTree_ release];
    [histories_ release];
    [altHistories_ release];
    [states_ release];
    [tabToUpdate_ release];
    [super dealloc];
}

- (void)openWindows:(BOOL)initial
{
    if (!self.layout) {
        NSLog(@"Bad layout");
        return;
    }
    self.parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    if (!self.parseTree) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
        return;
    }
    NSMutableArray *cmdList = [NSMutableArray array];
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:self.parseTree
                                                 callingSelector:@selector(appendRequestsForNode:toArray:)
                                                        onTarget:self
                                                      withObject:cmdList];
    // append start-control
    if (initial) {
        [cmdList addObject:[self dictForStartControlCommand]];
    }
    [gateway_ sendCommandList:cmdList];
}

- (void)updateLayoutInTab:(PTYTab *)tab;
{
    if (!self.layout) {
        NSLog(@"Bad layout");
        return;
    }
    if (!self.controller) {
        NSLog(@"No controller");
        return;
    }
    if (!self.gateway) {
        NSLog(@"No gateway");
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
             tmuxController:controller_];
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

@end

@implementation TmuxWindowOpener (Private)

- (NSDictionary *)dictForStartControlCommand
{
    ++pendingRequests_;
    NSString *command = @"control set-ready";
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(requestDidComplete)
                           responseObject:nil];
}

// This is called for each window pane via a DFS. It sends all commands needed
// to open a window.
- (id)appendRequestsForNode:(NSMutableDictionary *)node
                    toArray:(NSMutableArray *)cmdList
{
    NSNumber *wp = [node objectForKey:kLayoutDictWindowPaneKey];
    [self appendRequestsForWindowPane:wp toArray:cmdList];
    return nil;  // returning nil means keep going with the DFS
}

- (void)appendRequestsForWindowPane:(NSNumber *)wp
                            toArray:(NSMutableArray *)cmdList
{
    [cmdList addObject:[self dictForRequestHistoryForWindowPane:wp alt:NO]];
    [cmdList addObject:[self dictForRequestHistoryForWindowPane:wp alt:YES]];
    [cmdList addObject:[self dictForDumpStateForWindowPane:wp]];
}

- (NSDictionary *)dictForDumpStateForWindowPane:(NSNumber *)wp
{
    ++pendingRequests_;
    NSString *command = [NSString stringWithFormat:@"control -t %%%d get-emulator", [wp intValue]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpStateResponse:pane:)
                           responseObject:wp];
}

 - (NSDictionary *)dictForRequestHistoryForWindowPane:(NSNumber *)wp
                        alt:(BOOL)alternate
{
    ++pendingRequests_;
    NSString *command = [NSString stringWithFormat:@"control %@-t %%%d -l %d get-history",
                         (alternate ? @"-a " : @""), [wp intValue], self.maxHistory];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpHistoryResponse:paneAndAlternate:)
                           responseObject:[NSArray arrayWithObjects:
                                           wp,
                                           [NSNumber numberWithBool:alternate],
                                           nil]];
}

// Command response handler for dump-history
// info is an array: [window pane number, isAlternate flag]
- (void)dumpHistoryResponse:(NSString *)response
           paneAndAlternate:(NSArray *)info
{
    NSNumber *wp = [info objectAtIndex:0];
    NSNumber *alt = [info objectAtIndex:1];
    NSArray *history = [[TmuxHistoryParser sharedInstance] parseDumpHistoryResponse:response];
    if (history) {
        if ([alt boolValue]) {
            [altHistories_ setObject:history forKey:wp];
        } else {
            [histories_ setObject:history forKey:wp];
        }
    }
    [self requestDidComplete];
}

- (void)dumpStateResponse:(NSString *)response pane:(NSNumber *)wp
{
    NSDictionary *state = [[TmuxStateParser sharedInstance] parsedStateFromString:response];
    [states_ setObject:state forKey:wp];
    [self requestDidComplete];
}

- (void)requestDidComplete
{
    --pendingRequests_;
    if (pendingRequests_ == 0) {
        PseudoTerminal *term = nil;
        if (!tabToUpdate_) {
            term = [self.controller windowWithAffinityForWindowId:self.windowIndex];
        } else {
            term = [tabToUpdate_ realParentWindow];
        }
        if (!term) {
            term = [[iTermController sharedInstance] openWindow];
        }
        NSMutableDictionary *parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
        if (!parseTree) {
            [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Error parsing layout %@", self.layout]];
            return;
        }
        [self decorateParseTree:parseTree];
        if (tabToUpdate_) {
            [tabToUpdate_ setTmuxLayout:parseTree
                         tmuxController:controller_];
            if ([tabToUpdate_ layoutIsTooLarge]) {
                [controller_ fitLayoutToWindows];
            }
        } else {
            if (![self.controller window:windowIndex_]) {
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
            }
        }
        if (self.target) {
            [self.target performSelector:self.selector
                              withObject:[NSNumber numberWithInt:windowIndex_]];
        }
    }
}

// Add info from command responses to leaf nodes of parse tree.
- (void)decorateParseTree:(NSMutableDictionary *)parseTree
{
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:parseTree
                                                 callingSelector:@selector(decorateWindowPane:)
                                                        onTarget:self
                                                      withObject:nil];
}

// Callback for DFS of parse tree from decorateParseTree:
- (id)decorateWindowPane:(NSMutableDictionary *)parseTree
{
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
