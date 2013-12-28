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
    if (controller) {
        [controllers_ setObject:controller forKey:client];
    } else {
        [controllers_ removeObjectForKey:client];
    }
}

- (int)numberOfClients {
    return controllers_.count;
}

@end
