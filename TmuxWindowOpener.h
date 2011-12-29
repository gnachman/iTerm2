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
@class PTYTab;

@interface TmuxWindowOpener : NSObject <NSControlTextEditingDelegate> {
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
    PTYTab *tabToUpdate_;
    id target_;
    SEL selector_;
}

@property (nonatomic, assign) int windowIndex;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) NSSize size;
@property (nonatomic, copy) NSString *layout;
@property (nonatomic, assign) int maxHistory;
@property (nonatomic, retain) TmuxGateway *gateway;
@property (nonatomic, retain) NSMutableDictionary *parseTree;
@property (nonatomic, assign) TmuxController *controller;  // weak
@property (nonatomic, retain) id target;
// Selector is called even if the window is already open and nothing is done.
@property (nonatomic, assign) SEL selector;

+ (TmuxWindowOpener *)windowOpener;
- (void)openWindows:(BOOL)initial;
- (void)updateLayoutInTab:(PTYTab *)term;

@end
