//
//  TmuxControllerRegistry.m
//  iTerm
//
//  Created by George Nachman on 12/25/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxControllerRegistry.h"


@implementation TmuxControllerRegistry

+ (TmuxControllerRegistry *)sharedInstance
{
    static TmuxControllerRegistry *instance;
    if (!instance) {
        instance = [[TmuxControllerRegistry alloc] init];
    }
    return instance;
}

- (id)init
{
    self = [super init];
    if (self) {
        controllers_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (TmuxController *)controllerForClient:(TmuxClient *)client
{
    return [controllers_ objectForKey:client];
}

- (void)setController:(TmuxController *)controller forClient:(TmuxClient *)client
{
#ifdef TMUX_CRASH_DEBUG
    NSLog(@"setController:forClient: called.");
    NSLog(@"Controllers are: %@", controllers_);
#endif
    if (controller) {
#ifdef TMUX_CRASH_DEBUG
        NSLog(@"Set controller for client %@ to %@", client, controller);
#endif
        [controllers_ setObject:controller forKey:client];
    } else {
#ifdef TMUX_CRASH_DEBUG
        NSLog(@"Remove controller for client %@", client);
#endif
        [controllers_ removeObjectForKey:client];
    }
}

@end
