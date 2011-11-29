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

@implementation TmuxController

@synthesize gateway = gateway_;

- (id)initWithGateway:(TmuxGateway *)gateway
{
    self = [super init];
    if (self) {
        gateway_ = [gateway retain];
        windowPanes_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [gateway_ release];
    [windowPanes_ release];
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
    [windowOpener begin];
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
    [windowPanes_ setObject:aSession forKey:[self _keyForWindow:window windowPane:windowPane]];
}

- (void)deregisterWindow:(int)window windowPane:(int)windowPane
{
    [windowPanes_ removeObjectForKey:[self _keyForWindow:window windowPane:windowPane]];
}

- (void)detach
{
    // Close all sessions.
    for (NSString *key in windowPanes_) {
        PTYSession *session = [windowPanes_ objectForKey:key];
        [[[session tab] realParentWindow] closeSession:session];
    }

    // Clean up all state to avoid trying to reuse it.
    [windowPanes_ removeAllObjects];
    [gateway_ release];
    gateway_ = nil;
}

@end
