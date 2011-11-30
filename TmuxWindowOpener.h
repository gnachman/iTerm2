//
//  TmuxWindowOpener.h
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import <Foundation/Foundation.h>
#import "TmuxGateway.h"

@class TmuxGateway;
@class TmuxController;

@interface TmuxWindowOpener : NSObject {
    int windowIndex_;
    NSString *name_;
    NSSize size_;
    NSString *layout_;
    int maxHistory_;
    TmuxGateway *gateway_;
    NSMutableDictionary *parseTree_;
    int pendingRequests_;
    TmuxController *controller_;  // weak
    NSMutableDictionary *histories_;
    NSMutableDictionary *altHistories_;
    NSMutableDictionary *states_;
}

@property (nonatomic, assign) int windowIndex;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSSize size;
@property (nonatomic, copy) NSString *layout;
@property (nonatomic, assign) int maxHistory;
@property (nonatomic, retain) TmuxGateway *gateway;
@property (nonatomic, retain) NSMutableDictionary *parseTree;
@property (nonatomic, assign) TmuxController *controller;

+ (TmuxWindowOpener *)windowOpener;
- (void)openWindows:(BOOL)initial;

@end
