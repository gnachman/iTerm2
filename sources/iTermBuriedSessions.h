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

- (void)addBuriedSession:(PTYSession *)buriedSession;
- (void)restoreSession:(PTYSession *)session;
- (NSArray<PTYSession *> *)buriedSessions;

@end
