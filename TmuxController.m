//
//  TmuxController.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxController.h"
#import "TSVParser.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "TmuxWindowOpener.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"

@interface TmuxController (Private)

- (void)retainWindow:(int)window withTab:(PTYTab *)tab;
- (void)releaseWindow:(int)window;

@end

@implementation TmuxController

@synthesize gateway = gateway_;

- (id)initWithGateway:(TmuxGateway *)gateway
{
    self = [super init];
    if (self) {
        gateway_ = [gateway retain];
        windowPanes_ = [[NSMutableDictionary alloc] init];
        windows_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [gateway_ release];
    [windowPanes_ release];
    [windows_ release];
    [super dealloc];
}

- (void)openWindowWithIndex:(int)windowIndex
                       name:(NSString *)name
                       size:(NSSize)size
                     layout:(NSString *)layout
{
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.windowIndex = windowIndex;
    windowOpener.name = name;
    windowOpener.size = size;
    windowOpener.layout = layout;
    windowOpener.maxHistory = 1000;
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    [windowOpener openWindows:YES];
}

- (void)setLayoutInTab:(PTYTab *)tab
                toSize:(NSSize)size
             andLayout:(NSString *)layout
{
    TmuxWindowOpener *windowOpener = [TmuxWindowOpener windowOpener];
    windowOpener.size = size;
    windowOpener.layout = layout;
    windowOpener.controller = self;
    windowOpener.gateway = gateway_;
    [windowOpener updateLayoutInTab:tab];
}

- (void)initialListWindowsResponse:(NSString *)response
{
    TSVDocument *doc = [response tsvDocument];
    if (!doc) {
        [gateway_ abortWithErrorMessage:[NSString stringWithFormat:@"Bad response for initial list windows request: %@", response]];
        return;
    }
    for (NSArray *record in doc.records) {
        [self openWindowWithIndex:[[doc valueInRecord:record forField:@"window_index"] intValue]
                             name:[doc valueInRecord:record forField:@"window_name"]
                             size:NSMakeSize([[doc valueInRecord:record forField:@"window_width"] intValue],
                                             [[doc valueInRecord:record forField:@"window_height"] intValue])
                           layout:[doc valueInRecord:record forField:@"window_layout"]];
    }
}

- (void)openWindowsInitial
{
    [gateway_ sendCommand:@"list-windows -C"
           responseTarget:self
         responseSelector:@selector(initialListWindowsResponse:)];
}

- (NSString *)_keyForWindow:(int)window windowPane:(int)windowPane
{
    return [NSString stringWithFormat:@"%d.%d", window, windowPane];
}

- (PTYSession *)sessionForWindow:(int)window pane:(int)windowPane
{
    return [windowPanes_ objectForKey:[self _keyForWindow:window windowPane:windowPane]];
}

- (void)registerSession:(PTYSession *)aSession
               withPane:(int)windowPane
               inWindow:(int)window
{
    [self retainWindow:window withTab:[aSession tab]];
    [windowPanes_ setObject:aSession forKey:[self _keyForWindow:window windowPane:windowPane]];
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane
{
    [self releaseWindow:window];
    [windowPanes_ removeObjectForKey:[self _keyForWindow:window windowPane:windowPane]];
}

- (PTYTab *)window:(int)window
{
    return [[windows_ objectForKey:[NSNumber numberWithInt:window]] objectAtIndex:0];
}

- (void)detach
{
    // Close all sessions. Iterate over a copy of windowPanes_ because the loop
    // body modifies it by closing sessions.
    for (NSString *key in [[windowPanes_ copy] autorelease]) {
        PTYSession *session = [windowPanes_ objectForKey:key];
        [[[session tab] realParentWindow] closeSession:session];
    }

    // Clean up all state to avoid trying to reuse it.
    [windowPanes_ removeAllObjects];
    [gateway_ release];
    gateway_ = nil;
}

- (void)windowDidResize:(PseudoTerminal *)term
{
    NSSize size = [term tmuxCompatibleSize];
    [gateway_ sendCommand:[NSString stringWithFormat:@"set-control-client-attr client-size %d,%d", (int) size.width, (int)size.height]
           responseTarget:nil
         responseSelector:nil
           responseObject:nil];
}

@end

@implementation TmuxController (Private)

- (void)retainWindow:(int)window withTab:(PTYTab *)tab
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    if (entry) {
        NSNumber *refcount = [entry objectAtIndex:1];
        [entry replaceObjectAtIndex:1 withObject:[NSNumber numberWithInt:[refcount intValue] + 1]];
    } else {
        entry = [NSMutableArray arrayWithObjects:tab, [NSNumber numberWithInt:1], nil];
    }
    [windows_ setObject:entry forKey:k];
}

- (void)releaseWindow:(int)window
{
    NSNumber *k = [NSNumber numberWithInt:window];
    NSMutableArray *entry = [windows_ objectForKey:k];
    NSNumber *refcount = [entry objectAtIndex:1];
    refcount = [NSNumber numberWithInt:[refcount intValue] + 1];
    if ([refcount intValue]) {
        [entry replaceObjectAtIndex:1 withObject:refcount];
        [windows_ setObject:entry forKey:k];
    } else {
        [windows_ removeObjectForKey:k];
        return;
    }
}

@end
