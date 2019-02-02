//
//  TmuxControllerRegistry.h
//  iTerm
//
//  Created by George Nachman on 12/25/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TmuxController;

extern NSString *const kTmuxControllerRegistryDidChange;

@interface TmuxControllerRegistry : NSObject

@property(nonatomic, readonly) NSInteger numberOfClients;
@property(nonatomic, readonly) NSArray<NSString*> *clientNames;

+ (instancetype)sharedInstance;
- (TmuxController *)controllerForClient:(NSString *)client;
- (void)setController:(TmuxController *)controller forClient:(NSString *)client;
- (NSString *)uniqueClientNameBasedOn:(NSString *)preferredName;
- (TmuxController *)tmuxControllerWithSessionGUID:(NSString *)sessionGUID;

@end
