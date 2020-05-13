//
//  iTermBuriedSessions.h
//  iTerm2
//
//  Created by George Nachman on 1/25/17.
//
//

#import <Cocoa/Cocoa.h>

@class PTYSession;

extern NSString *const iTermSessionBuriedStateChangeTabNotification;

@interface iTermBuriedSessions : NSObject
@property (nonatomic, strong) NSArray<NSMenu *> *menus;

+ (instancetype)sharedInstance;

- (void)restoreFromState:(NSArray<NSDictionary *> *)state;

- (void)addBuriedSession:(PTYSession *)buriedSession;
- (void)restoreSession:(PTYSession *)session;
- (NSArray<PTYSession *> *)buriedSessions;
- (NSArray<NSDictionary *> *)restorableState;
- (void)updateMenus;

@end
