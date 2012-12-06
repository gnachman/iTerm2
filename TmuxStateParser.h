//
//  TmuxStateParser.h
//  iTerm
//
//  Created by George Nachman on 11/30/11.
//  Copyright (c) 2011 Georgetech. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *kStateDictInAlternateScreen;  // Deprecated, use SavedGrid
extern NSString *kStateDictSavedGrid;
extern NSString *kStateDictBaseCursorX;  // Deprecated, use SavedCX
extern NSString *kStateDictBaseCursorY;  // Deprecated, use SavedCY
extern NSString *kStateDictSavedCX;
extern NSString *kStateDictSavedCY;
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
