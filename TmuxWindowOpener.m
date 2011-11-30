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

@interface TmuxWindowOpener (Private)

- (void)requestHistoryFromParseTree:(NSMutableDictionary *)node
                                alt:(BOOL)alternate;
- (id)sendRequests:(NSMutableDictionary *)node;
- (void)decorateParseTree:(NSMutableDictionary *)parseTree;
- (id)decorateWindowPane:(NSMutableDictionary *)parseTree;
- (void)requestDidComplete;
- (void)dumpHistoryResponse:(NSString *)response
           paneAndAlternate:(NSArray *)info;


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
    }
    return self;
}

- (void)dealloc
{
    [histories_ release];
    [altHistories_ release];
    [super dealloc];
}

- (void)begin
{
    if (!self.layout) {
        NSLog(@"Bad layout");
        return;
    }
    self.parseTree = [[TmuxLayoutParser sharedInstance] parsedLayoutFromString:self.layout];
    [[TmuxLayoutParser sharedInstance] depthFirstSearchParseTree:self.parseTree
                                                 callingSelector:@selector(sendRequests:)
                                                        onTarget:self
                                                      withObject:nil];
}

@end

@implementation TmuxWindowOpener (Private)

// This is called for each window pane via a DFS. It sends all commands needed
// to open a window.
- (id)sendRequests:(NSMutableDictionary *)node
{
    [self requestHistoryFromParseTree:node alt:NO];
    [self requestHistoryFromParseTree:node alt:YES];
    return nil;
}

- (void)requestHistoryFromParseTree:(NSMutableDictionary *)node
                                alt:(BOOL)alternate
{
    ++pendingRequests_;
    NSNumber *wp = [node objectForKey:kLayoutDictWindowPaneKey];
    NSString *command = [NSString stringWithFormat:@"dump-history %@-t %d.%d -l 1000",
                         (alternate ? @"-a " : @""), windowIndex_, [wp intValue]];
    [gateway_ sendCommand:command
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

    return nil;
}

@end
