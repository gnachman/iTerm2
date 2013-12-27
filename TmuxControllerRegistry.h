//
//  TmuxControllerRegistry.h
//  iTerm
//
//  Created by George Nachman on 12/25/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TmuxController;

#define TmuxClient NSString

@interface TmuxControllerRegistry : NSObject {
    NSMutableDictionary *controllers_;  // client -> controller
}

+ (TmuxControllerRegistry *)sharedInstance;
- (TmuxController *)controllerForClient:(TmuxClient *)client;
- (void)setController:(TmuxController *)controller forClient:(TmuxClient *)client;
- (int)numberOfClients;

@end
