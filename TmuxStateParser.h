//
//  TmuxStateParser.h
//  iTerm
//
//  Created by George Nachman on 11/30/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *kStateDictInAlternateScreen;
extern NSString *kStateDictBaseCursorX;
extern NSString *kStateDictBaseCursorY;
extern NSString *kStateDictCursorX;
extern NSString *kStateDictCursorY;
extern NSString *kStateDictScrollRegionUpper;
extern NSString *kStateDictScrollRegionLower;
extern NSString *kStateDictTabstops;
extern NSString *kStateDictDECSCCursorX;
extern NSString *kStateDictDECSCCursorY;
extern NSString *kStateDictCursorMode;
extern NSString *kStateDictInsertMode;
extern NSString *kStateDictKCursorMode;
extern NSString *kStateDictKKeypadMode;
extern NSString *kStateDictWrapMode;
extern NSString *kStateDictMouseStandardMode;
extern NSString *kStateDictMouseButtonMode;
extern NSString *kStateDictMouseAnyMode;
extern NSString *kStateDictMouseUTF8Mode;

@interface TmuxStateParser : NSObject

+ (TmuxStateParser *)sharedInstance;
- (NSMutableDictionary *)parsedStateFromString:(NSString *)layout;

@end
