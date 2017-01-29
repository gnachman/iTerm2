//
//  iTermBuriedSessions.h
//  iTerm2
//
//  Created by George Nachman on 1/25/17.
//
//

#import <Foundation/Foundation.h>

@class PTYSession;

@interface iTermBuriedSessions : NSObject

+ (instancetype)sharedInstance;

- (void)restoreFromState:(NSArray<NSDictionary *> *)state;

- (void)addBuriedSession:(PTYSession *)buriedSession;
- (void)restoreSession:(PTYSession *)session;
- (NSArray<PTYSession *> *)buriedSessions;
- (NSArray<NSDictionary *> *)restorableState;

@end
