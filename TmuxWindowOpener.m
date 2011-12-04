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
- (NSDictionary *)dictForRequestHistoryForNode:(NSMutableDictionary *)node
                                           alt:(BOOL)alternate;
- (void)decorateParseTree:(NSMutableDictionary *)parseTree;
- (id)decorateWindowPane:(NSMutableDictionary *)parseTree;
- (void)requestDidComplete;
- (void)dumpHistoryResponse:(NSString *)response
           paneAndAlternate:(NSArray *)info;
- (NSDictionary *)dictForDumpStateForNode:(NSMutableDictionary *)node;
- (NSDictionary *)dictForStartControlCommand;

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
    [histories_ release];
    [altHistories_ release];
    [states_ release];
    [super dealloc];
}

- (void)openWindows:(BOOL)initial
{
    if (!self.layout) {
        NSLog(@"Bad layout");
        return;
    }
    self.parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    NSMutableArray *cmdList = [NSMutableArray array];
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:self.parseTree
                                                 callingSelector:@selector(appendRequestsForNode:toArray:)
                                                        onTarget:self
                                                      withObject:cmdList];
    if (initial) {
        [cmdList addObject:[self dictForStartControlCommand]];
    }
    // append start-control
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
    if (NSEqualSizes(NSZeroSize, self.size)) {
        NSLog(@"No size");
        return;
    }

    self.parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    // TODO: Use guids for window panes. If a window pane moves from one window to another,
    // it must be notified as the removal first and then the addition to avoid having one pane
    // in two windows.
    [tab setTmuxLayout:self.parseTree
         tmuxController:controller_];
}

@end

@implementation TmuxWindowOpener (Private)

- (NSDictionary *)dictForStartControlCommand
{
    ++pendingRequests_;
    return [gateway_ dictionaryForCommand:@"start-control"
                           responseTarget:self
                         responseSelector:@selector(requestDidComplete)
                           responseObject:nil];
}

// This is called for each window pane via a DFS. It sends all commands needed
// to open a window.
- (id)appendRequestsForNode:(NSMutableDictionary *)node
                    toArray:(NSMutableArray *)cmdList
{    
    [cmdList addObject:[self dictForRequestHistoryForNode:node alt:NO]];
    [cmdList addObject:[self dictForRequestHistoryForNode:node alt:YES]];
    [cmdList addObject:[self dictForDumpStateForNode:node]];
    return nil;
}

- (NSDictionary *)dictForDumpStateForNode:(NSMutableDictionary *)node
{
    ++pendingRequests_;
    NSNumber *wp = [node objectForKey:kLayoutDictWindowPaneKey];
    NSString *command = [NSString stringWithFormat:@"dump-state -t %d.%d",
                         windowIndex_, [wp intValue]];
    return [gateway_ dictionaryForCommand:command
                           responseTarget:self
                         responseSelector:@selector(dumpStateResponse:pane:)
                           responseObject:wp];
}

- (NSDictionary *)dictForRequestHistoryForNode:(NSMutableDictionary *)node
                                           alt:(BOOL)alternate
{
    ++pendingRequests_;
    NSNumber *wp = [node objectForKey:kLayoutDictWindowPaneKey];
    NSString *command = [NSString stringWithFormat:@"dump-history %@-t %d.%d -l 1000",
                         (alternate ? @"-a " : @""), windowIndex_, [wp intValue]];
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
        PseudoTerminal *term = [[iTermController sharedInstance] openWindow];
        NSMutableDictionary *parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
        [self decorateParseTree:parseTree];
        [term loadTmuxLayout:parseTree window:windowIndex_
              tmuxController:controller_
                        name:name_];
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
