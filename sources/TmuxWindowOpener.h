//
//  TmuxWindowOpener.h
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import <Foundation/Foundation.h>
#import "TmuxGateway.h"
#import "FutureMethods.h"

extern NSString * const kTmuxWindowOpenerStatePendingOutput;

extern NSString *const kTmuxWindowOpenerWindowFlagStyle;
extern NSString *const kTmuxWindowOpenerWindowFlagStyleValueFullScreen;

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
    BOOL ambiguousIsDoubleWidth_;
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
@property (nonatomic, assign) BOOL ambiguousIsDoubleWidth;

// Maps a window ID as a string to a dictionary of window flags (see WindowFlag constants above).
@property (nonatomic, retain) NSDictionary *windowFlags;

+ (TmuxWindowOpener *)windowOpener;
- (void)openWindows:(BOOL)initial;
- (void)updateLayoutInTab:(PTYTab *)term;

@end
