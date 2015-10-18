//
//  TmuxControllerRegistry.m
//  iTerm
//
//  Created by George Nachman on 12/25/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import "TmuxControllerRegistry.h"

NSString *const kTmuxControllerRegistryDidChange = @"kTmuxControllerRegistryDidChange";

@implementation TmuxControllerRegistry {
    // Key gives a client name.
    NSMutableDictionary<NSString *, TmuxController *> *controllers_;
}

+ (TmuxControllerRegistry *)sharedInstance
{
    static TmuxControllerRegistry *instance;
    if (!instance) {
        instance = [[TmuxControllerRegistry alloc] init];
    }
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        controllers_ = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (TmuxController *)controllerForClient:(NSString *)client
{
    return [controllers_ objectForKey:client];
}

- (NSString *)uniqueClientNameBasedOn:(NSString *)preferredName {
    int i = 1;
    NSString *candidate = preferredName;
    while (controllers_[candidate]) {
        i++;
        candidate = [NSString stringWithFormat:@"%@ (%d)", preferredName, i];
    }
    return candidate;
}

- (void)setController:(TmuxController *)controller forClient:(NSString *)client
{
    if (controller) {
        [controllers_ setObject:controller forKey:client];
    } else {
        [controllers_ removeObjectForKey:client];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:kTmuxControllerRegistryDidChange
                                                        object:client];
}

- (NSInteger)numberOfClients {
    return controllers_.count;
}

- (NSArray *)clientNames {
    return [[controllers_ allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

@end
