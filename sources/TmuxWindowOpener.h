//
//  TmuxWindowOpener.h
//  iTerm
//
//  Created by George Nachman on 11/29/11.
//

#import <Foundation/Foundation.h>
#import "TmuxGateway.h"
#import "FutureMethods.h"
#import "ProfileModel.h"

extern NSString * const kTmuxWindowOpenerStatePendingOutput;

extern NSString *const kTmuxWindowOpenerWindowOptionStyle;
extern NSString *const kTmuxWindowOpenerWindowOptionStyleValueFullScreen;

@class TmuxGateway;
@class TmuxController;
@class PTYTab;

@interface TmuxWindowOpener : NSObject <NSControlTextEditingDelegate>

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
// Nil means make no change, otherwise is a bool.
@property (nonatomic, retain) NSNumber *zoomed;
@property (nonatomic, assign) NSInteger unicodeVersion;

// Maps a window ID as a string to a dictionary of window flags (see WindowFlag constants above).
@property (nonatomic, retain) NSDictionary *windowOptions;
@property (nonatomic, assign) BOOL manuallyOpened;
@property (nonatomic, copy) NSDictionary<NSNumber *, NSString *> *tabColors;
@property (nonatomic, copy) Profile *profile;
@property (nonatomic, assign) BOOL initial;

+ (TmuxWindowOpener *)windowOpener;
- (BOOL)openWindows:(BOOL)initial;
- (void)updateLayoutInTab:(PTYTab *)term;

@end
